import assert from 'node:assert/strict';
import { test } from 'node:test';
import { languageFrom, t } from '../Resources/web/locale.js';
import { displayedStatus, observedAgentStatus, makeInventory, sendable } from '../Resources/web/model.js';

test('language preference supports English, Korean and Japanese', () => {
  assert.equal(languageFrom('en-US'), 'en');
  assert.equal(languageFrom('ko-KR'), 'ko');
  assert.equal(languageFrom('ja-JP'), 'ja');
  assert.equal(languageFrom('fr-FR'), 'en');
  assert.equal(new Set(['en','ko','ja'].map(locale => t('assign', locale))).size, 3);
});

test('unlabelled terminals use space placement and a remote address keeps its machine', () => {
  const terminal = { address: 'lab/t3', name: 'review', state: 'live', session: '800:72', program: {agent: true}, status: 'idle' };
  const spaces = [{name: 'Documentation', machine:'lab', tabs: [{name:'QA', terminals:['t3'] }]}];
  const [entry] = makeInventory([terminal], spaces);
  assert.equal(entry.team, 'Documentation');
  assert.equal(entry.machine, 'lab');
  assert.equal(entry.label, 'review');
  assert.equal(entry.location.tab, 'QA');
  assert.equal(sendable(entry,'live'), true);
  assert.equal(sendable(entry,'lost'), false);
  assert.equal(sendable({...entry,status:'blocked'},'live'), false);
});

test('explicit labels override space placement and a terminal parent stays separate', () => {
  const [parent, child] = makeInventory([
    {address:'t1',name:'Coordinator',state:'live'},
    {address:'t2',name:'Reviewer',state:'live',parent:'t1',labels:{'team.id':'release','team.title':'Release Team'}}
  ], [{name:'Workspace', tabs:[{name:'Team', terminals:['t1','t2']}]}]);
  assert.equal(parent.team,'Workspace');
  assert.equal(child.team,'Release Team');
  assert.equal(child.parentName,'Coordinator');
});

import { explicitHandoffs, registeredQuestions } from '../Resources/web/model.js';

const now = Date.parse('2026-01-02T10:00:00Z');
const terminal = (address, role, labels = {}) => ({
  address, state:'live', session:'42:50', label:role, program:{agent:true}, status:'idle', labels:{'recovery.role':role,...labels}
});
test('handoffs require explicit current labels and accepted receipts', () => {
  const member = terminal('t2','worker',{'flow.id':'f20260102095000aabbcc','flow.from':'lead','flow.task':'Check',
     'flow.phase':'result-sent','flow.session':'42:50','flow.updated':'2026-01-02T09:59:00Z'});
  const lead = terminal('t1','lead',{'flowack.f20260102095000aabbcc':'2026-01-02T10:00:00Z|worker|42:50'});
  const [item] = explicitHandoffs([lead,member],now);
  assert.equal(item.from.address,'t2');
  assert.equal(item.to.address,'t1');
  assert.equal(item.state,'questionAck');
  assert.equal(item.startedAt,Date.parse('2026-01-02T09:50:00Z'));
  assert.deepEqual(explicitHandoffs([lead,{...member,session:'42:51'}],now),[]);
  assert.deepEqual(explicitHandoffs([lead,terminal('t3','lead'),member],now),[]);
});

test('questions reject expired sessions and retain unconfirmed delivery', () => {
  const id = 'q20260102100000aabbcc';
  const asker = terminal('t1','lead',{'ask.id':id,'ask.text':'Which build?','ask.session':'42:50',
    'ask.expires':'2026-01-02T11:00:00Z','ask.choices':'["Alpha","Beta"]'});
  assert.equal(registeredQuestions([asker],{},now)[0].answerable,true);
  assert.equal(registeredQuestions([asker],{},now)[0].at,now);
  assert.equal(registeredQuestions([asker],{[id]:'needs_check'},now)[0].answerable,false);
  assert.equal(registeredQuestions([asker],{[id]:'needs_check'},now)[0].state,'needsCheck');
  assert.deepEqual(registeredQuestions([asker,{...asker,address:'t2'}],{},now),[]);
  assert.deepEqual(registeredQuestions([asker],{},now+7200000),[]);
});

