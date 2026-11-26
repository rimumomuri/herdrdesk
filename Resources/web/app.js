import { chatImageMarkup, ChatImagePreviews, chatImageHistory } from './chat-images.js';
import { chatMarkdownBlocks } from './chat-markdown.js';
import { markdownDocumentHTML } from './md-view.js';
import { waitingInboxItems, waitingInboxMarkup } from './waiting-inbox.js';
import { lineageMarkup, linkedWaiting } from './lineage.js';
import { chatShortcutSegments } from './chat-shortcuts.js';
import { portraitArtwork, withWorkTool, sheepStyles, sheepCoats, resolveSheepStyle, sheepAccessories, resolveSheepAccessory } from "./portrait.js";
import { roleLook } from './role-look.js';
import { leadFaceHTML, agentFaceHTML, isCardWorker } from './herd-face.js';
import { t, languageFrom } from './locale.js';
import { shortRoleTitle, nextKey, chatHidden, foldLeadChats, inRoomConversation, groupRows, moveChat, moveSection, toggleSection, addSection, renameSection, deleteSection } from './chat-sections.js';
import { buildChain, handoffCardsFor, handoffCardHTML, isDelegating } from './handoff-chain.js';
import { teamFlows, markWaiting } from './team-flow.js';
import { messageTag, awaitingResponse, tagHTML } from './message-tags.js';
import { DEFAULT_SOUNDS, newHandoffs, attentionKeys, attentionTick } from './sound-rules.js';
import { sheep } from './sheep.js';
import { companionState, companionSummary, featuredAgent } from './companion.js';
import { agentTrouble, machineTrouble } from './trouble.js';
import { computerRows, computerStripHTML, computerSheetHTML, cloneTeams, slotsValue, cloneRequest, mainMachineLabel } from './computers.js';
import { boardColumns, teamCounts, boardCardHTML, teamCountsText, boardSummaryHTML, BOARD_LABELS } from './task-board.js';
import { questionFormHTML, questionFilesHTML, keepTyping } from './chat-questions.js';
import { attentionOf, autoUnread, markSeen, snoozeActive, snoozeUntil, nextUrgent, waitingCount } from './triage.js';
import { filterPalette, paletteHTML } from './palette.js';
import { sendBlocked, deferredSaver } from './composer.js';
import { freshEntries } from './motion.js';
import { stickyScroll } from './chat-scroll.js';
import { makeInventory, makeTeamDirectory, listedGroup, sendable, registeredQuestions, explicitHandoffs, attentionCount, mergeConversationRecords, completedAgentTurn, observedAgentStatus, memoLast } from './model.js';
import { legacyDraftKey, retiredRoleName, archiveRoles, combineChat, appendLegacySend, draftFor, storeDraftFor, storeJSON, LEGACY_SEND_LIMIT } from './compatibility.js';
import { enterAction, SEND_DEDUPE_MS } from './keys.js';
import { createTerminalView } from './terminal-view.js';

const $ = selector => document.querySelector(selector);
const post = message => window.webkit?.messageHandlers?.desk?.postMessage(message);
const escape = input => String(input ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
function renderChatInline(text) {
  return chatShortcutSegments(text).map(segment=>{
    if(typeof segment==='string'){
      return escape(segment).replace(/\*\*([^*\n]+)\*\*/g,'<strong>$1</strong>');
    }
    if(segment.kind==='code')return '<code>'+escape(segment.label)+'</code>';
    return '<a class="chat-shortcut" data-shortcut="'+segment.kind+'" href="'+escape(segment.href)+'" title="'+escape(segment.title)+'">'
      +'<span aria-hidden="true"><img src="vendor/chat-icons/'+segment.kind+'.svg" alt=""></span>'+escape(segment.label)+'</a>';
  }).join('');
}
function renderChatText(text) {
  return '<div class="chat-message-body">'+chatMarkdownBlocks(text).map(block=>{
    if(!block.header)return '<p>'+renderChatInline(block.text)+'</p>';
    const cells=(items,tag)=>items.map(value=>'<'+tag+(tag==='th'?' scope="col"':'')+'>'+renderChatInline(value)+'</'+tag+'>').join('');
    return '<div class="chat-table"><table><thead><tr>'+cells(block.header,'th')+'</tr></thead><tbody>'
      +block.rows.map(row=>'<tr>'+cells(row,'td')+'</tr>').join('')+'</tbody></table></div>';
  }).join('')+'</div>';
}
const imagePreviews=new ChatImagePreviews(post,()=>render());
const imageObserver=new IntersectionObserver(entries=>{
  for(const entry of entries)if(entry.isIntersecting){imagePreviews.request(entry.target.dataset.chatPreview);imageObserver.unobserve(entry.target);}
});
function observeChatImages(){
  imageObserver.disconnect();
  for(const element of document.querySelectorAll('[data-chat-preview]'))imageObserver.observe(element);
}
function messageImages(entry){
  if(Array.isArray(entry.previews))return chatImageMarkup(entry.previews);
  const previewRole=entry.role?.startsWith('session:')?entry.address:(entry.role||entry.address);
  const record=(entry.images>0&&previewRole&&entry.session)?{id:entry.id,role:previewRole,session:entry.session,body:entry.imageBody??entry.text??entry.body??'',sentImages:true}:conversationRecords().find(record=>record.id===entry.id&&record.body===(entry.body??entry.text));
  return imagePreviews.markup(record);
}
const load = (key, fallback) => { try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; } };
const save = (key, value) => storeJSON(localStorage, key, value);
const localeKey = 'ui.language.v1';
const draftsKey = 'portable.drafts.v1';
const deliveriesKey = 'portable.deliveries.v1';
let language = languageFrom(load(localeKey, navigator.language));
let localeChosen = Boolean(load(localeKey, null));
let systemLocaleApplied = false;
$('#automaticChat').addEventListener('change',event=>post({type:'automaticChat',enabled:event.target.checked}));
const soundEnabled=$('#soundEnabled');
soundEnabled.checked=load('ui.sound.v1',true)===true;
soundEnabled.addEventListener('change',()=>save('ui.sound.v1',soundEnabled.checked));
const playSound=cue=>{if(soundEnabled.checked)post({type:'sound',cue});};
// One macOS sound per event, picked in settings; '' turns that event off.
const soundPicks=[...document.querySelectorAll('select[data-sound]')];
const soundChoice=event=>load('ui.sound.'+event+'.v1',DEFAULT_SOUNDS[event]);
const playSystem=event=>{const name=soundChoice(event);if(soundEnabled.checked&&name)post({type:'sound',system:name});};
function fillSoundPicks(names=[]){
  for(const select of soundPicks){
    const options=['',...names];
    if(select.options.length!==options.length)select.innerHTML=options.map(name=>'<option value="'+escape(name)+'">'+escape(name||copy('soundOff'))+'</option>').join('');
    else select.options[0].textContent=copy('soundOff');
    const chosen=soundChoice(select.dataset.sound);
    select.value=options.includes(chosen)?chosen:'';
  }
}
for(const select of soundPicks)select.addEventListener('change',()=>{
  save('ui.sound.'+select.dataset.sound+'.v1',select.value);
  if(select.value)post({type:'sound',system:select.value});   // let the user hear what they picked
});
let handoffSeen=null, attentionPrev=new Set(), attentionLast=0;
function checkAttention(){
  if(snapshot?.connection!=='live')return;
  const keys=attentionKeys(inventory,questions());
  const tick=attentionTick(attentionPrev,keys,attentionLast,Date.now());
  attentionPrev=keys; attentionLast=tick.lastAt;
  if(tick.play)playSystem('attention');
}
setInterval(checkAttention,5000);
// The floating companion sheep: same signals as the sounds; Swift shows it only while HerdrDesk is in the background.
let companionFlash=null, companionTarget=null, companionSignature='', companionFinished=null, companionFace=null;
const companionSettings={enabled:load('ui.companion.v1',true)!==false, attentionOnly:load('ui.companionAttentionOnly.v1',false)===true};
function companionAttention(){
  const byAddress=new Map(inventory.filter(term=>term.state==='live').map(term=>[term.address,term]));
  const item=term=>({address:term.address,session:term.session,team:term.team||term.label||term.address});
  return [...inventory.filter(term=>term.state==='live'&&term.program?.agent&&(term.status==='blocked'||agentTrouble(term)==='login')).map(item),
    ...questions().filter(q=>['answerNeeded','needsCheck'].includes(q.state))   // an approval asked for another agent waits on that agent
      .map(q=>byAddress.get(q.approval?.address||q.address)).filter(Boolean).map(item)];
}
/** The agent's own character for the companion: provider and chosen look, never names or text. Null when it has none. */
function companionPortrait(term,mood){
  const provider=portraitProvider(term);
  if(!provider)return null;
  return {provider,kind:isCardWorker(term.labels)?'agent':'lead',mouth:mouthOf(term),
    sleeping:mood==='idle'||mood==='offline',working:mood!=='attention'&&workingNow(term)};
}
function pushCompanion(){
  const state=companionState({connection:snapshot.connection,attention:companionAttention(),now:Date.now(),flash:companionFlash,
    limited:inventory.filter(term=>agentTrouble(term)==='limit').length,
    working:inventory.filter(term=>term.state==='live'&&term.program?.agent&&workingNow(term)).length});
  companionTarget=state.target;
  const live=inventory.filter(term=>term.state==='live'&&term.program?.agent);
  const limitedTerm=live.find(term=>agentTrouble(term)==='limit');
  companionFace=featuredAgent({mood:state.mood,flash:state.flash,targetKey:state.target&&sessionKey(state.target),limitKey:limitedTerm&&sessionKey(limitedTerm),finishedKey:companionFinished,previousKey:companionFace,
    workingKeys:live.filter(workingNow).sort((a,b)=>(b.statusMs||0)-(a.statusMs||0)).map(sessionKey)});
  const message={mood:state.mood,count:state.count,working:state.working,limited:state.limited,flash:state.flash,flashAt:state.flashAt,lines:companionSummary(state,copy),
    face:companionPortrait(inventory.find(term=>sessionKey(term)===companionFace),state.mood),
    enabled:companionSettings.enabled,attentionOnly:companionSettings.attentionOnly,
    menu:{snooze:copy('companionSnooze'),off:copy('companionOff')}};
  const signature=JSON.stringify(message);
  if(signature===companionSignature)return;
  companionSignature=signature;
  post({type:'companion',state:message});
}
setInterval(pushCompanion,2000);
for(const [id,key,field] of [['#companionEnabled','ui.companion.v1','enabled'],['#companionAttentionOnly','ui.companionAttentionOnly.v1','attentionOnly']]){
  $(id).checked=companionSettings[field];
  $(id).addEventListener('change',event=>{companionSettings[field]=event.target.checked;save(key,event.target.checked);pushCompanion();});
}
let soundStates=new Map();
let snapshot = { archiveRoles: [], terms: [], machines: [], spaces: [], ledger: {}, replies: [], connection: 'connecting', isolated: false };
let inventory = [];
const characterRoles=new Map();
let chatDirectory = [];
let chatTeamsBySession = new Map();
let chosen = null, selectedTab = 'chat', eventId = null, noticeKey = '', flight = null;
const drafts = load(draftsKey, {});
const legacyDrafts=load('drafts.v1',{});
let legacyMessages=Object.fromEntries(Object.entries(load('ownMessages.v1',{})).map(([role,rows])=>[role,Array.isArray(rows)?rows.slice(-LEGACY_SEND_LIMIT):rows]));
const attachmentsByTarget=new Map();
const loadingAttachments=new Set();
const attachmentPending=new Map();
const attachmentNotices=new Map();
// Drafts belong to one terminal session; an old role-keyed draft is shown only while that role is unambiguous.
const draftValue=term=>draftFor(term,inventory,drafts,legacyDrafts);
let legacyDraftsDirty=false;
function persistDrafts(){
  const saved=!legacyDraftsDirty||save('drafts.v1',legacyDrafts);
  legacyDraftsDirty=false;
  if(!save(draftsKey,drafts)||!saved)showNotice('saveFailed');
}
// Typing updates drafts in memory at once and writes them to storage once it pauses.
const draftSaver=deferredSaver(persistDrafts,400);
function storeDraft(term,value,typing=false){
  const next=storeDraftFor(term,inventory,drafts,legacyDrafts,value);
  const legacyChanged=Object.keys(next.legacy).length!==Object.keys(legacyDrafts).length;
  Object.keys(drafts).forEach(key=>delete drafts[key]); Object.assign(drafts,next.drafts);
  if(legacyChanged){ Object.keys(legacyDrafts).forEach(key=>delete legacyDrafts[key]); Object.assign(legacyDrafts,next.legacy); legacyDraftsDirty=true; }
  if(typing)draftSaver.schedule();
  else{ draftSaver.flush(); persistDrafts(); }
}
const deliveries = load(deliveriesKey, []).map(item => item.state === 'sending' ? { ...item, state: 'needsCheck' } : item);
const copy = key => t(key, language);
const active = () => inventory.find(term => term.address === chosen?.address && term.session === chosen?.session);
const sessionKey = term => term ? term.address + ':' + term.session : '';
const viewed = () => deliveries.filter(item => item.target === sessionKey(active()));
const byId = new Map();
let flowEntries=[];
let page='conversations', teamPage=0, directoryOpen=false;
let membersOpen=false;
const characterKey='ui.agentCharacters.v1';
const characters=new Map(Object.entries(load(characterKey,{})));
const defaultCharacter={style:'classic',coat:'cream',accessory:'none'};
// A card worker starts with its role's look; a look the person picked always wins.
const baseLook=term=>roleLook(term?.labels)||defaultCharacter;
const lookOf=term=>characters.get(characterID(term))||roleLook(term?.labels);
let characterDraft=null;
const pinKey='ui.pinnedChats.v1';
const storedPins=load(pinKey,[]);
const pinnedChats=new Set(Array.isArray(storedPins)?storedPins:[]);
let draggedChat=null;
const chatDragType='application/x-herdrdesk-chat';
const chatPreferencesKey='ui.chatPreferences.v1';
const chatPreferences=new Map(Object.entries(load(chatPreferencesKey,{})));
let sidebarRows=new Map(), showHiddenChats=false, contextChat=null, sectionChat=null;
// Triage: when each conversation was last looked at, snoozed conversations, and what needs the person now.
const seenKey='ui.seen.v1', snoozeKey='ui.snooze.v1';
let seenAt=load(seenKey,{}), snoozes=load(snoozeKey,{}), showSnoozed=false, triageRows=[], triageUnread=new Set(), snoozeTimer, refreshingQueue=false;
const timeOf=at=>typeof at==='number'?at:Date.parse(at)||0;
const chatSectionsKey='ui.chatSections.v1';
let chatSections=load(chatSectionsKey,{order:[],collapsed:[]})||{order:[],collapsed:[]};
let sidebarGroups=new Map(), sectionMode='move', contextSection=null, draggedSection=null, listMarker=null;
function saveSections(next){chatSections=next;save(chatSectionsKey,chatSections);}
function replacePreferences(next){
  chatPreferences.clear();
  for(const [key,value] of next)chatPreferences.set(key,value);
  save(chatPreferencesKey,Object.fromEntries(chatPreferences));
}
let terminalOpen=false, approvalTarget=null, pendingApproval=null;
let roomID=null, memberTeam=null, roomStarted=false, arrivalID=null;
const historyHandoffs=new Map(load('team.handoffs.v1',[]).map(row=>[row.id,row]));
const timelineIds=new Set(), routePulses=new Map();
const openProgress=new Set();
let roomEventsReady=false;
let roomCurrentKey='';
let previousInlineHandoff='';
const seenRoomEvents=new Set();
const roomUnread=new Map();
const assignmentMotion=new Map();
let pendingActivityTimer;
const motionPreference=matchMedia("(prefers-reduced-motion: reduce)");
// Short entrance motion for new messages, question cards and switched conversations. Off with Reduce Motion.
const seenEntries=new Map();
// Chats follow the newest message until the person scrolls up; then a "to the bottom" button appears.
const CHEVRON='<svg class="board-chevron" viewBox="0 0 12 12" width="11" height="11" aria-hidden="true"><path d="M2.5 4.5 6 8l3.5-3.5" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';
let boardOpen=load('ui.boardOpen.v1',false)===true;
const KEY='<svg class="trouble-icon" viewBox="0 0 14 14" width="14" height="14" aria-hidden="true"><circle cx="4.5" cy="7" r="2.6" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M7 7h6M11 7v2.2M12.8 7v1.6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>';
const HOURGLASS='<svg class="trouble-icon" viewBox="0 0 14 14" width="14" height="14" aria-hidden="true"><path d="M3.5 1.5h7M3.5 12.5h7M4.5 1.5c0 3 5 3.5 5 5.5s-5 2.5-5 5.5M9.5 1.5c0 3-5 3.5-5 5.5s5 2.5 5 5.5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>';
const DOWN='<svg viewBox="0 0 12 12" width="11" height="11" aria-hidden="true"><path d="M6 2v7M2.5 6 6 9.5 9.5 6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';
function showToBottom(selector,{stuck,unseen}){
  const button=$(selector);
  button.hidden=stuck;
  button.dataset.unseen=String(unseen);
  button.innerHTML=DOWN+'<span>'+escape(copy(unseen?'newMessagesBelow':'toBottom'))+'</span>';
}
const chatScroll=stickyScroll($('#chatHistory'),{onState:state=>showToBottom('#chatToBottom',state)});
const feedScroll=stickyScroll($('#roomFeed'),{onState:state=>showToBottom('#feedToBottom',state)});
$('#chatToBottom').addEventListener('click',()=>chatScroll.toBottom());
$('#feedToBottom').addEventListener('click',()=>feedScroll.toBottom());
const RISE=[{opacity:0,transform:'translateY(6px)'},{opacity:1,transform:'none'}];
const POP=[{opacity:0,transform:'scale(.97)'},{opacity:1,transform:'none'}];
const FADE=[{opacity:.2},{opacity:1}];
function enter(nodes,frames,duration){
  if(motionPreference.matches||document.hidden)return;
  for(const node of nodes)node.animate?.(frames,{duration,easing:'cubic-bezier(.22,.64,.28,1)'});
}
function enterFresh(panel,scope,attribute,frames,duration){
  const nodes=[...panel.querySelectorAll('['+attribute+']')];
  const fresh=new Set(freshEntries(scope,nodes.map(node=>node.getAttribute(attribute)),seenEntries));
  enter(nodes.filter(node=>fresh.has(node.getAttribute(attribute))),frames,duration);
}
let timelineRoom=null;
const assignedTeams=()=>snapshot.configuredTeams||[];
const memberPages=new Map();
let replayToken=0;
// Teams in the order the configuration lists them (the coordinating 'hq' group is shown on its own).
const primaryTeams=()=>assignedTeams().map(team=>team.id).filter(id=>id!=='hq');
const pageTitles={conversations:'conversations',overview:'overview',structure:'viewStructure',handoff:'viewHandoff',work:'viewWork'};
let activityReady=false;
const seenSteps=new Set();
const activityQueue=[];
let playingActivity=false;
const questionDrafts = new Map();
const questionSending = new Set();
const questionResults = new Map();

const terminalView = createTerminalView({
  panel: $('#terminal'), viewport: $('#terminalViewport'), screen: $('#terminalScreen'), status: $('#terminalStatus'),
  retry: $('#retry'), latest: $('#latest'), open: $('#open'),
  mode: $('#terminalMode'), post, Terminal: window.Terminal, text: copy
});

function showNotice(key) {
  noticeKey = key;
  const panel = $('#notice');
  panel.hidden = !key;
  panel.textContent = key ? copy(key) : '';
}

function time(at) {
  return new Intl.DateTimeFormat(language, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(at));
}

const questions = () => registeredQuestions(snapshot.terms,snapshot.ledger||{});
const needsAttention = term => ['blocked','error'].includes(term.status) || questions().some(q=>
  ['answerNeeded','needsCheck'].includes(q.state) && (q.approval?.address || q.address)===term.address);
