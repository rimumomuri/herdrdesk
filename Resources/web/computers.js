// Computers that can run card workers: connection (live from hc), readiness and weight class (machines.json
// via the task board), and how many card workers each runs now. Pure: no DOM.

/** state: ready | not-ready | offline. The local Mac is always reachable. */
export function computerRows(profiles = [], liveMachines = [], terms = []) {
  const live = new Map(liveMachines.map(machine => [machine.name, machine.state]));
  const listed = profiles.length ? profiles
    : [{ name: 'local', ready: true, tier: 'heavy', slots: 0 }, ...liveMachines.map(machine => ({ name: machine.name, ready: true, tier: 'heavy', slots: 0 }))];
  return listed.map(profile => {
    const connected = profile.name === 'local' || live.get(profile.name) === 'connected';
    const used = terms.filter(term => term.state === 'live' && term.labels?.['task.spawned'] === '1'
      && (term.machine || 'local') === profile.name).length;
    return { name: profile.name, label: profile.label || profile.name, tier: profile.tier || 'heavy', slots: profile.slots || 0,
             used, state: !connected ? 'offline' : profile.ready ? 'ready' : 'not-ready' };
  });
}

export function computerStripHTML(rows, copy, escape) {
  if (!rows.length) return '';
  return '<h3 class="computer-title">' + escape(copy('computers')) + '</h3>' + rows.map(row =>
    '<div class="computer-row" data-state="' + escape(row.state) + '" title="' + escape(copy('computer_' + row.state)) + '">'
    + '<i class="computer-dot" aria-hidden="true"></i><b>' + escape(row.label) + '</b>'
    + '<small>' + escape(copy(row.tier === 'light' ? 'tierLight' : 'tierHeavy')) + '</small>'
    + '<span class="computer-load">' + (row.slots ? row.used + '/' + row.slots : row.used) + '</span></div>').join('');
}
