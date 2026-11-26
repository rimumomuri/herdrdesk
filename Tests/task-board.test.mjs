import assert from 'node:assert/strict';
import { test } from 'node:test';
import { boardColumns, teamCounts, boardCardHTML, teamCountsText, boardSummaryHTML } from '../Resources/web/task-board.js';

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

test('waiting column: ready numbered cards first, then unnumbered oldest first, then cards that must wait', () => {
  const t = { cards: [
    card('k-1', 'queued', { owner: null, created: iso(now - 5_000) }),
    card('k-2', 'queued', { owner: null, priority: 2 }),
    card('k-3', 'queued', { owner: null, priority: 1, after: ['k-9'], waitingOn: ['k-9'] }),
    card('k-4', 'queued', { owner: null, created: iso(now - 9_000) }),
    card('k-5', 'queued', { owner: null, priority: 1 }),
    card('k-9', 'working', { title: 'Remove secrets' }),
  ] };
  const queued = boardColumns(t, now)[0].cards;
  assert.deepEqual(queued.map(c => c.id), ['k-5', 'k-2', 'k-4', 'k-1', 'k-3']);
  assert.equal(queued[0].priority, 1);
  assert.equal(queued[2].priority, null);
  assert.deepEqual(queued.at(-1).waitingOn, [{ id: 'k-9', title: 'Remove secrets' }]);
});

test('other columns keep the most recently changed first', () => {
  const t = { cards: [card('k-1', 'working', { priority: 1, updated: iso(now - 90_000) }), card('k-2', 'working', { priority: 2 })] };
  assert.deepEqual(boardColumns(t, now)[1].cards.map(c => c.id), ['k-2', 'k-1']);
});

test('a card shows its number and what it waits for, without emoji', () => {
  const copy = key => ({ boardWaitingOn: '{title} 끝나야 시작', boardPriority: '우선순위 {n}' })[key] || key;
  const esc = s => String(s).replace(/</g, '&lt;');
  const numbered = boardCardHTML({ id: 'k-5', title: 'A', owner: null, ageMs: 0, doneOf: [0, 1], blocker: null, priority: 2, waitingOn: [] }, x => x, () => '', esc, copy);
  assert.match(numbered, /<span class="board-card-priority" aria-label="우선순위 2">2<\/span>/);
  const locked = boardCardHTML({ id: 'k-3', title: 'B', owner: null, ageMs: 0, doneOf: [0, 1], blocker: null, priority: null,
    waitingOn: [{ id: 'k-9', title: '<x>' }] }, x => x, () => '', esc, copy);
  assert.match(locked, /data-waiting="true"/);
  assert.match(locked, /<span class="board-card-waiting"><svg[^>]*aria-hidden="true"[\s\S]*<\/svg>&lt;x> 끝나야 시작<\/span>/);
  assert.doesNotMatch(numbered + locked, /[①-⓿\u{1F300}-\u{1FAFF}]/u);
});

test('the collapsed board shows one line of per-column counts, each column labelled and coloured by state', () => {
  const copy = key => ({boardQueued:'대기', boardWorking:'진행', boardReview:'검토', boardBlocked:'막힘', boardDone:'완료'})[key] || key;
  const columns = [{state:'queued', cards:[{}, {}]}, {state:'working', cards:[{}]}, {state:'review', cards:[]}, {state:'blocked', cards:[{}]}, {state:'done', cards:[]}];
  const html = boardSummaryHTML(columns, copy);
  assert.equal((html.match(/class="board-chip"/g) || []).length, 5);
  assert.match(html, /<span class="board-chip" data-board-state="queued">대기 <b>2<\/b><\/span>/);
  assert.match(html, /data-board-state="blocked">막힘 <b>1<\/b>/);
  assert.match(html, /data-board-state="review" data-empty="true">검토 <b>0<\/b>/);
});

test('a finished card stays only while its worker is still there', () => {
  const t = { cards: [card('d-1', 'done', { owner: { address: 't2' } }), card('d-2', 'done', { owner: { address: 't9' } }),
    card('d-3', 'done', { owner: null }), card('w-1', 'working', { owner: { address: 't9' } })] };
  const live = owner => owner?.address === 't2';
  const cols = boardColumns(t, now, { ownerLive: live });
  assert.deepEqual(cols.at(-1).cards.map(c => c.id), ['d-1']);
  assert.deepEqual(cols[1].cards.map(c => c.id), ['w-1']);   // only finished cards are dropped
  assert.equal(boardColumns(t, now).at(-1).cards.length, 3);   // without the check, as before
});
