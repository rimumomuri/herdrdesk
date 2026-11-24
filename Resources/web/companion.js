// The floating sheep: what it should show, from the same signals that drive the sounds. Pure: no DOM, no clock.

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
