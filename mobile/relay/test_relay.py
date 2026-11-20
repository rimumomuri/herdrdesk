"""Synthetic-only contract/security regression tests; never runs installed hc."""
import http.client
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import uuid

import relay

TOKEN = 'synthetic-test-token-' + 'x' * 40


def message(**changes):
    value = dict(id=str(uuid.uuid4()), conversationId='direct:synthetic-lead',
                 address='synthetic-lead', session='100:1', role='synthetic-lead',
                 text='Synthetic user question')
    value.update(changes)
    return value


class RelayTests(unittest.TestCase):
    def setUp(self):
        self.app = relay.Relay(TOKEN)
        self.server = relay.make_server(self.app, port=0, request_timeout=0.3)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={'poll_interval': .01})
        self.thread.start()
        self.addCleanup(self.stop)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)
        self.assertFalse(self.thread.is_alive())

    def request(self, path='/v1/snapshot', method='GET', body=None, headers=None):
        conn = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=2)
        hdr = {'Authorization': 'Bearer ' + TOKEN}
        if isinstance(body, dict):
            body = json.dumps(body)
            hdr['Content-Type'] = 'application/json'
        hdr.update(headers or {})
        try:
            conn.request(method, path, body, hdr)
            response = conn.getresponse()
            data = response.read()
            return response.status, json.loads(data) if data else None, dict(response.getheaders())
        finally:
            conn.close()

    def test_health_has_only_public_contract_and_needs_no_token(self):
        status, data, headers = self.request('/v1/health', headers={'Authorization': ''})
        self.assertEqual((status, data), (200, {'schemaVersion': 1, 'service': 'herdrdesk-relay'}))
        self.assertEqual(headers['Cache-Control'], 'no-store')
        self.assertNotIn(TOKEN, json.dumps(headers))

    def test_snapshot_contract_and_synthetic_only_data(self):
        status, data, _ = self.request()
        self.assertEqual(status, 200)
        self.assertEqual(set(data), {'schemaVersion','mode','connection','capabilities','teams','agents','conversations','messages','tasks'})
        self.assertEqual(data['mode'], 'demo')
        self.assertEqual(data['connection'], 'live')
        self.assertEqual(data['capabilities'], dict(readMessages=True, sendMessages=True, runtimeApproval=False))
        self.assertEqual(set(data['agents'][0]), {'address','session','role','teamId','name','provider','status'})
        self.assertEqual(set(data['conversations'][0]), {'id','title','kind','teamId','address','session','role','unreadCount'})
        self.assertEqual(set(data['messages'][0]), {'id','conversationId','role','text','createdAt','state'})
        self.assertTrue(all('Synthetic' in m['text'] for m in data['messages']))

    def test_auth_and_cross_origin_and_host_fail_closed(self):
        for headers, expected in [({'Authorization': ''}, 401),
                                  ({'Authorization': 'Bearer wrong'}, 401),
                                  ({'Origin': 'https://evil.example'}, 403),
                                  ({'Origin': 'null'}, 403),
                                  ({'Origin': 'http://localhost.evil:123'}, 403),
                                  ({'Origin': 'http://localhost:123'}, 403),
                                  ({'Host': 'evil.example'}, 403)]:
            with self.subTest(headers=headers):
                self.assertEqual(self.request(headers=headers)[0], expected)
        origin = f'http://127.0.0.1:{self.server.server_port}'
        status, _, headers = self.request(headers={'Origin': origin})
        self.assertEqual(status, 200)
        self.assertEqual(headers['Access-Control-Allow-Origin'], origin)
        self.assertNotEqual(headers['Access-Control-Allow-Origin'], '*')
        self.assertEqual(self.request(method='OPTIONS', headers={'Origin':'https://evil.example'})[0], 403)

    def test_acceptance_replay_and_conflict_have_no_fake_assistant_final(self):
        body = message()
        first = self.request('/v1/messages', 'POST', body)
        self.assertEqual(first[:2], (200, {'id': body['id'], 'state': 'demo-accepted', 'mode': 'demo'}))
        self.assertEqual(self.request('/v1/messages', 'POST', body)[:2], first[:2])
        changed = dict(body, text='Another synthetic question')
        self.assertEqual(self.request('/v1/messages', 'POST', changed)[0], 409)
        messages = self.request()[1]['messages']
        accepted = [m for m in messages if m['id'] == body['id']]
        self.assertEqual(len(accepted), 1)
        self.assertEqual(accepted[0]['role'], 'user')
        self.assertEqual(accepted[0]['state'], 'demo-accepted')
        self.assertEqual(len([m for m in messages if m['role'] == 'assistant']), 1)

    def test_each_binding_field_is_required_and_must_match(self):
        for key in ['conversationId', 'address', 'session', 'role']:
            with self.subTest(key=key):
                self.assertEqual(self.request('/v1/messages','POST', message(**{key: 'stale'}))[0], 409)
        self.app.fixture['agents'][0]['session'] = '100:2'
        self.assertEqual(self.request('/v1/messages', 'POST', message())[0], 409)

    def test_bounded_strict_json_and_uuid(self):
        bad = [message(id='not-uuid'), message(text=''), message(text='x'*4001),
               message(extra='secret'), message(text=3), [], {'id': str(uuid.uuid4())}]
        for body in bad:
            with self.subTest(body=str(body)[:50]):
                self.assertEqual(self.request('/v1/messages','POST', json.dumps(body), {'Content-Type':'application/json'})[0], 400)
        for body in ['{"id":1,"id":2}', 'NaN', '['*30+'0'+']'*30]:
            self.assertEqual(self.request('/v1/messages','POST',body,{'Content-Type':'application/json'})[0],400)
        self.assertEqual(self.request('/v1/messages','POST','x'*16385, {'Content-Type':'application/json'})[0],413)
        self.assertEqual(self.request('/v1/messages','POST','{}')[0],415)
        self.assertEqual(self.request('/v1/messages','POST','{}',{'Content-Type':'application/json','Transfer-Encoding':'chunked'})[0],400)
        self.assertEqual(self.request('/v1/approval', 'POST', {})[0],404)

    def test_receipt_store_is_bounded_without_evicting_idempotence(self):
        self.app.max_receipts = 1
        first = message()
        self.assertEqual(self.request('/v1/messages','POST',first)[0],200)
        self.assertEqual(self.request('/v1/messages','POST',message())[0],503)
        self.assertEqual(self.request('/v1/messages','POST',first)[0],200)

    def test_stalled_request_is_closed_and_server_recovers(self):
        conn = socket.create_connection(self.server.server_address, timeout=1)
        conn.sendall(b'POST /v1/messages HTTP/1.1\r\nHost: localhost\r\n')
        time.sleep(.45)
        conn.settimeout(1)
        self.assertEqual(conn.recv(1024), b'')
        conn.close()
        self.assertEqual(self.request('/v1/health')[0],200)

    def test_public_bind_is_refused(self):
        for host in ['0.0.0.0', '::', '192.0.2.1', 'localhost.evil']:
            with self.subTest(host=host), self.assertRaises(ValueError):
                relay.make_server(self.app, host=host, port=0)



