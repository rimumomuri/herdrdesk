// Why an agent or computer cannot work right now: a login, a usage limit, or another error. Pure: no DOM.
// Only the status message the program itself reports is used; screen text is never read.

const LOGIN = /\blog ?in\b|\/login|\bsign ?in\b|logged out|re-?auth|authenticat|unauthori[sz]ed|\b401\b|token (?:has )?expired|credentials|로그인|인증|ログイン|認証/i;
const LIMIT = /usage limit|rate[ -]?limit|quota|too many requests|\b429\b|limit (?:reached|exceeded)|hit your .*limit|한도|사용량|上限|制限/i;

/** 'login' | 'limit' | 'error' | null for a live agent. A login wins when a message mentions both. */
export function agentTrouble(term) {
  if (term?.state !== 'live' || !term.program?.agent) return null;
  const message = String(term.statusMessage || '');
  if (term.status === 'blocked') return LOGIN.test(message) ? 'login' : null;
  if (term.status !== 'error') return null;
  return LOGIN.test(message) ? 'login' : LIMIT.test(message) ? 'limit' : 'error';
}

/** A computer whose SSH connection needs the person to log in again (`hc machine ls` reports needs_login). */
export function machineTrouble(machine) {
  return machine?.state === 'needs_login' ? 'login' : null;
}
