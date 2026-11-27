import assert from 'node:assert/strict';
import {test} from 'node:test';
import {waitingInboxItems,waitingInboxMarkup} from '../Resources/web/waiting-inbox.js';

const now=Date.parse('2026-11-19T09:00:00Z');
const term=(address,role,parent=null,labels={})=>({address,session:'800:71',state:'live',program:{agent:true},status:'working',label:role,team:'Team',teamID:'team',parent,labels:{'recovery.role':role,...labels}});
const question={'ask.id':'q20261119085900aabbcc','ask.text':'Registered purpose','ask.session':'800:71','ask.state':'open','ask.approval_role':'worker','ask.approval_session':'800:71'};

test('global inbox finds deep descendants and separately labels registered questions and unknown blockers',()=>{
  const inventory=[term('lead','lead'),term('middle','middle','lead'),term('worker','worker','middle'),term('deep','deep','worker',question)];
  inventory[2].status='blocked';
  const rows=waitingInboxItems(inventory,{},now);
  assert.equal(rows.length,2);
  const known=rows.find(row=>row.kind==='question'), unknown=rows.find(row=>row.kind==='blocked');
  assert.equal(known.summary,'Registered purpose');assert.equal(known.command,null);
  assert.deepEqual(known.path,['lead','middle','worker','deep']);
  assert.equal(known.target.address,'worker');assert.equal(known.target.session,'800:71');
  assert.equal(unknown.summary,null);assert.equal(unknown.command,null);assert.equal(unknown.since,null);
});

test('resolution, expiry and session changes remove stale waiting items',()=>{
  const worker={...term('worker','worker'),status:'blocked',statusMs:now-10000};
  const asker=term('asker','asker',null,question);
  assert.equal(waitingInboxItems([worker,asker],{},now).length,2);
  assert.equal(waitingInboxItems([{...worker,status:'working'},{...asker,labels:{...asker.labels,'ask.state':'acked'}}],{},now).length,0);
  assert.equal(waitingInboxItems([worker,{...asker,labels:{...asker.labels,'ask.expires':'2026-11-19T08:59:59Z'}}],{},now).length,1);
  assert.equal(waitingInboxItems([worker,{...asker,session:'900:72'}],{},now).length,1);
});

test('unregistered native blockers and other visible teams remain visible; cycles and remote parents are bounded',()=>{
  const a={...term('lab/a','a','b'),machine:'lab',status:'blocked',team:'Other'};
  const b={...term('lab/b','b','a'),machine:'lab'};
  const unregistered={...term('unregistered',''),labels:{},status:'blocked'};
  const rows=waitingInboxItems([a,b,unregistered],{},now);
  assert.equal(rows.length,2);assert.equal(rows.find(row=>row.actor.address==='lab/a').team,'Other');
  assert.ok(rows.find(row=>row.actor.address==='lab/a').path.length<=2);
});

test('ambiguous target has no open action and updated binding changes click fingerprint',()=>{
  const asker=term('asker','asker',null,question), worker=term('worker','worker');
  const first=waitingInboxItems([asker,worker],{},now)[0];
  assert.ok(first.target);
  const changed={...worker,session:'900:72'};
  const later=waitingInboxItems([asker,changed],{},now)[0];
  assert.equal(later.target,null);assert.notEqual(first.binding,later.binding);
  assert.equal(waitingInboxItems([asker,worker,term('duplicate','worker')],{},now)[0].target,null);
});

test('markup escapes registered summaries and has only honest open controls',()=>{
  const actor=term('asker','asker',null,{...question,'ask.text':'<script>private()</script>'});
  const html=waitingInboxMarkup(waitingInboxItems([actor,term('worker','worker')],{},now),key=>key,true,now);
  assert.ok(html.includes('&lt;script&gt;'));assert.ok(!html.includes('<script>'));
  assert.ok(html.includes('waitingSummaryOnly'));assert.ok(html.includes('waitingOpen'));
  assert.ok(!html.includes('data-approve'));assert.ok(!html.includes('data-deny'));
  assert.ok(waitingInboxMarkup(waitingInboxItems([actor,term('worker','worker')],{},now),key=>key,false,now).includes(' disabled'));
});

test('I04 registered origin and deep linked target have separate visible identities and parent paths',()=>{
  const hq=term('hq','hq'),origin={...term('origin','origin','hq',question),label:'Origin Lead',team:'Origin Team'};
  origin.labels={...origin.labels,'ask.approval_role':'deep-qa'};
  const lead={...term('target-lead','target-lead','hq'),label:'Target Lead',team:'Target Team'};
  const qaLead={...term('qa-lead','qa-lead','target-lead'),label:'QA Lead',team:'Target Team'};
  const deep={...term('deep-qa','deep-qa','qa-lead'),label:'Target Deep QA',team:'Target Team',status:'blocked'};
  const items=waitingInboxItems([hq,origin,lead,qaLead,deep],{},now),known=items.find(item=>item.kind==='question');
  assert.ok(known.origin);assert.equal(known.origin.actor.address,'origin');assert.deepEqual(known.origin.path,['hq','Origin Lead']);
  assert.equal(known.target.address,'deep-qa');assert.equal(known.targetLabel,'Target Deep QA');
  assert.deepEqual(known.targetPath,['hq','Target Lead','QA Lead','Target Deep QA']);
  const html=waitingInboxMarkup([known],key=>key,true,now);
  assert.ok(html.includes('Origin Lead'));assert.ok(html.includes('Target Deep QA'));assert.ok(html.includes('QA Lead'));
  assert.ok(html.includes('waitingRegisteredBy'));assert.ok(html.includes('waitingOpenTarget'));
  const unknown=waitingInboxMarkup(items.filter(item=>item.kind==='blocked'),key=>key,true,now);
  assert.equal((unknown.match(/data-waiting-identity/g)||[]).length,1);
});

test('a waiting item already shown in the open conversation is left out of the top list', async () => {
  const {notShownInChat} = await import('../Resources/web/waiting-inbox.js');
  const items = [{key: 'a', actor: {address: 't1'}, target: {address: 't1'}}, {key: 'b', actor: {address: 't9'}, target: {address: 't2'}},
    {key: 'c', actor: {address: 't7'}, target: null}];
  assert.deepEqual(notShownInChat(items, new Set(['t1'])).map(i => i.key), ['b', 'c']);
  assert.deepEqual(notShownInChat(items, new Set(['t2'])).map(i => i.key), ['a', 'c']);
  assert.deepEqual(notShownInChat(items, new Set()).map(i => i.key), ['a', 'b', 'c']);
});
