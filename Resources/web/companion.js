// The floating sheep: what it should show, from the same signals that drive the sounds. Pure: no DOM, no clock.

import { elapsedText } from './model.js';

export const FLASH_MS = 10_000;
const OFFLINE = new Set(['lost', 'missing']);

/**
 * attention: [{address, session, team}] for each blocked prompt or unanswered question (one agent may appear twice).
 * working: live agent sessions currently working. limited: agents stopped by a usage limit. flash: {kind:'done'|'handoff', at} of the latest finish or assignment.
 * Only team names and counts leave this function: no question text.
 */
export function companionState({ connection, attention = [], working = 0, limited = 0, flash = null, now }) {
  const agents = [];
  for (const item of attention) if (!agents.some(seen => seen.address === item.address)) agents.push(item);
  const teams = [];
  for (const agent of agents) {
    const row = teams.find(entry => entry.team === agent.team);
    if (row) row.n++; else teams.push({ team: agent.team, n: 1 });
  }
  const mood = agents.length ? 'attention' : OFFLINE.has(connection) ? 'offline' : limited > 0 ? 'limit' : working > 0 ? 'working' : 'idle';
  return {
    mood, count: agents.length, working, limited, teams,
    flash: flash && now - flash.at <= FLASH_MS ? flash.kind : null,
    flashAt: flash && now - flash.at <= FLASH_MS ? flash.at : null,
    target: agents.length ? { address: agents[0].address, session: agents[0].session } : null,
  };
}

/** One to a few short lines for the hover bubble. */
export function companionSummary(state, copy) {
  const fill = (key, values) => Object.entries(values).reduce((text, [name, value]) => text.replace('{' + name + '}', () => String(value)), copy(key));
  if (state.mood === 'attention') return state.teams.map(row => fill('companionNeeds', row));
  if (state.mood === 'offline') return [copy('companionOffline')];
  if (state.mood === 'limit') return [fill('companionLimit', { n: state.limited })];
  const lines = state.flash ? [copy(state.flash === 'done' ? 'companionDone' : 'companionHandoff')] : [];
  lines.push(state.mood === 'working' ? fill('companionWorking', { n: state.working }) : copy('companionIdle'));
  return lines;
}

/** Whose face the companion wears: who needs you, else who just finished, else the latest to start working, else the last face. */
export function featuredAgent({ mood, flash = null, targetKey = null, limitKey = null, finishedKey = null, workingKeys = [], previousKey = null }) {
  if (mood === 'attention' && targetKey) return targetKey;
  if (mood === 'limit' && limitKey) return limitKey;
  if (flash === 'done' && finishedKey) return finishedKey;
  return workingKeys[0] || previousKey || null;
}

export const STAT_ROWS = 4;
export const DONE_WINDOW_MS = 30 * 60_000;

/** The hover stat panel: who waits on you, who works and for how long, who finished in the last half hour.
 *  Input rows carry only a display name and a time; nothing else reaches the companion. Empty sections are left out. */
export function companionStats({ working = [], done = [], waiting = [] }, now, units, copy) {
  const section = (kind, title, rows) => rows.length ? [{
    kind, title, count: rows.length, rows: rows.slice(0, STAT_ROWS),
    more: rows.length > STAT_ROWS ? copy('statMore').replace('{n}', () => String(rows.length - STAT_ROWS)) : '',
  }] : [];
  const ago = at => now - at < 60_000 ? copy('statJustNow') : copy('statAgo').replace('{t}', () => elapsedText(now - at, units).replace(/ \S+$/, ''));
  return [
    ...section('waiting', copy('statWaiting'), waiting.map(row => ({ name: row.name, meta: '' }))),
    ...section('working', copy('statWorking'), [...working].sort((a, b) => a.since - b.since).map(row => ({ name: row.name, meta: elapsedText(now - row.since, units) }))),
    ...section('done', copy('statDone'), done.filter(row => now - row.at <= DONE_WINDOW_MS).sort((a, b) => b.at - a.at).map(row => ({ name: row.name, meta: ago(row.at) }))),
  ];
}
