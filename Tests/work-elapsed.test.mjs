import assert from 'node:assert/strict';
import { test } from 'node:test';
import { workingSince, elapsedText } from '../Resources/web/model.js';

const units = { s: '{s}초', ms: '{m}분 {s}초', hm: '{h}시간 {m}분' };

test('working time starts at the current turn when the transcript saw it start', () => {
  const term = { statusMs: 1_000_000 };
  assert.equal(workingSince(term, { state: 'working', at: new Date(1_000_500).toISOString() }), 1_000_500);
});

test('without a newer turn start it falls back to when the terminal became working', () => {
  assert.equal(workingSince({ statusMs: 2_000_000 }, { state: 'working', at: new Date(1_000_000).toISOString() }), 2_000_000);
  assert.equal(workingSince({ statusMs: 2_000_000 }, { state: 'done', at: new Date(2_500_000).toISOString() }), 2_000_000);
  assert.equal(workingSince({ statusMs: 2_000_000 }, undefined), 2_000_000);
  assert.equal(workingSince({}, undefined), null);
});

test('elapsed time reads like the terminal: seconds, then minutes and seconds, then hours and minutes', () => {
  assert.equal(elapsedText(12_400, units), '12초');
  assert.equal(elapsedText(3 * 60_000 + 5_000, units), '3분 5초');
  assert.equal(elapsedText(64 * 60_000 + 59_000, units), '1시간 4분');
  assert.equal(elapsedText(-5, units), '0초');
});
