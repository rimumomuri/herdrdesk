// What an Enter keydown in the composer means. Pure, so the IME rules are tested.
//  'ime'             – an input method is composing (or confirming a conversion): leave it alone, never send
//  'sendAfterCommit' – Korean: Enter arrived while the last syllable was composing; send once the commit lands
//  'swallow'         – the Enter WebKit can deliver right after a non-Korean commit (it only confirmed a conversion)
//  'newline'         – Shift+Enter
//  'send'            – Enter, ⌘↩ or Ctrl+↩
// Korean has no conversion to confirm: the Enter that commits a syllable is the person's send, so one press is enough.
// `text` is the composition's latest text (compositionupdate / compositionend data).
export const COMMIT_ECHO_MS = 120;
const HANGUL = /[ᄀ-ᇿㄱ-ㆎ가-힣]$/;
export function enterAction(e, composing, msSinceCompositionEnd, text = '') {
  if (e.key !== 'Enter') return 'other';
  const korean = HANGUL.test(text || '');
  if (e.isComposing || composing) return korean && !e.shiftKey ? 'sendAfterCommit' : 'ime';
  if (msSinceCompositionEnd < COMMIT_ECHO_MS) return korean ? (e.shiftKey ? 'newline' : 'send') : e.keyCode === 229 ? 'ime' : 'swallow';
  if (e.keyCode === 229) return 'ime';
  if (e.shiftKey) return 'newline';
  return 'send';
}

/** One Enter can reach both the composing keydown and the commit echo: a second send within this window is the same press. */
export const SEND_DEDUPE_MS = 400;
