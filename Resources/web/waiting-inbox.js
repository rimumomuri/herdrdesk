export function waitingInboxItems(inventory, ledger = {}, now = Date.now()) {
  const visible=inventory.filter(term=>term.state==='live'&&term.program?.agent&&term.session);
  const byAddress=new Map(inventory.filter(term=>term.state==='live').map(term=>[term.address,term]));
  const uniqueRole=role=>{
    const hits=visible.filter(term=>term.labels?.['recovery.role']===role);
    return role&&hits.length===1?hits[0]:null;
  };
  const identity=term=>term?{address:term.address,session:term.session,role:term.labels?.['recovery.role']||''}:null;
  const path=term=>{
    const chain=[],seen=new Set();let current=term;
    while(current&&!seen.has(current.address)&&chain.length<32){
      seen.add(current.address);chain.unshift(current);
      const machine=current.address.includes('/')?current.address.split('/')[0]:'';
      const parent=current.parent&&(machine&&!current.parent.includes('/')?machine+'/'+current.parent:current.parent);
      current=byAddress.get(parent)||(!parent&&current.parentRole?uniqueRole(current.parentRole):null);
    }
    return chain;
  };
  const rows=new Map();
  const add=(row,term)=>{
    row.actor=identity(term);row.actorLabel=term.label||term.name||term.address;
    const chain=path(term);
    row.team=[...chain].reverse().map(actor=>actor.team||actor.labels?.['team.title']||actor.labels?.['team.id']||'').find(Boolean)||'';
    row.path=chain.map(actor=>actor.label||actor.name||actor.address);row.command=null;
    row.origin={actor:row.actor,label:row.actorLabel,team:row.team,path:row.path};
    const target=byAddress.get(row.target?.address);
    const targetChain=target&&target.session===row.target.session?path(target):[];
    row.targetLabel=targetChain.length?(target.label||target.name||target.address):null;
    row.targetPath=targetChain.map(actor=>actor.label||actor.name||actor.address);
    row.targetTeam=[...targetChain].reverse().map(actor=>actor.team||actor.labels?.['team.title']||actor.labels?.['team.id']||'').find(Boolean)||'';
    row.binding=JSON.stringify([row.key,row.actor,row.target,row.linkRole||'',row.linkSession||'']);
    rows.set(row.key,row);
  };
  for(const term of visible){
    const labels=term.labels||{},id=labels['ask.id'],state=labels['ask.state']||'open';
    const role=labels['recovery.role'],expiry=Date.parse(labels['ask.expires']);
    if(/^q[0-9]{14}[0-9a-f]{6}$/.test(id||'')&&labels['ask.text']&&labels['ask.session']===term.session
      &&uniqueRole(role)===term&&['open','sending','needs-check','sent'].includes(state)
      &&(!Number.isFinite(expiry)||expiry>now)){
      const linkRole=labels['ask.approval_role']||'',linkSession=labels['ask.approval_session']||'';
      const candidate=linkRole?uniqueRole(linkRole):term;
      const target=candidate&&(!linkRole||candidate.session===linkSession)?candidate:null;
      const answered=state==='sent'||['sent','resolved_sent'].includes(ledger[id]);
      if(!answered||(linkRole&&target?.status==='blocked')){
        const stamp=id.slice(1,15),iso=stamp.slice(0,4)+'-'+stamp.slice(4,6)+'-'+stamp.slice(6,8)+'T'+stamp.slice(8,10)+':'+stamp.slice(10,12)+':'+stamp.slice(12,14)+'.000Z';
        const parsed=Date.parse(iso),since=Number.isFinite(parsed)&&new Date(parsed).toISOString()===iso&&parsed<=now?parsed:null;
        add({key:'ask:'+id+':'+term.session,kind:'question',requestId:id,summary:String(labels['ask.text']).slice(0,2000),since,
          target:identity(target),linkRole,linkSession,status:target?'registered':'target-unconfirmed'},term);
      }
    }
    if(term.status==='blocked'){
      const since=Number.isFinite(term.statusMs)&&term.statusMs>0&&term.statusMs<=now?term.statusMs:null;
      add({key:'blocked:'+term.address+':'+term.session,kind:'blocked',requestId:null,summary:null,since,target:identity(!role||uniqueRole(role)===term?term:null),status:'cause-unconfirmed'},term);
    }
  }
  return [...rows.values()].sort((a,b)=>(a.kind==='question'?0:1)-(b.kind==='question'?0:1)||(a.since??Infinity)-(b.since??Infinity)||a.key.localeCompare(b.key));
}

const escapeInbox=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
export function waitingInboxMarkup(items,copy,connected=true,now=Date.now()) {
  return items.map(item=>{
    const age=item.since===null?copy('waitingTimeUnknown'):copy('waitingMinutes').replace('{n}',String(Math.floor((now-item.since)/60000)));
    const kind=copy(item.kind==='question'?'waitingRegistered':'waitingUnknown');
    const summary=item.summary||copy('waitingPurposeUnknown');
    const person=(label,name,team,path)=>'<div class="waiting-identity" data-waiting-identity><small>'+escapeInbox(copy(label))+'</small><div><strong>'+escapeInbox(name||copy('waitingTargetUnknown'))+'</strong>'+(team?' <small>· '+escapeInbox(team)+'</small>':'')+'<b>'+escapeInbox(path.join(' → '))+'</b></div></div>';
    const identities=item.kind==='question'
      ?person('waitingRegisteredBy',item.origin.label,item.origin.team,item.origin.path)+person('waitingOpenTarget',item.targetLabel,item.targetTeam,item.targetPath)
      :person('waitingBlockedActor',item.origin.label,item.origin.team,item.origin.path);
    return '<article class="waiting-row" data-waiting-kind="'+item.kind+'"><div class="waiting-meta"><strong>'+escapeInbox(item.team||copy('waitingTeamUnknown'))+'</strong><span>'+escapeInbox(kind)+'</span><time>'+escapeInbox(age)+'</time></div>'
      +'<div class="waiting-detail">'+identities+'<p>'+escapeInbox(summary)+'</p><small>'+escapeInbox(copy('waitingCommandUnknown'))+(item.kind==='question'?' · '+escapeInbox(copy('waitingSummaryOnly')):'')+'</small></div>'
      +'<button type="button" data-inbox-key="'+escapeInbox(item.key)+'" data-inbox-binding="'+escapeInbox(item.binding)+'"'+(connected&&item.target?'':' disabled')+'>'+escapeInbox(copy(item.target?'waitingOpen':'waitingTargetUnknown'))+'</button></article>';
  }).join('');
}

/** Items not already shown as a card in the open conversation, so each waits in one place. `shown`: the question ids
 *  and the blocked members' addresses that the conversation's cards show right now. */
export function notShownInChat(items, shown) {
  return items.filter(item => item.kind === 'question' ? !shown.questions.has(item.requestId)
    : !(item.kind === 'blocked' && shown.blocked.has(item.actor?.address)));
}
