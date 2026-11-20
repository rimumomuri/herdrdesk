import assert from 'node:assert/strict';
import { test } from 'node:test';
import { boardColumns, teamCounts, boardCardHTML, teamCountsText } from '../Resources/web/task-board.js';

const now = Date.parse('2026-11-20T12:00:00Z');
const iso = ms => new Date(ms).toISOString();
const card = (id, state, extra = {}) => ({ id, state, title: 'T ' + id, done: ['a', 'b'], doneChecks: [true, false],
  owner: { address: 't2' }, created: iso(now - 3_600_000), updated: iso(now - 60_000), blocker: null, ...extra });
const team = { cards: [card('k-1', 'done'), card('k-2', 'cancelled'), card('k-3', 'blocked', { blocker: 'need key' }),
  card('k-4', 'review'), card('k-5', 'working'), card('k-6', 'queued', { owner: null }),
  card('k-7', 'done', { updated: iso(now - 25 * 3_600_000) })], counts: {}, warnings: [] };

test('columns follow state order and hide cancelled', () => {
  const cols = boardColumns(team, now);
  assert.deepEqual(cols.map(c => c.state), ['queued', 'working', 'review', 'blocked', 'done']);
  assert.ok(!cols.flatMap(c => c.cards).some(c => c.id === 'k-2'));
  const blocked = cols.find(c => c.state === 'blocked').cards[0];
  assert.equal(blocked.blocker, 'need key');
  assert.deepEqual(blocked.doneOf, [1, 2]);
  assert.equal(blocked.ageMs, 3_600_000);
  assert.equal(cols[0].cards[0].owner, null);
});

test('done column keeps only last 24h', () => {
  assert.deepEqual(boardColumns(team, now).at(-1).cards.map(c => c.id), ['k-1']);
});

test('missing team gives empty columns', () => {
  assert.deepEqual(boardColumns(undefined, now).map(c => c.cards.length), [0, 0, 0, 0, 0]);
});

test('card html escapes title and shows done progress', () => {
  const escape = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const html = boardCardHTML({ id: 'k-9', title: '<b>x</b>', owner: 't2', ageMs: 120_000, doneOf: [1, 3], blocker: '<i>' },
    a => a === 't2' ? 'Builder <1>' : '', () => '<svg></svg>', escape, k => k);
  assert.ok(html.includes('&lt;b&gt;x&lt;/b&gt;'));
  assert.ok(!html.includes('<b>x'));
  assert.ok(html.includes('1/3'));
  assert.ok(html.includes('Builder &lt;1&gt;'));
  assert.ok(html.includes('data-board-owner="t2"'));
  assert.ok(html.includes('&lt;i&gt;'));
});

test('team counts', () => {
  assert.deepEqual(teamCounts(team), { working: 1, blocked: 1, review: 1 });
  assert.deepEqual(teamCounts(undefined), { working: 0, blocked: 0, review: 0 });
});

test('counts text omits zero parts', () => {
  const copy = k => ({ teamCountWorking: '진행 {n}', teamCountBlocked: '막힘 {n}' })[k];
  assert.equal(teamCountsText({ working: 1, blocked: 0, review: 2 }, copy), '진행 1');
  assert.equal(teamCountsText({ working: 0, blocked: 2, review: 0 }, copy), '막힘 2');
  assert.equal(teamCountsText({ working: 3, blocked: 1, review: 0 }, copy), '진행 3 · 막힘 1');
  assert.equal(teamCountsText({ working: 0, blocked: 0, review: 4 }, copy), '');
});
