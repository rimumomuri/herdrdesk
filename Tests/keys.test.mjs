import {test} from 'node:test';
import assert from 'node:assert/strict';
import {enterAction, COMMIT_ECHO_MS} from '../Resources/web/keys.js';

const key = (extra = {}) => ({key: 'Enter', keyCode: 13, isComposing: false, shiftKey: false, ...extra});

test('plain Enter sends, Shift+Enter is a new line, other keys are ignored', () => {
  assert.equal(enterAction(key(), false, Infinity), 'send');
  assert.equal(enterAction(key({shiftKey: true}), false, Infinity), 'newline');
  assert.equal(enterAction({key: 'a'}, false, Infinity), 'other');
});

test('Korean: one Enter commits the last syllable and sends, whichever order WebKit reports it in', () => {
  // Enter arrives while the syllable is still composing: send once the commit lands
  assert.equal(enterAction(key({isComposing: true, keyCode: 229}), true, Infinity, '녕'), 'sendAfterCommit');
  // Enter arrives just after the commit (the echo): that is the person's Enter, send now
  assert.equal(enterAction(key(), false, 30, '안녕'), 'send');
  assert.equal(enterAction(key({keyCode: 229}), false, 30, '녕'), 'send');
  assert.equal(enterAction(key({shiftKey: true}), false, 30, '녕'), 'newline');
});

test('Japanese and other input methods: the Enter that confirms a conversion never sends', () => {
  assert.equal(enterAction(key({isComposing: true, keyCode: 229}), true, Infinity, 'にほんご'), 'ime');
  assert.equal(enterAction(key({keyCode: 229}), false, 30, '日本語'), 'ime');
  assert.equal(enterAction(key(), false, 30, '日本語'), 'swallow');
  assert.equal(enterAction(key(), false, COMMIT_ECHO_MS + 1, '日本語'), 'send', 'a later Enter sends');
});
