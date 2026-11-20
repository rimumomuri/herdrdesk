// When HerdrDesk makes a sound. Pure: no DOM, no clock.
// done: a member finished its turn. handoff: work was handed over. attention: someone waits for you
// (a permission prompt or an unanswered question); it repeats every minute until it is cleared.

export const DEFAULT_SOUNDS = { done: 'Glass', handoff: 'Pop', attention: 'Ping' };
export const ATTENTION_EVERY = 60_000;

/** New "assign" handoff cards since the last call; the first call only remembers what is already there. */
export function newHandoffs(cards = [], seen = null) {
  const ids = new Set(cards.filter(card => card.kind === 'assign').map(card => card.id));
  if (!seen) return { fresh: 0, seen: ids };
  let fresh = 0;
  for (const id of ids) if (!seen.has(id)) fresh++;
  return { fresh, seen: ids };
}

/** One key per thing waiting on you: a blocked agent session or an unanswered question. */
export function attentionKeys(terms = [], questions = []) {
  const keys = new Set();
  for (const term of terms) {
    if (term.program?.agent && term.status === 'blocked') keys.add('blocked:' + term.address + ':' + term.session);
  }
  for (const question of questions) {
    if (['answerNeeded', 'needsCheck'].includes(question.state)) keys.add('question:' + question.id);
  }
  return keys;
}

/** Rings at once when something new waits on you, then every minute while anything still does. */
export function attentionTick(previous, keys, lastAt, now, every = ATTENTION_EVERY) {
  if (!keys.size) return { play: false, lastAt: 0 };
  const added = [...keys].some(key => !previous.has(key));
  if (added || now - lastAt >= every) return { play: true, lastAt: now };
  return { play: false, lastAt };
}