import { attentionCount } from '../Resources/web/model.js';

test('an explicit question is counted and its linked approval address needs an exact current session', () => {
  const id='q20260102100000aabbcc';
  const asker=terminal('t1','asker',{'ask.id':id,'ask.text':'Approve?', 'ask.session':'42:50',
    'ask.approval_role':'operator','ask.approval_session':'42:50'});
  const target={...terminal('peer/t2','operator'),status:'blocked'};
  const terms=[asker,target];
  const queue=registeredQuestions(terms,{},now);
  assert.equal(queue[0].approval.address,'peer/t2');
  assert.equal(attentionCount(terms,queue),1);
  assert.equal(attentionCount([asker],registeredQuestions([asker],{},now)),1);
  const stale=registeredQuestions([asker,{...target,session:'42:51'}],{},now);
  assert.equal(stale[0].approval.address,null);
  assert.equal(registeredQuestions([asker,target,terminal('peer/t3','operator')],{},now)[0].approval.address,null);
});

import { makeTeamDirectory } from '../Resources/web/model.js';

test('directory preserves registered roles, nested reporting and unmatched terminals', () => {
  const setup=[{id:'release',title:'Release',lead:'lead',roles:[['lead','Lead'],['qa','QA'],['device','Device']],parents:{device:'qa'}}];
  const inventory=makeInventory([
    terminal('t1','lead'),terminal('t2','qa'),{...terminal('t3','extra'),parent:'t2'},
    {address:'t4',name:'Shell',session:'2:4',state:'live'}
  ],[],setup);
  const [group,other]=makeTeamDirectory(inventory,setup);
  const [lead]=group.roots;
  assert.equal(lead.role,'lead');
  const [qa]=lead.children;
  assert.deepEqual(qa.children.map(node=>[node.role,Boolean(node.term)]),[['device',false],['extra',true]]);
  assert.equal(other.roots[0].term.address,'t4');
});

test('directory renders each terminal once with cycles and ambiguous roles', () => {
  const setup=[{id:'test',title:'Test',lead:'lead',roles:[['lead','Lead'],['worker','Worker']]}];
  const inventory=makeInventory([
    {...terminal('t1','lead'),parent:'t2'},{...terminal('t2','worker'),parent:'t1'},
    terminal('t3','lead')
  ],[],setup);
  const flatten=nodes=>nodes.flatMap(node=>[node.term?.address,...flatten(node.children)]);
  assert.deepEqual(flatten(makeTeamDirectory(inventory,setup)[0].roots).sort(),['t1','t2','t3']);
});

test('a cleared working report applies to only the same live session, turn and timestamp', () => {
  const term = { status: 'working', session: '123:45', turn: 12, statusMs: 600,
    labels: { 'dashboard.working_cleared': '123:45|12|600' } };
  assert.equal(displayedStatus(term), 'done');
  assert.equal(displayedStatus({ ...term, turn: 13 }), 'working');
  assert.equal(displayedStatus({ ...term, session: '789:56' }), 'working');
  assert.equal(displayedStatus({ ...term, statusMs: 601 }), 'working');
  assert.equal(displayedStatus({ ...term, status: 'blocked' }), 'blocked');
});


test('a fresh provider turn overrides only older core status', () => {
  const statusMs=Date.parse('2026-11-19T03:00:00Z');
  const term={status:'working',session:'1:2',turn:102,statusMs,labels:{'dashboard.working_cleared':`1:2|102|${statusMs}`}};
  const turn={state:'working',at:'2026-11-19T03:01:00Z'};
  assert.equal(observedAgentStatus(term), 'done');
  assert.equal(observedAgentStatus(term,turn), 'working');
  assert.equal(observedAgentStatus(term,{...turn,state:'done'}), 'done');
  assert.equal(observedAgentStatus({...term,status:'blocked'},turn), 'blocked');
  assert.equal(observedAgentStatus({...term,status:'idle',statusMs:statusMs+120000},turn), 'idle');
});