const localMachine = () => snapshot.isolated ? copy('local') : snapshot.localMachine || mainMachineLabel(snapshot.tasks?.machines||[],copy) || copy('local');
const machineFor = term => term.machine || localMachine();
const agentName = term => ({'codex':'Codex','claude-code':'Claude Code'}[term?.agent] || '');
const agentLabel = term => [agentName(term),term?.modelOptions?.reportedModel].filter(Boolean).join(' · ');
const portraitProvider=term=>term?.agent==='codex'?'codex':term?.agent==='claude-code'?'claude':null;
const characterID=term=>{
  const role=legacyDraftKey(term);
  return role&&(characterRoles.get(role)||0)<2?'role:'+role:sessionKey(term);
};
// The herd faces follow the engine and the handoffs, so there is no look to pick any more.
const canCustomize=()=>false;
// A card worker is its engine's character. Anyone else is a sheep that keeps its mouth closed, opens it to hold
// the agents it has handed work to (until they hand it back), and sleeps when idle.
function agentPortrait(term, moving=false, preview=false, working=false) {
  const provider=portraitProvider(term);
  if(!provider)return '';
  const resting=!(working||moving||busyNow(term));
  let art;
  if(isCardWorker(term.labels))art=agentFaceHTML({engine:provider,resting});
  else{ const mouth=mouthOf(term); art=leadFaceHTML({engine:provider,mouth,resting,fresh:freshMouth(term,mouth.length),working:!resting,motion:!motionPreference.matches}); }
  return working?withWorkTool(art):art;
}
/** The agents this one handed work to and has not had back (confirmed handoffs only), with their engines. */
function mouthTargets(term){
  if(!term||snapshot.connection!=='live')return [];
  const seen=new Set();
  return (snapshot.handoffs?.edges||[]).filter(edge=>edge.state==='open'&&edge.from?.address===term.address&&(!edge.from.session||!term.session||edge.from.session===term.session)
      &&edge.to?.address&&edge.to.address!=='desk'&&!seen.has(edge.to.address)&&seen.add(edge.to.address))
    .map(edge=>({address:edge.to.address,engine:portraitProvider(inventory.find(item=>item.address===edge.to.address))||'codex'}));
}
const mouthOf=term=>mouthTargets(term).map(target=>target.engine);
// How many agents just went into a mouth (for 3.2s), so only those play the swallow motion. The first look plays none.
const mouthMemory=new Map();
const freshMouth=(term,count)=>freshMouthFor(sessionKey(term),count);
function freshMouthFor(key,count){
  const was=mouthMemory.get(key), now=Date.now();
  if(!was){mouthMemory.set(key,{count,fresh:0,until:0});return 0;}
  if(count>was.count){was.fresh=count-was.count;was.until=now+3200;}
  was.count=count;
  return now<was.until?Math.min(was.fresh,count):0;
}
const busyNow=term=>workingNow(term)&&!needsAttention(term);
const assignmentActive=term=>Boolean(term && (assignmentMotion.get(sessionKey(term))||0)>Date.now());
const effectiveStatus=term=>observedAgentStatus(term,snapshot.liveTurns?.[sessionKey(term)]);
const delegatingNow=term=>Boolean(term)&&snapshot.connection==='live'&&isDelegating(snapshot.handoffs,{address:term.address,session:term.session});
const workingNow=term=>snapshot.connection==='live'&&effectiveStatus(term)==='working';

function markAssignment(key){
  if(!key)return;
  const expiry=Date.now()+3200;
  assignmentMotion.set(key,expiry);
  setTimeout(()=>{
    if(assignmentMotion.get(key)!==expiry)return;
    assignmentMotion.delete(key);
    renderRooms();
    detail();
  },3200);
}
const avatar = label => '<span class="avatar" aria-hidden="true">'+escape(Array.from(label || '·')[0])+'</span>';

function metrics() {
  const live = snapshot.connection === 'live';
  const agents = inventory.filter(term => term.program?.agent);
  const remoteMachines = snapshot.machines.filter(machine => machine.state === 'connected');
  const stages = transferEntries().flatMap(entry=>entry.steps).filter(step=>['request','assignment','handoffReply'].includes(step.kind));
  const items=[
    ['deliveryConfirmed',stages.filter(step=>['questionAck','reply'].includes(step.state)).length,stages.length],
    ['due',live?attentionCount(inventory,questions()):null],
    ['activeAgents',live?agents.filter(term=>effectiveStatus(term)==='working').length:null,live?agents.length:null],
    ['devices',live?remoteMachines.length+1:null,live?snapshot.machines.length+1:null]
  ];
  setPanel('#metrics',items.map(([key,count,total])=>{
    const label=copy(key);
    const number=count ?? '—';
    const detail=label+' · '+number+(total!=null?' / '+total:'');
    return '<div class="metric'+(key==='due'&&count?' attention':'')+'" title="'+escape(detail)+'"><span>'+label+'</span><strong>'
      +number+'</strong></div>';
  }).join(''));
}

function structure() {
  byId.clear();
  const groups=new Map();
  const marked=new Set(selectedWork()?.steps.flatMap(step=>[step.from.key,step.to.key]));
  const members=inventory.map((term,id)=>{
    byId.set(String(id),term);
    return {id,term};
  });
  const org=$('#structure');
  if(org.closest('[hidden]'))return;
  const height=org.clientHeight;
  const columns=org.clientWidth>=560?3:org.clientWidth>=350?2:1;
  const hq=height>=150?members.find(({term})=>term.teamID==='hq' && term.isLead):null;
  for(const member of members){
    if(member===hq)continue;
    const {term}=member, key=term.teamID || term.team || '';
    if(!groups.has(key))groups.set(key,{key,title:term.team || copy('other'),members:[]});
    groups.get(key).members.push(member);
  }
  const order=[...new Set([...primaryTeams(),...(snapshot.configuredTeams||[]).map(team=>team.id)])];
  const rank=key=>order.includes(key)?order.indexOf(key):order.length;
  const cards=[...groups.values()].sort((a,b)=>rank(a.key)-rank(b.key));
  const total=Math.max(1,Math.ceil(cards.length/columns));
  teamPage=Math.min(teamPage,total-1);
  const visible=cards.slice(teamPage*columns,(teamPage+1)*columns);
  const rows=Math.max(1,Math.floor((height-(hq?49:0)-48)/27));
  const row=({id,term},root=false)=>{
    const nested=term.parentName && !term.isLead && inventory.some(parent=>
      parent.teamID===term.teamID && !parent.isLead &&
      (parent.address===term.parent || (term.parentRole && parent.labels?.['recovery.role']===term.parentRole)));
    const label=root?term.label:term.roleLabel || term.label;
    const status=needsAttention(term)?'due':effectiveStatus(term);
    const description=[term.label,term.parentName && '↳ '+term.parentName,agentLabel(term),copy(status)].filter(Boolean).join(' · ');
    return '<button class="member '+(root?'node root':'person')+(nested?' child':'')+(status==='due'?' attn':'')
      +'" data-id="'+id+'" data-address="'+escape(term.address)+'" data-state="'+escape(effectiveStatus(term))
      +'" title="'+escape(description)+'" aria-label="'+escape(description)+'" aria-pressed="'+(sessionKey(term)===sessionKey(chosen))+'">'
      +(agentPortrait(term)||avatar(label))+'<span class="label"><b>'+escape(label)+'</b></span>'
      +'<i class="state-dot" aria-hidden="true"></i></button>';
  };
  const focusAddress=document.activeElement?.dataset.address;
  const pagerFocus=document.activeElement?.dataset;
  if(!members.length){
    setPanel('#structure','<p class="muted">'+copy(snapshot.connection==='live'?'noTerminals':snapshot.connection)+'</p>');
  }else{
    const teamCards=visible.map(card=>{
      const index=new Map((snapshot.configuredTeams||[]).find(team=>team.id===card.key)?.roles.map(([role],i)=>[role,i])||[]);
      const rankMember=({term})=>index.get(term.labels?.['recovery.role'])??index.size;
      const ordered=[...card.members].sort((a,b)=>rankMember(a)-rankMember(b));
      const pages=Math.ceil(ordered.length/rows);
      const batch=Math.min(memberPages.get(card.key)||0,pages-1);
      memberPages.set(card.key,batch);
      const pager=pages>1?'<div class="pager member-pager" data-team="'+escape(card.key)+'">'+pageButtons(batch,pages,'member')+'</div>':'';
      return '<section class="team'+(ordered.some(({term})=>marked.has(sessionKey(term)))?' route':'')+'"><h3>'
        +'<span>'+escape(card.title)+'</span><small>'+ordered.length+'</small></h3><div class="people">'
        +ordered.slice(batch*rows,(batch+1)*rows).map(member=>row(member)).join('')+'</div>'+pager+'</section>';
    }).join('');
    const slots=Math.max(1,visible.length);
    const root=hq?row(hq,true)+(visible.length?'<div class="stem"></div><div class="trunk cols-'+slots+'"></div>':''):'';
    setPanel('#structure',root+'<div class="teams cols-'+slots+'">'+teamCards+'</div>');
  }
  if(focusAddress)Array.from(org.querySelectorAll('[data-address]')).find(button=>button.dataset.address===focusAddress)?.focus({preventScroll:true});
  if(pagerFocus?.memberPage){
    const pager=[...org.querySelectorAll('.member-pager')].find(el=>el.dataset.team===pagerFocus.team);
    const button=[...(pager?.querySelectorAll('button')||[])].find(el=>el.dataset.memberPage===pagerFocus.memberPage && !el.disabled);
    (button||pager?.querySelector('button:not(:disabled)'))?.focus({preventScroll:true});
  }
  const pager=$('#teamPager');
  pager.hidden=total<=1;
  setPanel('#teamPager',pageButtons(teamPage,total,'team'));
  $('#scope').textContent=cards.length+copy('teamCount');
}

function pageButtons(index,total,kind){
  const button=(step,label,symbol,disabled)=>'<button type="button" data-'+kind+'-page="'+step+'" aria-label="'+copy(label)
    +'" title="'+copy(label)+'"'+(disabled?' disabled':'')+'>'+symbol+'</button>';
  return button(-1,'previousPage','‹',index===0)+'<output>'+(index+1)+'/'+total+'</output>'+button(1,'nextPage','›',index>=total-1);
}

function rooms() {
  const groups=new Map(assignedTeams().map(team=>[team.id,{id:team.id,title:team.title,lead:team.lead,members:[],roles:new Map(team.roles)}]));
  for(const term of inventory){
    const team=chatTeamsBySession.get(sessionKey(term));
    const id=team?.id||term.teamID;
    if(!id||term.state==='archived')continue;
    if(!groups.has(id))groups.set(id,{id,title:team?.title||term.team,members:[],roles:new Map()});
    const group=groups.get(id);
    group.members.push(term);
    const role=legacyDraftKey(term);
    if(role&&!group.roles.has(role))group.roles.set(role,term.label);
  }
  const configured=new Set(assignedTeams().map(team=>team.id));
  return [...groups.values()].filter(group=>listedGroup(group.members,configured.has(group.id)));
}

const currentRoom=()=>page==='conversations'&&roomID ? rooms().find(room=>room.id===roomID) : null;
const roomLead=room=>{
  const leads=room?.members.filter(term=>term.isLead && term.program?.agent) || [];
  return leads.length===1?leads[0]:null;
};


function roomSignals() {
  if(snapshot.connection!=='live')return;
  const current=currentRoom();
  for(const group of rooms()){
    const events=[];
    const leadRole=group.lead||legacyDraftKey(roomLead(group));
    for(const reply of snapshot.replies||[]){
      if(leadRole&&reply.role===leadRole&&reply.kind==='reply')events.push({id:'reply:'+reply.id,tab:'team'});
    }
    for(const item of snapshot.teamMessages||[]){
      if(item.team===group.id&&group.roles.has(item.role))events.push({id:'share:'+item.id,tab:'team'});
    }
    for(const item of historyHandoffs.values()){
      if(item.team===group.id&&item.kind==='handoffReply')events.push({id:item.id,tab:'team'});
    }
    for(const event of events){
      const key=group.id+':'+event.id;
      if(seenRoomEvents.has(key))continue;
      seenRoomEvents.add(key);
      if(!roomEventsReady||(document.visibilityState==='visible'&&current?.id===group.id&&selectedTab===event.tab))continue;
      if(!roomUnread.has(group.id))roomUnread.set(group.id,new Set());
      roomUnread.get(group.id).add(event.tab);
    }
  }
  roomEventsReady=true;
}

function roomQuestions(room, term) {
  const addresses=new Set(room?room.members.map(member=>member.address):term?[term.address]:[]);
  return questions().filter(q=>['answerNeeded','needsCheck'].includes(q.state)
    && (addresses.has(q.address)||addresses.has(q.approval?.address)));
}

const roomLeadHistory=room=>roomLead(room) || (room?.lead && inventory.find(term=>
  term.state==='archived' && legacyDraftKey(term)===room.lead));

function flattenChatNodes(nodes){
  return nodes.flatMap(node=>[node,...flattenChatNodes(node.children)]);
}

function roomRoster(room){
  const group=chatDirectory.find(group=>group.id===room.id);
  if(!group)return room.members;
  return flattenChatNodes(group.roots).map(node=>node.term
    ||{label:node.label,roleLabel:node.label,state:'offline',status:'unknown',labels:{'recovery.role':node.role}});
}

function memberStatus(term){
  if(term.state!=='live')return copy('directoryOffline');
  if(snapshot.connection!=='live')return copy(snapshot.connection);
  const trouble=agentTrouble(term);
  if(trouble==='login'||trouble==='limit')return copy('trouble_'+trouble);
  const status=effectiveStatus(term);
  if(status!=='working'&&!['blocked','error'].includes(term.status)&&delegatingNow(term))return copy('waitingOnOthers');
  return copy(status!=='working'&&assignmentActive(term)?'assignmentArrived':status);
}

function snippet(value,limit=112){
  const compact=String(value??'').replace(/\s+/g,' ').trim();
  const letters=Array.from(compact.slice(0,limit*2));
  return letters.length>limit?letters.slice(0,limit-1).join('')+'…':compact;
}

function progressDisclosure(entry,key){
  return '<details class="progress-event" data-progress="'+escape(key)+'" data-kind="progress">'
    +'<summary>'+tagHTML('progress',copy,escape)+'<span class="progress-snippet">'
    +escape(snippet(entry.body))+'</span><small>'+time(entry.at)+'</small></summary>'
    +'<div class="progress-content"><small>'+escape(entry.author)+'</small>'+renderChatText(entry.body)+'</div></details>';
}

function restoreProgress(panel){
  for(const details of panel.querySelectorAll('[data-progress]'))details.open=openProgress.has(details.dataset.progress);
}

for(const panel of [$('#roomFeed'),$('#chatLog')]){
  panel.addEventListener('toggle',event=>{
    const node=event.target;
    if(!node.isConnected||!node.dataset.progress)return;
    if(node.open)openProgress.add(node.dataset.progress);
    else openProgress.delete(node.dataset.progress);
  },true);
}

function presence(term){
  const trouble=agentTrouble(term);
  const state=snapshot.connection==='live'&&term?.state==='live'
    ? trouble==='login'||trouble==='limit'?trouble:['blocked','error'].includes(term.status)?'due':workingNow(term)?'working':delegatingNow(term)?'waiting':'idle'
    : 'offline';
  return '<i class="presence-dot" data-presence="'+state+'" aria-hidden="true"></i>';
}

function teamEmblem(room,roster=roomRoster(room)){
  const initial=Array.from(room.title.trim())[0]||'·';
  const recent=new Map([...characters.keys()].map((key,index)=>[key,index+1]));
  const score=member=>recent.get(characterID(member))||0;
  const lead=roster.find(member=>member.isLead||(room.lead&&legacyDraftKey(member)===room.lead));
  if(lead&&portraitProvider(lead)){
    // The team as one sheep: its lead, holding the team's live card workers (and anyone it handed work to) in its mouth.
    const inside=new Map(mouthTargets(lead).map(target=>[target.address,target.engine]));
    for(const member of roster)if(member!==lead&&member.state==='live'&&isCardWorker(member.labels)&&!inside.has(member.address))inside.set(member.address,portraitProvider(member)||'codex');
    const mouth=[...inside.values()], working=busyNow(lead);
    const art=leadFaceHTML({engine:portraitProvider(lead),mouth,resting:!working,fresh:freshMouthFor('emblem:'+room.id,mouth.length),working,motion:!motionPreference.matches});
    return '<span class="team-emblem" data-members="1" data-herd aria-hidden="true"><span>'+(working?withWorkTool(art):art)+'</span></span>';
  }
  const ranked=roster.filter(member=>member!==lead).sort((a,b)=>score(b)-score(a));
  const faces=(lead?[lead,...ranked]:ranked).slice(0,3);
  return '<span class="team-emblem" data-members="'+Math.max(1,faces.length)+'" aria-hidden="true">'
    +(faces.length?faces.map(member=>'<span>'+(agentPortrait(member,busyNow(member),false,busyNow(member))||avatar(member.roleLabel||member.label))+'</span>').join('')
      :'<span>'+avatar(initial)+'</span>')+'</span>';
}

function renderRooms(){
  if(page!=='conversations'||draggedChat)return;
  const all=rooms(), selected=currentRoom();
  if(selected&&!document.hidden)roomUnread.get(selected.id)?.delete(selectedTab);
  const roleCounts=new Map();
  for(const term of inventory){
    const role=legacyDraftKey(term);
    if(role)roleCounts.set(role,(roleCounts.get(role)||0)+1);
  }
  const rows=all.map(room=>{
    const feed=roomFeedRows(room), roster=roomRoster(room);
    const latest=feed.findLast(row=>row.kind!=='progress'&&row.body);
    const status=room.members.find(workingNow);
    const roomAsks=roomQuestions(room), pending=roomAsks.length;
    const unread=Boolean(roomUnread.get(room.id)?.size);
    const lastAgent=feed.findLast(row=>row.author!==copy('you')&&row.kind!=='progress'&&row.body);
    const live=room.members.filter(member=>member.state==='live');
    return {
      lastAgentAt:timeOf(lastAgent?.at), trouble:live.some(member=>agentTrouble(member)==='login')?'login':null, questions:roomAsks.map(q=>q.id),
      blocked:live.some(member=>member.status==='blocked'),
      key:'room:'+room.id, room:room.id, selected:room.id===selected?.id,
      title:room.title, icon:teamEmblem(room,roster), at:feed.at(-1)?.at||0,
      preview:[countsLabel(room.id),latest?snippet(latest.author+' · '+latest.body):''].filter(Boolean).join(' · '),
      note:roster.length+copy(roster.length===1?'memberCountOne':'memberCount'), pending, unread,
      state:status?copy('working'):room.members.some(delegatingNow)?copy('waitingOnOthers'):'',
      indicator:status?presence(status):''
    };
  });
  for(const term of inventory.filter(term=>term.program?.agent||term.state==='archived')){
    const entries=personalChatEntries(term), role=legacyDraftKey(term);
    const latest=entries.findLast(entry=>entry.state!=='progress'&&(entry.text||entry.images));
    const team=chatTeamsBySession.get(sessionKey(term))?.title;
    const title=term.label;
    const shortTitle=shortRoleTitle(title,team);
    const asks=roomQuestions(null,term), pending=asks.length;
    const lastAgent=entries.findLast(entry=>entry.from&&entry.state!=='progress');
    rows.push({
      lastAgentAt:timeOf(lastAgent?.at), trouble:agentTrouble(term), blocked:term.state==='live'&&term.status==='blocked', questions:asks.map(q=>q.id),
      key:'direct:'+(role&&roleCounts.get(role)===1?role:sessionKey(term)),
      direct:sessionKey(term), selected:!selected&&sessionKey(term)===sessionKey(active()),
      title, shortTitle, team:team===title?'':team,
      icon:agentPortrait(term,busyNow(term),true,busyNow(term))||avatar(shortTitle), at:entries.at(-1)?.at||0,
      preview:latest?snippet(latest.text||copy('attachedImages')):'', state:memberStatus(term),
      pending, indicator:presence(term), archived:term.state==='archived'
    });
  }
  // A team with one lead shows once, as its room; the lead's own chat opens from the room header.
  const leadToRoom=new Map();
  for(const room of all){
    const lead=roomLead(room)||(room.members.length===1?room.members[0]:null), leadRow=lead&&rows.find(row=>row.direct===sessionKey(lead));
    if(leadRow)leadToRoom.set(leadRow.key,'room:'+room.id);
  }
  for(const [leadKey,roomKey] of leadToRoom){
    const section=chatPreferences.get(leadKey)?.section;
    if(section&&!chatPreferences.get(roomKey)?.section)changeChatPreference(roomKey,{section});
  }
  const selectedBeforeFold=rows.find(row=>row.selected)?.key||null;
  const folded=foldLeadChats(rows,[...pinnedChats],leadToRoom);
  if(folded.changed){pinnedChats.clear();for(const key of folded.pins)pinnedChats.add(key);save(pinKey,[...pinnedChats]);}
  rows.splice(0,rows.length,...folded.rows);
  // Unread: an agent spoke after the person last looked (never on first sight); looking at a conversation marks it seen.
  // a lead's own chat folds into its room: reading it counts as reading the room
  const looking=document.hidden||refreshingQueue||!selectedBeforeFold?null:rows.some(row=>row.key===selectedBeforeFold)?selectedBeforeFold:leadToRoom.get(selectedBeforeFold)||null, now=Date.now();
  const nextSeen=markSeen(seenAt,rows,looking,now);
  if(JSON.stringify(nextSeen)!==JSON.stringify(seenAt)){seenAt=nextSeen;save(seenKey,seenAt);}
  for(const row of rows)if(!row.selected&&autoUnread(row,seenAt))row.unread=true;
  // Snoozed rows drop to "Later" until their time, new agent activity or something that needs the person.
  const snoozed=new Set(rows.filter(row=>snoozeActive(snoozes[row.key],row,now)).map(row=>row.key));
  // expire only what was evaluated (or whose time is up): the empty list before the first snapshot cancels nothing
  const stale=Object.keys(snoozes).filter(key=>now>=snoozes[key].until||rows.some(row=>row.key===key)&&!snoozed.has(key));
  if(stale.length){for(const key of stale)delete snoozes[key];save(snoozeKey,snoozes);}
  // wake the sidebar when the next snooze is due, even if nothing else changes
  const due=Math.min(...Object.values(snoozes).map(entry=>entry.until));
  clearTimeout(snoozeTimer);
  if(Number.isFinite(due))snoozeTimer=setTimeout(renderRooms,Math.min(Math.max(due-now+50,1000),2**31-1));
  sidebarRows=new Map(rows.map(row=>[row.key,row]));
  setPanel('#computerStrip',computerStripHTML(computerRows(snapshot.tasks?.machines||[],snapshot.machines||[],inventory,workingNow),copy,escape));
  renderComputerSheet();
  const shown=rows.filter(row=>!chatHidden(row,chatPreferences.get(row.key))&&!snoozed.has(row.key));
  const pinned=[...pinnedChats].reverse().map(key=>sidebarRows.get(key)).filter(row=>row&&!chatHidden(row,chatPreferences.get(row.key))&&!snoozed.has(row.key));
  triageRows=rows.filter(row=>!chatHidden(row,chatPreferences.get(row.key))&&!snoozed.has(row.key));
  triageUnread=new Set(triageRows.filter(row=>row.unread||chatPreferences.get(row.key)?.unread).map(row=>row.key));
  renderUrgent();
  const recent=shown.filter(row=>!pinnedChats.has(row.key));
  const hidden=rows.filter(row=>chatHidden(row,chatPreferences.get(row.key)));
  if(!hidden.length)showHiddenChats=false;
  const hiddenToggle=$('#hiddenChatsToggle');
  hiddenToggle.hidden=!hidden.length;
  hiddenToggle.textContent=copy('hiddenChats')+(hidden.length?' '+hidden.length:'');
  hiddenToggle.setAttribute('aria-pressed',String(showHiddenChats));
  const shelf=$('#pinnedChats'), focus=document.activeElement?.dataset;
  shelf.hidden=pinned.length===0;
  shelf.setAttribute('aria-label',copy('pinnedChats'));
  const shelfUpdated=setPanel('#pinnedChats',pinned.map(row=>conversationItem(row,true)).join(''));
  const groups=groupRows(recent,chatPreferences,chatSections);
  sidebarGroups=new Map(groups.map(group=>[group.name,group.items.map(row=>row.key)]));
  const named=groups.some(group=>!group.unassigned);
  const listHTML=groups.filter(group=>!group.unassigned||group.items.length||named).map(group=>
    (named?sectionHeading(group):'')+(group.collapsed?'':group.items.map(row=>conversationItem(row,false)).join(''))).join('')
    +(rows.length?'<button type="button" class="add-section" data-add-section>'+escape('+ '+copy('addSection'))+'</button>':'');
  const hiddenHTML=showHiddenChats&&hidden.length?sidebarHeading(copy('hiddenChats'))
    +hidden.map(row=>conversationItem(row,false)).join(''):'';
  const later=rows.filter(row=>snoozed.has(row.key)&&!chatHidden(row,chatPreferences.get(row.key)));
  if(!later.length)showSnoozed=false;
  const laterHTML=later.length?'<button type="button" class="snoozed-toggle" data-snoozed-toggle aria-expanded="'+showSnoozed+'">'
    +'<span class="section-chevron" aria-hidden="true"></span>'+escape(copy('snoozedChats'))+' <small>'+later.length+'</small></button>'
    +(showSnoozed?later.map(row=>conversationItem(row,false)).join(''):''):'';
  const listUpdated=setPanel('#roomList',listHTML+laterHTML+hiddenHTML
    ||(!rows.length?'<p class="muted">'+copy('noDirectChats')+'</p>':''));
  if((shelfUpdated||listUpdated)&&focus){
    const button=[...$('#roomNav').querySelectorAll('button')].find(button=>
      (focus.direct&&button.dataset.direct===focus.direct)
      ||(focus.room&&button.dataset.room===focus.room));
    button?.focus({preventScroll:true});
  }
  $('#roomTools').hidden=false;
  $('#roomBack').hidden=Boolean(selected)||!all.some(room=>room.id===memberTeam);
}

