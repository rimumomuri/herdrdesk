import {test} from 'node:test';
import assert from 'node:assert/strict';
import {messageTag, awaitingResponse} from '../Resources/web/message-tags.js';

test('every message is one of six plain tags', () => {
  assert.equal(messageTag('sent'), 'sent');
  assert.equal(messageTag('sending'), 'sent');
  assert.equal(messageTag('progress'), 'progress');
  assert.equal(messageTag('card:assign'), 'handoff');
  assert.equal(messageTag('assignment'), 'handoff');
  assert.equal(messageTag('card:message'), 'addon');
  assert.equal(messageTag('card:pending'), 'addon');
  assert.equal(messageTag('card:reply'), 'result');
  assert.equal(messageTag('handoffReply'), 'result');
  assert.equal(messageTag('card:progress'), 'progress');
  assert.equal(messageTag('reply'), 'answer');
  assert.equal(messageTag('something-else'), null);
});

test('a sent message waits only until the other side shows anything after it', () => {
  const mine = {at: 10, state: 'sent'};
  assert.equal(awaitingResponse([mine], 0), true);
  assert.equal(awaitingResponse([mine, {at: 12, state: 'progress', from: 'lead'}], 0), false);
  assert.equal(awaitingResponse([{at: 5, state: 'reply', from: 'lead'}, mine], 1), true);
  assert.equal(awaitingResponse([mine, {at: 12, card: {}}], 0), false);
});
