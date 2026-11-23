import {test} from 'node:test';
import assert from 'node:assert/strict';
import {freshEntries} from '../Resources/web/motion.js';

test('opening a conversation animates nothing but remembers what is already there', () => {
  const seen = new Map();
  assert.deepEqual(freshEntries('chat:a', ['m1', 'm2'], seen), []);
  assert.deepEqual([...seen.get('chat:a')], ['m1', 'm2']);
});

test('only messages that arrive after that animate, once', () => {
  const seen = new Map();
  freshEntries('chat:a', ['m1'], seen);
  assert.deepEqual(freshEntries('chat:a', ['m1', 'm2'], seen), ['m2']);
  assert.deepEqual(freshEntries('chat:a', ['m1', 'm2'], seen), [], 'a re-render does not replay it');
});

test('each conversation keeps its own memory, and empty ids never animate', () => {
  const seen = new Map();
  freshEntries('chat:a', ['m1'], seen);
  assert.deepEqual(freshEntries('chat:b', ['m9'], seen), [], 'first view of b');
  assert.deepEqual(freshEntries('chat:a', ['m1', '', 'm3'], seen), ['m3']);
});
