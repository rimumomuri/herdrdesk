import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {approvalSignature, approvalDock, approvalHeadHTML, keepHidden} from '../Resources/web/chat-questions.js';

const copy = key => ({approvalWaitingTitle:'답변 대기', approvalHide:'숨기기', approvalShow:'다시 보기'})[key] || key;

test('the signature names what is waiting: questions by id, else a login/limit, else a blocked agent', () => {
  assert.equal(approvalSignature({requests:[{id:'q1'},{id:'q2'}]}), 'q:q1,q2');
  assert.equal(approvalSignature({requests:[], troubled:'s1', kind:'login'}), 'trouble:login:s1');
  assert.equal(approvalSignature({requests:[], waiting:'s2'}), 'waiting:s2');
  assert.equal(approvalSignature({requests:[]}), '');
});

test('nothing waiting shows neither the popup nor the pill', () => {
  assert.deepEqual(approvalDock('', null), {popup:false, pill:false});
  assert.deepEqual(approvalDock('', 'q:q1'), {popup:false, pill:false});
});

test('a waiting item pops up until it is hidden; hidden it leaves only the pill', () => {
  assert.deepEqual(approvalDock('q:q1', null), {popup:true, pill:false});
  assert.deepEqual(approvalDock('q:q1', 'q:q1'), {popup:false, pill:true});
});

test('a new item pops up again even after the earlier one was hidden', () => {
  assert.deepEqual(approvalDock('q:q1,q2', 'q:q1'), {popup:true, pill:false});
});

test('the popup head shows the count and a hide button', () => {
  const html = approvalHeadHTML(2, copy);
  assert.match(html, /답변 대기/);
  assert.match(html, /<b class="approval-count">2<\/b>/);
  assert.match(html, /data-approval-hide/);
  assert.match(html, /숨기기/);
});

test('the popup floats over the chat instead of taking space in it, and a pill brings it back', () => {
  const html = readFileSync(new URL('../Resources/web/index.html', import.meta.url), 'utf8');
  assert.match(html, /<button type="button" id="approvalPill"[^>]*hidden/);
  const css = readFileSync(new URL('../Resources/web/app.css', import.meta.url), 'utf8');
  assert.match(css, /#inlineApproval \{[^}]*position:absolute/);
  assert.match(css, /#approvalPill \{[^}]*position:absolute/);
});

test('the top waiting list floats too, with a hide button and a pill in the top bar to bring it back', () => {
  const html = readFileSync(new URL('../Resources/web/index.html', import.meta.url), 'utf8');
  assert.match(html, /id="waitingInboxHide"/);
  assert.match(html, /<header class="top">[^\n]*<button type="button" id="waitingInboxPill"[^>]*hidden/);
  const css = readFileSync(new URL('../Resources/web/app.css', import.meta.url), 'utf8');
  assert.match(css, /\.waiting-inbox\{[^}]*position:fixed/);
});

test('hiding lasts only while the same item waits: once it clears, a later wait from the same agent pops up', () => {
  let hidden = 'waiting:s1';
  hidden = keepHidden('waiting:s1', hidden);
  assert.equal(hidden, 'waiting:s1');
  hidden = keepHidden('', hidden);            // the block cleared
  assert.equal(hidden, null);
  assert.deepEqual(approvalDock('waiting:s1', hidden), {popup:true, pill:false});
  assert.equal(keepHidden('waiting:s2', 'waiting:s1'), null);
});
