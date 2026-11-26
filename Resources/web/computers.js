// Computers that can run card workers: connection (live from hc), readiness and weight class (machines.json
// via the task board), and how many card workers each runs now. Pure: no DOM.
import { machineTrouble } from './trouble.js';

/** state: ready | not-ready | needs-login | offline. The local Mac is always reachable. editable: the list came from machines.json.
 *  main: the Mac HerdrDesk runs on, where the leads and records live; always listed first. */
/** isWorking: the app's effective status (a fresh provider turn overrides a stale core status). */
export function computerRows(profiles = [], liveMachines = [], terms = [], isWorking = term => term.status === 'working') {
  const live = new Map(liveMachines.map(machine => [machine.name, machine.state]));
  const editable = profiles.length > 0;
  const listed = editable ? profiles
    : [{ name: 'local', ready: true, tier: 'heavy', slots: 0 }, ...liveMachines.map(machine => ({ name: machine.name, ready: true, tier: 'heavy', slots: 0 }))];
  const rows = listed.map(profile => {
    const connected = profile.name === 'local' || live.get(profile.name) === 'connected';
    // card workers on this computer: `used` are running now; `parked` finished but still hold a seat until retired
    const seated = terms.filter(term => term.state === 'live' && term.labels?.['task.spawned'] === '1'
      && (term.machine || 'local') === profile.name);
    // The board knows which workers hold a card (also between their turns); without it, count running turns.
    const used = Number.isInteger(profile.used) && profile.used >= 0 ? profile.used : seated.filter(isWorking).length;
    return { name: profile.name, label: profile.label || profile.name, tier: profile.tier || 'heavy', slots: profile.slots || 0,
             used, parked: Math.max(0, seated.length - used), ready: !!profile.ready, connected, editable, main: profile.name === 'local',
             projects: profile.projects === '*' ? '*' : (profile.projects || {}), rolesOff: profile.rolesOff || {}, repos: profile.repos || {},
             state: !connected ? (machineTrouble({ state: live.get(profile.name) }) === 'login' ? 'needs-login' : 'offline') : profile.ready ? 'ready' : 'not-ready' };
  });
  return [...rows.filter(row => row.main), ...rows.filter(row => !row.main)];
}

/** Device name for terminals on this Mac: the main computer's label from machines.json, or null when it has none. */
export function mainMachineLabel(profiles = [], copy) {
  const label = profiles.find(profile => profile.name === 'local')?.label;
  return label ? label + ' (' + copy('computerMain') + ')' : null;
}

export function computerStripHTML(rows, copy, escape) {
  if (!rows.length) return '';
  return '<h3 class="computer-title">' + escape(copy('computers')) + '</h3>' + rows.map(row => {
    const tag = row.editable ? 'button' : 'div';
    const extra = row.editable ? ' type="button" data-computer="' + escape(row.name) + '" aria-haspopup="dialog"' : '';
    const title = (row.main ? copy('computerMainHint') + ' · ' : '') + copy('computer_' + row.state);
    return '<' + tag + ' class="computer-row"' + extra + ' data-state="' + escape(row.state) + '" title="' + escape(title) + '">'
      + '<i class="computer-dot" aria-hidden="true"></i><b>' + escape(row.label) + '</b>'
      + '<span class="computer-role"' + (row.main ? ' data-main="true"' : '') + '>' + escape(copy(row.main ? 'computerMain' : 'computerWorker')) + '</span>'
      + '<small>' + escape(copy(row.tier === 'light' ? 'tierLight' : 'tierHeavy')) + '</small>'
      + (row.parked ? '<span class="computer-parked" title="' + escape(copy('computerParkedHint')) + '">' + escape(copy('computerParked').replace('{n}', row.parked)) + '</span>' : '')
      + '<span class="computer-load">' + (row.slots ? row.used + '/' + row.slots : row.used) + '</span></' + tag + '>';
  }).join('');
}

/** Teams a computer can receive: Mac Studio has their repo (prefilled) or a live local lead; minus what it already has. */
export function cloneTeams(configured = [], terms = [], projects = {}, repos = {}) {
  const titles = new Map(configured.map(team => [team.id, team.title]));
  const have = projects === '*' ? null : new Set(Object.keys(projects || {}));
  if (!have) return [];
  const ids = new Set(terms.filter(term => term.state === 'live' && !term.machine && !String(term.address || '').includes('/')
    && term.labels?.['team.role'] === 'lead' && term.labels?.['team.id']).map(term => term.labels['team.id']).concat(Object.keys(repos || {})));
  return [...ids].filter(id => !have.has(id)).sort().map(id => ({ id, title: titles.get(id) || id }));
}