/** "Waiting N" above the conversations; clicking it (or ⌘J) opens the next conversation that needs the person. */
function renderUrgent(){
  const n=waitingCount(triageRows,triageUnread), button=$('#urgentJump');
  button.hidden=!n;
  const label=copy('waitingCount').replace('{n}',String(n));
  if(button.dataset.label!==label){button.dataset.label=label;button.innerHTML='<b>'+escape(label)+'</b><kbd>⌘J</kbd>';}
  button.title=copy('nextUrgent')+' (⌘J)';
}
function openNextUrgent(){
  // the queue is only current while the sidebar renders; that refresh must not mark the old selection seen
  if(page!=='conversations'){page='conversations';refreshingQueue=true;try{render();}finally{refreshingQueue=false;}}
  const current=triageRows.find(row=>row.selected)?.key||null;
  const key=nextUrgent(triageRows,triageUnread,current), row=key&&sidebarRows.get(key);
  if(!row)return;
  if(chatPreferences.get(key)?.unread)changeChatPreference(key,{unread:false});
  if(row.room)openRoom(row.room);
  else{openDirectChat(inventory.find(term=>sessionKey(term)===row.direct));render();}
}

function sectionHeading(group){
  const label=group.unassigned?copy('unassignedChats'):group.name;
  return '<h3 class="sidebar-section-title section-head" data-section-head="'+escape(group.name)+'"'+(group.unassigned?'':' draggable="true"')+'>'
    +'<button type="button" class="section-toggle" data-section-toggle="'+escape(group.name)+'" aria-expanded="'+String(!group.collapsed)+'">'
    +'<span class="section-chevron" aria-hidden="true"></span><span class="section-label">'+escape(label)+'</span>'
    +'<small>'+group.items.length+'</small></button></h3>';
}
function sidebarHeading(name){
  return '<h3 class="sidebar-section-title">'+escape(name)+'</h3>';
}

function conversationItem(row,pinned){
  const pref=chatPreferences.get(row.key);
  const label=[row.title,row.team,row.note,row.state,(pref?.unread||row.unread)?copy('unreadStatus'):'',row.pending?copy('approvalTab')+' '+row.pending:'',row.preview].filter(Boolean).join(' · ');
  const title=escape(row.shortTitle||row.title);
  const tag=row.team?'<span class="chat-team-tag">'+escape(row.team)+'</span>':'';
  const count=row.note?'<small class="room-count">'+escape(row.note)+'</small>':'';
  const signals=(row.unread||pref?.unread?'<i class="room-unread" aria-hidden="true"></i>':row.indicator||'')
    +(row.pending?'<b class="room-waiting">'+row.pending+'</b>':'');
  // Pinned tiles are tiny: the team names the tile, the role is the small tag (seven "총괄" tiles were indistinguishable).
  const pinnedRole=Boolean(row.team);
  const face=pinned
    ?'<span class="pinned-face">'+row.icon+'<span class="pinned-signals">'+signals+'</span></span>'
      +'<span class="pinned-name">'+escape(pinnedRole?row.team:row.shortTitle||row.title)+'</span>'
      +(pinnedRole?'<span class="chat-team-tag">'+escape(row.shortTitle||row.title)+'</span>':tag||count)
    :row.icon+'<span class="room-preview-copy"><span class="conversation-heading"><span class="room-title">'
      +title+'</span>'+tag+'</span>'
      +(row.preview||row.state?'<small class="room-preview">'+escape(row.preview||row.state)+'</small>':'')
      +'</span><span class="room-signals">'+count+signals+'</span>';
  return '<div class="'+(pinned?'pinned-tile':'conversation-row')+(chatHidden(row,pref)?' hidden-conversation':'')+'" data-conversation="'+escape(row.key)+'"'+(chatHidden(row,pref)?'':' draggable="true"')+'><button class="'
    +(pinned?'pinned-open':'room-row')+'" type="button"'
    +(row.room?' data-room="'+escape(row.room)+'"':' data-direct="'+escape(row.direct)+'"')
    +' aria-haspopup="menu" aria-label="'+escape(label)+'" title="'+escape(label)+'" aria-pressed="'+row.selected+'">'+face+'</button></div>';
}

function renderGroupMembers(room){
  const group=$('#groupMembers');
  const roster=room?roomRoster(room):[];
  const toggle=$('#roomMembersToggle');
  toggle.hidden=!room||!roster.length;
  toggle.textContent=copy('roomPeople')+' '+roster.length;
  group.hidden=toggle.hidden||!membersOpen;
  toggle.setAttribute('aria-expanded',String(!group.hidden));
  group.setAttribute('aria-label',copy('roomPeople'));
  if(group.hidden)return;
  const member=term=>{
    const name=term.roleLabel||term.label;
    const status=[agentName(term),memberStatus(term)].filter(Boolean).join(' · ');
    return '<button class="roster-member" type="button" title="'+escape(term.label)+'"'
      +(term.address?' data-group-member="'+escape(sessionKey(term))+'"':' disabled')+'>'
      +(agentPortrait(term,busyNow(term)||assignmentActive(term),false,busyNow(term))||avatar(name))+'<span><b>'+escape(name)+'</b><small>'+escape(status)+'</small></span></button>';
  };
  const focus=document.activeElement?.dataset.groupMember;
  const changed=setPanel('#groupMembers','<div class="roster-head">'+teamEmblem(room,roster)+'<div><strong>'+escape(room.title)
    +'</strong><span class="group-label">'+escape(copy('roomPeople')+' '+roster.length)+'</span></div>'
    +'<button class="roster-close" type="button" aria-label="'+copy('closeGroupMembers')+'">×</button></div>'
    +'<div class="roster-list">'+roster.map(member).join('')+'</div>');
  if(changed&&focus)[...group.querySelectorAll('[data-group-member]')].find(button=>button.dataset.groupMember===focus)?.focus({preventScroll:true});
}

function openRoom(id, showMembers=false) {
  resetDrawer();
  membersOpen=showMembers;
  roomID=id;
  memberTeam=id;
  const lead=roomLeadHistory(currentRoom());
  chosen=lead?{address:lead.address,session:lead.session}:null;
  selectedTab='team';
  showNotice('');
  render();
}

// One render asked for this hundreds of times (every agent row, every image in the log): merge once per snapshot.
const EMPTY_RECORDS=[];
const mergedRecords=memoLast(mergeConversationRecords);
function conversationRecords() {
  return mergedRecords(snapshot.replies||EMPTY_RECORDS, snapshot.liveMessages||EMPTY_RECORDS);
}

function roomFeedRows(room) {
  const rows=[];
  const solo=roomLeadHistory(room)||(room.members.length===1?room.members[0]:null), leadDirect=solo?directConversationId(solo):null;
  const retained=new Map(Object.values(legacyMessages).flat().filter(item=>inRoomConversation(item,room.id,leadDirect)).map(item=>[item.id,{...item,at:Date.parse(item.at)}]));
  for(const item of deliveries)if(inRoomConversation(item,room.id,leadDirect))retained.set(item.id,item);
  for(const item of retained.values())rows.push({id:item.id,at:item.at,author:copy('you'),body:item.text||copy('attachedImages'),kind:item.state||'sent',previews:item.previews,images:item.images,role:item.role,session:item.session,address:item.address,imageBody:item.text||''});
  for(const entry of snapshot.teamMessages||[]){
    const author=room.members.find(term=>legacyDraftKey(term)===entry.role)?.label||room.roles.get(entry.role);
    if(entry.team!==room.id || !author || !Number.isFinite(Date.parse(entry.at)))continue;
    rows.push({id:entry.id,at:Date.parse(entry.at),author,body:entry.body,kind:entry.kind==='progress'?'progress':'teamMessage'});
  }
  const teamRole=role=>room.members.find(term=>legacyDraftKey(term)===role)?.label||room.roles.get(role);
  const leadRole=room.lead||legacyDraftKey(roomLead(room));
  for(const entry of conversationRecords()){
    const author=teamRole(entry.role), at=Date.parse(entry.at);
    if(!author||!Number.isFinite(at))continue;
    if(entry.kind==='agent-handoff'){
      if(snapshot.handoffs)continue;   // handoff cards cover these, including sender-side sends
      const recipient=entry.recipient&&teamRole(entry.recipient);
      if(!recipient)continue;
      const kind=entry.role===leadRole?'assignment':entry.recipient===leadRole?'handoffReply':'incomingHandoff';
      rows.push({id:entry.id,at,author,recipient,body:entry.body,kind});
    }else if(entry.role===leadRole&&['progress','reply'].includes(entry.kind)){
      rows.push({id:entry.id,at,author,body:entry.body,kind:entry.kind});
    }
  }
  for(const item of deliveries){
    if(retained.has(item.id))continue;
    if(item.teamRoom!==room.id||!['sent','sending','needsCheck'].includes(item.state))continue;
    rows.push({id:item.id,at:item.at,author:copy('you'),recipient:item.label,body:item.text||copy('attachedImages'),kind:item.state,previews:item.previews,images:item.images,role:item.role,session:item.session,address:item.address,imageBody:item.text||''});
  }
  for(const item of historyHandoffs.values()){
    if(item.team===room.id)rows.push(item);
  }
  for(const card of handoffCardsFor(snapshot.handoffs,room.members.map(member=>member.address),{withDesk:false}))
    rows.push({id:card.id,at:card.at,kind:'handoffCard',card});
  return rows.sort((a,b)=>a.at-b.at);
}

const boardTeam=id=>snapshot.tasks?.teams?.[id];
function countsLabel(id){
  return teamCountsText(teamCounts(boardTeam(id)),copy);
}
function boardOwnerTerm(address){
  return inventory.find(term=>term.address===address&&term.state!=='archived')
    ||inventory.find(term=>legacyDraftKey(term)===address&&term.state!=='archived');
}
function renderTaskBoard(room,show){
  const panel=$('#taskBoard');
  const team=room&&boardTeam(room.id);
  panel.hidden=!show||!team||!(team.cards||[]).length;
  if(panel.hidden)return;
  const name=address=>{const term=boardOwnerTerm(address);return term?.label||address;};
  const portrait=address=>{const term=boardOwnerTerm(address);return term?agentPortrait(term):'';};
  const columns=boardColumns(team,Date.now());
  const scrolled=panel.querySelector('.board-inner');
  const offset=scrolled?[scrolled.scrollTop,scrolled.scrollLeft]:null;
  const changed=setPanel('#taskBoard','<button type="button" class="board-toggle" aria-controls="boardBody">'
    +'<span class="board-summary">'+boardSummaryHTML(columns,copy)+'</span>'
    +'<span class="board-toggle-label" data-when="closed">'+escape(copy('boardExpand'))+'</span>'
    +'<span class="board-toggle-label" data-when="open">'+escape(copy('boardCollapse'))+'</span>'+CHEVRON+'</button>'
    +'<div class="board-body" id="boardBody"><div class="board-inner">'
    +(team.warnings?.length?'<p class="board-warning">'+escape(copy('boardWarning'))+'</p>':'')
    +'<div class="board-columns" aria-label="'+escape(copy('boardTitle'))+'">'+columns.map(column=>
      '<section class="board-column" data-board-state="'+column.state+'"><h3>'+escape(copy(BOARD_LABELS[column.state]))
      +' <span>'+column.cards.length+'</span></h3>'
      +(column.cards.map(card=>boardCardHTML(card,name,portrait,escape,copy)).join('')||'<p class="board-empty">·</p>')
      +'</section>').join('')+'</div></div></div>');
  const inner=changed&&offset&&panel.querySelector('.board-inner');
  if(inner)[inner.scrollTop,inner.scrollLeft]=offset;
  showBoardOpen();
}
function showBoardOpen(){
  const panel=$('#taskBoard');
  panel.toggleAttribute('data-open',boardOpen);
  panel.querySelector('.board-toggle')?.setAttribute('aria-expanded',String(boardOpen));
  $('#boardBody')?.toggleAttribute('inert',!boardOpen);
}

function renderRoomFeed(room) {
  if(!room)return;
  const visible=roomFeedRows(room).slice(-150);
  const panel=$('#roomFeed');
  const sameRoom=timelineRoom===room.id;
  if(!sameRoom){timelineIds.clear();routePulses.clear();}
  const html=visible.map(row=>{
    if(row.kind==='progress')return progressDisclosure(row,'room:'+room.id+':'+row.id);
    if(row.kind==='handoffCard')return chatHandoffCard(row.card);
    const matching=room.members.filter(term=>term.label===row.author);
    const icon=(matching.length===1?agentPortrait(matching[0]):'')||avatar(row.author);
    const routed=['assignment','handoffReply','incomingHandoff','sent'].includes(row.kind)&&row.recipient;
    const heading=routed
      ? '<strong class="feed-route" aria-label="'+escape(row.author+' → '+row.recipient)+'">'+escape(row.author)+'<i class="route-stroke" aria-hidden="true"></i>'+escape(row.recipient)+'</strong>'
      : '<strong>'+escape(row.author)+(row.recipient?' → '+escape(row.recipient):'')+'</strong>';
    const transfer=['incomingHandoff','handoffReply'].includes(row.kind)||row.state==='questionAck'?'received':'sent';
    return '<article class="feed-row" data-feed="'+escape(row.id)+'"'+(routed?' data-transfer="'+transfer+'"':'')+(row.author===copy('you')?' data-mine':'')+' data-kind="'+escape(row.kind)+'">'
      +'<header><span class="feed-author">'+tagHTML(messageTag(row.kind),copy,escape)+icon+heading+'</span><small>'+(messageTag(row.kind)?'':escape(copy(row.kind))+' · ')+time(row.at)
      +'</small></header>'+renderChatText(row.body)+messageImages(row)+lineageMarkup(snapshot.lineage,'room:'+room.id,row.id,inventory,snapshot.ledger||{},copy)+'</article>';
  }).join('') || '<p class="muted">'+copy('teamFeedEmpty')+'</p>';
  const addedRows=sameRoom&&visible.some(row=>!timelineIds.has(row.id));
  const updated=setPanel('#roomFeed',html);
  if(updated)enterFresh(panel,'room:'+room.id,'data-feed',RISE,180);
  if(!sameRoom&&timelineRoom)enter([panel],FADE,140);
  observeChatImages();
  if(updated)restoreProgress(panel);
  if(updated&&!panel.hidden&&sameRoom && !matchMedia('(prefers-reduced-motion: reduce)').matches){
    const now=performance.now();
    for(const [id,start] of routePulses)if(now-start>=720)routePulses.delete(id);
    for(const node of panel.querySelectorAll('[data-feed]')){
      const id=node.dataset.feed, fresh=!timelineIds.has(id);
      if(fresh&&node.querySelector('.route-stroke'))routePulses.set(id,now);
      if(routePulses.has(id)){
        node.style.setProperty('--route-delay',`-${now-routePulses.get(id)}ms`);
        node.dataset.routing='true';
      }
      if(!fresh)continue;
      node.animate([{opacity:.7,transform:'translateY(3px)',backgroundColor:'#ffffff14'},
        {opacity:1,transform:'translateY(0)',backgroundColor:'transparent'}],
        {duration:380,easing:'cubic-bezier(.22,.64,.28,1)'});
    }
  }
  timelineIds.clear();
  for(const row of visible)timelineIds.add(row.id);
  timelineRoom=room.id;
  if(!sameRoom)feedScroll.toBottom();
  else if(updated)feedScroll.contentChanged(addedRows);
}

function recordHandoffs() {
  let changed=false;
  for(const flow of flowEntries){
    const team=flow.from.teamID===flow.to.teamID?flow.from.teamID:'';
    const stage=(from,to,at,kind)=>({id:flow.id+':'+kind,team,at,author:from.label,recipient:to.label,
      fromRole:legacyDraftKey(from),toRole:legacyDraftKey(to),body:flow.text,kind,state:flow.state});
    const rows=flow.returning
      ? [stage(flow.from,flow.to,flow.at,'handoffReply'),...(flow.startedAt!=null&&flow.startedAt<=flow.at?[stage(flow.to,flow.from,flow.startedAt,'assignment')]:[])]
      : [stage(flow.from,flow.to,flow.at,'assignment')];
    for(const row of rows){
      if(historyHandoffs.get(row.id)?.toRole&&historyHandoffs.get(row.id)?.state===row.state)continue;
      historyHandoffs.set(row.id,row);
      changed=true;
    }
  }
  if(changed){
    while(historyHandoffs.size>300)historyHandoffs.delete(historyHandoffs.keys().next().value);
    save('team.handoffs.v1',[...historyHandoffs.values()]);
  }
}

