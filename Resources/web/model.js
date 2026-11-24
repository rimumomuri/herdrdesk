export function makeInventory(terms, spaces, configuredTeams=[]) {
  const roles = new Map();
  for (const team of configuredTeams) {
    for (const [role,label] of team.roles || []) {
      if (typeof role==='string'&&typeof label==='string'&&typeof team.title==='string') roles.set(role,{label,team:team.title,teamID:team.id,lead:team.lead===role,parent:team.parents?.[role]});
    }
  }
  const placement = new Map();
  for (const space of spaces) {
    for (const tab of space.tabs || []) {
      for (const address of tab.terminals || []) {
        const qualified = space.machine && !address.includes('/') ? space.machine + '/' + address : address;
        placement.set(qualified, { space: space.name, tab: tab.name });
      }
    }
  }
  const live = terms.filter(term => term.state === 'live');
  const byAddress = new Map(live.map(term => [term.address, term]));
  return live.map(term => {
    const machine = term.address.includes('/') ? term.address.split('/')[0] : '';
    const location = placement.get(term.address);
    const configured=roles.get(term.labels?.['recovery.role']);
    const label = term.labels?.['display.title'] || configured?.label || term.name || term.agent || term.address;
    const team = configured?.team || term.labels?.['team.title'] || term.labels?.['team.id'] || location?.space || '';
    return { ...term, machine, location, label, team,
      teamID:configured?.teamID || term.labels?.['team.id'] || team,
      roleLabel:configured?.label || term.labels?.['role.title'] || label,
      isLead:configured?.lead ?? (term.labels?.['team.lead']==='true'), parentRole:configured?.parent, parentName: byAddress.get(term.parent)?.labels?.['display.title'] ||
      byAddress.get(term.parent)?.name || (byAddress.has(term.parent) ? term.parent : roles.get(configured?.parent)?.label || '') };
  });
}

export const activeAgent = term => term?.program?.agent === true && !['blocked', 'error'].includes(term.status);
export const sendable = (term, connection) => connection === 'live' && activeAgent(term);

export function registeredQuestions(terms, ledger, now = Date.now()) {
  const candidates = terms.flatMap(term => {
    const label = term.labels || {}, id = label['ask.id'];
    if (term.state !== 'live' || !term.program?.agent || !label['recovery.role'] || !/^q[0-9]{14}[0-9a-f]{6}$/.test(id || '')) return [];
    const expires = Date.parse(label['ask.expires']);
    if (!label['ask.text'] || term.session !== label['ask.session'] || label['ask.state'] === 'withdrawn' ||
        (Number.isFinite(expires) && expires < now)) return [];
    const saved = ledger[id], state = label['ask.state'] || 'open';
    const blocked = ['blocked','error'].includes(term.status);
    const role = label['ask.approval_role'], session = label['ask.approval_session'];
    const possibleTargets = role ? terms.filter(t => t.state==='live'&&t.program?.agent&&t.labels?.['recovery.role']===role) : [];
    const target = possibleTargets.length===1&&possibleTargets[0].session===session ? possibleTargets[0] : null;
    let choices=[];
    try { const value=JSON.parse(label['ask.choices'] || '[]'); if(Array.isArray(value))choices=value.filter(x=>typeof x==='string').slice(0,5); } catch {}
    return [{id, at:recordTime(id), address:term.address, ask:label['ask.text'], choices, state:state==='acked'?'questionAck':
      saved==='needs_check'||saved==='sending'?'needsCheck':saved==='sent'||saved==='resolved_sent'||state==='sent'?'sent':'answerNeeded',
      answerable:state==='open'&&!blocked&&!['needs_check','sending','sent','resolved_sent'].includes(saved),
      approval:role&&session&&['open','sending','needs-check','sent'].includes(state) ? {role, address:target?.address || null} : null}];
  });
  return candidates.filter(q=>candidates.filter(other=>other.id===q.id).length===1);
}

export function attentionCount(terms, questions) {
  const attention = new Set(terms.filter(term => term.program?.agent && ['blocked','error'].includes(term.status))
    .map(term => term.address));
  for (const question of questions) {
    if (['answerNeeded','needsCheck'].includes(question.state)) {
      attention.add(question.approval?.address || question.address);
    }
  }
  return attention.size;
}

