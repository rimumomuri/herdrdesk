import assert from 'node:assert/strict';
import { test } from 'node:test';
import { chatImageMarkup, ChatImagePreviews } from '../Resources/web/chat-images.js';

const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aFKsAAAAASUVORK5CYII=';

test('shown images carry their message token and place, so the viewer can page through them', () => {
  const html = chatImageMarkup([{ name: 'a.png', thumbnail: png }, { name: 'b.png', thumbnail: png }], 'image7');
  assert.match(html, /<div class="chat-images" data-chat-images="image7">/);
  assert.match(html, /<figure class="chat-image" data-index="0"[^>]*>/);
  assert.match(html, /<figure class="chat-image" data-index="1"[^>]*>/);
  assert.doesNotMatch(chatImageMarkup([{ name: 'a', thumbnail: png }]), /data-chat-images/);   // no token, as before
});

test('asking for a viewer-size image names the already shown record, never a path', () => {
  const sent = [];
  const client = new ChatImagePreviews(message => sent.push(message), () => {});
  const record = { id: 'r1', role: 'lead', session: '1:2', body: '![x](/Users/demo/Pictures/a.png)' };
  const token = client.markup(record).match(/data-chat-preview="([^"]+)"/)[1];
  client.large(token, 0);
  assert.deepEqual(sent, [{ type: 'chatImageLarge', token, index: 0, id: 'r1', role: 'lead', session: '1:2', body: record.body }]);
  client.large('missing', 0); client.large(token, 9);
  assert.equal(sent.length, 1);
});
