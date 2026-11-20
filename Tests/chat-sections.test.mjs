import assert from 'node:assert/strict';
import { test } from 'node:test';
import { shortRoleTitle, nextKey, groupRows, moveChat, moveSection, toggleSection, addSection, renameSection, deleteSection } from '../Resources/web/chat-sections.js';

const rows = [{ key: 'a', at: 1 }, { key: 'b', at: 5 }, { key: 'c', at: 3 }, { key: 'd', at: 4 }];
const empty = { order: [], collapsed: [] };

test('old section data without a section store keeps its sections, unassigned last', () => {
  const prefs = new Map([['a', { section: 'Work' }], ['c', { section: 'Work' }]]);
  const groups = groupRows(rows, prefs, empty);
  assert.deepEqual(groups.map(g => [g.name, g.unassigned, g.items.map(r => r.key)]),
    [['Work', false, ['c', 'a']], ['', true, ['b', 'd']]]);
});

test('sections follow stored order, then names, and empty created sections stay', () => {
  const prefs = new Map([['a', { section: 'Zeta' }], ['b', { section: 'Alpha' }]]);
  const groups = groupRows(rows, prefs, { order: ['Zeta', 'Empty'], collapsed: ['Zeta'] });
  assert.deepEqual(groups.map(g => g.name), ['Zeta', 'Empty', 'Alpha', '']);
  assert.equal(groups[0].collapsed, true);
  assert.deepEqual(groups[1].items, []);
});

test('ranked chats come first in rank order, the rest newest first', () => {
  const prefs = new Map([['a', { rank: 2 }], ['c', { rank: 1 }]]);
  assert.deepEqual(groupRows(rows, prefs, empty).at(-1).items.map(r => r.key), ['c', 'a', 'b', 'd']);
});

test('moveChat inserts before a chat and renumbers the section', () => {
  const prefs = new Map([['a', { section: 'Work', unread: true }], ['c', { section: 'Work' }]]);
  const next = moveChat(prefs, 'b', 'Work', ['c', 'a'], 'a');
  assert.deepEqual(['c', 'b', 'a'].map(k => next.get(k).rank), [1, 2, 3]);
  assert.equal(next.get('b').section, 'Work');
  assert.equal(next.get('a').unread, true);
  assert.equal(prefs.get('b'), undefined);
});

test('moveChat to the end and to unassigned', () => {
  const prefs = new Map([['a', { section: 'Work' }]]);
  const next = moveChat(prefs, 'a', '', ['b', 'd'], null);
  assert.equal(next.get('a').section, undefined);
  assert.deepEqual(['b', 'd', 'a'].map(k => next.get(k).rank), [1, 2, 3]);
});

test('moveSection reorders and adds unknown names', () => {
  assert.deepEqual(moveSection({ order: ['A', 'B', 'C'], collapsed: [] }, 'C', 'A').order, ['C', 'A', 'B']);
  assert.deepEqual(moveSection({ order: ['A'], collapsed: [] }, 'New', null).order, ['A', 'New']);
});

test('toggleSection and addSection', () => {
  const once = toggleSection(empty, 'A');
  assert.deepEqual(once.collapsed, ['A']);
  assert.deepEqual(toggleSection(once, 'A').collapsed, []);
  assert.deepEqual(addSection(addSection(empty, 'A'), 'A').order, ['A']);
  assert.deepEqual(addSection(empty, '  ').order, []);
});

test('renameSection moves chats and order; deleteSection unassigns chats', () => {
  const prefs = new Map([['a', { section: 'Old', rank: 1 }], ['b', { section: 'Keep' }]]);
  const [renamed, sections] = renameSection(prefs, { order: ['Old', 'Keep'], collapsed: ['Old'] }, 'Old', 'New');
  assert.equal(renamed.get('a').section, 'New');
  assert.deepEqual(sections, { order: ['New', 'Keep'], collapsed: ['New'] });
  const [deleted, after] = deleteSection(renamed, sections, 'New');
  assert.equal(deleted.get('a').section, undefined);
  assert.equal(deleted.get('a').rank, undefined);
  assert.deepEqual(after.order, ['Keep']);
});