// Herdr's question and flow IDs encode a UTC creation time.
function recordTime(id) {
  const match = /^[qf](\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})[a-f0-9]{6}$/.exec(id);
  if (!match) return null;
  const [, year, month, day, hour, minute, second] = match;
  const timestamp = year+'-'+month+'-'+day+'T'+hour+':'+minute+':'+second+'Z';
  const at = Date.parse(timestamp);
  return Number.isFinite(at) && new Date(at).toISOString() === timestamp.replace('Z','.000Z') ? at : null;
}

export function explicitHandoffs(terms, now = Date.now()) {
  const byRole = new Map();
  for (const term of terms) {
    const role = term.labels?.['recovery.role'];
    if (!role || term.state !== 'live' || !term.program?.agent) continue;
    byRole.set(role,[...(byRole.get(role)||[]),term]);
  }
  const handoffs=[];
  for (const [role, workers] of byRole) {
    if (workers.length!==1) continue;
    const term=workers[0], label=term.labels||{}, phase=label['flow.phase'];
    const source=byRole.get(label['flow.from']), at=Date.parse(label['flow.updated']);
    if (!label['flow.id'] || !label['flow.task'] || source?.length!==1 ||
        label['flow.session']!==term.session || !Number.isFinite(at) || at>now+60000 || now-at>21600000 ||
        !['working','result-sent'].includes(phase)) continue;
    const lead=source[0], id=label['flow.id'];
    const ack=lead.labels?.['flowack.'+id]?.split('|');
    const receipt=phase==='result-sent'&&ack?.[1]===role&&ack?.[2]===term.session;
    const returning=phase==='result-sent';
    handoffs.push({id:'f:'+id,at,from: returning?term:lead,to:returning?lead:term,
      text:label['flow.task'], startedAt:returning ? recordTime(id) : null, returning, state:receipt?'questionAck':returning?'sent':'working'});
  }
  return handoffs;
}

/** A group appears as a team only when it is configured or has an agent: a workspace of plain shells is nobody to chat with. */
export const listedGroup = (members, configured) => configured || members.some(term => term?.program?.agent);

export function makeTeamDirectory(inventory, configuration=[]) {
  const groups = new Map(configuration.map(team => [team.id, {
    id: team.id, title: team.title, lead: team.lead, parents: team.parents || {},
    roles: team.roles || [], nodes: []
  }]));
  const byRole = new Map();
  const titleGroups = new Map();
  for (const group of groups.values()) {
    titleGroups.set(group.title, titleGroups.has(group.title) ? null : group);
    for (const [role] of group.roles) byRole.set(role, byRole.has(role) ? null : group);
  }
  const roleOf = term => term.labels?.['recovery.role'];
  const byAddress = new Map(inventory.filter(term => term.state==='live').map(term => [term.address,term]));
  const nativeParent = term => {
    if (!term?.parent) return null;
    const address = term.machine && !term.parent.includes('/') ? term.machine+'/'+term.parent : term.parent;
    return byAddress.get(address);
  };
  const membership = (term, visited = new Set()) => {
    if (!term || visited.has(term)) return null;
    visited.add(term);
    const known = byRole.get(roleOf(term)) || groups.get(term.teamID) || titleGroups.get(term.team);
    if (known) return known;
    if (term.labels?.['team.id'] || term.labels?.['team.title']) return null;
    return membership(nativeParent(term), visited);
  };
  for (const term of inventory) {
    const existing = membership(term);
    const key = existing?.id || term.teamID || '';
    if (!groups.has(key)) groups.set(key, {id:key,title:term.team,parents:{},roles:[],nodes:[]});
    groups.get(key).nodes.push({role:roleOf(term),label:term.roleLabel||term.label,term,children:[]});
  }
  return [...groups.values()].map(group => {
    const found = new Set(group.nodes.map(node=>node.role));
    const order = new Map(group.roles.map(([role],index)=>[role,index]));
    for (const [role,label] of group.roles) {
      if (!found.has(role)) group.nodes.push({role,label,term:null,children:[]});
    }
    const rank = node => order.get(node.role) ?? order.size;
    group.nodes.sort((a,b)=>rank(a)-rank(b));
    const unique = role => {
      if (!role) return null;
      const hits = group.nodes.filter(node=>node.role===role);
      return hits.length===1 ? hits[0] : null;
    };
    const marked = group.nodes.filter(node=>node.term?.isLead);
    const lead = group.lead ? unique(group.lead) : marked.length===1 ? marked[0] : null;
    const byTerm = new Map(group.nodes.filter(node=>node.term).map(node=>[node.term,node]));
    const parents = new Map(group.nodes.map(node=>{
      const manager = node===lead ? null
        : unique(group.parents[node.role]) || byTerm.get(nativeParent(node.term)) || lead;
      return [node,manager];
    }));
    const roots = [];
    for (const node of group.nodes) {
      const parent = parents.get(node);
      const seen = new Set([node]);
      let ancestor = parent;
      while (ancestor && !seen.has(ancestor)) {
        seen.add(ancestor);
        ancestor = parents.get(ancestor);
      }
      if (parent && !ancestor) parent.children.push(node);
      else roots.push(node);
    }
    const listed=listedGroup(group.nodes.map(node=>node.term),configuration.some(team=>team.id===group.id));
    return {id:group.id,title:group.title,roots,count:listed?group.nodes.length:0};
  }).filter(group=>group.count);
}


