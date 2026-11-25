import {test} from 'node:test';
import assert from 'node:assert/strict';
import {questionFormHTML, questionFilesHTML, keepTyping} from '../Resources/web/chat-questions.js';

const copy = key => ({answerHint:'답변 입력', answer:'답변', openApproval:'승인 창 열기', approvalUnavailable:'승인 창 없음', answerNeeded:'답변 필요'})[key] || key;
const escape = text => String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const q = {id:'q1', ask:'어느 쪽으로 할까요?', choices:['A안', 'B안'], state:'answerNeeded', answerable:true};

test('an answerable question carries its text, choices, a draft field and a send button in the chat', () => {
  const html = questionFormHTML(q, {label:'킁킁 총괄', canAnswer:true, feedback:'answerNeeded', draft:'초안<'}, copy, escape);
  assert.match(html, /^<form class="question chat-question" data-question="q1">/);
  assert.match(html, /킁킁 총괄/);
  assert.match(html, /어느 쪽으로 할까요\?/);
  assert.match(html, /data-choice="A안"/);
  assert.match(html, /data-choice="B안"/);
  assert.match(html, /<textarea name="answer"[^>]*>초안&lt;<\/textarea>/);
  assert.match(html, /<button type="submit">답변<\/button>/);
});

test('a question that cannot be answered now shows only its text', () => {
  const html = questionFormHTML(q, {label:'킁킁 총괄', canAnswer:false, feedback:'sending'}, copy, escape);
  assert.doesNotMatch(html, /textarea|type="submit"/);
  assert.match(html, /sending/);
});

test('an approval question offers to open the approval terminal, disabled when it is gone', () => {
  const approval = {...q, approval:{address:'t9', role:'kunkun-codex-lead'}};
  assert.match(questionFormHTML(approval, {label:'x', canAnswer:false, feedback:'answerNeeded', approvalLabel:'킁킁 총괄', live:true}, copy, escape),
    /<button type="button" data-approval >승인 창 열기 · 킁킁 총괄<\/button>/);
  assert.match(questionFormHTML(approval, {label:'x', canAnswer:false, feedback:'answerNeeded', live:true}, copy, escape),
    /data-approval disabled>승인 창 없음 · kunkun-codex-lead/);
});

test('a focused answer field is kept only while that question can still be answered', () => {
  const requests = [q];
  assert.equal(keepTyping(requests, 'q1', true, new Set()), true);
  assert.equal(keepTyping(requests, 'q1', false, new Set()), false, 'connection dropped');
  assert.equal(keepTyping([{...q, answerable:false}], 'q1', true, new Set()), false, 'agent can no longer take it');
  assert.equal(keepTyping(requests, 'q1', true, new Set(['q1'])), false, 'already sending');
  assert.equal(keepTyping(requests, 'other', true, new Set()), false, 'not in this chat');
  assert.equal(keepTyping(requests, undefined, true, new Set()), false);
});

test('an answerable question can carry images: a picker, the asker\'s attached images and a remove button for each', () => {
  const files = [{id:'img1', name:'screen<.png', thumbnail:'QUJD'}];
  const html = questionFormHTML(q, {label:'x', canAnswer:true, feedback:'answerNeeded', files, filesKey:'t3:800:7'}, copy, escape);
  assert.match(html, /<button type="button" class="question-attach" data-question-attach[^>]*>/);
  assert.match(html, /<input type="file" accept="image\/\*" multiple hidden data-question-file>/);
  assert.match(html, /data-question-files="t3:800:7"/);
  assert.match(html, /<img src="data:image\/png;base64,QUJD" alt="">/);
  assert.match(html, /screen&lt;\.png/);
  assert.match(html, /data-question-remove="img1"/);
});

test('the image list is empty and the picker is off while images are still being added', () => {
  assert.equal(questionFilesHTML([], false, copy, escape), '');
  assert.match(questionFilesHTML([{id:'a', name:'a.png', thumbnail:''}], true, copy, escape), /data-question-remove="a"[^>]* disabled/);
  const busy = questionFormHTML(q, {label:'x', canAnswer:true, feedback:'answerNeeded', files:[], filesKey:'k', attachBusy:true}, copy, escape);
  assert.match(busy, /data-question-attach[^>]* disabled/);
});

test('a question that cannot be answered has no image picker', () => {
  assert.doesNotMatch(questionFormHTML(q, {label:'x', canAnswer:false, feedback:'sending', files:[{id:'a',name:'a',thumbnail:''}]}, copy, escape), /data-question-attach|data-question-files/);
});

test('a recommended answer shows on the card and in the empty field\'s hint', () => {
  const html = questionFormHTML({...q, recommend: 'A안<'}, {label:'x', canAnswer:true, feedback:'answerNeeded'}, key => ({recommended:'추천', answerHintRecommend:'Enter로 추천대로 답하기: {answer}'})[key] || copy(key), escape);
  assert.match(html, /<p class="question-recommend"[^>]*>추천 · <b>A안&lt;<\/b><\/p>/);
  assert.match(html, /placeholder="Enter로 추천대로 답하기: A안&lt;"/);
  assert.match(html, /data-recommend="A안&lt;"/);
});
