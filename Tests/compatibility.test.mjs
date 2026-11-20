import assert from 'node:assert/strict';
import { test } from 'node:test';
import { combineChat, legacyDraftKey, archiveRoles, appendLegacySend } from '../Resources/web/compatibility.js';

const old = { reviewer:[{id:'mold',session:'1:2',text:'Archived text',images:1,at:'2026-11-18T00:00:00Z'},
                       {id:'mnew',session:'6:7',text:'Newest',at:'2026-11-18T01:00:00Z'}] };
const term = {address:'remote/t3', session:'6:7',labels:{'recovery.role':'reviewer'}};
const deliveries = [{id:'mnew',state:'sent',text:'Newest',at:Date.parse('2026-11-18T01:00:00Z'),role:'reviewer',target:'remote/t3:6:7'}];

test('legacy and current chat deduplicate on id and survive an address and session change', () => {
  const chat=combineChat(term,old,deliveries,[]);
  assert.deepEqual(chat.map(item=>item.text),['Archived text','Newest']);
  assert.equal(chat[0].images,1);
  assert.equal(combineChat({...term,address:'t9',session:'8:9'},old,deliveries,[]).length,2);
});
test('roles with existing drafts or replies stay discoverable without a live terminal', () => {
  assert.deepEqual(archiveRoles([],old,{other:'A draft'},[{role:'replying'}]),['other','replying','reviewer']);
  assert.equal(legacyDraftKey(term), 'reviewer');
  assert.equal(legacyDraftKey({...term,labels:{}}), null);
});
test('sent work is readable from the legacy app without deleting any existing record', () => {
  const updated=appendLegacySend(old,{...deliveries[0],id:'mthird',text:'Third',images:2},'reviewer');
  assert.deepEqual(updated.reviewer.map(item=>item.id),['mold','mnew','mthird']);
  assert.equal(updated.reviewer.at(-1).images,2);
  assert.equal(old.reviewer.length,2);
});

test('published user messages and assistant replies preserve their author and full body', () => {
  const body='x'.repeat(10000);
  const chat=combineChat(term,old,deliveries,[
    {id:'mold',role:'reviewer',kind:'message',body:'duplicate',at:'2026-11-18T00:00:00Z'},
    {id:'r1',role:'reviewer',kind:'message',body,at:'2026-11-18T02:00:00Z'},
    {id:'r2',role:'reviewer',kind:'reply',body:'reply',at:'2026-11-18T03:00:00Z'}
  ]);
  assert.equal(chat[0].text,'Archived text');
  assert.equal(chat[2].text.length,10000);
  assert.equal(chat[2].from,null);
  assert.equal(chat[3].state,'reply');
});

test('a retired role key reads as team and role in plain words', async () => {
  const { retiredRoleName } = await import('../Resources/web/compatibility.js');
  const teams = [{ id: 'shop', title: '숍' }, { id: 'cafe', title: '카페' }];
  assert.equal(retiredRoleName('shop-production', teams), '숍 · 제작');
  assert.equal(retiredRoleName('cafe-qa', teams), '카페 · QA');
  assert.equal(retiredRoleName('shop-concepts', teams), '숍 · 시안');
  assert.equal(retiredRoleName('unknown-thing', teams), 'unknown-thing');
  assert.equal(retiredRoleName('', teams), '');
});