/** Inner HTML of the settings dialog for one computer. */
export function computerSheetHTML(row, teams, copy, escape) {
  const option = (value, label, selected) => '<option value="' + escape(value) + '"' + (selected ? ' selected' : '') + '>' + escape(label) + '</option>';
  let html = '<h2 id="computerTitle">' + escape(row.label) + '</h2>'
    + (row.main ? '<p class="computer-main-note">' + escape(copy('computerMainNote')) + '</p>' : '')
    + '<p class="computer-state" data-state="' + escape(row.state) + '"><i class="computer-dot" aria-hidden="true"></i>' + escape(copy('computer_' + row.state)) + '</p>'
    + '<div class="computer-settings">'
    + '<label class="computer-check"><input id="computerReady" type="checkbox"' + (row.ready ? ' checked' : '') + '>' + escape(copy('computerReady')) + '</label>'
    + '<label>' + escape(copy('computerTier')) + '<select id="computerTier">'
    + option('heavy', copy('tierHeavy'), row.tier !== 'light') + option('light', copy('tierLight'), row.tier === 'light') + '</select></label>'
    + '<label>' + escape(copy('computerSlots')) + '<input id="computerSlots" type="number" min="0" max="64" value="' + escape(row.slots) + '"></label>'
    + '</div>';
  const off = Object.entries(row.rolesOff || {});
  if (off.length) {
    html += '<h3>' + escape(copy('computerRolesOff')) + '</h3><ul class="computer-list">'
      + off.map(([role, why]) => '<li><b>' + escape(role) + '</b><small>' + escape(why) + '</small></li>').join('') + '</ul>';
  }
  html += '<h3>' + escape(copy('computerProjects')) + '</h3>';
  if (row.projects === '*') return html + '<p class="computer-empty">' + escape(copy('allProjects')) + '</p>';
  const projects = Object.entries(row.projects || {});
  html += projects.length
    ? '<ul class="computer-list">' + projects.map(([team, path]) => '<li><b>' + escape(team) + '</b><small>' + escape(path) + '</small>'
      + '<button type="button" data-unlink="' + escape(team) + '">' + escape(copy('computerUnlink')) + '</button></li>').join('') + '</ul>'
    : '<p class="computer-empty">' + escape(copy('computerNoProjects')) + '</p>';
  if (!row.connected) return html + '<p class="computer-empty">' + escape(copy('computerCloneOffline')) + '</p>';
  if (!teams.length) return html;
  return html + '<form id="computerCloneForm" class="computer-clone"><h3>' + escape(copy('computerClone')) + '</h3>'
    + '<label>' + escape(copy('computerCloneTeam')) + '<select id="computerCloneTeam" required>' + option('', copy('computerChooseTeam'), true)
    + teams.map(team => option(team.id, team.title, false)).join('') + '</select></label>'
    + '<label>' + escape(copy('computerCloneUrl')) + '<input id="computerCloneUrl" required maxlength="512" spellcheck="false"></label>'
    + '<label>' + escape(copy('computerClonePath')) + '<input id="computerClonePath" required maxlength="1024" spellcheck="false"></label>'
    + '<p class="computer-note">' + escape(copy('computerCloneNote')) + '</p>'
    + '<p id="computerCloneStatus" class="computer-status" role="status"></p>'
    + '<div><button type="submit" class="primary" id="computerCloneSubmit">' + escape(copy('computerCloneSubmit')) + '</button></div></form>';
}

/** Worker count typed in the sheet: an integer 0–64, or null (empty or invalid input is not saved). */
export function slotsValue(text) {
  const value = String(text ?? '').trim();
  if (!/^\d{1,2}$/.test(value)) return null;
  const slots = Number(value);
  return slots <= 64 ? slots : null;
}

/** The clone request for the form, or null while the chosen team's lookup is pending or a field is empty. */
export function cloneRequest({ name, team, url, path, suggesting }) {
  const request = { action: 'clone', name, team, url: String(url || '').trim(), path: String(path || '').trim() };
  if (suggesting || !team || !request.url || !request.path) return null;
  return request;
}