class CoreTests(unittest.TestCase):
    def test_uuid_case_variants_replay_once_and_changed_body_conflicts(self):
        app = relay.Relay(TOKEN)
        body = message(id='AABBCCDD-0011-4234-ABCD-001122334455')
        self.assertEqual(app.accept(body)[0], 200)
        self.assertEqual(app.accept(body)[1]['id'], 'aabbccdd-0011-4234-abcd-001122334455')
        lower = dict(body, id=body['id'].lower())
        self.assertEqual(app.accept(lower), app.accept(body))
        self.assertEqual(app.accept(dict(lower, text='Different synthetic body'))[0],409)
        self.assertEqual(len(app.snapshot()['messages']),2)
        self.assertEqual(app.snapshot()['messages'][-1]['id'], 'aabbccdd-0011-4234-abcd-001122334455')

    def test_binding_replay_and_capacity_without_network(self):
        app = relay.Relay(TOKEN)
        body = message()
        status, receipt = app.accept(body)
        self.assertEqual((status,receipt), (200, dict(id=body['id'],state='demo-accepted',mode='demo')))
        self.assertEqual(app.accept(body),(status,receipt))
        for key in ['conversationId','address','session','role']:
            self.assertEqual(app.accept(dict(message(),**{key:'stale'}))[0],409)
        self.assertEqual(app.accept(dict(body,text='Changed synthetic body'))[0],409)
        app.max_receipts = 1
        self.assertEqual(app.accept(message())[0],503)
        self.assertEqual(app.accept(body),(status,receipt))
        app.fixture['agents'][0]['session']='100:2'
        self.assertEqual(app.accept(body)[0],409)

    def test_invalid_payloads_and_parser_limits_without_network(self):
        app = relay.Relay(TOKEN)
        for value in [[],None,message(id='bad'),message(text=' '),message(text='x'*4001),message(extra=1),message(role=1)]:
            with self.subTest(value=str(value)[:30]):
                self.assertEqual(app.accept(value)[0],400)
        for raw in [b'{"x":1,"x":2}',b'NaN',b'Infinity',b'\xff',b'['*30+b'0'+b']'*30]:
            with self.subTest(raw=raw), self.assertRaises(ValueError): relay.strict_json(raw)

    def test_snapshot_copy_cannot_mutate_receipts_or_binding(self):
        app = relay.Relay(TOKEN)
        data=app.snapshot()
        data['agents'].clear()
        self.assertEqual(app.accept(message())[0],200)
        data=app.snapshot()
        self.assertEqual(data['mode'],'demo')
        self.assertEqual(data['messages'][-1]['role'],'user')
        self.assertEqual(data['messages'][-1]['state'],'demo-accepted')
        self.assertEqual(len([m for m in data['messages'] if m['role']=='assistant']),1)

    def test_public_listener_refused_before_socket_creation(self):
        app=relay.Relay(TOKEN)
        for host in ['0.0.0.0','::','192.0.2.1','localhost.evil']:
            with self.subTest(host=host), self.assertRaises(ValueError):
                relay.make_server(app,host=host,port=0)


