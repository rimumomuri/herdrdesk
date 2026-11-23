// Message box helpers kept cheap enough to run on every keystroke. Pure: no DOM.

/** True when the send button must stay disabled. */
export function sendBlocked({inputDisabled, text, files, loadingFiles, sending}) {
  return inputDisabled || (!String(text || '').trim() && !files) || loadingFiles > 0 || sending;
}

/** Coalesces many save requests into one write after `delay` ms; flush() writes a pending save now. */
export function deferredSaver(write, delay, timers = {set:setTimeout, clear:clearTimeout}) {
  let timer = null;
  const run = () => { timer = null; write(); };
  return {
    schedule() { if (timer === null) timer = timers.set(run, delay); },
    flush() { if (timer === null) return; timers.clear(timer); run(); },
  };
}
