import {test} from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdtempSync, writeFileSync, readFileSync, chmodSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const cli = join(dirname(fileURLToPath(import.meta.url)), '..', 'cli', 'herdr-ask');

// A fake hc: `get` returns one live agent terminal; every `label` call is appended to a log.
function fakeHc() {
  const dir = mkdtempSync(join(tmpdir(), 'herdr-ask-'));
  const log = join(dir, 'labels.log'), hc = join(dir, 'hc');
  writeFileSync(hc, `#!/usr/bin/python3 -I
import sys, json
a = sys.argv[1:]
if a[0] == 'get':
    print(json.dumps({'address':'t1','state':'live','created_ms':1,'pid':2,'status':{'app':'codex','state':'working'},'labels':{'recovery.role':'lead'}}))
elif a[0] == 'label':
    open(${JSON.stringify(log)}, 'a').write(json.dumps(a[2:]) + '\\n')
`);
  chmodSync(hc, 0o755);
  return {log, env: {...process.env, HERDR_ASK_HC: hc, HC_TERMINAL_ID: 't1'}};
}
const labels = log => readFileSync(log, 'utf8').trim().split('\n').map(line => JSON.parse(line)).flat();

test('open --recommend stores the recommended answer with the question', () => {
  const {log, env} = fakeHc();
  execFileSync(cli, ['open', '--text', 'Which plan?', '--choice', 'A', '--choice', 'B', '--recommend', 'A'], {env});
  assert.ok(labels(log).includes('ask.recommend=A'));
});

test('a question without a recommendation clears an earlier one', () => {
  const {log, env} = fakeHc();
  execFileSync(cli, ['open', '--text', 'Which plan?'], {env});
  assert.ok(labels(log).includes('ask.recommend='));
});

test('a recommendation is one short line', () => {
  const {env} = fakeHc();
  const long = spawnSync(cli, ['open', '--text', 'Q', '--recommend', 'x'.repeat(201)], {env});
  assert.notEqual(long.status, 0);
  const multi = spawnSync(cli, ['open', '--text', 'Q', '--recommend', 'a\nb'], {env});
  assert.notEqual(multi.status, 0);
});
