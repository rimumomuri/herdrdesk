// Which rendered items are new enough to animate. The app re-renders whole panels, so motion keys off ids it has seen. Pure: no DOM.

/** ids that appeared in `scope` since it was last rendered; the first render of a scope animates nothing. `seen` is updated. */
export function freshEntries(scope, ids, seen) {
  const known = seen.get(scope);
  const present = ids.filter(Boolean);
  seen.set(scope, new Set([...(known || []), ...present]));
  return known ? present.filter(id => !known.has(id)) : [];
}
