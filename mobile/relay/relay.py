#!/usr/bin/env python3
"""Explicit foreground, loopback-only development relay. Standard library only.

API v1 policy: UUID input is case-insensitive; receipt keys, response IDs and
stored message IDs are canonical lowercase. Clients must compare UUID identity
or submit lowercase IDs. Case variants replay the same receipt without insertion.
Message text is limited to 4000 Unicode code points; the entire UTF-8 JSON request
body is limited to 16384 bytes (including JSON escaping and all other fields).
"""
import argparse
import copy
from datetime import datetime, timezone
import hmac
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import re
import selectors
import socket
import stat
import subprocess
import threading
import time
import uuid

MAX_JSON = 16384
MAX_HC_OUTPUT = 65536
MAX_TERMINALS = 64
ADDRESS = re.compile(r'[A-Za-z0-9][A-Za-z0-9_.:/-]{0,159}\Z')


class UpstreamError(Exception):
    """Generic failure; subprocess content must never be exposed."""


def strict_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate key')
            result[key] = value
        return result

    def invalid_constant(_):
        raise ValueError('nonfinite number')

    try:
        value = json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid_constant)
        def bounded(item, depth=0):
            if depth > 12:
                raise ValueError('too deep')
            if isinstance(item, dict):
                for child in item.values(): bounded(child, depth + 1)
            elif isinstance(item, list):
                for child in item: bounded(child, depth + 1)
        bounded(value)
        return value
    except (UnicodeError, RecursionError, json.JSONDecodeError) as error:
        raise ValueError('invalid JSON') from error


def load_token(path):
    path = Path(os.path.abspath(path))
    if any(part.is_symlink() for part in (path, *path.parents)):
        raise ValueError('token path must not contain symlinks')
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1):
                raise ValueError('token must be an owner-only 0600 regular file')
            raw = stream.read(513)
    except OSError as error:
        raise ValueError('cannot safely open token file') from error
    if len(raw) > 512:
        raise ValueError('token too large')
    try:
        token = raw.decode('ascii').removesuffix('\n')
    except UnicodeError as error:
        raise ValueError('token must be ASCII') from error
    if not re.fullmatch(r'[A-Za-z0-9_-]{32,256}', token):
        raise ValueError('token must contain 32-256 URL-safe characters')
    return token


def fixture_snapshot():
    return {
        'schemaVersion': 1, 'mode': 'demo', 'connection': 'live',
        'capabilities': dict(readMessages=True, sendMessages=True, runtimeApproval=False),
        'teams': [dict(id='herdrdesk', title='HerdrDesk', memberCount=1)],
        'agents': [dict(address='synthetic-lead',session='100:1',role='synthetic-lead',teamId='herdrdesk',name='Lead',provider='codex',status='working')],
        'conversations': [dict(id='direct:synthetic-lead',title='Lead',kind='direct',teamId='herdrdesk',address='synthetic-lead',session='100:1',role='synthetic-lead',unreadCount=0)],
        'messages': [dict(id='synthetic-reply',conversationId='direct:synthetic-lead',role='assistant',text='Synthetic fixture; no real agent response.',createdAt='2026-11-20T00:00:00Z',state='received')],
        'tasks': [dict(id='synthetic-task',teamId='herdrdesk',title='Synthetic task',state='working',owner='Lead')]
    }


