// The floating companion page: draws the state the main page computed (relayed by Swift). It reads no data and takes no actions.

const CHECK = '<svg viewBox="0 0 12 12" width="11" height="11" aria-hidden="true"><path d="M2.5 6.2 5 8.6l4.5-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const ARROW = '<svg viewBox="0 0 12 12" width="11" height="11" aria-hidden="true"><path d="M2 6h7.5M6.5 3l3 3-3 3" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const UNPLUGGED = '<svg viewBox="0 0 12 12" width="10" height="10" aria-hidden="true"><path d="M2 2l8 8M4 7.5 2.5 9M8 4.5 9.5 3M5 3.5l3.5 3.5-1.2 1.2a2 2 0 0 1-2.8 0l-.7-.7a2 2 0 0 1 0-2.8z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>';
const NUDGE_EVERY = 60_000;

const root = document.getElementById('companion');
const escapeText = text => String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
let current = null, nudgeTimer = null;

function nudge() {
  root.classList.remove('nudge');
  void root.offsetWidth;   // restart the animation
  root.classList.add('nudge');
}

window.companion = {
  /** state: {mood, count, working, flash, lines} */
  show(state) {
    const moodChanged = current?.mood !== state.mood;
    const newFlash = state.flash && state.flash !== current?.flash;
    root.hidden = false;
    root.dataset.mood = state.mood;
    if (moodChanged || newFlash || !root.querySelector('.sheep'))
      document.getElementById('companionSheep').innerHTML = sheep(newFlash ? (state.flash === 'handoff' ? 'handoff' : 'notice') : 'still');
    const badge = document.getElementById('companionBadge');
    badge.hidden = !['attention', 'working', 'offline'].includes(state.mood);
    badge.innerHTML = state.mood === 'offline' ? UNPLUGGED : String(state.mood === 'attention' ? state.count : state.working);
    const flash = document.getElementById('companionFlash');
    flash.hidden = !state.flash;
    flash.dataset.kind = state.flash || '';
    flash.innerHTML = state.flash === 'handoff' ? ARROW : state.flash ? CHECK : '';
    document.getElementById('companionBubble').innerHTML = (state.lines || []).slice(0, 4).map(line => '<div>' + escapeText(line) + '</div>').join('');
    if (state.mood === 'attention') {
      if (moodChanged || state.count > (current?.count || 0)) nudge();
      nudgeTimer ??= setInterval(nudge, NUDGE_EVERY);
    } else {
      clearInterval(nudgeTimer);
      nudgeTimer = null;
    }
    current = state;
  },
  hover(on) { root.classList.toggle('hovered', !!on); },
};