export function completedAgentTurn(before, current) {
  if (!before || current.status !== 'done') return false;
  if (before.wasWorking) return true;
  // A fast turn can end between snapshots. Both the turn and status must advance.
  return Number.isInteger(before.turn) && Number.isInteger(current.turn)
    && current.turn > before.turn && Number.isFinite(before.statusMs)
    && Number.isFinite(current.statusMs) && current.statusMs > before.statusMs;
}


export function displayedStatus(term) {
  const status = term?.status ?? 'unknown';
  if (status !== 'working' || !term.session || !Number.isInteger(term.turn) || !Number.isFinite(term.statusMs)) return status;
  const currentReport = [term.session, term.turn, term.statusMs].join('|');
  return term.labels?.['dashboard.working_cleared'] === currentReport ? 'done' : status;
}

export function observedAgentStatus(term, runtime) {
  const status=displayedStatus(term);
  if(!runtime||!['working','done'].includes(runtime.state)||['blocked','error'].includes(status))return status;
  const at=Date.parse(runtime.at);
  return Number.isFinite(at)&&at>=Number(term?.statusMs||0)?runtime.state:status;
}

// Pair at most one explicit publication with one captured final. Without a complete,
// unambiguous provider-turn interval preserve both records rather than hide a reply.
// Same answer text, ignoring emphasis and code marks, all whitespace and a Codex memory citation footer.
const replyText = body => String(body || '').replace(/\s*<oai-mem-citation>[\s\S]*?(?:<\/oai-mem-citation>|$)/g, '')
  .replace(/[\s*_`]/g, '');

export function mergeConversationRecords(published = [], live = []) {
  const paired = new Set();
  const aliases = new Map();
  const kept = published.filter(entry => {
    if (entry.kind === 'reply') {
      const at = Date.parse(entry.at);
      const precision = /T\d{2}:\d{2}:\d{2}Z$/.test(entry.at || '') ? 999 : 0;
      const matches = live.filter(item => item.kind === 'reply' && item.turn && item.session
        && item.role === entry.role && item.session === entry.session && replyText(item.body) === replyText(entry.body)
        && Number.isFinite(at) && at + precision >= Date.parse(item.turnStartedAt) && at <= Date.parse(item.turnEndedAt));
      if (matches.length === 1 && !paired.has(matches[0].id)) {
        paired.add(matches[0].id); aliases.set(matches[0].id, entry.id); return false;
      }
    }
    return entry.kind !== 'agent-handoff' || !live.some(item => item.kind === 'agent-handoff'
      && entry.role === item.role && entry.recipient === item.recipient
      && entry.body.trim() === item.body.trim() && Math.abs(Date.parse(entry.at)-Date.parse(item.at)) < 15000);
  });
  return [...kept, ...live.map(item => aliases.has(item.id) ? {...item, publicationID: aliases.get(item.id)} : item)];
}
