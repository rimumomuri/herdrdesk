// Team card board: columns and counts from the `tasks` snapshot (herdr-task board --json). Pure helpers.

export const BOARD_STATES = ['queued', 'working', 'review', 'blocked', 'done'];
const DONE_WINDOW = 24 * 3_600_000;
const ms = iso => { const value = Date.parse(iso || ''); return Number.isFinite(value) ? value : 0; };

const priorityOf = card => Number.isInteger(card.priority) && card.priority >= 1 ? card.priority : null;

/** Waiting column order: cards that can start (numbered by priority, then unnumbered oldest first), then cards that must wait. */
function waitingOrder(a, b) {
  const wait = card => (card.waitingOn || []).length ? 1 : 0;
  const rank = card => priorityOf(card) ?? Infinity;
  return wait(a) - wait(b) || rank(a) - rank(b) || ms(a.created) - ms(b.created);
}

/** `ownerLive(owner)`: is the worker that did a card still there? A finished card whose worker has ended is dropped. */
export function boardColumns(team, now, { ownerLive = null } = {}) {
  const cards = team?.cards || [];
  const titles = new Map(cards.map(card => [card.id, card.title || card.id]));
  return BOARD_STATES.map(state => ({
    state,
    cards: cards
      .filter(card => card.state === state && (state !== 'done' || (now - ms(card.updated) <= DONE_WINDOW
        && (!ownerLive || Boolean(card.owner && ownerLive(card.owner))))))
      .sort(state === 'queued' ? waitingOrder : (a, b) => ms(b.updated) - ms(a.updated))
      .map(card => ({
        id: card.id, title: card.title || '', owner: card.owner?.address || null,
        ageMs: Math.max(0, now - ms(card.created)),
        doneOf: [(card.doneChecks || []).filter(Boolean).length, (card.done || []).length],
        blocker: card.blocker || null, priority: priorityOf(card),
        waitingOn: (card.waitingOn || []).map(id => ({ id, title: titles.get(id) || id })),
      })),
  }));
}

export function teamCountsText(counts, copy) {
  return [counts.working ? copy('teamCountWorking').replace('{n}', counts.working) : '',
    counts.blocked ? copy('teamCountBlocked').replace('{n}', counts.blocked) : ''].filter(Boolean).join(' · ');
}

export function teamCounts(team) {
  const count = state => (team?.cards || []).filter(card => card.state === state).length;
  return { working: count('working'), blocked: count('blocked'), review: count('review') };
}

const age = ms => ms < 3_600_000 ? Math.max(1, Math.round(ms / 60_000)) + 'm' : ms < 86_400_000 ? Math.round(ms / 3_600_000) + 'h' : Math.round(ms / 86_400_000) + 'd';

const LOCK = '<svg viewBox="0 0 12 12" width="11" height="11" aria-hidden="true"><rect x="2" y="5.5" width="8" height="5.5" rx="1.2" fill="currentColor"/>'
  + '<path d="M4 5.5V4a2 2 0 0 1 4 0v1.5" fill="none" stroke="currentColor" stroke-width="1.3"/></svg>';

export function boardCardHTML(card, nameOf, portraitOf, escape, copy) {
  const owner = card.owner ? nameOf(card.owner) : '';
  const [checked, total] = card.doneOf;
  const waiting = card.waitingOn || [];
  const number = card.priority
    ? '<span class="board-card-priority" aria-label="' + escape(copy('boardPriority').replace('{n}', card.priority)) + '">' + card.priority + '</span>' : '';
  return '<button type="button" class="board-card"' + (card.owner ? ' data-board-owner="' + escape(card.owner) + '"' : ' disabled')
    + ' data-board-card="' + escape(card.id) + '"' + (waiting.length ? ' data-waiting="true"' : '') + '>'
    + '<span class="board-card-head">' + number + '<span class="board-card-title">' + escape(card.title) + '</span></span>'
    + (waiting.length ? '<span class="board-card-waiting">' + LOCK
      + escape(copy('boardWaitingOn').replace('{title}', () => waiting.map(item => item.title).join(', '))) + '</span>' : '')
    + (card.blocker ? '<span class="board-card-blocker">' + escape(card.blocker) + '</span>' : '')
    + '<span class="board-card-meta">'
    + (card.owner ? '<span class="board-card-owner">' + (portraitOf(card.owner) || '') + escape(owner || card.owner) + '</span>' : '')
    + (total ? '<span class="board-card-done">' + checked + '/' + total + '</span>' : '')
    + '<span class="board-card-age">' + escape(age(card.ageMs)) + '</span>'
    + '</span></button>';
}

export const BOARD_LABELS = { queued: 'boardQueued', working: 'boardWorking', review: 'boardReview', blocked: 'boardBlocked', done: 'boardDone' };

/** One line of counts per column, shown while the board is folded away. */
export function boardSummaryHTML(columns, copy) {
  return columns.map(column => '<span class="board-chip" data-board-state="' + column.state + '"' + (column.cards.length ? '' : ' data-empty="true"') + '>'
    + copy(BOARD_LABELS[column.state]) + ' <b>' + column.cards.length + '</b></span>').join('');
}
