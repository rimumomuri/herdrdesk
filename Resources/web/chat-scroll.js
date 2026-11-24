// Keeps a chat scrolled to the newest message while the person is at the bottom, and leaves it alone once they scroll up.
// Works on any element with scrollTop/scrollHeight/clientHeight and addEventListener (no other DOM use).

const NEAR = 48;

/** onState({stuck, unseen}) runs when either changes: stuck = following the bottom, unseen = new messages arrived while scrolled up. */
export function stickyScroll(box, {onState} = {}) {
  let stuck = true, unseen = false;
  const nearBottom = () => box.scrollHeight - box.scrollTop - box.clientHeight < NEAR;
  const set = (nextStuck, nextUnseen) => {
    if (nextStuck === stuck && nextUnseen === unseen) return;
    stuck = nextStuck; unseen = nextUnseen;
    onState?.({stuck, unseen});
  };
  const jump = () => { box.scrollTop = box.scrollHeight; };
  box.addEventListener('scroll', () => { const near = nearBottom(); set(near, near ? false : unseen); });
  box.addEventListener('load', () => { if (stuck) jump(); }, true);   // images load after the text and push it up
  return {
    state: () => ({stuck, unseen}),
    toBottom() { jump(); set(true, false); },
    /** After a render. isNew: a message was added (marks unseen while scrolled up); otherwise only the height may have changed. */
    contentChanged(isNew) {
      if (stuck) jump();
      else if (isNew) set(false, true);
    },
  };
}