// Questions appear only inside their conversation: no banner and no count at the top.
function renderArrival() {
  $('#alertCount').hidden=true;
  $('#arrival').hidden=true;
}
function renderDirectory() {
  if(page!=='structure')return;
  const groups=makeTeamDirectory(inventory,assignedTeams());
  const focused=document.activeElement?.dataset.directoryTerm;
  const labelNode=({label,term})=>{
    const name=label||term?.label||'—';
    const state=term?.state==='live'?(needsAttention(term)?'due':effectiveStatus(term)):'directoryOffline';
    const machine=term?.state==='live'?machineFor(term):copy('directoryOffline');
    const suffix=[agentLabel(term),machine,copy(state)].filter(Boolean).join(' · ');
    const attrs='class="directory-row'+(state==='due'?' attn':'')+'" data-state="'+escape(effectiveStatus(term))+'" title="'+escape(name+' · '+suffix)+'"';
    const contents=(agentPortrait(term)||avatar(name))+'<strong>'+escape(name)+'</strong><small>'+escape(machine)
      +'</small><i class="state-dot" aria-hidden="true"></i>';
    return term
      ? '<button type="button" '+attrs+' data-directory-term="'+escape(sessionKey(term))+'" aria-label="'+escape(name+' · '+suffix)
        +'" aria-pressed="'+(directoryOpen&&sessionKey(term)===sessionKey(chosen))+'">'+contents+'</button>'
      : '<div '+attrs+'>'+contents+'</div>';
  };
  const branch=(nodes,className)=>'<ul class="'+className+'">'+nodes.map(node=>'<li>'+labelNode(node)
    +(node.children.length?branch(node.children,'directory-children'):'')+'</li>').join('')+'</ul>';
  const groupHtml=group=>'<section class="directory-group"><header><h2>'+escape(group.title||copy('other'))+'</h2><small>'
    +group.count+'</small></header>'+branch(group.roots,'directory-roots')+'</section>';
  const hq=groups.find(group=>group.id==='hq');
  const primary=primaryTeams();
  const ordered=[...groups.filter(group=>primary.includes(group.id)).sort((a,b)=>primary.indexOf(a.id)-primary.indexOf(b.id)),
    ...groups.filter(group=>group!==hq&&!primary.includes(group.id))];
  const root=hq?.roots[0];
  setPanel('#directoryHQ',root?'<div class="directory-root">'+labelNode(root)+'</div>':'');
  const remainder=hq?[...hq.roots.slice(1),...(root?.children||[])]:[];
  const headquarters=remainder.length?[{...hq,roots:remainder,count:hq.count-1}]:[];
  setPanel('#directoryGroups',[...headquarters,...ordered].map(groupHtml).join('')
    ||(root?'':'<p class="muted">'+copy(snapshot.connection==='live'?'noTerminals':snapshot.connection)+'</p>'));
  $('#directoryCount').textContent=groups.length+copy('teamCount')+' · '+groups.reduce((sum,group)=>sum+group.count,0)+copy('directoryCount');
  const devices=[localMachine(),...snapshot.machines.map(machine=>machine.name).filter(Boolean)];
  $('#directoryMachines').textContent=[...new Set(devices)].join(' · ');
  if(focused)[...$('#directoryPanel').querySelectorAll('[data-directory-term]')].find(row=>row.dataset.directoryTerm===focused)?.focus({preventScroll:true});
}

function showQuestions() {
  const list=registeredQuestions(snapshot.terms,snapshot.ledger||{});
  renderArrival(list);
  const tab=$('[data-tab=questions]');
  tab.hidden=true;
  if(selectedTab==='questions')selectedTab='chat';
  const waiting=list.filter(q=>['answerNeeded','needsCheck'].includes(q.state)).length;
  const label=copy('approvalTab')+(waiting?' <span class="tab-count">'+waiting+'</span>':'');
  if(tab.innerHTML!==label)tab.innerHTML=label;
  $('#questionPanel').hidden=selectedTab!=='questions';
  const panel=$('#questions');
  const focused=document.activeElement?.closest('[data-question]')?.dataset.question;
  if(focused && panel.dataset.lang===language && list.some(q=>q.id===focused&&q.answerable) &&
     document.activeElement.matches('textarea') && snapshot.connection==='live') return;
  panel.dataset.lang=language;
  panel.innerHTML=list.map(questionHTML).join('');
}

// The agent that asked: its attachment tray (the one its conversation's composer uses) goes out with the answer.
const askerOf=q=>inventory.find(term=>term.address===q.address&&term.state==='live')||null;
const askerFor=form=>{const q=questions().find(item=>item.id===form?.dataset.question);return q?askerOf(q):null;};
function questionHTML(q) {
  const approvalTerm=inventory.find(term=>term.address===q.approval?.address);
  const asker=askerOf(q);
  if(asker)fetchAttachments(asker);
  return questionFormHTML(q,{label:asker?.label||inventory.find(term=>term.address===q.address)?.label||q.address,
    canAnswer:q.answerable&&snapshot.connection==='live'&&!questionSending.has(q.id),
    feedback:questionResults.get(q.id)||q.state, draft:questionDrafts.get(q.id)||'',
    approvalLabel:approvalTerm?.label, live:snapshot.connection==='live',
    files:asker?filesFor(asker):[], filesKey:asker?sessionKey(asker):'', attachBusy:asker?pendingFiles(sessionKey(asker))>0:true},copy,escape);
}
/** Question cards are not rebuilt while someone types in them, so their image lists are patched in place. */
function refreshQuestionFiles(){
  for(const box of document.querySelectorAll('[data-question-files]')){
    const term=inventory.find(item=>sessionKey(item)===box.dataset.questionFiles);
    const busy=!term||pendingFiles(box.dataset.questionFiles)>0;
    const html=questionFilesHTML(term?filesFor(term):[],busy,copy,escape);
    if(box.innerHTML!==html)box.innerHTML=html;
    const button=box.closest('[data-question]')?.querySelector('[data-question-attach]');
    if(button)button.disabled=busy;
  }
}

const participant = term => ({key:sessionKey(term),label:term.label,machine:machineFor(term),address:term.address});
const pending = step => ['approvalWaiting','answerNeeded','needsCheck'].includes(step.state);
const you = () => ({key:'user',label:copy('you')});

function transferEntries() {
  const messages=deliveries.filter(item=>['sent','needsCheck'].includes(item.state)).map(item=>{
    const target=inventory.find(term=>sessionKey(term)===item.target);
    const to=target?participant(target):{key:item.target,label:item.label};
    const text=item.text || copy('attachedImages');
    return {...item,text,steps:[{...item,text,from:you(),to,kind:'request'}]};
  });
  const flows=flowEntries.map(item=>{
    const from=participant(item.from), to=participant(item.to);
    const result={...item,id:item.id+(item.returning?':reply':':start'),from,to,kind:item.returning?'handoffReply':'assignment'};
    const steps=item.startedAt!==null && item.startedAt<=item.at
      ? [{...result,id:item.id+':start',at:item.startedAt,from:to,to:from,kind:'assignment',state:'working'},result]
      : [result];
    return {...item,steps};
  });
  const asks=questions().filter(q=>q.at!==null).flatMap(q=>{
    const term=inventory.find(term=>term.address===q.address);
    if(!term)return [];
    const state=q.approval && q.state==='answerNeeded'?'approvalWaiting':q.state;
    const step={id:q.id,at:q.at,from:participant(term),to:you(),text:q.ask,state,kind:q.approval?'approvalRequest':'questions',question:q};
    return [{...step,steps:[step]}];
  });
  const replies=(snapshot.replies||[]).flatMap(reply=>{
    const at=Date.parse(reply.at);
    if(reply.kind!=='reply'||!Number.isFinite(at)||typeof reply.body!=='string')return [];
    const matching=inventory.filter(term=>legacyDraftKey(term)===reply.role);
    const exact=matching.filter(term=>term.session===reply.session);
    const from=exact.length===1?participant(exact[0]):{
      key:'reply:'+reply.role+':'+reply.session,label:matching[0]?.label||reply.role
    };
    const step={id:'reply:'+reply.id,from,to:you(),at,text:reply.body,state:'reply',kind:'handoffReply'};
    return [{...step,steps:[step]}];
  });
  return [...messages,...flows,...asks,...replies].sort((a,b)=>b.at-a.at);
}

const selectedWork = (entries=transferEntries()) => entries.find(entry=>entry.id===eventId) || entries[0];
const workTitle = work => work.text.split(/\r?\n/,1)[0].slice(0,70);
const statusBadge = step => '<span class="badge'+(pending(step)?' pending':'')+'">'+copy(step.state)+'</span>';

function transfers() {
  const entries=transferEntries(), work=selectedWork(entries);
  const title=work?workTitle(work):'';
  $('#routeName').textContent=title;
  $('#logName').textContent=title;
  const tasks=work?[...entries.slice(0,3).filter(item=>item.id!==work.id).slice(0,2),work].sort((a,b)=>b.at-a.at):[];
  const taskButton=item=>'<button type="button" class="task" data-event="'+escape(item.id)+'" aria-pressed="'+(work?.id===item.id)+'">'
    +escape(workTitle(item))+'</button>';
  setPanel('#taskList',tasks.map(taskButton).join(''));
  setPanel('#workList',entries.length?'<ul class="work-list">'+entries.slice(0,200).map(item=>{
    const last=item.steps.at(-1);
    return '<li>'+taskButton(item)+'<span>'+escape(last.from.label+' → '+last.to.label)+'</span><time>'+time(last.at)+'</time>'+statusBadge(last)+'</li>';
  }).join('')+'</ul>':'<p class="muted">'+copy('noHandoffs')+'</p>');
  setPanel('#transfers',work?'<ol class="events">'+work.steps.map(step=>'<li class="event'+(pending(step)?' pending':'')+'"><time>'+time(step.at)
    +'</time><span class="direction" aria-hidden="true">→</span><span><b>'+escape(step.from.label)+' → '+escape(step.to.label)
    +'</b><small>'+copy(step.kind)+' · '+escape(step.text.slice(0,120))+'</small></span>'+statusBadge(step)+'</li>').join('')+'</ol>'
    +(work.state==='approvalWaiting'||work.state==='answerNeeded'?'<p class="action">'+copy(work.state==='approvalWaiting'?'approvalNext':'answerNext')+'</p>':'')
    +(work.question?.approval?'<button type="button" class="direct-approval" '+(snapshot.connection==='live'&&work.question.approval.address?'':'disabled')
      +' data-approve="'+escape(work.question.id)+'">'+copy('openApproval')+'</button>':'')
    :'<p class="muted">'+copy('noHandoffs')+'</p>');
  $('#replay').disabled=!work;
  $('#replay').setAttribute('aria-label',copy('replay'));
  $('#replay').title=copy('replay');
  renderLanes(work);
}

function setPanel(selector, html) {
  const panel=$(selector);
  if(panel.dataset.signature===html)return false;
  panel.dataset.signature=html;
  panel.innerHTML=html;
  return true;
}

function renderLanes(work) {
  if(!work){
    setPanel('#lanes','<p class="muted">'+copy('noHandoffs')+'</p>');
    return;
  }
  const people=[...new Map(work.steps.flatMap(step=>[step.from,step.to]).map(person=>[person.key,person])).values()];
  const heads=people.map(person=>{
    const label=avatar(person.label)+'<b>'+escape(person.label)+'</b><small>'+escape(person.machine||'')+'</small>';
    return person.address
      ? '<button type="button" class="node" data-participant="'+escape(person.key)+'">'+label+'</button>'
      : '<div class="node">'+label+'</div>';
  }).join('');
  const lines=work.steps.map(step=>{
    const description=[step.from.label+' → '+step.to.label,copy(step.kind),copy(step.state),time(step.at)].join(' · ');
    return '<button type="button" class="hop'+(pending(step)?' pending':'')+'" data-step="'+escape(step.id)+'" title="'+escape(description)
      +'" aria-label="'+escape(description)+'"><b>'+copy(step.kind)+'</b><time>'+time(step.at)+'</time></button>';
  }).join('');
  if(!setPanel('#lanes','<div class="lane-head">'+heads+'</div><div class="sequence">'
    +people.map(()=>'<i class="life" aria-hidden="true"></i>').join('')+lines+'</div>'))return;
  const columns='repeat('+people.length+', minmax(0,1fr))';
  const sequence=$('.sequence');
  $('.lane-head').style.gridTemplateColumns=columns;
  sequence.style.gridTemplateColumns=columns;
  sequence.style.gridTemplateRows='repeat('+work.steps.length+', var(--hop-height, 44px))';
  Array.from(sequence.querySelectorAll('.life')).forEach((life,index)=>{life.style.gridColumn=index+1;});
  Array.from(sequence.querySelectorAll('.hop')).forEach((hop,index)=>{
    const {from,to}=work.steps[index];
    const start=people.findIndex(person=>person.key===from.key);
    const end=people.findIndex(person=>person.key===to.key);
    hop.style.gridColumn=(Math.min(start,end)+1)+' / '+(Math.max(start,end)+2);
    hop.style.gridRow=index+1;
    hop.style.setProperty('--inset',50/(Math.abs(start-end)+1)+'%');
    hop.classList.toggle('reverse',start>end);
  });
}

async function motion(stepId) {
  const token=++replayToken;
  flight?.cancel();
  if(document.hidden)return;
  const hops=[...document.querySelectorAll('.hop')].filter(hop=>!stepId||hop.dataset.step===stepId);
  for(const hop of hops){
    if(token!==replayToken || !hop.isConnected || !hop.clientWidth)break;
    if(stepId){
      const body=$('#routePanel .content');
      const delta=hop.getBoundingClientRect().bottom-body.getBoundingClientRect().bottom;
      if(delta>0)body.scrollTop+=Math.ceil(delta)+5;
    }
    if(matchMedia('(prefers-reduced-motion: reduce)').matches){
      hop.classList.add('recent');
      await new Promise(resolve=>setTimeout(resolve,520));
      hop.classList.remove('recent');
      continue;
    }
    const inset=parseFloat(hop.style.getPropertyValue('--inset'))/100;
    const distance=hop.clientWidth*(1-2*inset);
    const direction=hop.classList.contains('reverse')?-1:1;
    const marker=document.createElement('i');
    marker.className='motion-marker';
    marker.setAttribute('aria-hidden','true');
    marker.style.left=(direction<0?100-inset*100:inset*100)+'%';
    hop.append(marker);
    flight=marker.animate([
      {transform:'translateX(0) scaleX(.35)',opacity:0},
      {opacity:1,offset:.18},
      {opacity:1,offset:.78},
      {transform:'translateX('+direction*distance+'px) scaleX(.55)',opacity:0}
    ],{duration:540,easing:'cubic-bezier(.24,.72,.24,1)'});
    try{await flight.finished;}catch{}finally{marker.remove();}
  }
}

// Establish a baseline on connection. Only animate a work item's newest unseen stage.
function scanActivity() {
  if(snapshot.connection!=='live')return;
  const arrived=[];
  for(const work of transferEntries()){
    const step=work.steps.at(-1);
    const qualifies=['sent','working','questionAck','reply'].includes(step.state)
      && ['request','assignment','handoffReply'].includes(step.kind);
    if(activityReady && qualifies && !seenSteps.has(step.id)){
      arrived.push({work:work.id,step:step.id,at:step.at});
      if(step.kind==='assignment')markAssignment(step.to.key);
    }
    if(qualifies)for(const recorded of work.steps)seenSteps.add(recorded.id);
  }
  activityReady=true;
  activityQueue.push(...arrived.sort((a,b)=>a.at-b.at));
}

async function playActivity() {
  if(playingActivity)return;
  playingActivity=true;
  try{
    while(activityQueue.length){
      const item=activityQueue.shift();
      if(!transferEntries().some(work=>work.id===item.work && work.steps.some(step=>step.id===item.step)))continue;
      eventId=item.work;
      structure();
      transfers();
      await motion(item.step);
    }
  }finally{
    playingActivity=false;
  }
}

const filesFor=term=>attachmentsByTarget.get(sessionKey(term))||[];
const pendingFiles=key=>attachmentPending.get(key)||0;

function fetchAttachments(term){
  if(!term)return;
  const key=sessionKey(term);
  if(attachmentsByTarget.has(key)||loadingAttachments.has(key))return;
  loadingAttachments.add(key);
  post({type:'attachments',address:term.address,session:term.session});
}

function renderAttachments(term){
  const key=sessionKey(term), files=filesFor(term), count=pendingFiles(key);
  const disabled=!sendable(term,snapshot.connection)||viewed().some(record=>record.state==='sending');
  const message=attachmentNotices.get(key);
  $('#attachmentNotice').textContent=message?copy(message):'';
  const container=$('#attachmentList');
  container.hidden=!files.length;
  const signature=JSON.stringify([key,language,disabled,count,files.map(x=>x.id)]);
  if(container.dataset.signature===signature)return;
  container.dataset.signature=signature;
  container.innerHTML=files.map(file=>'<span class="attachment-item">'
    +(file.thumbnail?'<img src="data:image/png;base64,'+file.thumbnail+'" alt="">':'')
    +'<span>'+escape(file.name)+'</span><button type="button" data-remove="'+escape(file.id)+'" aria-label="'
    +copy('removeAttachment')+' · '+escape(file.name)+'"'+(disabled||count?' disabled':'')+'>×</button></span>').join('');
}

async function addAttachments(list,term=active()){
  const key=sessionKey(term);
  if(!sendable(term,snapshot.connection)||pendingFiles(key)||deliveries.some(entry=>entry.target===key&&entry.state==='sending'))return;
  const available=4-filesFor(term).length;
  const inputs=Array.from(list);
  attachmentNotices.delete(key);
  if(inputs.length>available)attachmentNotices.set(key,'attachmentLimit');
  const files=inputs.slice(0,available).filter(file=>{
    const valid=file.size<=25*1024*1024;
    if(!valid)attachmentNotices.set(key,'attachmentFailed');
    return valid;
  });
  if(!files.length){updateComposer();refreshQuestionFiles();return}
  for(const file of files){
    attachmentPending.set(key,pendingFiles(key)+1);
    const reader=new FileReader();
    const failed=()=>{attachmentPending.set(key,Math.max(0,pendingFiles(key)-1));attachmentNotices.set(key,'attachmentFailed');updateComposer();refreshQuestionFiles()};
    reader.onload=()=>{
      const encoded=String(reader.result).split(',')[1];
      if(encoded)post({type:'attach',address:term.address,session:term.session,name:file.name,data:encoded});
      else failed();
    };
    reader.onerror=failed;
    reader.readAsDataURL(file);
  }
  updateComposer();
}

function directConversationId(term){
  const role=legacyDraftKey(term);
  return 'direct:'+(role&&inventory.filter(item=>legacyDraftKey(item)===role).length===1?role:sessionKey(term));
}
function personalChatEntries(term){
  const roleName=role=>inventory.find(member=>legacyDraftKey(member)===role)?.label
    ||assignedTeams().flatMap(team=>team.roles).find(([key])=>key===role)?.[1]||role;
  const records=conversationRecords().filter(record=>!(snapshot.handoffs&&record.kind==='agent-handoff'));
  const entries=combineChat(term,legacyMessages,deliveries,records,roleName,directConversationId(term));
  const role=legacyDraftKey(term);
  if(page==='conversations'&&term){
    for(const card of handoffCardsFor(snapshot.handoffs,[term.address]))
      if(card.from.address!=='desk'&&card.to.address!=='desk')entries.push({id:card.id,at:card.at,state:'handoffCard',card});
    entries.sort((a,b)=>a.at-b.at);
  }
  if(page==='conversations'&&role){
    for(const row of historyHandoffs.values()){
      if(row.toRole===role||row.fromRole===role)entries.push({text:row.body,at:row.at,
        state:row.toRole===role?'incomingHandoff':'outgoingHandoff',from:row.author+' → '+row.recipient});
    }
    entries.sort((a,b)=>a.at-b.at);
  }
  return entries;
}

function updateSendButton(term=active(), history=viewed()) {
  $('#send').disabled = sendBlocked({inputDisabled:$('#draft').disabled, text:$('#draft').value, files:filesFor(term).length,
    loadingFiles:pendingFiles(sessionKey(term)), sending:history.some(record => record.state === 'sending')});
}

