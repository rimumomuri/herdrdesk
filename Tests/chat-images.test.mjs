import test from 'node:test';
import assert from 'node:assert/strict';
import {appendLegacySend, combineChat} from '../Resources/web/compatibility.js';
const module = await import('../Resources/web/chat-images.js').catch(()=>({}));
test('native PNG previews render with escaped labels; URLs and oversized payloads cannot become image src',()=>{
 assert.equal(typeof module.chatImageMarkup,'function');
 const html=module.chatImageMarkup([{name:'"<img onerror=x>',thumbnail:'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aFKsAAAAASUVORK5CYII='}]);
 assert.match(html,/src="data:image\/png;base64,/);assert.ok(!html.includes('<img onerror'));
 for(const thumbnail of ['https://evil/x.png','file:///private/key.png','A'.repeat(200000)])assert.ok(!module.chatImageMarkup([{name:'missing',thumbnail}]).includes('src='));
});
test('sent native attachment previews stay attached to the direct message before history compaction',()=>{
 const previews=[{name:'one.png',thumbnail:'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aFKsAAAAASUVORK5CYII='}];
 const record={id:'message01',role:'lead',session:'1:2',address:'t1',target:'t1:1:2',conversationId:'room:team',state:'sent',text:'photo',at:100,previews};
 const saved=JSON.parse(JSON.stringify(appendLegacySend({},record,'lead')));
 const term={address:'t1',session:'1:2',label:'Lead',labels:{'recovery.role':'lead'}};
 assert.deepEqual(combineChat(term,saved,[],[])[0].previews,previews);
});
test('visible exact bindings request once and changed bodies never inherit cached thumbnails',()=>{
 assert.equal(typeof module.ChatImagePreviews,'function');
 const sent=[];let changes=0;const client=new module.ChatImagePreviews(row=>sent.push(row),()=>changes++);
 const record={id:'r1',role:'lead',session:'1:2',body:'![x](/Users/demo/Pictures/a.png)'};
 const initial=client.markup(record);const token=initial.match(/data-chat-preview="([^"]+)"/)[1];
 assert.equal(sent.length,0);client.request(token);client.request(token);assert.equal(sent.length,1);
 assert.deepEqual(sent[0],{type:'chatImages',token,...record});
 client.receive({token:'unknown',previews:[{name:'wrong',thumbnail:'bad'}]});assert.equal(changes,0);
 client.receive({token,previews:[{name:'a.png',thumbnail:'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aFKsAAAAASUVORK5CYII='}]});
 assert.match(client.markup(record),/data:image\/png/);
 for(const mutation of [{body:'![x](/Users/demo/Pictures/b.png)'},{role:'other'},{session:'2:3'}])assert.ok(!client.markup({...record,...mutation}).includes('data:image'));
});
test('failed sends do not preserve preview bytes',()=>{
 const saved=appendLegacySend({},{id:'fail001',state:'notSent',at:100,previews:[{name:'a',thumbnail:'abc'}]},'lead');
 assert.equal(saved.lead[0].previews,undefined);
});

test('captionless sent image history keeps exact native binding without duplicating base64 in localStorage',()=>{
 const row={id:'mcaptionless',role:'lead',session:'1:2',text:'',images:1,previews:[{name:'a.png',thumbnail:'abc'}]};
 const saved=JSON.parse(JSON.stringify(module.chatImageHistory([row])))[0];
 assert.deepEqual(saved,{id:'mcaptionless',role:'lead',session:'1:2',text:'',images:1});
 const sent=[];const client=new module.ChatImagePreviews(x=>sent.push(x),()=>{});
 const html=client.markup({id:saved.id,role:saved.role,session:saved.session,body:saved.text,sentImages:true});
 const token=html.match(/data-chat-preview="([^"]+)"/)[1];client.request(token);
 assert.equal(sent[0].body,'');assert.equal(sent[0].session,'1:2');
});
