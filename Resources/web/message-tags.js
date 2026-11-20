// Six plain tags so every line in a conversation reads at a glance:
// sent (mine) · progress · handoff · addon · result · answer. Pure: no DOM.

const TAGS = {
  sent: 'sent', sending: 'sent', needsCheck: 'sent', notSent: 'sent', refused: 'sent',
  progress: 'progress', 'card:progress': 'progress',
  'card:assign': 'handoff', assignment: 'handoff', incomingHandoff: 'handoff', outgoingHandoff: 'handoff',
  'card:message': 'addon', 'card:pending': 'addon',
  'card:reply': 'result', handoffReply: 'result',
  reply: 'answer',
};

export const TAG_LABEL = { sent: 'tagSent', progress: 'tagProgress', handoff: 'tagHandoff', addon: 'tagAddon', result: 'tagResult', answer: 'tagAnswer' };

/** The tag for a chat entry state, feed row kind, or `card:<kind>`; null when it is none of the six. */
export function messageTag(kind) {
  return Object.prototype.hasOwnProperty.call(TAGS, kind) ? TAGS[kind] : null;
}

/** True while nothing from the other side (progress, card or answer) has appeared after my message. */
export function awaitingResponse(entries, index) {
  const at = entries[index]?.at || 0;
  return !entries.slice(index + 1).some(entry => (entry.card || entry.from) && (entry.at || entry.card?.at || 0) >= at);
}

export function tagHTML(tag, copy, escape) {
  return tag ? '<b class="msg-tag" data-tag="' + escape(tag) + '">' + escape(copy(TAG_LABEL[tag])) + '</b>' : '';
}