function updateComposer() {
  const term = active();
  const key = sessionKey(term);
  const history = viewed();
  const item = history.at(-1);
  $('#draft').disabled = !sendable(term,snapshot.connection);
  updateSendButton(term, history);
  $('#draft').setAttribute('aria-description',copy('imageInput'));
  $('#draft').placeholder = term?.program?.agent ? copy('sendMessageTo').replace('{name}',()=>term.label) : copy('chatUnavailable');
  $('#sendStatus').textContent = item&&item.state!=='sent' ? copy(item.state) : '';
  const log=$('#chatLog'), transcript=$(page==='conversations'?'#chatHistory':'#chatTranscript');
  const entries=personalChatEntries(term);
  const showConversation=page==='conversations';
  $('#chatHistory').hidden=selectedTab!=='chat'||(!entries.length&&!showConversation);
  if(showConversation)$('#chatHistory').open=true;
  $('#historyLabel').textContent=copy('chatHistory')+' · '+entries.length;
  const content=entries.map((entry,index)=>entry.card?chatHandoffCard(entry.card):entry.state==='progress'&&showConversation
    ?progressDisclosure({author:entry.from,body:entry.text,at:entry.at},'direct:'+key+':'+entry.id)
    :'<div class="chat-entry" data-record-id="'+escape(entry.id||'')+'"'+(entry.from?'':' data-mine')+' data-kind="'+escape(entry.state)+'" data-tag="'+escape(messageTag(entry.state)||'')+'"><small>'
    +entryMeta(entry,entries,index)
    +(entry.images?' · '+copy('attachedImages')+' '+entry.images:'')
    +'</small>'+renderChatText(entry.text)+messageImages(entry)+(showConversation?lineageMarkup(snapshot.lineage,directConversationId(term),entry.id,inventory,snapshot.ledger||{},copy):'')+'</div>').join('') || (showConversation?'<p class="chat-empty">'+copy('chatEmpty')+'</p>':'');
  renderAttachments(term);
  if (content !== log.dataset.signature || log.dataset.target !== key) {
    const switched = log.dataset.target!==key;
    const follow = transcript.scrollHeight-transcript.scrollTop-transcript.clientHeight<48 || switched;
    const added = !switched && entries.length > Number(log.dataset.count || 0);
    log.dataset.count = String(entries.length);
    log.innerHTML = content;
    enterFresh(log,'chat:'+key,'data-record-id',RISE,180);
    if(switched&&log.dataset.target)enter([log],FADE,140);
    restoreProgress(log);
    observeChatImages();
    log.dataset.signature = content;
    log.dataset.target = key;
    if(showConversation){ if(switched)chatScroll.toBottom(); else chatScroll.contentChanged(added); }
    else if(follow)transcript.scrollTop=transcript.scrollHeight;
  }
}

const expandedChains=new Set();
let handoffRailTimer;
const RAIL_HAMMER='<svg class="hr-tool" viewBox="0 0 14 14" aria-hidden="true"><rect x="6" y="5" width="2" height="9" rx="1"/><rect class="hr-tool-head" x="2" y="1.5" width="10" height="4.5" rx="1.2"/></svg>';
const RAIL_ICONS={working:'<span class="hr-dots" aria-hidden="true"><i></i><i></i><i></i></span>',waiting:'<span class="hr-clock" aria-hidden="true"></span>'};
const railStatus=address=>{
  const term=inventory.find(item=>item.address===address&&item.state==='live');
  return term?(workingNow(term)?'working':effectiveStatus(term)):'';
};
function railName(node){
  if(node.address==='desk')return copy('you');
  return inventory.find(item=>item.address===node.address&&(!node.session||item.session===node.session))?.label||retiredRoleName(node.role,snapshot.configuredTeams)||node.address;
}
// A branch starts under the node it forks from, not under the first node of the chain.
function alignRailBranches(rail){
  for(const flow of rail.querySelectorAll('.hr-flow'))alignFlowBranches(flow);
}
function alignFlowBranches(rail){
  const main=rail.querySelector('.hr-row:not(.hr-branch)');
  if(!main)return;
  const nodes=main.querySelectorAll('.hr-node'), left=main.getBoundingClientRect().left;
  for(const row of rail.querySelectorAll('.hr-branch')){
    const node=nodes[Number(row.dataset.at)];
    if(!node)continue;
    const box=node.getBoundingClientRect();
    row.style.paddingLeft=Math.max(0,Math.round(box.left+box.width/2-left-1))+'px';
  }
}
// Strip machine envelopes from a one-line summary ([HerdrDesk lineage …], <hc …>).
const cleanSummary=text=>String(text||'').replace(/\[HerdrDesk[^\]]*\]/g,'').replace(/<\/?hc[^>]*>/g,'').replace(/\s+/g,' ').trim();
function railNode(node){
  const term=inventory.find(item=>item.address===node.address&&(!node.session||item.session===node.session));
  // One label: working now (handoff or terminal), waiting on someone named, or the handoff state.
  const working=node.state==='working'||node.sessionActivity==='working';
  const state=working?'working':node.state;
  const face=node.address==='desk'?avatar(copy('you')):(term&&agentPortrait(term,working))||leadFaceHTML({engine:'neutral',resting:true});
  const label=working?copy('flowWorking'):state==='waiting'&&node.waitingFor?copy('flowWaitingFor').replace('{name}',()=>railName({address:node.waitingFor,role:''})):copy('chainState_'+state);
  return '<div class="hr-node" data-state="'+escape(state)+'"'+(node.address==='desk'?' data-desk':'')+(node.sessionActivity?' data-activity="'+escape(node.sessionActivity)+'"':'')+'><span class="hr-face">'+face+(working?RAIL_HAMMER:'')+'</span>'
    +'<b class="hr-name">'+escape(railName(node))+'</b><small class="hr-state">'+(RAIL_ICONS[state]||'')+escape(label)+'</small></div>';
}
const railLink=link=>'<span class="hr-link" data-kind="'+escape(link.kind)+'" aria-hidden="true"><svg viewBox="0 0 100 12" preserveAspectRatio="none"><path d="M0 6H100"/></svg><i class="hr-head"></i><i class="hr-packet"></i></span>';
function railRow(nodes,links,hidden=0,hiddenAt=-1,key=''){
  let html='';
  nodes.forEach((node,index)=>{
    if(index===hiddenAt)html+='<button type="button" class="hr-more" data-chain-expand="'+escape(key)+'">'+escape(copy('chainHidden').replace('{n}',String(hidden)))+'</button>';
    if(index>0&&links[index-1])html+=railLink(links[index-1]);
    html+=railNode(node);
  });
  return html;
}
function railPortrait(party){
  if(party.address==='desk')return avatar(copy('you'));
  const term=inventory.find(item=>item.address===party.address&&(!party.session||item.session===party.session));
  return (term&&agentPortrait(term))||leadFaceHTML({engine:'neutral',resting:true});
}
const chatHandoffCard=card=>handoffCardHTML(card,railName,railPortrait,escape,copy,time);

/** "[tag] name · time", plus "확인 전" on my message until the other side shows anything after it. */
function entryMeta(entry,entries,index){
  const tag=messageTag(entry.state);
  if(!entry.from){
    const extra=entry.state==='sent'?(awaitingResponse(entries,index)?' · '+copy('tagWaiting'):''):' · '+copy(entry.state);
    return tagHTML(tag||'sent',copy,escape)+(entry.at?time(entry.at):'—')+extra;
  }
  return tagHTML(tag,copy,escape)+escape(entry.from)+' · '+(entry.at?time(entry.at):'—')+(tag?'':' · '+copy(entry.state));
}
function railChainHTML(chain,key){
  return '<div class="hr-flow"><div class="hr-row">'+railRow(chain.nodes,chain.links,chain.hidden,chain.hiddenAt,key)+'</div>'
    +chain.branches.map(branch=>'<div class="hr-row hr-branch" data-at="'+branch.at+'"><span class="hr-fork" aria-hidden="true"></span>'+railLink(branch.links[0])+railRow(branch.nodes,branch.links.slice(1))+'</div>').join('')+'</div>';
}
// A team room shows every flow running in the team; a direct conversation shows that agent's own chain.
function renderHandoffRail(term,room){
  const rail=$('#handoffRail');
  clearTimeout(handoffRailTimer);
  if(page!=='conversations'||snapshot.connection!=='live'||(!room&&!term)){rail.hidden=true;return false;}
  const key=room?'room:'+room.id:sessionKey(term);
  const expanded=expandedChains.has(key);
  let chains=[], hidden=0;
  if(room){
    const members=room.members.map(member=>({address:member.address,session:member.session,role:legacyDraftKey(member)}));
    ({flows:chains,hidden}=teamFlows(snapshot.handoffs,members,railStatus,Date.now(),{limit:expanded?20:3,collapse:!expanded}));
  }else{
    const chain=buildChain(snapshot.handoffs,{address:term.address,session:term.session,role:legacyDraftKey(term)},railStatus,Date.now(),{collapse:!expanded});
    if(chain)chains=[markWaiting(chain,snapshot.handoffs?.edges||[])];
  }
  if(!chains.length){rail.hidden=true;setPanel('#handoffRail','');return false;}
  const nodes=chains.flatMap(chain=>[...chain.nodes,...chain.branches.flatMap(branch=>branch.nodes)]);
  const name=role=>railName(nodes.find(node=>node.role===role)||{role,address:''});
  const working=[...new Set(nodes.filter(node=>node.address!=='desk'&&(node.state==='working'||node.sessionActivity==='working')).map(node=>railName(node)))];
  const latest=(snapshot.handoffs?.edges||[]).filter(edge=>nodes.some(node=>node.address===edge.to.address)).sort((a,b)=>b.updatedAt-a.updatedAt)[0];
  const first=chains[0];
  const note=working.length?copy('flowNow').replace('{names}',()=>working.join(', ')):copy(first.note.key).replace('{name}',()=>name(first.note.name));
  const html=(room&&chains.length+hidden>1?'<p class="hr-title">'+escape(copy('flowCount').replace('{n}',String(chains.length+hidden)))+'</p>':'')
    +chains.map(chain=>railChainHTML(chain,key)).join('')
    +(hidden?'<button type="button" class="hr-more hr-more-flows" data-chain-expand="'+escape(key)+'">'+escape(copy('flowMore').replace('{n}',String(hidden)))+'</button>':'')
    +'<p class="hr-note" role="status">'+escape(note)
    +(latest?.summary?'<small title="'+escape(latest.summary)+'">'+escape(snippet(cleanSummary(latest.summary),70))+'</small>':'')+'</p>';
  setPanel('#handoffRail',html);
  alignRailBranches(rail);
  rail.dataset.motion=motionPreference.matches?'off':'on';
  rail.hidden=false;
  if(chains.some(chain=>chain.links.some(link=>link.kind==='go')))handoffRailTimer=setTimeout(()=>renderHandoffRail(active(),currentRoom()),3200);
  return true;
}
document.addEventListener('click',event=>{
  const body=event.target.closest('.hc-body');
  if(!body)return;
  const card=body.closest('.hc-card');
  card.toggleAttribute('data-open');
});
$('#handoffRail').addEventListener('click',event=>{
  const button=event.target.closest('[data-chain-expand]');
  if(!button)return;
  expandedChains.add(button.dataset.chainExpand);
  renderHandoffRail(active(),currentRoom());
});

function renderAgentActivity(term,room) {
  const activity=$('#agentActivity'), group=$('#groupActivity');
  clearTimeout(pendingActivityTimer);
  activity.hidden=true;
  group.hidden=true;
  if(page!=='conversations'||snapshot.connection!=='live')return;
  const actor=workingNow(term)?term:room?.members.find(workingNow)||term;
  if(actor?.state!=='live')return;
  const status=effectiveStatus(actor), key=sessionKey(actor);
  const request=deliveries.findLast(item=>item.target===key&&item.state==='sent');
  const runtime=snapshot.liveTurns?.[key];
  const statusAt=Math.max(Number(actor.statusMs||0),Date.parse(runtime?.at)||0);
  const lastReply=(snapshot.replies||[]).some(entry=>entry.role===legacyDraftKey(actor)&&entry.kind==='reply'
    &&Date.parse(entry.at)>=request?.at);
  const waitRemaining=request?request.at+10*60*1000-Date.now():0;
  const waiting=waitRemaining>0&&!lastReply
    &&!(status==='done'&&statusAt>=request.at);
  const needsReply=needsAttention(actor);
  if(!needsReply&&status!=='working'&&!waiting)return;
  const state=needsReply?'due':status==='working'?'working':'waitingForAgent';
  const moving=state==='working';
  if(state==='waitingForAgent')pendingActivityTimer=setTimeout(()=>renderAgentActivity(active(),currentRoom()),waitRemaining);
  const role=legacyDraftKey(actor);
  const evidence=conversationRecords().filter(entry=>entry.recipient===role
    ||(moving&&entry.role===role&&entry.kind==='progress'))
    .reduce((latest,entry)=>!latest||Date.parse(entry.at)>Date.parse(latest.at)?entry:latest,null);
  const task=evidence&&Date.parse(evidence.at)>=(request?.at||0)?evidence.body:request?.text;
  const label=actor.label+' · '+copy(state);
  const icon=agentPortrait(actor,moving)||sheep(moving?'trot':'still');
  const taskLabel=task?'<small>'+escape(snippet(task,95))+'</small>':'';
  const panel=room?group:activity;
  panel.dataset.state=state;
  if(room)setPanel('#groupActivity',icon+'<span role="status">'+escape(label)+taskLabel+'</span>');
  else{
    setPanel('#activitySheep',icon);
    setPanel('#agentActivityText',escape(label)+taskLabel);
  }
  panel.hidden=false;
}

function renderChatContext(term,room) {
  const transcript=$(page==='conversations'?'#chatHistory':'#chatTranscript');
  const follow=transcript.scrollHeight-transcript.scrollTop-transcript.clientHeight<48;
  const history=room?[...historyHandoffs.values()].filter(item=>item.team===room.id):[];
  const latest=history.reduce((best,row)=>{
    if(!best||row.at>best.at)return row;
    if(row.at===best.at && (row.kind==='handoffReply' || best.kind!=='handoffReply'))return row;
    return best;
  },null);
  const handoff=$('#inlineHandoff');
  handoff.hidden=!latest || page!=='conversations';
  const currentKey=room?.id || sessionKey(term);
  if(latest&&page==='conversations'){
    const fresh=roomCurrentKey===currentKey && previousInlineHandoff!==latest.id;
    const changed=setPanel('#inlineHandoff','<button type="button" class="chat-handoff" aria-label="'+escape(copy('handoffDetails')+' · '+latest.author+' → '+latest.recipient)
      +'">'+sheep()+'<span><b>'+escape(latest.author+' → '+latest.recipient)
      +'</b><small>'+escape(copy(latest.kind)+' · '+latest.body)+'</small></span><span aria-hidden="true">›</span></button>');
    if(changed&&fresh&&selectedTab==='chat')handoff.querySelector('.sheep').dataset.motion='handoff';
  }
  const requests=page==='conversations'?roomQuestions(room,term):[];
  const request=requests.at(-1);
  const waiting=[term,...(room?.members||[])].find(member=>member?.state==='live'&&member.status==='blocked');
  // what needs the person comes first: a login, then a permission prompt; a usage limit only shows when nothing else does
  const people=snapshot.connection==='live'?[term,...(room?.members||[])]:[];
  const troubled=people.find(member=>agentTrouble(member)==='login')||(!waiting&&people.find(member=>agentTrouble(member)==='limit'))||null;
  const approval=$('#inlineApproval');
  approval.hidden=!request&&!waiting&&!troubled || page!=='conversations';
  const typing=approval.contains(document.activeElement)&&document.activeElement.matches('textarea')
    &&keepTyping(requests,document.activeElement.closest('[data-question]')?.dataset.question,snapshot.connection==='live',questionSending);
  if(request){
    if(!typing&&setPanel('#inlineApproval','<div class="chat-questions">'+requests.map(questionHTML).join('')+'</div>'))
      enterFresh(approval,'questions','data-question',POP,160);
  }else if(troubled){
    // a login or usage limit: say what the person can do, and offer the terminal where it is shown
    const kind=agentTrouble(troubled);
    setPanel('#inlineApproval','<div class="chat-approval chat-trouble" data-trouble="'+kind+'">'+(kind==='login'?KEY:HOURGLASS)
      +'<span><strong>'+escape(copy('trouble_'+kind)+' · '+troubled.label)+'</strong><p>'+escape(copy('troubleHint_'+kind))+'</p></span>'
      +'<button type="button" data-waiting-terminal="'+escape(sessionKey(troubled))+'">'+copy('terminal')+'</button></div>');
  }else if(waiting){
    setPanel('#inlineApproval','<div class="chat-approval"><strong>'+escape(copy('due')+' · '+waiting.label)
      +'</strong><button type="button" data-waiting-terminal="'+escape(sessionKey(waiting))+'">'+copy('terminal')+'</button></div>');
  }
  roomCurrentKey=currentKey;
  previousInlineHandoff=latest?.id||'';
  if(page==='conversations')chatScroll.contentChanged(false);
  else if(follow)transcript.scrollTop=transcript.scrollHeight;
}

function detail() {
  const term = active(), key = sessionKey(term), room=currentRoom();
  const icon=agentPortrait(term,busyNow(term),false,busyNow(term))||escape(Array.from(term?.roleLabel || term?.label || '·')[0]);
  const editPortrait=page==='conversations'&&!room&&canCustomize(term);
  $('#targetAvatar').hidden=editPortrait;
  const editButton=$('#characterEdit');
  editButton.hidden=!editPortrait;
  editButton.setAttribute('aria-label',copy('characterEdit'));
  editButton.title=copy('characterEdit');
  if(editPortrait)setPanel('#characterEdit',(agentPortrait(term,busyNow(term),true,busyNow(term))||icon)+'<span aria-hidden="true" class="character-pencil">✎</span>');
  else setPanel('#targetAvatar',room?teamEmblem(room):icon);
  $('#recipient').textContent=term?copy('recipient')+' · '+term.label:'';
  $('#targetTitle').textContent = room?.title || term?.label || (chosen && snapshot.connection === 'live' ? copy('sessionChanged') : copy('select'));
  $('#targetPath').textContent=room?(term?copy('leadTo')+' · '+term.label:copy('leadUnavailable'))
    :term?[agentLabel(term),machineFor(term)].filter(Boolean).join(' · '):'';
  $('#send').textContent=copy(room?'sendToLead':page==='conversations'?'directSend':'send');
  if(!room && selectedTab==='team')selectedTab='chat';
  const showFeed=Boolean(room)&&selectedTab==='team';
  const feed=$('#roomFeed');
  const openingFeed=showFeed&&feed.hidden;
  feed.hidden=!showFeed;
  renderTaskBoard(room,showFeed);
  $('[data-tab=team]').hidden=!room;
  renderGroupMembers(room);
  $('[data-tab=chat]').hidden=Boolean(room);
  $('[data-tab=chat]').textContent=copy(page==='conversations'?'personalChats':'chat');
  const launchModel=agentName(term)&&!term.modelOptions?.reportedModel&&term.modelOptions?.launchModel;
  $('#launchModel').textContent=launchModel?copy('launchModel')+' · '+launchModel:'';
  $('#targetPath').title=term ? [machineFor(term),term.location?.space,term.location?.tab,term.address].filter(Boolean).join(' › ') : '';
  $('#sessionState').textContent = term ? copy(effectiveStatus(term)) : '';
  if (selectedTab==='activity' && page==='conversations') selectedTab=room?'team':'chat';
  $('#chat').hidden = !['chat','team'].includes(selectedTab);
  const inChat=page==='conversations';
  const showTerminal=inChat?terminalOpen:selectedTab==='terminal'||terminalOpen;
  const inspected=approvalTarget
    ?inventory.find(candidate=>candidate.address===approvalTarget.address&&candidate.session===approvalTarget.session):term;
  $('#terminal').hidden=!showTerminal;
  $('#terminal').closest('.content').classList.toggle('terminal-drawer-open',inChat&&showTerminal);
  $('#terminalTarget').textContent=inspected?.label||copy('streamUnavailable');
  $('#terminalToggle').hidden=!inChat||!term;
  $('#terminalToggle').setAttribute('aria-expanded',String(inChat&&showTerminal));
  $('[data-tab=terminal]').hidden=inChat;
  $('#tabs').hidden=inChat;

  $('#transferPanel').hidden=selectedTab!=='activity';
  $('#questionPanel').hidden=selectedTab!=='questions';
  document.querySelectorAll('[data-tab]').forEach(button => {
    button.setAttribute('aria-pressed', String(button.dataset.tab === selectedTab));
  });
  if ($('#draft').dataset.target !== key) {
    $('#draft').value = draftValue(term);
    fetchAttachments(term);
    $('#draft').dataset.target = key;
  }
  updateComposer();
  renderAgentActivity(term,room);
  if(renderHandoffRail(term,room)){$('#agentActivity').hidden=true;$('#groupActivity').hidden=true;}
  renderChatContext(term,room);
  if(page==='conversations'&&selectedTab==='chat'){
    const history=$('#chatHistory');
    if(history.dataset.displayedTarget!==key){
      history.dataset.displayedTarget=key;
      chatScroll.toBottom();
    }
  }
  renderRoomFeed(room);
  if(openingFeed)feedScroll.toBottom();
  if (showTerminal && !document.hidden) terminalView.sync(inspected,snapshot.connection==='live');
  else terminalView.stop();
}

