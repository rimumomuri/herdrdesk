import assert from 'node:assert/strict';
import {test} from 'node:test';
import {lineageForMessage,linkedWaiting,lineageMarkup} from '../Resources/web/lineage.js';
import {combineChat,appendLegacySend} from '../Resources/web/compatibility.js';
const owner={address:'t1',session:'800:71',role:'lead'}, child={address:'t2',session:'900:72',role:'worker'};
const now=1000, graph={roots:[{originRequestId:'mRoot001',conversationId:'room:one',recipient:owner,expiresAt:5000}],tasks:[{id:'root',originRequestId:'mRoot001',owner,expiresAt:5000},{id:'child',originRequestId:'mRoot001',parentTaskId:'root',owner:child,expiresAt:5000}],edges:[{id:'edge',originRequestId:'mRoot001',parentTaskId:'root',childTaskId:'child',from:owner,to:child,delivery:'intent'}],pendingLinks:[]};
test('lineage is attached only to the exact original conversation and message, never by team or selected actor',()=>{
  const tree=lineageForMessage(graph,'room:one','mRoot001',[],now);
  assert.ok(tree);assert.equal(tree.tasks.length,2);assert.equal(tree.edges[0].delivery,'intent');
  assert.equal(lineageForMessage(graph,'room:two','mRoot001',[],now),null);
  assert.equal(lineageForMessage(graph,'room:one','another-message',[],now),null);
  assert.equal(lineageForMessage({...graph,roots:[]},'room:one','mRoot001',[],now),null);
});
test('cross-root, cycles, duplicate edges, stale roots and over-depth graphs fail closed',()=>{
  const check=graph=>lineageForMessage(graph,'room:one','mRoot001',[],now);
  assert.equal(check({...graph,roots:[{...graph.roots[0],expiresAt:now}]}),null);
  assert.equal(check({...graph,tasks:[graph.tasks[0],{...graph.tasks[1],originRequestId:'other'}]}),null);
  assert.equal(check({...graph,tasks:[{...graph.tasks[0],parentTaskId:'child'},graph.tasks[1]]}),null);
  assert.equal(check({...graph,edges:[...graph.edges,graph.edges[0]]}),null);
  const tasks=[graph.tasks[0]];for(let i=1;i<=16;i++)tasks.push({id:'d'+i,originRequestId:'mRoot001',parentTaskId:i===1?'root':'d'+(i-1),owner,expiresAt:5000});
  assert.equal(check({...graph,tasks,edges:[]}),null);
});
test('only exact explicit manual ask links attach; native blockers never become task approvals',()=>{
  const q='q20261119000000aabbcc';
  const term=(identity,labels={})=>({...identity,label:identity.role,state:'live',status:'working',program:{agent:true},labels:{'recovery.role':identity.role,...labels}});
  const inventory=[term(owner,{'ask.id':q,'ask.text':'Synthetic question','ask.session':owner.session,'ask.state':'open','ask.approval_role':child.role,'ask.approval_session':child.session}),{...term(child),status:'blocked'}];
  const link={id:'pending',kind:'manualAsk',originRequestId:'mRoot001',taskId:'root',requestId:q,requester:owner,target:child,expiresAt:5000};
  const snapshot={...graph,pendingLinks:[link]};
  const linked=linkedWaiting(snapshot,inventory,{},now);
  assert.equal(linked.length,1);assert.equal(linked[0].row.kind,'question');
  assert.equal(linkedWaiting({...graph,pendingLinks:[]},inventory,{},now).length,0);
  assert.equal(linkedWaiting(snapshot,inventory.map(item=>item.address===child.address?{...item,session:'900:99'}:item),{},now).length,0);
  assert.equal(linkedWaiting(snapshot,inventory,{[q]:'sent'},now).length,1); // still blocked, honest manual link
  const html=lineageMarkup(snapshot,'room:one','mRoot001',inventory,{},key=>key,now);
  assert.ok(html.includes('data-lineage-pending="pending"'));assert.ok(html.includes('lineageManual'));
  assert.ok(!html.includes('data-waiting-kind="blocked"'));assert.ok(!html.includes('data-approve'));
  assert.equal(lineageMarkup(snapshot,'room:other','mRoot001',inventory,{},key=>key,now),'');
  assert.equal(linkedWaiting({...snapshot,pendingLinks:[link,{...link,id:'ambiguous'}]},inventory,{},now).length,0);
});
test('new outgoing anchors retain exact conversation and state across history, without cross-chat association',()=>{
  const term={...owner,labels:{'recovery.role':owner.role}};
  const outgoing={id:'mRoot001',conversationId:'room:one',target:owner.address+':'+owner.session,...owner,text:'Synthetic original',at:1000,state:'needsCheck'};
  const legacy=appendLegacySend({},outgoing,owner.role);
  assert.equal(legacy.lead[0].conversationId,'room:one');assert.equal(legacy.lead[0].state,'needsCheck');
  assert.equal(combineChat(term,legacy,[],[],undefined,'direct:lead').length,0);
  assert.equal(combineChat(term,legacy,[],[],undefined,'room:one')[0].state,'needsCheck');
});
