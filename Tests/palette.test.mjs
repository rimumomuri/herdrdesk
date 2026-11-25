import {test} from 'node:test';
import assert from 'node:assert/strict';
import {filterPalette, paletteHTML} from '../Resources/web/palette.js';

const items = [
  {id: 'chat:room:kunkun', kind: 'chat', label: '킁킁맵', detail: '팀 · 총괄'},
  {id: 'chat:direct:t3', kind: 'chat', label: 'Builder', detail: 'Storefront'},
  {id: 'chat:direct:t4', kind: 'chat', label: 'Reviewer', detail: 'Storefront'},
  {id: 'computer:m6', kind: 'computer', label: 'M6 맥북', detail: '작업자'},
  {id: 'action:next', kind: 'action', label: '다음 급한 곳', detail: '⌘J'},
];

test('an empty query lists actions first, then everything else in order', () => {
  assert.deepEqual(filterPalette(items, '').map(item => item.id), ['action:next', 'chat:room:kunkun', 'chat:direct:t3', 'chat:direct:t4', 'computer:m6']);
});

test('matches on name or detail, case-insensitively; names that start with the query come first', () => {
  assert.deepEqual(filterPalette(items, 'store').map(item => item.id), ['chat:direct:t3', 'chat:direct:t4']);
  assert.deepEqual(filterPalette(items, 'RE').map(item => item.id), ['chat:direct:t4', 'chat:direct:t3']);
  assert.deepEqual(filterPalette(items, '킁킁').map(item => item.id), ['chat:room:kunkun']);
  assert.deepEqual(filterPalette(items, 'm6').map(item => item.id), ['computer:m6']);
  assert.deepEqual(filterPalette(items, 'zzz'), []);
});

test('every word must match somewhere', () => {
  assert.deepEqual(filterPalette(items, 'rev store').map(item => item.id), ['chat:direct:t4']);
});

test('the list caps at 12 and marks the selected row', () => {
  const many = Array.from({length: 20}, (_, n) => ({id: 'c' + n, kind: 'chat', label: 'Agent ' + n, detail: ''}));
  assert.equal(filterPalette(many, 'agent').length, 12);
  const escape = text => String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
  const html = paletteHTML([{id: 'a<', kind: 'chat', label: 'A<b', detail: 'x'}], 0, key => key, escape);
  assert.match(html, /role="option" aria-selected="true" data-palette="a&lt;"/);
  assert.match(html, /A&lt;b/);
});