let waitingExpiryTimer;
function renderWaitingInbox(){
  clearTimeout(waitingExpiryTimer);
  const now=Date.now(),expiry=[...inventory.map(term=>Date.parse(term.labels?.['ask.expires'])),
    ...['roots','tasks','pendingLinks'].flatMap(key=>(snapshot.lineage?.[key]||[]).map(item=>item.expiresAt))].filter(value=>Number.isFinite(value)&&value>now);
  if(expiry.length)waitingExpiryTimer=setTimeout(()=>render(),Math.min(2147483647,Math.max(1,Math.min(...expiry)-now+1)));
  const messages=[...Object.values(legacyMessages).flat(),...deliveries];
  const linked=new Set(linkedWaiting(snapshot.lineage,inventory,snapshot.ledger||{}).filter(({root})=>messages.some(message=>message.id===root.originRequestId&&message.conversationId===root.conversationId)).map(item=>item.row.key));
  const items=waitingInboxItems(inventory,snapshot.ledger||{}).filter(item=>!linked.has(item.key));
  const panel=$('#waitingInbox');panel.hidden=!items.length;
  $('#waitingInboxCount').textContent=copy('waitingRegistered')+' '+items.filter(item=>item.kind==='question').length+' · '+copy('waitingUnknown')+' '+items.filter(item=>item.kind==='blocked').length;
  const focused=document.activeElement?.dataset.inboxKey;
  const changed=setPanel('#waitingInboxList',waitingInboxMarkup(items,copy,snapshot.connection==='live'));
  if(changed&&focused)[...panel.querySelectorAll('[data-inbox-key]')].find(button=>button.dataset.inboxKey===focused)?.focus({preventScroll:true});
}
document.addEventListener('click',event=>{
  const button=event.target.closest('[data-inbox-key]');if(!button)return;
  const item=waitingInboxItems(inventory,snapshot.ledger||{}).find(row=>row.key===button.dataset.inboxKey);
  if(snapshot.connection!=='live'||!item?.target||item.binding!==button.dataset.inboxBinding){showNotice('waitingStale');renderWaitingInbox();return;}
  const wrapper=button.closest('[data-lineage-pending]');let lineage={};
  if(wrapper){
    const exact=linkedWaiting(snapshot.lineage,inventory,snapshot.ledger||{}).find(({link,row,root})=>link.id===wrapper.dataset.lineagePending&&link.taskId===wrapper.dataset.lineageTask&&root.originRequestId===wrapper.dataset.lineageRoot&&root.conversationId===wrapper.dataset.lineageConversation&&row.key===item.key&&row.binding===item.binding);
    if(!exact){showNotice('waitingStale');return;}
    lineage={pendingId:exact.link.id,taskId:exact.link.taskId,originRequestId:exact.root.originRequestId,conversationId:exact.root.conversationId};
  }
  post({type:'waitingTarget',...lineage,kind:item.kind,requestID:item.requestId||'',actorAddress:item.actor.address,actorSession:item.actor.session,actorRole:item.actor.role,
    address:item.target.address,session:item.target.session,role:item.target.role});
});

function render() {
  document.documentElement.lang = language;
  $('#language').value = language;
  for (const element of document.querySelectorAll('[data-copy]')) element.textContent = copy(element.dataset.copy);
  $('#connection').textContent = copy(snapshot.connection);
  $('#connection').dataset.state=snapshot.connection;
  $('#connection').title=copy(snapshot.connection);
  renderWaitingInbox();
  $('main').dataset.page=page;
  $('.heading h1').textContent=copy(pageTitles[page]);
  document.querySelectorAll('[data-view]').forEach(button=>{
    const selected=button.dataset.view===page;
    button.setAttribute('aria-pressed',String(selected));
    if(button.dataset.view==='conversations')button.hidden=selected;
  });
  $('#metrics').hidden=page!=='overview';
  $('.heading').hidden=['overview','conversations'].includes(page);
  $('#roomNav').hidden=page!=='conversations';
  $('[data-tab=activity]').hidden=page==='conversations';
  $('.dashboard').hidden=['conversations','structure'].includes(page);
  $('#directoryPanel').hidden=page!=='structure';
  $('.side').hidden=page==='structure'&&!directoryOpen;
  $('#directoryClose').hidden=page!=='structure';
  $('#directoryClose').setAttribute('aria-label',copy('close'));
  renderDirectory();
  if(page!=='conversations')$('#roomTools').hidden=true;
  renderRooms();
  $('#orgPanel').hidden=['handoff','work'].includes(page);
  $('#routePanel').hidden=page==='structure';
  $('#workPanel').hidden=page!=='work';
  terminalView.relabel();
  showNotice(noticeKey);
  metrics();
  structure();
  transfers();
  showQuestions();
  detail();
}

function choose(term) {
  chosen = term ? {address:term.address,session:term.session} : null;
  showNotice('');
  structure();
  renderDirectory();
  renderRooms();
  detail();
}

$('#language').addEventListener('change',event=>{
  language=languageFrom(event.target.value);
  localeChosen=true;
  save(localeKey,language);
  post({ type:'language', value:language });
  render();
});
$('#structure').addEventListener('click',event=>{
  const button=event.target.closest('[data-id]');
  if(button) choose(byId.get(button.dataset.id));

});
$('#teamPager').addEventListener('click',event=>{
  const button=event.target.closest('[data-team-page]');
  if(!button)return;
  teamPage+=Number(button.dataset.teamPage);
  structure();
  const buttons=[...$('#teamPager').querySelectorAll('button:not(:disabled)')];
  (buttons.find(el=>el.dataset.teamPage===button.dataset.teamPage)||buttons[0])?.focus({preventScroll:true});
});
$('#structure').addEventListener('click',event=>{
  const button=event.target.closest('[data-member-page]');
  if(!button)return;
  const team=button.closest('[data-team]').dataset.team;
  memberPages.set(team,(memberPages.get(team)||0)+Number(button.dataset.memberPage));
  structure();
});
new ResizeObserver(structure).observe($('#structure'));
$('#tabs').addEventListener('click',event=>{
  const tab=event.target.closest('[data-tab]')?.dataset.tab;
  if(!tab)return;
  if(tab==='terminal'&&page==='conversations'){openTerminalDrawer();return;}
  selectedTab=tab;renderRooms();detail();
});
$('.controls').addEventListener('click',event=>{
  const action=event.target.closest('[data-action]')?.dataset.action;
  if(action)post({type:action==='configure'?'chooseCore':'refresh'});
});
/** Enter-to-send for text fields under `root` (fieldOf picks the field from an event target, or null).
 * One Enter sends: in Korean the press that commits the last syllable also sends. When WebKit reports that one press twice
 * (composing keydown, then the commit echo), only the echo of that same commit, in that field, is ignored. */
function enterSends(root,fieldOf,send){
  const state={composing:false,ended:-Infinity,text:'',pending:null,pendingAt:0,sentCommit:null};
  root.addEventListener('compositionstart',event=>{if(fieldOf(event.target)){state.composing=true;state.text='';}});
  root.addEventListener('compositionupdate',event=>{if(fieldOf(event.target))state.text=event.data||'';});
  root.addEventListener('compositionend',event=>{
    const field=fieldOf(event.target);
    if(!field)return;
    state.composing=false;state.ended=performance.now();state.text=event.data||state.text;
    if(state.pending===field&&performance.now()-state.pendingAt<1000){
      state.pending=null;state.sentCommit={field,at:state.ended};
      setTimeout(()=>send(field),0);
    }
  });
  root.addEventListener('keydown',event=>{
    const field=fieldOf(event.target);
    if(!field)return;
    const action=enterAction(event,state.composing,performance.now()-state.ended,state.text);
    if(action==='sendAfterCommit'){state.pending=field;state.pendingAt=performance.now();return;}
    if(action==='other')return;
    state.pending=null;
    if(action==='swallow'||action==='send')event.preventDefault();
    // the echo of a commit that already sent (same field, same commit) is that same press
    const echo=state.sentCommit&&state.sentCommit.field===field&&state.sentCommit.at===state.ended&&performance.now()-state.ended<SEND_DEDUPE_MS;
    if(action==='send'&&!echo)send(field);
    if(action==='send')state.sentCommit=null;
  });
}
enterSends($('#draft'),target=>target.id==='draft'?target:null,()=>{if(!$('#send').disabled)$('#composer').requestSubmit($('#send'));});
// Per keystroke only the draft and the send button change; the chat history is not rebuilt.
$('#draft').addEventListener('input',event=>{
  const term=active();
  if(term)storeDraft(term,event.target.value,true);
  updateSendButton(term);
});
$('#attachmentList').addEventListener('click',event=>{
  const id=event.target.closest('[data-remove]')?.dataset.remove,term=active();
  if(id&&term)post({type:'detach',address:term.address,session:term.session,id});
});
const chatSurface=$('#chat');
const isImageFile=file=>file.type.startsWith('image/')||(!file.type&&/\.(png|jpe?g|gif|webp|heic|heif|tiff?|bmp|avif|ico)$/i.test(file.name));
function transferredImages(transfer){
  const files=Array.from(transfer?.files||[]);
  return (files.length?files:Array.from(transfer?.items||[]).map(item=>item.getAsFile()).filter(Boolean)).filter(isImageFile);
}
chatSurface.addEventListener('paste',event=>{
  if(event.target.closest?.('[data-question]'))return;   // a question card takes its own images
  const files=transferredImages(event.clipboardData);
  if(files.length){event.preventDefault();addAttachments(files);}
});
chatSurface.addEventListener('dragover',event=>{
  if(!event.dataTransfer?.types.includes('Files'))return;
  event.preventDefault();
  const available=!$('#draft').disabled;
  event.dataTransfer.dropEffect=available?'copy':'none';
  if(available)$('#composer').classList.add('dropping');
});
chatSurface.addEventListener('dragleave',event=>{
  if(!chatSurface.contains(event.relatedTarget))$('#composer').classList.remove('dropping');
});
chatSurface.addEventListener('drop',event=>{
  $('#composer').classList.remove('dropping');
  if(!event.dataTransfer?.types.includes('Files'))return;
  event.preventDefault();
  const files=transferredImages(event.dataTransfer);
  if(files.length){
    addAttachments(files);
    $('#draft').focus({preventScroll:true});
  }
});
$('#composer').addEventListener('submit',event=>{
  event.preventDefault();
  const term=active(), value=$('#draft').value, text=value.trim();
  const selectedFiles=filesFor(term).map(file=>file.id);
  if(!sendable(term,snapshot.connection)||(!text&&!selectedFiles.length)||$('#send').disabled)return;
  const id='m'+crypto.randomUUID().replaceAll('-','');
  const conversationId=currentRoom()?'room:'+currentRoom().id:directConversationId(term);
  const record={id,conversationId,teamRoom:currentRoom()?.id,target:sessionKey(term),address:term.address,session:term.session,label:term.label,role:legacyDraftKey(term),text,draft:value,images:selectedFiles.length,at:Date.now(),state:'sending'};
  deliveries.push(record);
  save(deliveriesKey,chatImageHistory(deliveries.slice(-200)));
  if(currentRoom())feedScroll.toBottom(); else chatScroll.toBottom();   // sending always brings the newest message into view
  updateComposer();
  post({type:'send',id,conversationId,address:term.address,session:term.session,text,attachments:selectedFiles});
});
$('.top').addEventListener('click',event=>{
  const view=event.target.closest('[data-view]')?.dataset.view;
  if(!view)return;
  if(view!==page){directoryOpen=false;resetDrawer();}
  $('.settings').open=false;
  page=view;
  if(view==='conversations'&&roomID){
    openRoom(roomID);
    return;
  }
  render();
});
for(const selector of ['#taskList','#workList']){
  $(selector).addEventListener('click',event=>{
    const id=event.target.closest('[data-event]')?.dataset.event;
    if(!id)return;
    eventId=id;
    structure();
    transfers();
    motion(selectedWork()?.steps.at(-1)?.id);
    [...$(selector).querySelectorAll('button')].find(button=>button.dataset.event===id)?.focus({preventScroll:true});
  });
}
function openDirectChat(term){
  resetDrawer();
  memberTeam=chatTeamsBySession.get(sessionKey(term))?.id||term?.teamID||roomID||memberTeam;
  roomID=null;
  selectedTab='chat';
  choose(term);
}
function changeChatPreference(key,changes){
  const next={...chatPreferences.get(key),...changes};
  for(const field of Object.keys(next))if(!next[field])delete next[field];
  if(Object.keys(next).length)chatPreferences.set(key,next);
  else chatPreferences.delete(key);
  save(chatPreferencesKey,Object.fromEntries(chatPreferences));
}

function toggleChatPin(key){
  const added=!pinnedChats.delete(key);
  if(added)pinnedChats.add(key);
  save(pinKey,[...pinnedChats]);
  renderRooms();
  if(added)$('#pinnedChats').scrollTop=0;
}

function closeChatContext(restore=false){
  const key=contextChat;
  contextChat=null;
  $('#chatContextMenu').hidden=true;
  if(restore){
    [...$('#roomNav').querySelectorAll('[data-conversation]')].find(row=>row.dataset.conversation===key)
      ?.querySelector('button')?.focus({preventScroll:true});
  }
}

function renderCharacterPicker() {
  if(!characterDraft)return;
  const {style,coat,accessory,key}=characterDraft;
  const term=inventory.find(member=>characterID(member)===key);
  const provider=portraitProvider(term)||'neutral';
  const name=id=>copy('sheep.'+id);
  const pickerButton=(kind,id,label,art,selected)=>'<button type="button" aria-pressed="'+selected
    +'" data-'+kind+'="'+id+'" aria-label="'+escape(label)+'" title="'+escape(label)+'">'+art+'</button>';
  $('#characterSelection').textContent=[name(style),name(coat),accessory!=='none'?copy('accessory.'+accessory):''].filter(Boolean).join(' · ');
  $('#characterGrid').setAttribute('aria-label',copy('characterShapes'));
  $('#characterCoats').setAttribute('aria-label',copy('characterCoats'));
  setPanel('#characterHero',portraitArtwork(provider,false,style,coat,true,accessory));
  setPanel('#characterGrid',sheepStyles.map(id=>pickerButton('sheep-style',id,name(id),
    portraitArtwork(provider,false,id,coat,true,accessory)+'<span>'+escape(name(id))+'</span>',id===style)).join(''));
  setPanel('#characterCoats',[...sheepCoats].map(([id,color])=>pickerButton('sheep-coat',id,name(id),
    '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="11" fill="'+color+'"/></svg>',id===coat)).join(''));
  setPanel('#characterAccessories',sheepAccessories.map(id=>pickerButton('sheep-accessory',id,copy('accessory.'+id),
    portraitArtwork(provider,false,style,coat,true,id)+'<span>'+escape(copy('accessory.'+id))+'</span>',id===accessory)).join(''));
}

function openCharacterPicker(term, opener) {
  if(!canCustomize(term))return;
  const key=characterID(term);
  const base=baseLook(term), character=characters.get(key)||base;
  characterDraft={key,base,style:resolveSheepStyle(character.style),coat:sheepCoats.has(character.coat)?character.coat:base.coat,accessory:resolveSheepAccessory(character.accessory),opener};
  $('#characterOwner').textContent=term.label;
  renderCharacterPicker();
  $('#characterDialog').showModal();
  $('#characterGrid [aria-pressed=true]').focus({preventScroll:true});
}

$('#characterEdit').addEventListener('click',event=>openCharacterPicker(active(),event.currentTarget));
$('#characterClose').addEventListener('click',()=>$('#characterDialog').close());
$('#characterDialog').addEventListener('close',event=>{
  if(event.currentTarget.open)return;
  const opener=characterDraft?.opener;
  characterDraft=null;
  if(opener?.isConnected)opener.focus({preventScroll:true});
});
$('#characterReset').addEventListener('click',()=>{
  Object.assign(characterDraft,characterDraft.base);
  renderCharacterPicker();
});
$('#characterSave').addEventListener('click',()=>{
  const {key,style,coat,accessory,base}=characterDraft;
  const previous=characters.get(key)||base;
  if(style!==resolveSheepStyle(previous.style)||coat!==previous.coat||accessory!==resolveSheepAccessory(previous.accessory)){
    characters.delete(key);
    if(style!==base.style||coat!==base.coat||accessory!==base.accessory){
      characters.set(key,{style,coat,accessory});
    }
  }
  save(characterKey,Object.fromEntries(characters));
  $('#characterDialog').close();
  render();
});
$('#characterDialog').addEventListener('click',event=>{
  const button=event.target.closest('button');
  if(!button||!characterDraft)return;
  const options={style:'data-sheep-style',coat:'data-sheep-coat',accessory:'data-sheep-accessory'};
  const kind=Object.keys(options).find(key=>button.hasAttribute(options[key]));
  if(!kind)return;
  const attribute=options[kind];
  const value=button.getAttribute(attribute);
  characterDraft[kind]=value;
  renderCharacterPicker();
  $('#characterDialog ['+attribute+'="'+value+'"]').focus({preventScroll:true});
});

function openChatContext(key,x,y){
  const row=sidebarRows.get(key);
  if(!row)return;
  contextChat=key;
  const prefs=chatPreferences.get(key)||{};
  const direct=inventory.find(term=>sessionKey(term)===row.direct);
  const sections=[...new Set([...chatSections.order,...[...chatPreferences.values()].map(item=>item.section).filter(Boolean)])];
  const item=(action,label,icon,section='')=>'<button type="button" role="menuitem" data-menu-action="'+action+'"'
    +(section?' data-section="'+escape(section)+'"':'')+'><span aria-hidden="true">'+icon+'</span>'+escape(label)+'</button>';
  const menu=$('#chatContextMenu');
  menu.innerHTML=
    item('pin',copy(pinnedChats.has(key)?'unpinChat':'pinChat'),'⌖')
    +(canCustomize(direct)?item('character',copy('characterEdit'),'✎'):'')
    +item('newSection',copy('newChatSection'),'⊞')
    +sections.filter(name=>name!==prefs.section).map(name=>item('section',name,'↳',name)).join('')
    +(prefs.section?item('section',copy('unassignedChats'),'↳'):'')
    +item('unread',copy(prefs.unread||row.unread?'markRead':'markUnread'),'◉')
    +(snoozes[key]?item('unsnooze',copy('unsnooze'),'↺'):item('snoozeHour',copy('snoozeHour'),'◔')+item('snoozeMorning',copy('snoozeMorning'),'☾'))
    +item('copy',copy('copyChatID'),'▣')
    +item('hide',copy(chatHidden(row,prefs)?'restoreChat':'hideChat'),chatHidden(row,prefs)?'◈':'◇');
  menu.setAttribute('aria-label',row.title);
  menu.hidden=false;
  menu.style.left=Math.max(6,Math.min(x,innerWidth-menu.offsetWidth-6))+'px';
  menu.style.top=Math.max(6,Math.min(y,innerHeight-menu.offsetHeight-6))+'px';
  menu.firstElementChild.focus({preventScroll:true});
}

