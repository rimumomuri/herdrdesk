// What needs the person: unread agent messages, snoozed conversations and the next one to look at. Pure: no DOM.
// A row is a sidebar conversation: {key, lastAgentAt, pending, trouble, blocked}.

const RANK = ['question', 'login', 'blocked', 'unread'];

/** The most urgent thing a conversation needs: a question, a login, a blocked prompt, an unread message, or null. */
export function attentionOf(row, unread) {
  if (row.pending > 0) return 'question';
  if (row.trouble === 'login') return 'login';
  if (row.blocked) return 'blocked';
  return unread ? 'unread' : null;
}

/** An agent said something after the person last looked. A conversation never looked at counts as seen (no flood). */
export function autoUnread(row, seen) {
  const at = seen?.[row.key];
  return at !== undefined && row.lastAgentAt > at;
}

/** Seen times after a render: new conversations start as seen; the one being looked at is seen now. */
export function markSeen(seen, rows, lookingAt, now) {
  const next = { ...seen };
  for (const row of rows) if (next[row.key] === undefined) next[row.key] = row.lastAgentAt || 0;
  if (lookingAt) next[lookingAt] = Math.max(now, next[lookingAt] ?? 0);
  return next;
}

/** A snooze holds until its time, until the agent says something new, or until the conversation needs the person. */
export function snoozeActive(entry, row, now) {
  if (!entry || now >= entry.until) return false;
  if (row.lastAgentAt > entry.at) return false;
  return !attentionOf(row, false);
}

/** 'hour': an hour from now. 'morning': the next 9:00 local time. */
export function snoozeUntil(choice, now) {
  if (choice === 'hour') return now + 3_600_000;
  const at = new Date(now);
  at.setHours(9, 0, 0, 0);
  if (at.getTime() <= now) at.setDate(at.getDate() + 1);
  return at.getTime();
}

// A question shows in its team room and in the asker's own chat: it counts once, at the row that comes first.
function ordered(rows, unread) {
  const counted = new Set();
  const fresh = rows.filter(row => {
    const ids = row.questions || [];
    if (row.pending > 0 && ids.length && ids.every(id => counted.has(id)) && !row.trouble && !row.blocked && !unread.has(row.key)) return false;
    ids.forEach(id => counted.add(id));
    return true;
  });
  return RANK.flatMap(kind => fresh.filter(row => attentionOf(row, unread.has(row.key)) === kind));
}

/** The next conversation to look at after `current`: questions, logins, blocked, unread; wraps around. */
export function nextUrgent(rows, unread, current) {
  const list = ordered(rows, unread);
  if (!list.length) return null;
  const at = list.findIndex(row => row.key === current);
  return list[(at + 1) % list.length].key;
}

export function waitingCount(rows, unread) {
  return ordered(rows, unread).length;
}
