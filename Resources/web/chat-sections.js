// Sidebar sections: grouping, manual order, collapse. Pure: maps and plain objects in, new ones out.
// prefs: Map(chatKey → {section?, rank?, ...}); sections: {order: string[], collapsed: string[]}.

const sectionOf = (prefs, key) => prefs.get(key)?.section || '';

/** A member's title without its team name: 'Shop Lead' in Shop → 'Lead'; also a shared first word. */
export function shortRoleTitle(title, team) {
  const clean = String(title || '').trim(), group = String(team || '').trim();
  if (!group || clean === group) return clean;
  const strip = prefix => clean.slice(prefix.length).replace(/^[\s·]+/, '');
  if (clean.startsWith(group + ' ') || clean.startsWith(group + '·')) return strip(group) || clean;
  const first = group.split(/\s+/)[0];
  if (first && first.length > 1 && clean.startsWith(first + ' ')) return strip(first) || clean;
  return clean;
}

/** The item after `key` once `dragged` is taken out of `keys` (null at the end). */
export function nextKey(keys, key, dragged) {
  const rest = keys.filter(k => k !== dragged);
  const at = rest.indexOf(key);
  return at < 0 ? null : rest[at + 1] ?? null;
}

/** Hidden by the user's choice; a conversation whose terminal has ended is hidden unless the user shows it. */
export function chatHidden(row, pref) {
  return pref?.hidden ?? !!row?.archived;
}

/** One entry per team: a lead's direct chat folds into its team room; a pin on the lead chat becomes a pin on the room. */
export function foldLeadChats(rows, pins, leadToRoom) {
  const folded = rows.filter(row => !leadToRoom.has(row.key));
  const moved = [...new Set(pins.map(key => leadToRoom.get(key) || key))];
  return { rows: folded, pins: moved, changed: moved.length !== pins.length || moved.some((key, i) => key !== pins[i]) };
}

/** A message belongs in the team room if it was sent there or, before rooms were the only entry, to the lead directly. */
export function inRoomConversation(item, roomId, leadDirectId) {
  const id = item?.conversationId;
  return id === 'room:' + roomId || (Boolean(leadDirectId) && id === leadDirectId);
}

export function groupRows(rows, prefs, sections) {
  const order = sections?.order || [], collapsed = new Set(sections?.collapsed || []);
  const used = new Set(rows.map(row => sectionOf(prefs, row.key)).filter(Boolean));
  const names = [...order, ...[...used].filter(name => !order.includes(name)).sort((a, b) => a.localeCompare(b))];
  const byRank = (a, b) => {
    const ra = prefs.get(a.key)?.rank, rb = prefs.get(b.key)?.rank;
    if (ra != null && rb != null) return ra - rb;
    if (ra != null) return -1;
    if (rb != null) return 1;
    if (Boolean(a.room) !== Boolean(b.room)) return a.room ? -1 : 1;   // team rooms first
    return b.at - a.at;
  };
  const groups = names.map(name => ({ name, unassigned: false, collapsed: collapsed.has(name),
    items: rows.filter(row => sectionOf(prefs, row.key) === name).sort(byRank) }));
  groups.push({ name: '', unassigned: true, collapsed: collapsed.has(''),
    items: rows.filter(row => !sectionOf(prefs, row.key)).sort(byRank) });
  return groups;
}

/** Puts `key` into `section` before `beforeKey` (end when null) and renumbers that section's ranks. */
export function moveChat(prefs, key, section, orderedKeys, beforeKey) {
  const next = new Map([...prefs].map(([k, v]) => [k, { ...v }]));
  const keys = orderedKeys.filter(k => k !== key);
  const at = beforeKey == null ? -1 : keys.indexOf(beforeKey);
  keys.splice(at < 0 ? keys.length : at, 0, key);
  keys.forEach((k, index) => {
    const value = next.get(k) || {};
    value.rank = index + 1;
    if (k === key) { if (section) value.section = section; else delete value.section; }
    next.set(k, value);
  });
  return next;
}

export function moveSection(sections, name, beforeName) {
  const order = (sections?.order || []).filter(item => item !== name);
  const at = beforeName == null ? -1 : order.indexOf(beforeName);
  order.splice(at < 0 ? order.length : at, 0, name);
  return { order, collapsed: [...(sections?.collapsed || [])] };
}

export function toggleSection(sections, name) {
  const collapsed = new Set(sections?.collapsed || []);
  if (collapsed.has(name)) collapsed.delete(name); else collapsed.add(name);
  return { order: [...(sections?.order || [])], collapsed: [...collapsed] };
}

export function addSection(sections, name) {
  const clean = String(name || '').trim();
  const order = [...(sections?.order || [])];
  if (clean && !order.includes(clean)) order.push(clean);
  return { order, collapsed: [...(sections?.collapsed || [])] };
}

export function renameSection(prefs, sections, from, to) {
  const clean = String(to || '').trim();
  if (!clean || clean === from) return [prefs, sections];
  const next = new Map([...prefs].map(([k, v]) => [k, v.section === from ? { ...v, section: clean } : v]));
  const swap = list => [...new Set((list || []).map(item => item === from ? clean : item))];
  return [next, { order: swap(sections?.order), collapsed: swap(sections?.collapsed) }];
}

export function deleteSection(prefs, sections, name) {
  const next = new Map([...prefs].map(([k, v]) => {
    if (v.section !== name) return [k, v];
    const { section, rank, ...rest } = v;
    return [k, rest];
  }));
  return [next, { order: (sections?.order || []).filter(item => item !== name),
    collapsed: (sections?.collapsed || []).filter(item => item !== name) }];
}