class TokenTests(unittest.TestCase):
    def test_secure_token_file_and_permission_symlink_owner_rejection(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp).resolve() / 'token'
            path.write_text(TOKEN + '\n')
            path.chmod(0o600)
            self.assertEqual(relay.load_token(path), TOKEN)
            for mode in [0o644, 0o400, 0o660]:
                path.chmod(mode)
                with self.assertRaises(ValueError): relay.load_token(path)
            path.chmod(0o600)
            link = path.with_name('link')
            link.symlink_to(path)
            with self.assertRaises(ValueError): relay.load_token(link)
            parent = path.parent / 'linked-dir'
            parent.symlink_to(path.parent, target_is_directory=True)
            with self.assertRaises(ValueError): relay.load_token(parent / 'token')
            with patch('relay.os.getuid', return_value=os.getuid()+1):
                with self.assertRaises(ValueError): relay.load_token(path)
            path.write_text('short')
            with self.assertRaises(ValueError): relay.load_token(path)


class LiveTests(unittest.TestCase):
    def fake(self, directory, behavior):
        path = Path(directory) / 'fake-hc'
        path.write_text('#!/usr/bin/env python3\n' + behavior)
        path.chmod(0o700)
        return str(path)

    def test_fake_hc_allowlist_empty_messages_and_no_send(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.fake(tmp, '''import json,sys
row = {'address':'t-synthetic','state':'live','created_ms':100,'pid':2,
       'status':{'app':'codex','state':'working','msg':'PRIVATE'},
       'labels':{'team.id':'demo-team','team.title':'Demo team','display.title':'Synthetic lead',
                 'recovery.role':'synthetic-role','private':'PRIVATE','ask.text':'PRIVATE'},
       'argv':['PRIVATE'],'cwd':'PRIVATE','archive':'PRIVATE'}
if sys.argv[1:] == ['ls','--json']: print(json.dumps({'terminals':[row]}))
elif sys.argv[1:] == ['get','t-synthetic','--json']: print(json.dumps(row))
else: sys.exit(99)
''')
            app = relay.Relay(TOKEN, mode='live-readonly', hc_path=path)
            data = app.snapshot()
            self.assertEqual(data['mode'], 'live-readonly')
            self.assertEqual(data['connection'], 'live')
            self.assertEqual(data['capabilities'], dict(readMessages=False,sendMessages=False,runtimeApproval=False))
            self.assertEqual(data['messages'], [])
            self.assertEqual(data['tasks'], [])
            self.assertEqual(data['agents'], [dict(address='t-synthetic',session='100:2',role='synthetic-role',teamId='demo-team',name='Synthetic lead',provider='codex',status='working')])
            self.assertNotIn('PRIVATE', json.dumps(data))
            self.assertEqual(app.accept(message())[0],403)

    def test_fake_hc_errors_timeout_overflow_and_binding_drift_fail_closed(self):
        behaviors = ["import time; time.sleep(2)", "print('bad JSON')", "print('x'*70000)",
                     "import sys; sys.exit(3)",
                     "import json,sys; print(json.dumps({'terminals':[{'address':'--bad'}]}))"]
        with tempfile.TemporaryDirectory() as tmp:
            for behavior in behaviors:
                with self.subTest(behavior=behavior):
                    path = self.fake(tmp, behavior)
                    app = relay.Relay(TOKEN, mode='live-readonly', hc_path=path, hc_timeout=.1)
                    start = time.monotonic()
                    with self.assertRaises(relay.UpstreamError): app.snapshot()
                    self.assertLess(time.monotonic()-start,1)
            path = self.fake(tmp, '''import json,sys
if sys.argv[1]=='ls': print(json.dumps({'terminals':[{'address':'synthetic'}]}))
else: print(json.dumps({'address':'other','state':'live','created_ms':1,'pid':2,'labels':{}}))
''')
            with self.assertRaises(relay.UpstreamError):
                relay.Relay(TOKEN, mode='live-readonly', hc_path=path).snapshot()


if __name__ == '__main__':
    unittest.main()
