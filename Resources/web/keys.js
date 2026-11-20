// What an Enter keydown in the composer means. Pure, so the IME rules are tested.
//  'ime'     – an input method (Korean, Japanese, …) is composing: leave it alone, never send
//  'swallow' – the Enter WebKit can deliver right after compositionend (it only committed the syllable)
//  'newline' – Shift+Enter
//  'send'    – Enter, ⌘↩ or Ctrl+↩
export const COMMIT_ECHO_MS = 120;
export function enterAction(e, composing, msSinceCompositionEnd) {
  if (e.key !== 'Enter') return 'other';
  if (e.isComposing || composing || e.keyCode === 229) return 'ime';
  if (msSinceCompositionEnd < COMMIT_ECHO_MS) return 'swallow';
  if (e.shiftKey) return 'newline';
  return 'send';
}
