export function legacyDraftKey(term) {
  const role = term?.labels?.['recovery.role'];
  return typeof role === 'string' && /^[A-Za-z0-9._-]{1,64}$/.test(role) && role !== '.' && role !== '..' ? role : null;
}

export function archiveRoles(terms, legacy, drafts, replies) {
  const current = new Set(terms.map(legacyDraftKey));
  const roles = new Set([
    ...Object.keys(legacy).filter(role => Array.isArray(legacy[role]) && legacy[role].length),
    ...Object.keys(drafts).filter(role => typeof drafts[role] === 'string' && drafts[role]),
    ...replies.map(reply => reply.kind==='agent-handoff'?reply.recipient:reply.role)
  ]);
  return [...roles].filter(role => !current.has(role) && legacyDraftKey({labels:{'recovery.role':role}})).sort();
}

export function combineChat(term, legacy, outgoing, replies, roleName = role => role, conversationId = null) {
  if (!term) return [];
  const role = legacyDraftKey(term);
  const currentKey = term.address + ':' + term.session;
  const storageKey=role||'session:'+currentKey;
  const own = Array.isArray(legacy[storageKey]) ? legacy[storageKey] : [];
  const items = new Map();
  for (const entry of own) {
    if (!entry || typeof entry.id !== 'string' || (conversationId&&entry.conversationId&&entry.conversationId!==conversationId)) continue;
    const at = Date.parse(entry.at);
    items.set(entry.id, { ...entry, state:entry.state||'sent', at:Number.isFinite(at)?at:0 });
  }
  for (const entry of outgoing) {
    if ((!conversationId||!entry.conversationId||entry.conversationId===conversationId)&&(entry.target === currentKey || (role && entry.role === role))) items.set(entry.id, entry);
  }
  for (const reply of replies) {
    const handoff=reply.kind==='agent-handoff';
    if (!role || (reply.role!==role && (!handoff||reply.recipient!==role))) continue;
    if (items.has(reply.id)) continue;
    const at = Date.parse(reply.at), mine=reply.kind==='message';
    const leaving=handoff&&reply.role===role;
    items.set(reply.id, {id:reply.id,text:reply.body,at:Number.isFinite(at)?at:0,
      state:mine?'sent':handoff?(leaving?'outgoingHandoff':'incomingHandoff'):reply.kind==='progress'?'progress':'reply',
      from:mine?null:leaving?term.label+' → '+roleName(reply.recipient):handoff?roleName(reply.role):term.label});
  }
  return [...items.values()].sort((a,b)=>a.at-b.at);
}

export function appendLegacySend(legacy, record, role) {
  const previous = Array.isArray(legacy[role]) ? legacy[role] : [];
  if (previous.some(item=>item.id===record.id)) return legacy;
  return { ...legacy, [role]: [...previous, {
    id:record.id, role:record.role??role, session:record.session, text:record.text, at:new Date(record.at).toISOString(), images:record.images||0,
    ...(record.state==='sent'&&Array.isArray(record.previews)?{previews:record.previews.slice(0,4)}:{}),
    ...(record.conversationId?{conversationId:record.conversationId,address:record.address,state:record.state}: {})
  }] };
}

const ROLE_WORDS = { production: '제작', qa: 'QA', lead: '기획', planner: '기획', concepts: '시안', design: '시안', image: '이미지', user1: '유저 1', user2: '유저 2', demo: '시연', secretary: '비서' };
/** A role key whose session is gone ("shop-builder") as plain words ("Shop · Builder"), using the configured team titles. */
export function retiredRoleName(role, teams) {
  if (!role) return '';
  const cut = role.indexOf('-');
  if (cut < 1) return role;
  const team = (teams || []).find(item => item.id === role.slice(0, cut));
  const word = ROLE_WORDS[role.slice(cut + 1)];
  return team && word ? team.title + ' · ' + word : role;
}
