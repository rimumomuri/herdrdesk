import assert from 'node:assert/strict';
import { test } from 'node:test';
import { leadFrame, leadRow, mouthSlots, leadFaceHTML, agentFaceHTML, isCardWorker } from '../Resources/web/herd-face.js';

test('a card worker is drawn as its engine character, everyone else as a sheep', () => {
  assert.equal(isCardWorker({ 'recovery.role': 'lime-builder-000039' }), true);
  assert.equal(isCardWorker({ 'task.spawned': '1', 'team.role': 'qa' }), true);
  assert.equal(isCardWorker({ 'recovery.role': 'lime-codex-lead', 'team.role': 'lead' }), false);
  assert.equal(isCardWorker(undefined), false);
});

test('a lead keeps its mouth closed, opens it while it has handed work out, and sleeps when idle', () => {
  assert.equal(leadFrame({ mouth: [], resting: false }), 'closed');
  assert.equal(leadFrame({ mouth: [], resting: true }), 'sleep');
  assert.equal(leadFrame({ mouth: ['codex'], resting: true }), 'open');
});

test('the ring follows the lead engine, and turns mixed when the mouth holds both engines', () => {
  assert.equal(leadRow('claude', []), 0);
  assert.equal(leadRow('codex', ['codex', 'codex']), 1);
  assert.equal(leadRow('codex', ['claude', 'codex']), 2);
  assert.equal(leadRow('neutral', []), 1);
});

test('up to four agents fit in the mouth; more shows three and a "more" mark', () => {
  assert.equal(mouthSlots(0).length, 0);
  assert.equal(mouthSlots(1).length, 1);
  assert.equal(mouthSlots(4).filter(slot => !slot.more).length, 4);
  const many = mouthSlots(7);
  assert.equal(many.length, 4);
  assert.equal(many.filter(slot => slot.more).length, 1);
  // big enough to read, filling the mouth and spilling a little over the lip, never off the sheep
  for (const n of [1, 2, 3, 4]) for (const slot of mouthSlots(n)) {
    assert.ok(slot.x >= 55 && slot.x + slot.size <= 295 && slot.y >= 160 && slot.y + slot.size <= 330, JSON.stringify(slot));
    assert.ok(slot.size >= 78, 'readable: ' + JSON.stringify(slot));
  }
  assert.ok(mouthSlots(2).some(slot => slot.x < 85), 'one agent sticks out over the left lip');
});

test('the face markup names its frame and holds one image per agent in the mouth', () => {
  const open = leadFaceHTML({ engine: 'codex', mouth: ['codex', 'claude'] });
  assert.match(open, /data-frame="open"/);
  assert.match(open, /data-row="2"/);
  assert.equal((open.match(/class="herd-mouth-agent"/g) || []).length, 2);
  assert.match(leadFaceHTML({ engine: 'claude', resting: true }), /data-frame="sleep"/);
  const worker = agentFaceHTML({ engine: 'claude' });
  assert.match(worker, /data-face="agent"/);
  assert.match(worker, /data-engine="claude"/);
  assert.match(agentFaceHTML({ engine: 'nope' }), /data-engine="codex"/);
});

test('a light runs along the ring when motion is on, faster while working, never while asleep', () => {
  assert.doesNotMatch(leadFaceHTML({ engine: 'codex' }), /animateMotion/);
  const calm = leadFaceHTML({ engine: 'codex', motion: true });
  assert.match(calm, /<animateMotion dur="3.6s"/);
  assert.match(leadFaceHTML({ engine: 'codex', motion: true, working: true }), /<animateMotion dur="1.3s"/);
  assert.doesNotMatch(leadFaceHTML({ engine: 'codex', motion: true, resting: true }), /animateMotion/);
  // same state, same markup: screens compare HTML to skip redraws
  assert.equal(leadFaceHTML({ motion: true }), leadFaceHTML({ motion: true }));
  assert.doesNotMatch(calm, / id="/);
});
