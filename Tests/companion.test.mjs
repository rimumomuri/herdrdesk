import {test} from 'node:test';
import assert from 'node:assert/strict';
import {companionState, companionSummary, featuredAgent, FLASH_MS} from '../Resources/web/companion.js';

const now = 1_000_000;
const base = {connection:'live', attention:[], working:0, flash:null, now};

test('someone waiting on you wins over everything, counted once per agent even with a blocked prompt and a question', () => {
  const state = companionState({...base, working:3, flash:{kind:'done', at:now},
    attention:[{address:'t1', session:'s1', team:'킁킁맵'}, {address:'t1', session:'s1', team:'킁킁맵'}, {address:'t2', session:'s2', team:'라인챗봇'}]});
  assert.equal(state.mood, 'attention');
  assert.equal(state.count, 2);
  assert.deepEqual(state.teams, [{team:'킁킁맵', n:1}, {team:'라인챗봇', n:1}]);
  assert.deepEqual(state.target, {address:'t1', session:'s1'});
});

test('a lost or missing connection is shown as offline, never as idle; the first connect is not', () => {
  assert.equal(companionState({...base, connection:'lost'}).mood, 'offline');
  assert.equal(companionState({...base, connection:'missing', working:2}).mood, 'offline');
  assert.equal(companionState({...base, connection:'connecting'}).mood, 'idle');
  assert.equal(companionState({...base, connection:'lost', attention:[{address:'t1', session:'s', team:'x'}]}).mood, 'attention');
});

test('working shows how many sessions work; with nothing going on it is idle', () => {
  assert.deepEqual([companionState({...base, working:2}).mood, companionState({...base, working:2}).working], ['working', 2]);
  assert.equal(companionState(base).mood, 'idle');
  assert.equal(companionState(base).target, null);
});

test('a finish or a new assignment flashes briefly on top of the mood, then fades', () => {
  assert.equal(companionState({...base, working:1, flash:{kind:'done', at:now - 1000}}).flash, 'done');
  assert.equal(companionState({...base, flash:{kind:'handoff', at:now - 1000}}).flash, 'handoff');
  assert.equal(companionState({...base, flash:{kind:'handoff', at:now - 1000}}).mood, 'idle');
  assert.equal(companionState({...base, flash:{kind:'done', at:now - FLASH_MS - 1}}).flash, null);
});

test('the hover line names teams and counts only, never question text', () => {
  const copy = key => ({companionNeeds:'{team} 확인 {n}개', companionWorking:'{n}개 작업 중', companionOffline:'연결 끊김', companionIdle:'쉬는 중',
    companionDone:'방금 끝남', companionHandoff:'새 배정'})[key];
  const attention = companionState({...base, attention:[{address:'t1', session:'s', team:'킁킁맵', ask:'비밀 질문'}]});
  assert.deepEqual(companionSummary(attention, copy), ['킁킁맵 확인 1개']);
  assert.ok(!JSON.stringify(attention).includes('비밀'));
  assert.deepEqual(companionSummary(companionState({...base, working:3, flash:{kind:'done', at:now}}), copy), ['방금 끝남', '3개 작업 중']);
  assert.deepEqual(companionSummary(companionState({...base, connection:'lost'}), copy), ['연결 끊김']);
});

test('each flash carries its event time, so a second finish of the same kind is still new', () => {
  assert.equal(companionState({...base, flash:{kind:'handoff', at:now - 2000}}).flashAt, now - 2000);
  assert.equal(companionState({...base, flash:{kind:'handoff', at:now - FLASH_MS - 1}}).flashAt, null);
});

test('the face shown is whoever needs you, else who just finished, else the latest to start working, else the last face', () => {
  const working = ['w-new', 'w-old'];
  assert.equal(featuredAgent({mood:'attention', flash:'done', targetKey:'a', finishedKey:'f', workingKeys:working, previousKey:'p'}), 'a');
  assert.equal(featuredAgent({mood:'working', flash:'done', finishedKey:'f', workingKeys:working, previousKey:'p'}), 'f');
  assert.equal(featuredAgent({mood:'working', flash:'handoff', finishedKey:'f', workingKeys:working, previousKey:'p'}), 'w-new');
  assert.equal(featuredAgent({mood:'idle', workingKeys:[], previousKey:'p'}), 'p');
  assert.equal(featuredAgent({mood:'idle', workingKeys:[]}), null);
});

test('a usage limit shows as its own mood below needs-you and offline but above working, with no target to open', () => {
  assert.equal(companionState({...base, working:2, limited:1}).mood, 'limit');
  assert.equal(companionState({...base, limited:1}).limited, 1);
  assert.equal(companionState({...base, connection:'lost', limited:1}).mood, 'offline');
  assert.equal(companionState({...base, limited:1, attention:[{address:'t1', session:'s', team:'x'}]}).mood, 'attention');
  const copy = key => ({companionLimit:'{n}개 한도 초과'})[key] || key;
  assert.deepEqual(companionSummary(companionState({...base, limited:2}), copy), ['2개 한도 초과']);
});

test('while at a usage limit the face is the limited agent', () => {
  assert.equal(featuredAgent({mood:'limit', limitKey:'l', workingKeys:['w'], previousKey:'p'}), 'l');
});