const roomNav=$('#roomNav'), pinDropHint=$('#pinDropHint');
const pinTarget=target=>target.closest('#pinnedChats,#pinDropHint');
const roomList=$('#roomList');
let insertionTile=null;
function listDrop(event){
  const row=event.target.closest('#roomList [data-conversation]:not(.hidden-conversation)');
  if(row){
    const key=row.dataset.conversation, section=chatPreferences.get(key)?.section||'';
    const keys=sidebarGroups.get(section)||[], rect=row.getBoundingClientRect();
    const after=event.clientY>rect.top+rect.height/2;
    return {el:row,mark:after?'after':'before',section,keys,beforeKey:after?nextKey(keys,key,draggedChat):key};
  }
  const head=event.target.closest('#roomList [data-section-head]');
  if(head){
    const section=head.dataset.sectionHead, keys=sidebarGroups.get(section)||[];
    return {el:head,mark:'into',section,keys,beforeKey:keys[0]??null};
  }
  return null;
}
function markList(el,mark){
  if(listMarker!==el)listMarker?.removeAttribute('data-insert');
  listMarker=el;
  el?.setAttribute('data-insert',mark);
}
function clearPinPreview(){
  insertionTile?.removeAttribute('data-insert');
  insertionTile=null;
  markList(null);
  roomNav.removeAttribute('data-pin-drop');
  roomList.removeAttribute('data-unpin-hint');
}
function pinInsertion(event){
  const tile=event.target.closest('#pinnedChats [data-conversation]');
  if(!tile)return {tile:null,after:false};
  const rect=tile.getBoundingClientRect();
  return {tile,after:event.clientX>rect.left+rect.width/2+1};
}
function finishChatDrag(){
  if(!draggedChat&&draggedSection===null)return;
  draggedChat=null;
  draggedSection=null;
  pinDropHint.hidden=true;
  clearPinPreview();
  for(const preview of document.querySelectorAll('.pin-drag-preview'))preview.remove();
  renderRooms();
}
// WebKit can skip dragend (a drag cancelled outside the window). The sidebar does not redraw during a drag, so a lost
// dragend froze it: the next click opened a conversation while the old one stayed highlighted. A pointer press can only
// come after a drag has ended, so it closes any drag still marked open.
// The stale state is cleared at once, but the redraw waits until the press is over so the row being clicked is not replaced
// under the pointer (the click itself redraws when it opens a conversation).
document.addEventListener('pointerdown',()=>{
  if(!draggedChat&&draggedSection===null)return;
  draggedChat=null;draggedSection=null;
  pinDropHint.hidden=true;
  clearPinPreview();
  for(const preview of document.querySelectorAll('.pin-drag-preview'))preview.remove();
  document.addEventListener('pointerup',()=>setTimeout(renderRooms,0),{once:true,capture:true});
},true);
roomNav.addEventListener('dragstart',event=>{
  const head=event.target.closest('[data-section-head][draggable=true]');
  if(head&&event.dataTransfer){
    draggedSection=head.dataset.sectionHead;
    event.dataTransfer.effectAllowed='move';
    event.dataTransfer.setData('text/plain',draggedSection);
    return;
  }
  const row=event.target.closest('[data-conversation][draggable=true]');
  if(!row||!event.dataTransfer)return;
  draggedChat=row.dataset.conversation;
  event.dataTransfer.effectAllowed='move';
  event.dataTransfer.setData(chatDragType,draggedChat);
  const item=sidebarRows.get(draggedChat);
  if(item){
    const preview=document.createElement('div');
    preview.className='pin-drag-preview';
    preview.setAttribute('aria-hidden','true');
    preview.innerHTML=conversationItem(item,true);
    document.body.appendChild(preview);
    const side=preview.getBoundingClientRect().width;
    event.dataTransfer.setDragImage(preview,side/2,side/2);
    requestAnimationFrame(()=>preview.remove());
  }
  pinDropHint.hidden=!$('#pinnedChats').hidden;
});
roomNav.addEventListener('dragover',event=>{
  if(draggedSection!==null){
    const head=event.target.closest('#roomList [data-section-head]');
    if(!head||head.dataset.sectionHead===draggedSection){markList(null);return;}
    event.preventDefault();
    const rect=head.getBoundingClientRect();
    markList(head,head.dataset.sectionHead&&event.clientY<rect.top+rect.height/2?'before':'after');
    return;
  }
  if(!draggedChat)return;
  const target=pinTarget(event.target);
  if(!target&&roomList.contains(event.target)){
    event.preventDefault();
    event.dataTransfer.dropEffect='move';
    insertionTile?.removeAttribute('data-insert');
    insertionTile=null;
    const spot=listDrop(event);
    markList(spot&&spot.el.dataset.conversation!==draggedChat?spot.el:null,spot?.mark);
    if(pinnedChats.has(draggedChat)){
      roomNav.dataset.pinDrop='remove';
      roomList.dataset.unpinHint=copy('dropToUnpin');
    }else roomNav.removeAttribute('data-pin-drop');
    return;
  }
  if(!target){clearPinPreview();return;}
  event.preventDefault();
  event.dataTransfer.dropEffect='move';
  markList(null);
  roomList.removeAttribute('data-unpin-hint');
  const {tile,after}=pinInsertion(event);
  if(tile!==insertionTile)insertionTile?.removeAttribute('data-insert');
  insertionTile=tile;
  roomNav.dataset.pinDrop=tile?'reorder':'pin';
  if(tile&&tile.dataset.conversation!==draggedChat)tile.dataset.insert=after?'after':'before';
});
roomNav.addEventListener('dragleave',event=>{
  if(!(event.relatedTarget instanceof Node)||!roomNav.contains(event.relatedTarget))clearPinPreview();
});
roomNav.addEventListener('drop',event=>{
  if(draggedSection!==null){
    const head=event.target.closest('#roomList [data-section-head]');
    if(head&&head.dataset.sectionHead!==draggedSection){
      event.preventDefault();
      const names=[...sidebarGroups.keys()].filter(Boolean), target=head.dataset.sectionHead;
      const rect=head.getBoundingClientRect(), before=target&&event.clientY<rect.top+rect.height/2;
      const beforeName=!target?null:before?target:nextKey(names,target,draggedSection);
      saveSections(moveSection({order:names,collapsed:chatSections.collapsed},draggedSection,beforeName===draggedSection?null:beforeName));
    }
    finishChatDrag();
    return;
  }
  if(!draggedChat)return;
  const key=draggedChat;
  if(!pinTarget(event.target)){
    if(roomList.contains(event.target)){
      event.preventDefault();
      if(pinnedChats.delete(key))save(pinKey,[...pinnedChats]);
      const spot=listDrop(event);
      if(spot&&!(spot.el.dataset.conversation===key))
        replacePreferences(moveChat(chatPreferences,key,spot.section,spot.keys,spot.beforeKey===key?null:spot.beforeKey));
    }
    finishChatDrag();
    return;
  }
  event.preventDefault();
  const {tile,after}=pinInsertion(event);
  const target=tile?.dataset.conversation;
  if(target!==key){
    const visible=[...$('#pinnedChats').querySelectorAll('[data-conversation]')];
    const ordered=[...pinnedChats].reverse().filter(pin=>pin!==key);
    const anchor=target||visible.at(-1)?.dataset.conversation;
    const at=ordered.indexOf(anchor);
    ordered.splice(at<0?0:at+Number(after||!target),0,key);
    pinnedChats.clear();
    for(const pin of ordered.reverse())pinnedChats.add(pin);
    save(pinKey,[...pinnedChats]);
  }
  finishChatDrag();
});
roomNav.addEventListener('dragend',finishChatDrag);

$('#roomNav').addEventListener('contextmenu',event=>{
  const head=event.target.closest('[data-section-head]');
  if(head&&head.dataset.sectionHead){
    event.preventDefault();
    contextChat=null;contextSection=head.dataset.sectionHead;
    const menu=$('#chatContextMenu');
    const item=(action,label,icon)=>'<button type="button" role="menuitem" data-menu-action="'+action+'"><span aria-hidden="true">'+icon+'</span>'+escape(label)+'</button>';
    menu.innerHTML=item('renameSection',copy('renameSection'),'✎')+item('deleteSection',copy('deleteSection'),'⊖');
    menu.setAttribute('aria-label',contextSection);
    menu.hidden=false;
    menu.style.left=Math.max(6,Math.min(event.clientX,innerWidth-menu.offsetWidth-6))+'px';
    menu.style.top=Math.max(6,Math.min(event.clientY,innerHeight-menu.offsetHeight-6))+'px';
    menu.firstElementChild.focus({preventScroll:true});
    return;
  }
  const row=event.target.closest('[data-conversation]');
  if(!row)return;
  event.preventDefault();
  openChatContext(row.dataset.conversation,event.clientX,event.clientY);
});
$('#roomNav').addEventListener('keydown',event=>{
  if(event.key!=='ContextMenu'&&!(event.shiftKey&&event.key==='F10'))return;
  const row=event.target.closest('[data-conversation]');
  if(!row)return;
  event.preventDefault();
  const rect=row.getBoundingClientRect();
  openChatContext(row.dataset.conversation,rect.left+16,rect.bottom);
});
$('#roomNav').addEventListener('click',event=>{
  const row=event.target.closest('[data-conversation]');
  if(row&&chatPreferences.get(row.dataset.conversation)?.unread)changeChatPreference(row.dataset.conversation,{unread:false});
  const room=event.target.closest('[data-room]')?.dataset.room;
  if(room){openRoom(room);return;}
  const key=event.target.closest('[data-direct]')?.dataset.direct;
  if(key)openDirectChat(inventory.find(term=>sessionKey(term)===key));
});

$('#chatContextMenu').addEventListener('keydown',event=>{
  const buttons=[...event.currentTarget.querySelectorAll('button')], index=buttons.indexOf(document.activeElement);
  if(event.key==='Escape'||event.key==='Tab'){event.preventDefault();closeChatContext(true);return;}
  if(event.key==='ArrowDown'||event.key==='ArrowUp'){
    event.preventDefault();
    buttons[(index+(event.key==='ArrowDown'?1:buttons.length-1))%buttons.length]?.focus();
  }
});
document.addEventListener('pointerdown',event=>{
  if(contextChat&&!event.target.closest('#chatContextMenu'))closeChatContext();
});
window.addEventListener('resize',()=>{closeChatContext();alignRailBranches($('#handoffRail'));});
$('#chatContextMenu').addEventListener('click',event=>{
  const item=event.target.closest('[data-menu-action]'), key=contextChat;
  if(item&&contextSection!==null&&['renameSection','deleteSection'].includes(item.dataset.menuAction)){
    const name=contextSection;
    closeChatContext(true);
    contextSection=null;
    if(item.dataset.menuAction==='deleteSection'){
      const [prefs,sections]=deleteSection(chatPreferences,chatSections,name);
      replacePreferences(prefs);saveSections(sections);renderRooms();
    }else openSectionDialog('rename',name);
    return;
  }
  const row=sidebarRows.get(key);
  if(!item||!row)return;
  closeChatContext(true);
  const action=item.dataset.menuAction, prefs=chatPreferences.get(key)||{};
  if(action==='pin'){toggleChatPin(key);return;}
  if(action==='character'){
    openCharacterPicker(inventory.find(term=>sessionKey(term)===row.direct),document.activeElement);
    return;
  }
  if(action==='newSection'){
    sectionChat=key;
    openSectionDialog('move');
    return;
  }
  if(action==='section')changeChatPreference(key,{section:item.dataset.section});
  if(action==='hide')changeChatPreference(key,{hidden:!chatHidden(row,prefs)});
  if(action==='unread'){
    const read=prefs.unread||row.unread;
    if(row.room&&row.unread)roomUnread.delete(row.room);
    if(read){seenAt={...seenAt,[key]:Math.max(Date.now(),row.lastAgentAt||0)};save(seenKey,seenAt);}
    changeChatPreference(key,{unread:!read});
  }
  if(action==='copy'){post({type:'copyChatID',value:key});return;}
  if(action==='snoozeHour'||action==='snoozeMorning'){snoozes[key]={until:snoozeUntil(action==='snoozeHour'?'hour':'morning',Date.now()),at:Math.max(Date.now(),row.lastAgentAt||0)};save(snoozeKey,snoozes);}
  if(action==='unsnooze'){delete snoozes[key];save(snoozeKey,snoozes);}
  renderRooms();
});
$('#roomList').addEventListener('click',event=>{
  if(!event.target.closest('[data-snoozed-toggle]'))return;
  showSnoozed=!showSnoozed;
  renderRooms();
});
$('#urgentJump').addEventListener('click',openNextUrgent);

// Command palette (Cmd+K): conversations, computers and a few actions, filtered as you type.
let paletteItems=[], paletteShown=[], paletteSelected=0;
function buildPaletteItems(){
  const items=[];
  // always offered: the jump refreshes its own queue, so a cached count here could only be stale
  items.push({id:'action:next',kind:'action',label:copy('nextUrgent'),detail:'⌘J'});
  const current=active();
  if(current?.address&&current.state==='live')items.push({id:'action:terminal',kind:'action',label:copy('actionTerminal').replace('{name}',current.label||current.address),detail:''});
  items.push({id:'action:settings',kind:'action',label:copy('actionSettings'),detail:''});
  // read straight from the current data (not the sidebar's last render), so any page searches what exists now
  for(const room of rooms())items.push({id:'room:'+room.id,kind:'chat',label:room.title,detail:copy('paletteTeam')});
  for(const term of inventory.filter(term=>term.program?.agent&&term.state==='live')){
    const team=chatTeamsBySession.get(sessionKey(term))?.title;
    items.push({id:'direct:'+sessionKey(term),kind:'chat',label:term.label||term.address,detail:[team,memberStatus(term)].filter(Boolean).join(' · ')});
  }
  for(const machine of computerRows(snapshot.tasks?.machines||[],snapshot.machines||[],inventory,workingNow).filter(row=>row.editable))
    items.push({id:'computer:'+machine.name,kind:'computer',label:machine.label||machine.name,detail:machine.name});
  return items;
}
function renderPalette(){
  paletteShown=filterPalette(paletteItems,$('#paletteInput').value);
  paletteSelected=Math.min(paletteSelected,Math.max(0,paletteShown.length-1));
  $('#paletteList').innerHTML=paletteHTML(paletteShown,paletteSelected,copy,escape);
  if(paletteShown.length)$('#paletteInput').setAttribute('aria-activedescendant','palette-option-'+paletteSelected);
  else $('#paletteInput').removeAttribute('aria-activedescendant');
  $('#paletteEmpty').hidden=paletteShown.length>0;
  $('#paletteList').querySelector('[aria-selected="true"]')?.scrollIntoView({block:'nearest'});
}
function openPalette(){
  const dialog=$('#paletteDialog');
  if(document.querySelector('dialog[open]'))return;   // never over another dialog (its choices would land underneath)
  paletteItems=buildPaletteItems();paletteSelected=0;
  $('#paletteInput').value='';$('#paletteInput').placeholder=copy('palettePlaceholder');
  $('#paletteEmpty').textContent=copy('paletteEmpty');dialog.setAttribute('aria-label',copy('palettePlaceholder'));
  renderPalette();dialog.showModal();$('#paletteInput').focus();
}
function runPalette(id){
  $('#paletteDialog').close();
  if(!id)return;
  if(id==='action:next'){openNextUrgent();return;}
  if(id==='action:terminal'){const term=active();if(term){page='conversations';render();openTerminalDrawer(term);}return;}
  if(id==='action:settings'){$('.settings').open=true;$('.settings summary').focus();return;}
  if(id.startsWith('computer:')){
    computerOpen=id.slice('computer:'.length);computerMessage('');renderComputerSheet(true);$('#computerDialog').showModal();return;
  }
  page='conversations';
  // like a sidebar click, opening a conversation clears its manual unread mark
  for(const row of sidebarRows.values())
    if((row.room&&'room:'+row.room===id||row.direct&&'direct:'+row.direct===id)&&chatPreferences.get(row.key)?.unread)changeChatPreference(row.key,{unread:false});
  if(id.startsWith('room:')){openRoom(id.slice('room:'.length));return;}
  const term=inventory.find(item=>sessionKey(item)===id.slice('direct:'.length));
  // a lead's chat is folded into its room in the sidebar: reading it clears the room's manual unread mark too
  const ledRoom=term&&rooms().find(room=>roomLead(room)&&sessionKey(roomLead(room))===sessionKey(term));
  if(ledRoom&&chatPreferences.get('room:'+ledRoom.id)?.unread)changeChatPreference('room:'+ledRoom.id,{unread:false});
  if(term){openDirectChat(term);render();}
}
$('#paletteInput').addEventListener('input',()=>{paletteSelected=0;renderPalette();});
// Enter runs the highlighted item (one press in Korean; never on a Japanese conversion confirm)
enterSends($('#paletteInput'),target=>target.id==='paletteInput'?target:null,()=>runPalette(paletteShown[paletteSelected]?.id));
$('#paletteInput').addEventListener('keydown',event=>{
  if(event.isComposing||event.keyCode===229||event.key==='Enter')return;
  if(event.key==='ArrowDown'||event.key==='ArrowUp'){
    event.preventDefault();
    const n=paletteShown.length;if(!n)return;
    paletteSelected=(paletteSelected+(event.key==='ArrowDown'?1:n-1))%n;renderPalette();
  }
});
$('#paletteList').addEventListener('click',event=>runPalette(event.target.closest('[data-palette]')?.dataset.palette));
$('#paletteDialog').addEventListener('click',event=>{if(event.target===event.currentTarget)$('#paletteDialog').close();});
// Escape closes only the palette (the dialog's own cancel), never the panel underneath
$('#paletteDialog').addEventListener('keydown',event=>{if(event.key==='Escape')event.stopPropagation();});
document.addEventListener('keydown',event=>{
  if(event.isComposing||event.keyCode===229)return;   // Ctrl/Cmd+J may belong to an input method while composing
  if(event.metaKey&&!event.ctrlKey&&!event.shiftKey&&!event.altKey&&event.key.toLowerCase()==='j'){event.preventDefault();openNextUrgent();}
  if(event.metaKey&&!event.ctrlKey&&!event.shiftKey&&!event.altKey&&event.key.toLowerCase()==='k'){event.preventDefault();openPalette();}
});
$('#hiddenChatsToggle').addEventListener('click',()=>{
  showHiddenChats=!showHiddenChats;
  $('.settings').open=false;
  renderRooms();
  if(showHiddenChats){
    const firstHidden=$('#roomList .hidden-conversation .room-row');
    firstHidden?.scrollIntoView({block:'nearest'});
    firstHidden?.focus({preventScroll:true});
  }
});
$('#chatSectionCancel').addEventListener('click',()=>$('#chatSectionDialog').close());
$('#chatSectionDialog').addEventListener('close',()=>{sectionChat=null;sectionMode='move';contextSection=null;});
function openSectionDialog(mode,name=''){
  sectionMode=mode;
  if(mode==='rename')contextSection=name;
  $('#chatSectionForm').reset();
  $('#chatSectionTitle').textContent=copy(mode==='rename'?'renameSection':mode==='create'?'addSection':'newChatSection');
  $('#chatSectionName').value=name;
  $('#chatSectionDialog').showModal();
  $('#chatSectionName').focus();
}
$('#chatSectionForm').addEventListener('submit',event=>{
  event.preventDefault();
  const section=$('#chatSectionName').value.trim();
  if(!section)return;
  if(sectionMode==='create')saveSections(addSection(chatSections,section));
  else if(sectionMode==='rename'&&contextSection){
    const [prefs,sections]=renameSection(chatPreferences,chatSections,contextSection,section);
    replacePreferences(prefs);saveSections(sections);
  }else if(sectionChat){
    saveSections(addSection(chatSections,section));
    changeChatPreference(sectionChat,{section});
  }else return;
  $('#chatSectionDialog').close();
  renderRooms();
});
$('#roomList').addEventListener('click',event=>{
  const toggle=event.target.closest('[data-section-toggle]');
  if(toggle){saveSections(toggleSection(chatSections,toggle.dataset.sectionToggle));renderRooms();return;}
  if(event.target.closest('[data-add-section]'))openSectionDialog('create');
});
$('#roomMembersToggle').addEventListener('click',()=>{
  const open=!membersOpen;
  resetDrawer();
  membersOpen=open;
  detail();
});
$('#taskBoard').addEventListener('click',event=>{
  if(event.target.closest('.board-toggle')){
    boardOpen=!boardOpen;
    save('ui.boardOpen.v1',boardOpen);
    showBoardOpen();
    return;
  }
  const address=event.target.closest('[data-board-owner]')?.dataset.boardOwner;
  const term=address&&boardOwnerTerm(address);
  if(term)openDirectChat(term);
});
$('#groupMembers').addEventListener('click',event=>{
  if(event.target.closest('.roster-close')){
    membersOpen=false;
    renderGroupMembers(currentRoom());
    $('#roomMembersToggle').focus();
    return;
  }
  const key=event.target.closest('[data-group-member]')?.dataset.groupMember;
  if(key)openDirectChat(inventory.find(term=>sessionKey(term)===key));
});
$('#directoryPanel').addEventListener('click',event=>{
  const key=event.target.closest('[data-directory-term]')?.dataset.directoryTerm;
  const term=inventory.find(item=>sessionKey(item)===key);
  if(!term)return;
  directoryOpen=true;
  $('.side').hidden=false;
  selectedTab='chat';
  choose(term);
});
function closeDirectory() {
  if(page!=='structure'||!directoryOpen)return;
  directoryOpen=false;
  $('.side').hidden=true;
  selectedTab='chat';
  detail();
  renderDirectory();
  [...$('#directoryPanel').querySelectorAll('[data-directory-term]')].find(row=>row.dataset.directoryTerm===sessionKey(chosen))?.focus({preventScroll:true});
}
$('#directoryClose').addEventListener('click',closeDirectory);
document.addEventListener('keydown',event=>{if(event.key==='Escape')closeDirectory();});
$('#roomBack').addEventListener('click',()=>{if(memberTeam)openRoom(memberTeam);});