import { mergeConversationRecords } from '../Resources/web/model.js';
test('automatic final merges one explicit copy within its own turn, regardless of arrival order', () => {
  const final = {id:'auto1',kind:'reply',role:'lead',session:'s1',turn:'p1',turnStartedAt:'2026-11-19T00:00:00Z',turnEndedAt:'2026-11-19T00:00:03Z',body:'Same',at:'2026-11-19T00:00:02Z'};
  const explicit = {id:'explicit1',kind:'reply',role:'lead',session:'s1',body:'Same',at:'2026-11-19T00:00:01Z'};
  assert.deepEqual(mergeConversationRecords([explicit],[final]).map(x=>x.id),['auto1']);
  const second = {...final,id:'auto2',turn:'p2',turnStartedAt:'2026-11-19T00:00:04Z',turnEndedAt:'2026-11-19T00:00:07Z',at:'2026-11-19T00:00:06Z'};
  assert.equal(mergeConversationRecords([explicit],[final,second]).length,2);
  for(const changed of [{session:'s2'},{body:'Different'},{at:'invalid'},{at:'2026-11-19T01:00:00Z'}]) {
    assert.equal(mergeConversationRecords([{...explicit,...changed}],[final]).length,2);
  }
  assert.equal(mergeConversationRecords([explicit],[{...final,turn:''}]).length,2);
  assert.equal(mergeConversationRecords([explicit],[{...final,turnEndedAt:''}]).length,2);
  assert.equal(mergeConversationRecords([explicit,{...explicit,id:'explicit2'}],[final]).length,2);
  assert.equal(mergeConversationRecords([{...explicit,at:'2026-11-19T00:00:00Z'}],[{...final,turnStartedAt:'2026-11-19T00:00:00.500Z'}]).length,1);
  const adjacent={...final,id:'auto3',turn:'p3',turnStartedAt:'2026-11-19T00:00:00.600Z'};
  assert.equal(mergeConversationRecords([{...explicit,at:'2026-11-19T00:00:00Z'}],[{...final,turnEndedAt:'2026-11-19T00:00:00.550Z'},adjacent]).length,3);
  assert.equal(mergeConversationRecords([explicit],[final])[0].publicationID,'explicit1');
});

test('a herdr-reply copy merges with the transcript final that only adds emphasis and a citation footer', () => {
  const final = {id:'auto1',kind:'reply',role:'lead',session:'s1',turn:'p1',turnStartedAt:'2026-11-20T04:05:14.248Z',turnEndedAt:'2026-11-20T04:08:28.363Z',
    body:'파일에 **OK**를 기록했습니다.\n\n<oai-mem-citation>\n<citation_entries>\nMEMORY.md:3-3\n</citation_entries>\n</oai-mem-citation>',at:'2026-11-20T04:08:28.131Z'};
  const explicit = {id:'explicit1',kind:'reply',role:'lead',session:'s1',body:'파일에 OK를 기록했습니다.',at:'2026-11-20T04:08:23.076+00:00'};
  assert.deepEqual(mergeConversationRecords([explicit],[final]).map(x=>x.id),['auto1']);
});

test('a herdr-reply copy merges even when the final adds code ticks and line breaks', () => {
  const final = {id:'auto2',kind:'reply',role:'lead',session:'s1',turn:'p2',turnStartedAt:'2026-11-20T04:50:00Z',turnEndedAt:'2026-11-20T04:52:00Z',
    body:'t1p가 flow `f2026` 을 **done**으로 닫았고,\n\n제품 재실행은 없었습니다.',at:'2026-11-20T04:51:50Z'};
  const explicit = {id:'explicit2',kind:'reply',role:'lead',session:'s1',body:'t1p가 flow f2026을 done으로 닫았고, 제품 재실행은 없었습니다.',at:'2026-11-20T04:51:45Z'};
  assert.deepEqual(mergeConversationRecords([explicit],[final]).map(x=>x.id),['auto2']);
});