test('nextKey skips the dragged item so dropping below its upper neighbour stays in place', () => {
  assert.equal(nextKey(['a', 'b', 'c'], 'a', 'b'), 'c');
  assert.equal(nextKey(['a', 'b', 'c'], 'b', 'a'), 'c');
  assert.equal(nextKey(['a', 'b'], 'b', 'x'), null);
  assert.equal(nextKey(['a', 'b'], 'a', 'b'), null);
});

test('unranked team rooms come before personal chats', () => {
  const mixed = [{ key: 'd1', at: 9 }, { key: 'r1', at: 1, room: 'shop' }, { key: 'd2', at: 5 }, { key: 'r2', at: 3, room: 'cafe' }];
  assert.deepEqual(groupRows(mixed, new Map(), empty).at(-1).items.map(r => r.key), ['r2', 'r1', 'd1', 'd2']);
  const ranked = new Map([['d2', { rank: 1 }]]);
  assert.deepEqual(groupRows(mixed, ranked, empty).at(-1).items.map(r => r.key), ['d2', 'r2', 'r1', 'd1']);
});

test('shortRoleTitle drops the team name or its shared first word', () => {
  assert.equal(shortRoleTitle('숍 총괄', '숍'), '총괄');
  assert.equal(shortRoleTitle('HerdrDesk 총괄', 'HerdrDesk 개발팀'), '총괄');
  assert.equal(shortRoleTitle('지휘본부 · 비서', '지휘본부'), '비서');
  assert.equal(shortRoleTitle('제작', '숍'), '제작');
  assert.equal(shortRoleTitle('숍', '숍'), '숍');
  assert.equal(shortRoleTitle('이미지 담당', ''), '이미지 담당');
});

test('an ended conversation is hidden until the user shows it', async () => {
  const { chatHidden } = await import('../Resources/web/chat-sections.js');
  assert.equal(chatHidden({ key: 'live' }, undefined), false);
  assert.equal(chatHidden({ key: 'gone', archived: true }, undefined), true);
  assert.equal(chatHidden({ key: 'gone', archived: true }, { hidden: false }), false);
  assert.equal(chatHidden({ key: 'live' }, { hidden: true }), true);
});

test('each team shows once: its lead chat folds into the team room, pins move with it', async () => {
  const { foldLeadChats } = await import('../Resources/web/chat-sections.js');
  const rows = [{ key: 'room:kk' }, { key: 'direct:kk-lead' }, { key: 'direct:other' }, { key: 'room:hd' }];
  const leadToRoom = new Map([['direct:kk-lead', 'room:kk']]);
  const out = foldLeadChats(rows, ['direct:kk-lead', 'direct:other', 'room:kk'], leadToRoom);
  assert.deepEqual(out.rows.map(r => r.key), ['room:kk', 'direct:other', 'room:hd']);
  assert.deepEqual(out.pins, ['room:kk', 'direct:other']);
  assert.equal(out.changed, true);
  assert.equal(foldLeadChats(rows, ['direct:other'], leadToRoom).changed, false);
});

test('the team room also shows what I once sent to the lead directly', async () => {
  const { inRoomConversation } = await import('../Resources/web/chat-sections.js');
  assert.equal(inRoomConversation({ conversationId: 'room:kk' }, 'kk', 'direct:kk-lead'), true);
  assert.equal(inRoomConversation({ conversationId: 'direct:kk-lead' }, 'kk', 'direct:kk-lead'), true);
  assert.equal(inRoomConversation({ conversationId: 'direct:other' }, 'kk', 'direct:kk-lead'), false);
  assert.equal(inRoomConversation({ conversationId: 'direct:kk-lead' }, 'kk', null), false);
});