def hc_json(path, args, deadline):
    """No shell, stdin, transcript command, stderr capture or unbounded output."""
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise UpstreamError()
    try:
        process = subprocess.Popen([path, *args], stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                   close_fds=True)
    except OSError as error:
        raise UpstreamError() from error
    data = bytearray()
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise UpstreamError()
                chunk = os.read(process.stdout.fileno(), min(8192, MAX_HC_OUTPUT + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
                if len(data) > MAX_HC_OUTPUT:
                    raise UpstreamError()
        if process.wait(timeout=max(.001, deadline-time.monotonic())) != 0:
            raise UpstreamError()
        try:
            return strict_json(data)
        except ValueError as error:
            raise UpstreamError() from error
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        process.stdout.close()


def safe_string(value, maximum=160):
    return isinstance(value, str) and 0 < len(value) <= maximum and all(ord(c) >= 32 and ord(c) != 127 for c in value)


def public_agent(row):
    """Construct API fields individually. Never export a labels object or status msg."""
    if not isinstance(row, dict):
        raise UpstreamError()
    address, created, pid = row.get('address'), row.get('created_ms'), row.get('pid')
    if not isinstance(address, str) or not ADDRESS.fullmatch(address):
        raise UpstreamError()
    if row.get('state') != 'live':
        return None
    labels = row.get('labels', {})
    status = row.get('status', {})
    if not isinstance(labels, dict):
        raise UpstreamError()
    if isinstance(status, dict):
        provider, state = status.get('app'), status.get('state')
    else:
        provider, state = row.get('agent'), status
    if provider not in ('codex', 'claude-code'):
        return None
    role = labels.get('recovery.role')
    team = labels.get('team.id', 'unassigned')
    title = labels.get('display.title', role)
    if (type(created) is not int or type(pid) is not int or created <= 0 or pid <= 0
            or not all(safe_string(x) for x in (role, team, title))):
        raise UpstreamError()
    return dict(address=address, session=f'{created}:{pid}', role=role, teamId=team,
                name=title, provider=provider,
                status=state if state in ('working','idle','waiting','blocked','error','done','needs-user','queued') else 'unknown')


class Relay:
    def __init__(self, token, mode='fixture', hc_path=None, hc_timeout=2):
        if mode not in ('fixture', 'live-readonly'):
            raise ValueError('invalid mode')
        if mode == 'live-readonly' and (not hc_path or not os.path.isabs(hc_path)):
            raise ValueError('live-readonly requires explicit absolute hc executable')
        if not 0 < hc_timeout <= 5:
            raise ValueError('invalid hc timeout')
        self.token, self.mode, self.hc_path, self.hc_timeout = token, mode, hc_path, hc_timeout
        self.fixture = fixture_snapshot()
        self.receipts = {}
        self.max_receipts = 64
        self.lock = threading.Lock()

    def snapshot(self):
        if self.mode == 'fixture':
            with self.lock:
                return copy.deepcopy(self.fixture)
        deadline = time.monotonic() + self.hc_timeout
        listing = hc_json(self.hc_path, ['ls', '--json'], deadline)
        rows = listing.get('terminals') if isinstance(listing, dict) else None
        if not isinstance(rows, list) or len(rows) > MAX_TERMINALS:
            raise UpstreamError()
        agents, teams, conversations, addresses = [], {}, [], set()
        for row in rows:
            address = row.get('address') if isinstance(row, dict) else None
            if not isinstance(address, str) or not ADDRESS.fullmatch(address) or address in addresses:
                raise UpstreamError()
            addresses.add(address)
            current = hc_json(self.hc_path, ['get', address, '--json'], deadline)
            if not isinstance(current, dict) or current.get('address') != address:
                raise UpstreamError()
            agent = public_agent(current)
            if agent is None:
                continue
            agents.append(agent)
            team = agent['teamId']
            title = current.get('labels', {}).get('team.title', team)
            if not safe_string(title):
                raise UpstreamError()
            teams.setdefault(team, dict(id=team,title=title,memberCount=0))['memberCount'] += 1
            conversations.append(dict(id='direct:'+address,title=agent['name'],kind='direct',teamId=team,
                                      address=address,session=agent['session'],role=agent['role'],unreadCount=0))
        return dict(schemaVersion=1,mode='live-readonly',connection='live',
                    capabilities=dict(readMessages=False,sendMessages=False,runtimeApproval=False),
                    teams=list(teams.values()),agents=agents,conversations=conversations,messages=[],tasks=[])

    def accept(self, body):
        if self.mode != 'fixture':
            return 403, {'error':'read-only'}
        keys = {'id','conversationId','address','session','role','text'}
        if not isinstance(body, dict) or set(body) != keys or not all(isinstance(v,str) for v in body.values()):
            return 400, {'error':'invalid message'}
        try:
            canonical_id = str(uuid.UUID(body['id']))
            valid_id = canonical_id == body['id'].lower()
        except ValueError:
            valid_id = False
        if (not valid_id or not body['text'].strip() or len(body['text']) > 4000
                or not all(safe_string(body[k]) for k in keys - {'text'})):
            return 400, {'error':'invalid message'}
        body = dict(body, id=canonical_id)
        with self.lock:
            matches = [c for c in self.fixture['conversations'] if c['id'] == body['conversationId']]
            if len(matches) != 1 or any(matches[0].get(k) != body[k] for k in ('address','session','role')):
                return 409, {'error':'stale target'}
            agents = [a for a in self.fixture['agents'] if a['address'] == body['address']]
            if len(agents) != 1 or any(agents[0].get(k) != body[k] for k in ('session','role')):
                return 409, {'error':'stale target'}
            previous = self.receipts.get(body['id'])
            if previous:
                return (200, copy.deepcopy(previous[1])) if previous[0] == body else (409, {'error':'id conflict'})
            if len(self.receipts) >= self.max_receipts:
                return 503, {'error':'demo capacity reached'}
            receipt = dict(id=body['id'],state='demo-accepted',mode='demo')
            self.receipts[body['id']] = (copy.deepcopy(body), receipt)
            self.fixture['messages'].append(dict(id=body['id'],conversationId=body['conversationId'],role='user',
                text=body['text'],createdAt=datetime.now(timezone.utc).isoformat().replace('+00:00','Z'),state='demo-accepted'))
            return 200, copy.deepcopy(receipt)


class Handler(BaseHTTPRequestHandler):
    # Unbuffered reads plus a whole-request deadline bound slow headers and bodies.
    rbufsize = 0
    server_version = 'HerdrDeskRelay'
    sys_version = ''

    def log_message(self, *_):
        pass

    def handle_one_request(self):
        def expire():
            try: self.connection.shutdown(socket.SHUT_RDWR)
            except OSError: pass
        timer = threading.Timer(self.server.request_timeout, expire)
        timer.daemon = True
        self.connection.settimeout(self.server.request_timeout)
        timer.start()
        try:
            super().handle_one_request()
        except (OSError, ValueError):
            self.close_connection = True
        finally:
            timer.cancel()

    def reply(self, status, value):
        raw = json.dumps(value, ensure_ascii=True, separators=(',',':')).encode('ascii')
        self.send_response(status)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(raw)))
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        if getattr(self,'allowed_origin',None):
            self.send_header('Access-Control-Allow-Origin',self.allowed_origin)
            self.send_header('Vary','Origin')
        self.send_header('Connection','close')
        self.end_headers()
        self.wfile.write(raw)
        self.close_connection = True

    def guard(self):
        port = self.server.server_port
        hosts = {f'127.0.0.1:{port}', f'localhost:{port}'}
        if port == 80: hosts |= {'127.0.0.1','localhost'}
        if len(self.headers.get_all('Host',[])) != 1 or self.headers.get('Host') not in hosts:
            self.reply(403, {'error':'invalid host'})
            return False
        origins = self.headers.get_all('Origin',[])
        if origins:
            if len(origins) != 1 or origins[0] not in {f'http://{h}' for h in hosts}:
                self.reply(403, {'error':'origin denied'})
                return False
            self.allowed_origin = origins[0]
        if self.path != '/v1/health' or self.command != 'GET':
            auth = self.headers.get_all('Authorization',[])
            expected = 'Bearer '+self.server.app.token
            if len(auth) != 1 or not hmac.compare_digest(auth[0].encode(),expected.encode()):
                self.reply(401, {'error':'unauthorized'})
                return False
        return True

    def do_GET(self):
        if not self.guard(): return
        if self.path == '/v1/health':
            self.reply(200, dict(schemaVersion=1,service='herdrdesk-relay'))
        elif self.path == '/v1/snapshot':
            try:
                data = self.server.app.snapshot()
                if len(json.dumps(data).encode()) > 2*1024*1024:
                    raise UpstreamError()
                self.reply(200,data)
            except (UpstreamError, subprocess.TimeoutExpired):
                self.reply(503, {'error':'metadata unavailable'})
        else:
            self.reply(404, {'error':'not found'})

    def do_POST(self):
        if not self.guard(): return
        if self.path != '/v1/messages':
            self.reply(404, {'error':'not found'})
            return
        if self.server.app.mode != 'fixture':
            self.reply(403, {'error':'read-only'})
            return
        lengths = self.headers.get_all('Content-Length',[])
        if self.headers.get_all('Transfer-Encoding') or len(lengths) != 1 or not re.fullmatch('[0-9]{1,8}', lengths[0]):
            self.reply(400, {'error':'invalid framing'})
            return
        length = int(lengths[0])
        if length > MAX_JSON:
            self.reply(413, {'error':'body too large'})
            return
        if self.headers.get_all('Content-Type',[]) != ['application/json']:
            self.reply(415, {'error':'expected application/json'})
            return
        try:
            raw = bytearray()
            while len(raw) < length:
                chunk = self.rfile.read(length-len(raw))
                if not chunk: raise ValueError('truncated body')
                raw.extend(chunk)
            status, data = self.server.app.accept(strict_json(raw))
            self.reply(status,data)
        except ValueError:
            self.reply(400, {'error':'invalid JSON'})

    def do_OPTIONS(self):
        if self.guard(): self.reply(405, {'error':'method not allowed'})