function revealQuestions() {
  if(page==='structure'){
    directoryOpen=true;
    $('.side').hidden=false;
  }
  if(selectedTab==='questions')selectedTab=currentRoom()?'team':'chat';
  detail();
  $('#inlineApproval').querySelector('textarea,button:not(:disabled)')?.focus();
}
$('#inlineHandoff').addEventListener('click',()=>{
  selectedTab='team';
  renderRooms();
  detail();
});
function resetDrawer(){
  terminalOpen=false;
  approvalTarget=null;
  pendingApproval=null;
  terminalView.stop();
}
function openTerminalDrawer(target=null){
  membersOpen=false;
  terminalOpen=true;
  approvalTarget=target;
  detail();
}
function closeTerminalDrawer(){
  resetDrawer();
  if(selectedTab==='terminal')selectedTab=currentRoom()?'team':'chat';
  detail();
  $('#terminalToggle').focus();
}
function checkApprovalTarget(id){
  if(arrivalID===id){arrivalID=null;$('#arrival').hidden=true;}
  pendingApproval=id;
  post({type:'approval',id});
}
$('#terminalToggle').addEventListener('click',()=>{ if(terminalOpen)closeTerminalDrawer();else openTerminalDrawer(); });
$('#terminalClose').addEventListener('click',closeTerminalDrawer);
$('#inlineApproval').addEventListener('click',event=>{
  const waiting=event.target.closest('[data-waiting-terminal]')?.dataset.waitingTerminal;
  if(waiting){
    const target=inventory.find(term=>sessionKey(term)===waiting);
    if(target)openTerminalDrawer(target);
    return;
  }
  const id=event.target.closest('[data-chat-question]')?.dataset.chatQuestion;
  const item=questions().find(q=>q.id===id);
  if(!item)return;
  if(item.approval?.address&&snapshot.connection==='live')checkApprovalTarget(item.id);
  else revealQuestions();
});
$('#alertCount').addEventListener('click',()=>{arrivalID=null;revealQuestions();});
$('#arrivalOpen').addEventListener('click',()=>{
  const item=questions().find(q=>q.id===arrivalID);
  arrivalID=null;
  $('#arrival').hidden=true;
  if(item?.approval?.address && snapshot.connection==='live')checkApprovalTarget(item.id);
  else revealQuestions();
});
$('#arrivalDismiss').addEventListener('click',()=>{arrivalID=null;$('#arrival').hidden=true;});
$('#lanes').addEventListener('click',event=>{
  const step=event.target.closest('[data-step]')?.dataset.step;
  if(step){motion(step);return;}
  const key=event.target.closest('[data-participant]')?.dataset.participant;
  const term=inventory.find(candidate=>sessionKey(candidate)===key);
  if(term)choose(term);
});
$('#transfers').addEventListener('click',event=>{
  const id=event.target.closest('[data-approve]')?.dataset.approve;
  if(id)checkApprovalTarget(id);
});
for(const panel of [$('#questions'),$('#inlineApproval')]){
panel.addEventListener('input',event=>{
  const form=event.target.closest('[data-question]');
  if(form&&event.target.matches('textarea'))questionDrafts.set(form.dataset.question,event.target.value);
});
panel.addEventListener('click',event=>{
  const target=event.target.closest('button'), form=target?.closest('[data-question]');
  if(!form)return;
  if(target.hasAttribute('data-choice')){
    const field=form.elements.answer;
    field.value=target.dataset.choice;
    questionDrafts.set(form.dataset.question,field.value);
    field.focus();
  }
  if(target.hasAttribute('data-approval'))checkApprovalTarget(form.dataset.question);
  if(target.hasAttribute('data-question-attach'))form.querySelector('[data-question-file]')?.click();
  const remove=target.dataset.questionRemove, asker=askerFor(form);
  if(remove&&asker)post({type:'detach',address:asker.address,session:asker.session,id:remove});
});
panel.addEventListener('change',event=>{
  if(!event.target.matches('[data-question-file]'))return;
  const asker=askerFor(event.target.closest('[data-question]'));
  const files=Array.from(event.target.files||[]).filter(isImageFile);
  if(asker&&files.length)addAttachments(files,asker).then(refreshQuestionFiles);
  event.target.value='';
});
panel.addEventListener('paste',event=>{
  const form=event.target.closest?.('[data-question]'), files=transferredImages(event.clipboardData);
  if(!form||!files.length)return;
  event.preventDefault();
  const asker=askerFor(form);
  if(asker)addAttachments(files,asker).then(refreshQuestionFiles);
});
// Enter sends the answer like the composer (Shift+Enter: new line; one Enter in Korean too).
enterSends(panel,target=>target.matches?.('[data-question] textarea')?target:null,field=>field.closest('form')?.requestSubmit());
panel.addEventListener('submit',event=>{
  event.preventDefault();
  const form=event.target,id=form.dataset.question;
  const asker=askerFor(form), key=asker?sessionKey(asker):'';
  const attachments=asker?filesFor(asker).map(file=>file.id):[];
  // an empty box with no images sends the asker's recommended answer, which the card shows
  const typed=form.elements.answer?.value.trim()||'', recommend=questions().find(q=>q.id===id)?.recommend||'';
  const text=typed||(attachments.length?'':recommend);
  if((!text&&!attachments.length)||questionSending.has(id)||(key&&pendingFiles(key)))return;
  questionSending.add(id);
  post({type:'answer',id,text,attachments});
  showQuestions();
  detail();
});
}
$('#replay').addEventListener('click',()=>motion());
document.addEventListener('visibilitychange',()=>{
  if(document.hidden)draftSaver.flush();
  document.documentElement.toggleAttribute('data-inactive',document.hidden);
  renderRooms();
  detail();
});
motionPreference.addEventListener('change',()=>{renderRooms();detail();});
window.addEventListener('pagehide',()=>{draftSaver.flush();terminalView.stop();});

// Computer settings sheet: edits machines.json through `herdr-task machine ...` (Swift checks every field).
let computerOpen=null,machineToken=0;
const machinePending=new Map();
function machineRequest(request,done){
  const token='m'+(++machineToken);
  machinePending.set(token,done);
  post({type:'machine',token,...request});
}
const computerRowFor=name=>computerRows(snapshot.tasks?.machines||[],snapshot.machines||[],inventory,workingNow).find(row=>row.name===name&&row.editable);
const computerMessage=text=>{$('#computerMessage').textContent=text||'';};
const machineFailure=result=>copy('computerFailed')+(result.error||'');
function renderComputerSheet(force=false){
  if(!computerOpen)return;
  const form=$('#computerCloneForm');
  if(!force&&(document.activeElement?.closest?.('#computerSheet')||form?.dataset.busy))return;
  const row=computerRowFor(computerOpen);
  if(!row){$('#computerDialog').close();return;}
  const kept=form?{team:$('#computerCloneTeam').value,url:$('#computerCloneUrl').value,path:$('#computerClonePath').value}:null;
  $('#computerSheet').innerHTML=computerSheetHTML(row,cloneTeams(snapshot.configuredTeams||[],inventory,row.projects,computerRowFor('local')?.repos),copy,escape);
  if(kept&&$('#computerCloneForm')&&[...$('#computerCloneTeam').options].some(option=>option.value===kept.team)){
    $('#computerCloneTeam').value=kept.team;$('#computerCloneUrl').value=kept.url;$('#computerClonePath').value=kept.path;
  }
}
$('#computerStrip').addEventListener('click',event=>{
  const button=event.target.closest('[data-computer]');
  if(!button)return;
  computerOpen=button.dataset.computer;
  computerMessage('');
  renderComputerSheet(true);
  $('#computerDialog').showModal();
});
$('#computerClose').addEventListener('click',()=>$('#computerDialog').close());
$('#computerDialog').addEventListener('close',()=>{computerOpen=null;});
function saveComputerSetting(change){
  machineRequest({action:'set',name:computerOpen,...change},result=>{
    computerMessage(result.ok?copy('computerSaved'):machineFailure(result));
    if(!result.ok)renderComputerSheet(true);
  });
}
$('#computerSheet').addEventListener('change',event=>{
  const field=event.target;
  if(field.id==='computerReady')saveComputerSetting({ready:field.checked?'on':'off'});
  else if(field.id==='computerTier')saveComputerSetting({tier:field.value});
  else if(field.id==='computerSlots'){
    const slots=slotsValue(field.value);
    if(slots===null)renderComputerSheet(true);   // emptied or invalid: show the saved value again, change nothing
    else saveComputerSetting({slots});
  }else if(field.id==='computerCloneTeam'){
    // the previous team's URL and folder must never be sent for this team: clear now, hold Receive until the lookup ends
    const form=$('#computerCloneForm'),team=field.value;
    $('#computerCloneUrl').value='';$('#computerClonePath').value='';
    if(!team){delete form.dataset.suggesting;$('#computerCloneSubmit').disabled=false;return;}
    form.dataset.suggesting=team;
    $('#computerCloneSubmit').disabled=true;
    machineRequest({action:'suggest',team},result=>{
      if(!form.isConnected||form.dataset.suggesting!==team)return;
      delete form.dataset.suggesting;
      $('#computerCloneSubmit').disabled=false;
      if(!result.ok){computerMessage(copy('computerSuggestFailed'));return;}
      $('#computerCloneUrl').value=result.result?.url||'';
      $('#computerClonePath').value=result.result?.path||'';
    });
  }
});
$('#computerSheet').addEventListener('submit',event=>{
  if(event.target.id!=='computerCloneForm')return;
  event.preventDefault();
  const form=event.target,name=computerOpen;
  const request=cloneRequest({name,team:$('#computerCloneTeam').value,url:$('#computerCloneUrl').value,path:$('#computerClonePath').value,suggesting:form.dataset.suggesting});
  if(!request)return;
  form.dataset.busy='1';
  $('#computerCloneSubmit').disabled=true;
  $('#computerCloneStatus').textContent=copy('computerCloning');
  computerMessage('');
  machineRequest(request,result=>{
    delete form.dataset.busy;
    if(result.ok){
      computerMessage(copy('computerSaved')+' · '+(result.result?.path||''));
      if(computerOpen===name)renderComputerSheet(true);
    }else if(form.isConnected){
      $('#computerCloneSubmit').disabled=false;
      $('#computerCloneStatus').textContent=machineFailure(result);
    }else computerMessage(machineFailure(result));
  });
});
$('#computerSheet').addEventListener('click',event=>{
  const button=event.target.closest('[data-unlink]');
  if(!button)return;
  button.disabled=true;
  machineRequest({action:'unlink',name:computerOpen,team:button.dataset.unlink},result=>{
    computerMessage(result.ok?copy('computerSaved'):machineFailure(result));
    if(!result.ok)button.disabled=false;
  });
});
$('#documentClose').addEventListener('click',()=>$('#documentDialog').close());
function showDocument(doc){
  const dialog=$('#documentDialog');
  $('#documentTitle').textContent=doc?.name||'';
  $('#documentPath').textContent=doc?.path||'';
  $('#documentBody').innerHTML=markdownDocumentHTML(doc?.text||'',renderChatInline,escape,String(doc?.path||'').replace(/\/[^/]*$/,''));
  $('#documentBody').scrollTop=0;
  if(!dialog.open)dialog.showModal();
}
window.desk={
  showDocument,
  openCompanionTarget(){
    const target=companionTarget&&inventory.find(term=>term.address===companionTarget.address&&term.session===companionTarget.session);
    if(!target)return;
    page='conversations';
    const room=rooms().find(item=>roomLead(item)?.address===target.address);
    if(room)openRoom(room.id); else{openDirectChat(target);render();}
  },
  companionOff(){
    companionSettings.enabled=false;
    save('ui.companion.v1',false);
    $('#companionEnabled').checked=false;
    pushCompanion();
  },
  machineResult(payload){
    const done=machinePending.get(payload?.token);
    machinePending.delete(payload?.token);
    done?.(payload);
  },
  update(payload){
    if(!('handoffs' in payload)&&snapshot?.handoffs)payload.handoffs=snapshot.handoffs;   // sent only when it changes
    if(!('tasks' in payload)&&snapshot?.tasks)payload.tasks=snapshot.tasks;
    // large parts are sent only when they change; keep the previous ones (the same objects, so derived results are reused)
    for(const key of ['replies','teamMessages','liveMessages','liveTurns','lineage','configuredTeams','spaces','systemSounds','archiveRoles','machines','ledger'])
      if(!(key in payload)&&snapshot&&key in snapshot)payload[key]=snapshot[key];
    snapshot=payload;
    $('#automaticChat').checked=payload.automaticChat!==false;
    if(!localeChosen&&!systemLocaleApplied&&payload.preferredLocale){
      systemLocaleApplied=true;
      language=languageFrom(payload.preferredLocale);
      post({type:'language',value:language});
    }
    inventory=makeInventory(payload.terms,payload.spaces,payload.configuredTeams);
    const known=archiveRoles(inventory,legacyMessages,legacyDrafts,[...(payload.replies||[]),...(payload.archiveRoles||[]).map(role=>({role}))]);
    const titles=new Map((payload.configuredTeams||[]).flatMap(team=>team.roles.map(([role,label])=>[role,team.title+' · '+label])));
    inventory.push(...known.map(role=>({address:'archive:'+role,session:'archive',label:titles.get(role)||role,team:copy('archived'),machine:'',
      labels:{'recovery.role':role},state:'archived',status:'unknown',program:{agent:false}})));
    characterRoles.clear();
    for(const term of inventory){
      const role=legacyDraftKey(term);
      if(role)characterRoles.set(role,(characterRoles.get(role)||0)+1);
    }
    chatDirectory=makeTeamDirectory(inventory,assignedTeams());
    chatTeamsBySession=new Map(chatDirectory.flatMap(group=>flattenChatNodes(group.roots)
      .filter(node=>node.term).map(node=>[sessionKey(node.term),group])));
    flowEntries=explicitHandoffs(inventory);
    const nextSoundStates=new Map();
    let didComplete=false;
    if(payload.connection==='live'){
      for(const term of inventory){
        if(term.state!=='live'||!term.program?.agent||!term.session)continue;
        const key=sessionKey(term), before=soundStates.get(key);
        const wasWorking=term.status==='working'||(term.status==='blocked'&&before?.wasWorking);
        nextSoundStates.set(key,{status:term.status,wasWorking,turn:term.turn,statusMs:term.statusMs});
        if(completedAgentTurn(before,term)){didComplete=true;companionFinished=key;}
      }
    }
    soundStates=nextSoundStates;
    if(didComplete){playSystem('done');companionFlash={kind:'done',at:Date.now()};}
    recordHandoffs();
    fillSoundPicks(payload.systemSounds||[]);
    const handoffs=newHandoffs(payload.handoffs?.cards||[],handoffSeen);
    handoffSeen=handoffs.seen;
    if(handoffs.fresh){playSystem('handoff');companionFlash={kind:'handoff',at:Date.now()};}
    checkAttention();
    if(!roomStarted && payload.connection==='live' && (inventory.length||assignedTeams().length)){
      roomStarted=true;
      const all=rooms();
      const firstRoom=all.find(room=>room.id===primaryTeams()[0] && roomLead(room))||all.find(roomLead)||all[0];
      if(firstRoom&&page==='conversations'){
        roomID=firstRoom.id; memberTeam=roomID; selectedTab='team';
      }
    }
    if(currentRoom()){
      const lead=roomLeadHistory(currentRoom());
      if(!chosen || !lead || sessionKey(lead)!==sessionKey(chosen))
        chosen=lead?{address:lead.address,session:lead.session}:null;
    }
    if(characterDraft)renderCharacterPicker();
    if(!chosen&&inventory.length&&!currentRoom()){
      const first=inventory.find(term=>term.program?.agent && term.teamID===primaryTeams()[0] && term.isLead)
        || inventory.find(term=>term.program?.agent) || inventory[0];
      chosen={address:first.address,session:first.session};
    }
    roomSignals();
    scanActivity();
    render();
    pushCompanion();
    playActivity();
  },
  chatImages(payload){imagePreviews.receive(payload);},
  sendResult(id,state,previews=[]){
    const item=deliveries.find(entry=>entry.id===id);
    if(!item||item.state!=='sending')return;
    item.state=state;
    if(state==='sent')item.previews=previews;
    legacyMessages=appendLegacySend(legacyMessages,item,item.role||'session:'+item.target);
    if(!save('ownMessages.v1',Object.fromEntries(Object.entries(legacyMessages).map(([role,rows])=>[role,chatImageHistory(rows)]))))showNotice('saveFailed');
    if(state==='sent'){
      playSound('sent');
      markAssignment(item.target);
      const reference={address:item.address,session:item.session,labels:{'recovery.role':item.role}};
      if(draftValue(reference)===item.draft){
        storeDraft(reference,'');
        if(sessionKey(active())===item.target)$('#draft').value='';
      }
    }
    delete item.draft;
    save(deliveriesKey,chatImageHistory(deliveries.slice(-200)));
    scanActivity();
    render();
    playActivity();
  },
  attachmentResult(result){
    const key=result.address+':'+result.session;
    loadingAttachments.delete(key);
    if(result.completed)attachmentPending.set(key,Math.max(0,pendingFiles(key)-1));
    if(result.items)attachmentsByTarget.set(key,result.items);
    if(result.error)attachmentNotices.set(key,result.error);
    else attachmentNotices.delete(key);
    if(sessionKey(active())===key)updateComposer();
    refreshQuestionFiles();
  },
  compatibilitySummary(probe){
    if(probe){
      const matches = entry => entry.role===probe.role && entry.session===probe.session && entry.kind==='reply' && (!probe.address||entry.fromAddress===probe.address);
      const raw=[...(snapshot.replies||[]),...(snapshot.liveMessages||[])].filter(entry=>entry.id===probe.id&&matches(entry));
      const merged=conversationRecords().filter(entry=>(entry.id===probe.id||entry.publicationID===probe.id)&&matches(entry));
      if(probe.select===true && merged.length===1 && snapshot.connection==='live'){
        const targets=inventory.filter(term=>term.state==='live'&&term.program?.agent&&legacyDraftKey(term)===probe.role&&term.session===probe.session&&(!probe.address||term.address===probe.address));
        if(targets.length===1 && (page!=='conversations'||currentRoom()||sessionKey(active())!==sessionKey(targets[0])||selectedTab!=='chat')){
          page='conversations';
          openDirectChat(targets[0]);
        }
      }
      const ids=new Set(merged.map(entry=>entry.id));
      const nodes=[...document.querySelectorAll('[data-record-id],[data-feed]')].filter(node=>ids.has(node.dataset.recordId||node.dataset.feed));
      const geometry=node=>{
        if(!node.getClientRects().length)return {visible:false,inViewport:false};
        const r=node.getBoundingClientRect();
        let left=r.left,right=r.right,top=r.top,bottom=r.bottom;
        for(let ancestor=node;ancestor;ancestor=ancestor.parentElement){
          const style=getComputedStyle(ancestor);
          if(style.display==='none'||style.visibility==='hidden'||style.visibility==='collapse'||Number(style.opacity)===0||style.contentVisibility==='hidden')return {visible:false,inViewport:false};
          if(ancestor!==node){
            const box=ancestor.getBoundingClientRect();
            if(/^(hidden|clip|scroll|auto)$/.test(style.overflowX)){
              left=Math.max(left,box.left+ancestor.clientLeft);right=Math.min(right,box.left+ancestor.clientLeft+ancestor.clientWidth);
            }
            if(/^(hidden|clip|scroll|auto)$/.test(style.overflowY)){
              top=Math.max(top,box.top+ancestor.clientTop);bottom=Math.min(bottom,box.top+ancestor.clientTop+ancestor.clientHeight);
            }
          }
        }
        const visible=right>left&&bottom>top;
        return {visible,inViewport:visible&&Math.min(right,innerWidth)>Math.max(left,0)&&Math.min(bottom,innerHeight)>Math.max(top,0)};
      };
      const visibility=nodes.map(geometry);
      return {nonce:probe.nonce,snapshotCount:raw.length,mergedCount:merged.length,domCount:nodes.length,
        visible:visibility.some(item=>item.visible),inViewport:visibility.some(item=>item.inViewport)};
    }
    const roles=[...new Set(Object.keys(legacyMessages))];
    return {legacyMessageCount:Object.values(legacyMessages).reduce((sum,list)=>sum+(Array.isArray(list)?list.length:0),0),
      legacyDraftCount:Object.values(legacyDrafts).filter(value=>typeof value==='string'&&value).length,
      retainedRoles:roles.filter(role=>inventory.some(term=>legacyDraftKey(term)===role)).length,
      historyRoles:roles.length, publishedReplyCount:(snapshot.replies||[]).filter(item=>['reply','message'].includes(item.kind)).length, visibleHistory:combineChat(active(),legacyMessages,deliveries,snapshot.replies||[]).length,
      attachmentCount:filesFor(active()).length};
  },
  questionResult(id,state){
    questionSending.delete(id);
    if(state==='sent')questionDrafts.delete(id);
    if(state==='cancel')questionResults.delete(id);
    else questionResults.set(id,state);
    showQuestions();
  },
  approvalTarget(request){
    if(request.id!==pendingApproval)return;
    pendingApproval=null;
    if(page==='conversations')selectedTab=currentRoom()?'team':'chat';
    openTerminalDrawer(request);
  },
  terminalEvent: terminalView.event,
  terminalOutput: terminalView.output,
  notice: showNotice
};
render();
post({type:'ready'});
