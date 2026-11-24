// A registered question shown inside the conversation it came from, answered there. Pure: no DOM.

const IMAGE = '<svg viewBox="0 0 16 16" aria-hidden="true"><rect x="2" y="3" width="12" height="10" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.4"/>'
  + '<circle cx="6" cy="6.5" r="1.2" fill="currentColor"/><path d="M3 12l3.5-3.5 2.5 2.5 2-2 2 2" fill="none" stroke="currentColor" stroke-width="1.4"/></svg>';

/** The asker's attached images inside its question card: a thumbnail, the name and a remove button each. */
export function questionFilesHTML(files, busy, copy, escape) {
  return (files || []).map(file => '<span class="attachment-item">'
    + (file.thumbnail ? '<img src="data:image/png;base64,' + file.thumbnail + '" alt="">' : '')
    + '<span>' + escape(file.name) + '</span><button type="button" data-question-remove="' + escape(file.id) + '" aria-label="'
    + copy('removeAttachment') + ' · ' + escape(file.name) + '"' + (busy ? ' disabled' : '') + '>×</button></span>').join('');
}

/** view: {label, canAnswer, feedback, draft, approvalLabel, live, files, filesKey, attachBusy}. approvalLabel is set only while the
 * approval terminal exists. files are the asker's attached images (its conversation's tray), sent with the answer. */
export function questionFormHTML(q, view, copy, escape) {
  const answer = view.canAnswer
    ? '<textarea name="answer" aria-label="' + copy('answerHint') + '" placeholder="' + copy('answerHint') + '" maxlength="2000" rows="2">'
      + escape(view.draft || '') + '</textarea>'
      + '<div class="attachment-list question-files" data-question-files="' + escape(view.filesKey || '') + '">'
      + questionFilesHTML(view.files, view.attachBusy, copy, escape) + '</div><div class="controls">'
      + '<button type="button" class="question-attach" data-question-attach aria-label="' + copy('attachImage') + '" title="' + copy('attachImage') + '"'
      + (view.attachBusy ? ' disabled' : '') + '>' + IMAGE + '</button><input type="file" accept="image/*" multiple hidden data-question-file>'
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
