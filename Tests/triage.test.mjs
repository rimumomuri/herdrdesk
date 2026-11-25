import {test} from 'node:test';
import assert from 'node:assert/strict';
import {attentionOf, autoUnread, snoozeActive, snoozeUntil, nextUrgent, waitingCount, markSeen} from '../Resources/web/triage.js';

const row = (key, extra = {}) => ({key, lastAgentAt: 0, pending: 0, trouble: null, blocked: false, ...extra});

test('what a conversation needs from the person, most urgent first', () => {
  assert.equal(attentionOf(row('a', {pending: 1, trouble: 'login'}), false), 'question');
  assert.equal(attentionOf(row('a', {trouble: 'login', blocked: true}), false), 'login');
  assert.equal(attentionOf(row('a', {blocked: true}), true), 'blocked');
  assert.equal(attentionOf(row('a'), true), 'unread');
  assert.equal(attentionOf(row('a', {trouble: 'limit'}), false), null, 'a usage limit is not something to answer');
  assert.equal(attentionOf(row('a'), false), null);
});

test('an agent message after the person last looked is unread; the first sighting counts as seen', () => {
  assert.equal(autoUnread(row('a', {lastAgentAt: 500}), {a: 400}), true);
  assert.equal(autoUnread(row('a', {lastAgentAt: 400}), {a: 400}), false);
  assert.equal(autoUnread(row('a', {lastAgentAt: 500}), {}), false);
  assert.equal(autoUnread(row('a', {lastAgentAt: 0}), {a: 0}), false);
});

test('marking seen records the newest agent message, and first sightings start as seen', () => {
  const seen = markSeen({}, [row('a', {lastAgentAt: 300}), row('b', {lastAgentAt: 900})], 'b', 1000);
  assert.deepEqual(seen, {a: 300, b: 1000});
  assert.deepEqual(markSeen(seen, [row('a', {lastAgentAt: 800})], null, 2000), {a: 300, b: 1000}, 'nothing new marked without looking');
  assert.equal(markSeen({}, [row('c', {lastAgentAt: 9000})], 'c', 1000).c, 9000, 'an agent clock ahead of ours still counts as seen');
});

test('a snoozed conversation stays down until its time, new agent activity, or something that needs the person', () => {
  const entry = {until: 5000, at: 1000};
  assert.equal(snoozeActive(entry, row('a', {lastAgentAt: 900}), 2000), true);
  assert.equal(snoozeActive(entry, row('a', {lastAgentAt: 900}), 5000), false, 'time is up');
  assert.equal(snoozeActive(entry, row('a', {lastAgentAt: 1500}), 2000), false, 'the agent said something new');
  assert.equal(snoozeActive(entry, row('a', {pending: 1}), 2000), false, 'a question comes back up');
  assert.equal(snoozeActive(entry, row('a', {trouble: 'login'}), 2000), false);
  assert.equal(snoozeActive(null, row('a'), 2000), false);
});

test('snooze choices: an hour, or tomorrow 9:00 local time', () => {
  const now = new Date(2026, 10, 25, 14, 30).getTime();
  assert.equal(snoozeUntil('hour', now), now + 3_600_000);
  assert.equal(snoozeUntil('morning', now), new Date(2026, 10, 26, 9, 0).getTime());
  const early = new Date(2026, 10, 25, 6, 0).getTime();
  assert.equal(snoozeUntil('morning', early), new Date(2026, 10, 25, 9, 0).getTime(), 'before 9 it is this morning');
});

test('next urgent goes question, login, blocked, unread, then cycles; counts what is waiting', () => {
  const rows = [row('u'), row('b', {blocked: true}), row('q', {pending: 1}), row('l', {trouble: 'login'}), row('calm')];
  const unread = new Set(['u']);
  assert.equal(nextUrgent(rows, unread, null), 'q');
  assert.equal(nextUrgent(rows, unread, 'q'), 'l');
  assert.equal(nextUrgent(rows, unread, 'l'), 'b');
  assert.equal(nextUrgent(rows, unread, 'b'), 'u');
  assert.equal(nextUrgent(rows, unread, 'u'), 'q');
  assert.equal(nextUrgent(rows, unread, 'calm'), 'q');
  assert.equal(nextUrgent([row('calm')], new Set(), null), null);
  assert.equal(waitingCount(rows, unread), 4);
});

test('one question shown in a team room and in the asker\'s own chat counts once, where it appears first', () => {
  const rows = [row('room', {pending: 1, questions: ['q1']}), row('asker', {pending: 1, questions: ['q1']}), row('other', {pending: 1, questions: ['q2']})];
  assert.equal(waitingCount(rows, new Set()), 2);
  assert.equal(nextUrgent(rows, new Set(), 'room'), 'other');
  assert.equal(nextUrgent(rows, new Set(), 'other'), 'room');
});
