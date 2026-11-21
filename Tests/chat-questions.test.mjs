import {test} from 'node:test';
import assert from 'node:assert/strict';
import {questionFormHTML} from '../Resources/web/chat-questions.js';

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
