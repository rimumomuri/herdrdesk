import {test} from 'node:test';
import assert from 'node:assert/strict';
import {newHandoffs, attentionKeys, attentionTick, DEFAULT_SOUNDS} from '../Resources/web/sound-rules.js';

test('defaults cover the three events', () => {
  assert.deepEqual(Object.keys(DEFAULT_SOUNDS).sort(), ['attention','done','handoff']);
});

test('a handoff sounds once when it first appears, never for history on startup', () => {
  const a = {id:'c1', kind:'assign'}, b = {id:'c2', kind:'assign'}, m = {id:'c3', kind:'message'};
  let r = newHandoffs([a], null);
  assert.equal(r.fresh, 0);
  r = newHandoffs([a, b, m], r.seen);
  assert.equal(r.fresh, 1);
  r = newHandoffs([a, b, m], r.seen);
  assert.equal(r.fresh, 0);
});

test('attention means a blocked agent or an unanswered question', () => {
  const terms = [
    {address:'t1', session:'1', status:'blocked', program:{agent:true}},
    {address:'t2', session:'2', status:'error', program:{agent:true}},
    {address:'t3', session:'3', status:'working', program:{agent:true}},
  ];
  const questions = [{id:'q1', state:'answerNeeded'}, {id:'q2', state:'answered'}];
  assert.deepEqual([...attentionKeys(terms, questions)].sort(), ['blocked:t1:1', 'question:q1']);
});

test('attention rings at once for something new, then every minute until it is cleared', () => {
  let s = attentionTick(new Set(), new Set(['q']), 0, 1000);
  assert.equal(s.play, true);
  s = attentionTick(new Set(['q']), new Set(['q']), s.lastAt, 30_000);
  assert.equal(s.play, false);
  s = attentionTick(new Set(['q']), new Set(['q']), s.lastAt, 61_000);
  assert.equal(s.play, true);
  s = attentionTick(new Set(['q']), new Set(['q','r']), s.lastAt, 70_000);
  assert.equal(s.play, true);
  s = attentionTick(new Set(['q','r']), new Set(), s.lastAt, 200_000);
  assert.equal(s.play, false);
  assert.equal(s.lastAt, 0);
});
