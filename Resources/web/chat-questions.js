// A registered question shown inside the conversation it came from, answered there. Pure: no DOM.

/** view: {label, canAnswer, feedback, draft, approvalLabel, live}. approvalLabel is set only while the approval terminal exists. */
export function questionFormHTML(q, view, copy, escape) {
  const answer = view.canAnswer
    ? '<textarea name="answer" aria-label="' + copy('answerHint') + '" placeholder="' + copy('answerHint') + '" maxlength="2000" rows="2">'
      + escape(view.draft || '') + '</textarea><div class="controls">'
      + (q.choices || []).map(choice => '<button type="button" data-choice="' + escape(choice) + '">' + escape(choice) + '</button>').join('')
      + '<button type="submit">' + copy('answer') + '</button></div>'
    : '';
  const approval = q.approval
    ? '<button type="button" data-approval ' + (view.live && view.approvalLabel ? '' : 'disabled') + '>'
      + copy(view.approvalLabel ? 'openApproval' : 'approvalUnavailable') + ' · ' + escape(view.approvalLabel || q.approval.role) + '</button>'
    : '';
  return '<form class="question chat-question" data-question="' + q.id + '"><div><strong>' + escape(view.label) + '</strong><small> · '
    + copy(view.feedback) + '</small></div><p>' + escape(q.ask) + '</p>' + answer + approval + '</form>';
}

/** Skip re-rendering the chat's question cards while the person types in one that can still be answered as shown. */
export function keepTyping(requests, focusedId, live, sending) {
  return live && !sending.has(focusedId) && requests.some(q => q.id === focusedId && q.answerable);
}