class RelayServer(HTTPServer):
    allow_reuse_address = False
    request_queue_size = 4

    def handle_error(self, request, client_address):
        # No request body, credential, subprocess stderr or tracebacks in logs.
        pass


def make_server(app, host='127.0.0.1', port=8765, request_timeout=3):
    if host not in ('127.0.0.1','localhost'):
        raise ValueError('loopback listener only')
    if not 0 < request_timeout <= 10:
        raise ValueError('invalid request timeout')
    server = RelayServer(('127.0.0.1',port),Handler)
    server.app, server.request_timeout = app, request_timeout
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--token-file', required=True)
    parser.add_argument('--host', choices=('127.0.0.1','localhost'), default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--mode', choices=('fixture','live-readonly'), default='fixture')
    parser.add_argument('--hc', help='Explicit absolute executable; live-readonly only')
    args = parser.parse_args()
    try:
        app = Relay(load_token(args.token_file),args.mode,args.hc)
        with make_server(app,args.host,args.port) as server:
            print(f'HerdrDesk relay {args.mode} on 127.0.0.1:{server.server_port}; foreground, Ctrl-C to stop',flush=True)
            server.serve_forever(poll_interval=.2)
    except KeyboardInterrupt:
        pass
    except (ValueError,OSError):
        parser.exit(2,'Relay configuration or listener unavailable.\n')


if __name__ == '__main__':
    main()
