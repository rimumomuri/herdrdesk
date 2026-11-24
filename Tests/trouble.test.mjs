import {test} from 'node:test';
import assert from 'node:assert/strict';
import {agentTrouble, machineTrouble} from '../Resources/web/trouble.js';

const agent = (status, statusMessage = '') => ({state:'live', program:{agent:true}, status, statusMessage});

test('an error that asks to sign in is a login problem, in any of the app languages', () => {
  for (const msg of ['Please log in again', 'Not logged in · Please run /login', 'Unauthorized (401)', 'Your access token has expired',
                     'Authentication required', '로그인이 필요합니다', 'ログインしてください'])
    assert.equal(agentTrouble(agent('error', msg)), 'login', msg);
});

test('an error about usage or rate is a limit', () => {
  for (const msg of ["You've hit your usage limit. Try again at 3:05 PM.", 'Rate limit reached', 'HTTP 429 Too Many Requests',
                     'Quota exceeded', 'Claude usage limit reached', '사용 한도에 도달했습니다', '利用上限に達しました'])
    assert.equal(agentTrouble(agent('error', msg)), 'limit', msg);
});

test('any other error, or one with no message, stays a plain error', () => {
  assert.equal(agentTrouble(agent('error', 'stream disconnected')), 'error');
  assert.equal(agentTrouble(agent('error')), 'error');
});

test('a person-needed prompt is login only when it says so; healthy or plain states are no trouble', () => {
  assert.equal(agentTrouble(agent('blocked', 'Sign in to continue')), 'login');
  assert.equal(agentTrouble(agent('blocked', 'Allow command?')), null);
  for (const status of ['working', 'idle', 'done']) assert.equal(agentTrouble(agent(status, 'usage limit')), null, status);
  assert.equal(agentTrouble({...agent('error', 'usage limit'), state:'finished'}), null);
  assert.equal(agentTrouble({...agent('error', 'usage limit'), program:{agent:false}}), null);
});

test('a computer whose connection needs a login is a login problem', () => {
  assert.equal(machineTrouble({name:'macbook-m6', state:'needs_login'}), 'login');
  assert.equal(machineTrouble({name:'macbook-m6', state:'connected'}), null);
  assert.equal(machineTrouble(undefined), null);
});
