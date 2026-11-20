import {waitingInboxItems,waitingInboxMarkup} from './waiting-inbox.js';
const same=(a,b)=>a&&b&&['address','session','role'].every(key=>(a[key]||'')===(b[key]||''));
const lineageActive=(record,now)=>Number.isFinite(record?.expiresAt)&&record.expiresAt>now;
const escapeLineage=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));

export function lineageForMessage(snapshot, conversationId, originRequestId, inventory, now=Date.now()) {
  if(!snapshot||!conversationId||!originRequestId)return null;
  const roots=(snapshot.roots||[]).filter(root=>root.originRequestId===originRequestId);
  if(roots.length!==1||roots[0].conversationId!==conversationId||!lineageActive(roots[0],now))return null;
  const root=roots[0],all=snapshot.tasks||[];
  if(new Set(all.map(task=>task.id)).size!==all.length)return null;
  const tasks=all.filter(task=>task.originRequestId===originRequestId);
  const byId=new Map(tasks.map(task=>[task.id,task]));
  for(const task of tasks){
    if(!lineageActive(task,now)||task.expiresAt>root.expiresAt)return null;
    const seen=new Set([task.id]);let parent=task.parentTaskId,depth=1;
    if(!parent&&!same(task.owner,root.recipient))return null;
    while(parent){
      if(seen.has(parent)||++depth>16)return null;
      seen.add(parent);const ancestor=byId.get(parent);if(!ancestor)return null;
      parent=ancestor.parentTaskId;
    }
  }
  const edges=(snapshot.edges||[]).filter(edge=>edge.originRequestId===originRequestId),seenChildren=new Set();
  if(new Set(edges.map(edge=>edge.id)).size!==edges.length)return null;
  for(const edge of edges){
    const parent=byId.get(edge.parentTaskId),child=byId.get(edge.childTaskId);
    if(!parent||!child||child.parentTaskId!==parent.id||!same(parent.owner,edge.from)||!same(child.owner,edge.to)
      ||seenChildren.has(child.id)||!['intent','dispatching','dispatched','not_sent','needs_check'].includes(edge.delivery))return null;
    if(edge.acceptedAt&&edge.delivery==='intent')return null;
    if(edge.completedAt&&!edge.acceptedAt)return null;
    seenChildren.add(child.id);
  }
  const pendingLinks=(snapshot.pendingLinks||[]).filter(link=>link.originRequestId===originRequestId&&link.kind==='manualAsk'&&lineageActive(link,now))
    .filter(link=>byId.has(link.taskId)&&!byId.get(link.taskId).completedAt&&same(byId.get(link.taskId).owner,link.requester)&&link.expiresAt<=byId.get(link.taskId).expiresAt);
  if(new Set(pendingLinks.map(link=>link.id)).size!==pendingLinks.length)return null;
  return {root,tasks,edges,pendingLinks};
}

export function linkedWaiting(snapshot,inventory,ledger={},now=Date.now()) {
  const waiting=waitingInboxItems(inventory,ledger,now),links=[];
  for(const root of snapshot?.roots||[]){
    const tree=lineageForMessage(snapshot,root.conversationId,root.originRequestId,inventory,now);if(!tree)continue;
    for(const link of tree.pendingLinks){
      const row=waiting.find(item=>item.kind==='question'&&item.requestId===link.requestId&&same(item.actor,link.requester)&&same(item.target,link.target));
      if(row)links.push({link,row,root});
    }
  }
  return links.filter(item=>links.filter(other=>other.row.key===item.row.key).length===1);
}

export function lineageMarkup(snapshot,conversationId,originRequestId,inventory,ledger,copy,now=Date.now()) {
  const tree=lineageForMessage(snapshot,conversationId,originRequestId,inventory,now);
  if(!tree||!tree.tasks.length)return '';
  const waiting=linkedWaiting(snapshot,inventory,ledger,now);
  const ownerName=identity=>{
    const term=inventory.find(term=>term.address===identity.address&&term.session===identity.session&&(term.labels?.['recovery.role']||'')===identity.role);
    return term?.label||identity.role||identity.address;
  };
  const node=task=>{
    const edge=tree.edges.find(edge=>edge.childTaskId===task.id);
    const status=task.completedAt?'lineageCompleted':task.acceptedAt?'lineageAccepted':'lineageDeclared';
    const children=tree.tasks.filter(child=>child.parentTaskId===task.id);
    const pending=waiting.filter(item=>item.link.taskId===task.id&&item.root.originRequestId===originRequestId);
    return '<li data-lineage-task="'+escapeLineage(task.id)+'"><div class="lineage-task"><strong>'+escapeLineage(ownerName(task.owner))+'</strong><code>'+escapeLineage(task.id)+'</code><span>'+escapeLineage(copy(status))+'</span>'
      +(edge?'<small>'+escapeLineage(copy('lineageDelivery.'+edge.delivery))+'</small>':'')+'</div>'
      +pending.map(({link,row})=>'<div class="lineage-pending" data-lineage-pending="'+escapeLineage(link.id)+'" data-lineage-task="'+escapeLineage(task.id)+'" data-lineage-root="'+escapeLineage(originRequestId)+'" data-lineage-conversation="'+escapeLineage(conversationId)+'"><small>'+escapeLineage(copy('lineageManual'))+'</small>'+waitingInboxMarkup([row],copy,true,now)+'</div>').join('')
      +(children.length?'<ol>'+children.map(node).join('')+'</ol>':'')+'</li>';
  };
  return '<details class="request-lineage" open data-origin-request="'+escapeLineage(originRequestId)+'"><summary>'+escapeLineage(copy('lineageTitle'))+' · '+tree.tasks.length+'</summary><ol>'+tree.tasks.filter(task=>!task.parentTaskId).map(node).join('')+'</ol></details>';
}
