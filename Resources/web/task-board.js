// Team card board: columns and counts from the `tasks` snapshot (herdr-task board --json). Pure helpers.

export const BOARD_STATES = ['queued', 'working', 'review', 'blocked', 'done'];
const DONE_WINDOW = 24 * 3_600_000;
const ms = iso => { const value = Date.parse(iso || ''); return Number.isFinite(value) ? value : 0; };

export function boardColumns(team, now) {
  const cards = team?.cards || [];
  return BOARD_STATES.map(state => ({
    state,
    cards: cards
      .filter(card => card.state === state && (state !== 'done' || now - ms(card.updated) <= DONE_WINDOW))
      .sort((a, b) => ms(b.updated) - ms(a.updated))
      .map(card => ({
        id: card.id, title: card.title || '', owner: card.owner?.address || null,
        ageMs: Math.max(0, now - ms(card.created)),
        doneOf: [(card.doneChecks || []).filter(Boolean).length, (card.done || []).length],
        blocker: card.blocker || null,
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

export function boardCardHTML(card, nameOf, portraitOf, escape, copy) {
  const owner = card.owner ? nameOf(card.owner) : '';
  const [checked, total] = card.doneOf;
  return '<button type="button" class="board-card"' + (card.owner ? ' data-board-owner="' + escape(card.owner) + '"' : ' disabled')
    + ' data-board-card="' + escape(card.id) + '">'
    + '<span class="board-card-title">' + escape(card.title) + '</span>'
    + (card.blocker ? '<span class="board-card-blocker">' + escape(card.blocker) + '</span>' : '')
    + '<span class="board-card-meta">'
    + (card.owner ? '<span class="board-card-owner">' + (portraitOf(card.owner) || '') + escape(owner || card.owner) + '</span>' : '')
    + (total ? '<span class="board-card-done">' + checked + '/' + total + '</span>' : '')
    + '<span class="board-card-age">' + escape(age(card.ageMs)) + '</span>'
    + '</span></button>';
}
