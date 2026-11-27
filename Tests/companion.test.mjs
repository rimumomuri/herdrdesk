import {test} from 'node:test';
import assert from 'node:assert/strict';
import {companionState, companionSummary, featuredAgent, FLASH_MS} from '../Resources/web/companion.js';

const now = 1_000_000;
const base = {connection:'live', attention:[], working:0, flash:null, now};

test('someone waiting on you wins over everything, counted once per agent even with a blocked prompt and a question', () => {
  const state = companionState({...base, working:3, flash:{kind:'done', at:now},
    attention:[{address:'t1', session:'s1', team:'킁킁맵'}, {address:'t1', session:'s1', team:'킁킁맵'}, {address:'t2', session:'s2', team:'라인챗봇'}]});
  assert.equal(state.mood, 'attention');
  assert.equal(state.count, 2);
  assert.deepEqual(state.teams, [{team:'킁킁맵', n:1}, {team:'라인챗봇', n:1}]);
  assert.deepEqual(state.target, {address:'t1', session:'s1'});
});

test('a lost or missing connection is shown as offline, never as idle; the first connect is not', () => {
  assert.equal(companionState({...base, connection:'lost'}).mood, 'offline');
  assert.equal(companionState({...base, connection:'missing', working:2}).mood, 'offline');
  assert.equal(companionState({...base, connection:'connecting'}).mood, 'idle');
  assert.equal(companionState({...base, connection:'lost', attention:[{address:'t1', session:'s', team:'x'}]}).mood, 'attention');
});

test('working shows how many sessions work; with nothing going on it is idle', () => {
  assert.deepEqual([companionState({...base, working:2}).mood, companionState({...base, working:2}).working], ['working', 2]);
  assert.equal(companionState(base).mood, 'idle');
  assert.equal(companionState(base).target, null);
});

test('a finish or a new assignment flashes briefly on top of the mood, then fades', () => {
  assert.equal(companionState({...base, working:1, flash:{kind:'done', at:now - 1000}}).flash, 'done');
  assert.equal(companionState({...base, flash:{kind:'handoff', at:now - 1000}}).flash, 'handoff');
  assert.equal(companionState({...base, flash:{kind:'handoff', at:now - 1000}}).mood, 'idle');
  assert.equal(companionState({...base, flash:{kind:'done', at:now - FLASH_MS - 1}}).flash, null);
});

test('the hover line names teams and counts only, never question text', () => {
  const copy = key => ({companionNeeds:'{team} 확인 {n}개', companionWorking:'{n}개 작업 중', companionOffline:'연결 끊김', companionIdle:'쉬는 중',
    companionDone:'방금 끝남', companionHandoff:'새 배정'})[key];
  const attention = companionState({...base, attention:[{address:'t1', session:'s', team:'킁킁맵', ask:'비밀 질문'}]});
  assert.deepEqual(companionSummary(attention, copy), ['킁킁맵 확인 1개']);
  assert.ok(!JSON.stringify(attention).includes('비밀'));
  assert.deepEqual(companionSummary(companionState({...base, working:3, flash:{kind:'done', at:now}}), copy), ['방금 끝남', '3개 작업 중']);
  assert.deepEqual(companionSummary(companionState({...base, connection:'lost'}), copy), ['연결 끊김']);
});

test('each flash carries its event time, so a second finish of the same kind is still new', () => {
  assert.equal(companionState({...base, flash:{kind:'handoff', at:now - 2000}}).flashAt, now - 2000);
  assert.equal(companionState({...base, flash:{kind:'handoff', at:now - FLASH_MS - 1}}).flashAt, null);
});

test('the face shown is whoever needs you, else who just finished, else the latest to start working, else the last face', () => {
  const working = ['w-new', 'w-old'];
  assert.equal(featuredAgent({mood:'attention', flash:'done', targetKey:'a', finishedKey:'f', workingKeys:working, previousKey:'p'}), 'a');
  assert.equal(featuredAgent({mood:'working', flash:'done', finishedKey:'f', workingKeys:working, previousKey:'p'}), 'f');
  assert.equal(featuredAgent({mood:'working', flash:'handoff', finishedKey:'f', workingKeys:working, previousKey:'p'}), 'w-new');
  assert.equal(featuredAgent({mood:'idle', workingKeys:[], previousKey:'p'}), 'p');
  assert.equal(featuredAgent({mood:'idle', workingKeys:[]}), null);
});

test('a usage limit shows as its own mood below needs-you and offline but above working, with no target to open', () => {
  assert.equal(companionState({...base, working:2, limited:1}).mood, 'limit');
  assert.equal(companionState({...base, limited:1}).limited, 1);
  assert.equal(companionState({...base, connection:'lost', limited:1}).mood, 'offline');
  assert.equal(companionState({...base, limited:1, attention:[{address:'t1', session:'s', team:'x'}]}).mood, 'attention');
  const copy = key => ({companionLimit:'{n}개 한도 초과'})[key] || key;
  assert.deepEqual(companionSummary(companionState({...base, limited:2}), copy), ['2개 한도 초과']);
});

test('while at a usage limit the face is the limited agent', () => {
  assert.equal(featuredAgent({mood:'limit', limitKey:'l', workingKeys:['w'], previousKey:'p'}), 'l');
});

test('the floating sheep has no backdrop circle, only a shadow so it reads on any screen', async () => {
  const {readFileSync} = await import('node:fs');
  const css = readFileSync(new URL('../Resources/web/companion.css', import.meta.url), 'utf8');
  const figure = css.match(/\.companion-figure \{[^}]*\}/)[0];
  assert.match(figure, /background:transparent/);
  assert.doesNotMatch(figure, /border-radius:50%/);
  assert.match(css, /drop-shadow/);
});

test('the stat panel lists who works (with time), who just finished and who waits on you', async () => {
  const {companionStats} = await import('../Resources/web/companion.js');
  const copy = key => ({statWorking: 'Working', statDone: 'Done', statWaiting: 'Waiting on you', statMore: '+{n} more', statJustNow: 'just now', statAgo: '{t} ago'})[key] || key;
  const units = {s: '{s}s', ms: '{m}m {s}s', hm: '{h}h {m}m'};
  const now = 10_000_000;
  const stats = companionStats({
    working: [{name: 'Kunkun lead', since: now - 723_000}, {name: 'Research', since: now - 130_000}],
    done: [{name: 'Lime lead', at: now - 20_000}, {name: 'Old', at: now - 3_600_000}],
    waiting: [{name: 'Realestate lead'}],
  }, now, units, copy);
  assert.deepEqual(stats.map(s => s.kind), ['waiting', 'working', 'done']);
  assert.deepEqual(stats[1].rows, [{name: 'Kunkun lead', meta: '12m 3s'}, {name: 'Research', meta: '2m 10s'}]);
  assert.equal(stats[1].title, 'Working');
  assert.equal(stats[1].count, 2);
  assert.deepEqual(stats[2].rows, [{name: 'Lime lead', meta: 'just now'}]);   // finished over 30 minutes ago drops out
  assert.deepEqual(stats[0].rows, [{name: 'Realestate lead', meta: ''}]);
});

test('a long list shows four rows and how many more', async () => {
  const {companionStats} = await import('../Resources/web/companion.js');
  const copy = key => ({statWorking: 'Working', statMore: '+{n} more'})[key] || key;
  const now = 1_000_000;
  const working = Array.from({length: 6}, (_, i) => ({name: 'A' + i, since: now - 1000}));
  const [section] = companionStats({working, done: [], waiting: []}, now, {s: '{s}s', ms: '', hm: ''}, copy);
  assert.equal(section.rows.length, 4);
  assert.equal(section.more, '+2 more');
  assert.equal(section.count, 6);
});

test('nothing going on gives no panel', async () => {
  const {companionStats} = await import('../Resources/web/companion.js');
  assert.deepEqual(companionStats({working: [], done: [], waiting: []}, 0, {}, k => k), []);
});

test('the stat panel draws each section with its count, rows and times, escaping names', async () => {
  const {statPanelHTML} = await import('../Resources/web/companion-stats.js');
  const html = statPanelHTML([{kind: 'working', title: 'Working', count: 6, rows: [{name: 'A<b>', meta: '12m 3s'}], more: '+5 more'}]);
  assert.match(html, /data-kind="working"/);
  assert.match(html, /Working<b>6<\/b>/);
  assert.match(html, /<span>A&lt;b&gt;<\/span><time>12m 3s<\/time>/);
  assert.match(html, /stat-more">\+5 more/);
});

test('the sheep is pinned to a corner of the window, so resizing for the panel never moves it', async () => {
  const {readFileSync} = await import('node:fs');
  const css = readFileSync(new URL('../Resources/web/companion.css', import.meta.url), 'utf8');
  const figure = css.match(/\.companion-figure \{[^}]*\}/)[0];
  assert.match(figure, /position:absolute/);
  assert.match(figure, /right:10px/);
  assert.match(figure, /bottom:10px/);
  assert.match(css, /\.companion\.bubble-right \.companion-figure \{[^}]*left:10px/);
  assert.match(css, /\.companion\.bubble-down \.companion-figure \{[^}]*top:10px/);
  // no layout that depends on the hover class or the window height
  assert.doesNotMatch(css, /\.companion\.hovered \{[^}]*align-items/);
});

test('hover sets the direction first and shows the panel only when asked', async () => {
  const {readFileSync} = await import('node:fs');
  const page = readFileSync(new URL('../Resources/web/companion-page.js', import.meta.url), 'utf8');
  assert.match(page, /direction\(right, down\)/);
  assert.match(page, /reveal\(on\)/);
});

test('the stat panel window shows only the panel, beside the sheep', async () => {
  const {readFileSync} = await import('node:fs');
  const css = readFileSync(new URL('../Resources/web/companion.css', import.meta.url), 'utf8');
  const page = readFileSync(new URL('../Resources/web/companion-page.js', import.meta.url), 'utf8');
  assert.match(page, /panelOnly\(\) \{ root\.classList\.add\('panel-only'\)/);
  // no URL fragment for the panel window: WebKit refused it and the app never connected
  assert.doesNotMatch(page, /location\.hash/);
  assert.match(css, /\.companion\.panel-only \.companion-figure \{ display:none \}/);
  assert.match(css, /\.companion\.panel-only \.companion-bubble \{ display:block/);
});

test('a long name is cut with an ellipsis instead of pushing the count and the time out of the panel', async () => {
  const {readFileSync} = await import('node:fs');
  const css = readFileSync(new URL('../Resources/web/companion.css', import.meta.url), 'utf8');
  assert.match(css, /\.stat-panel \{[^}]*grid-template-columns:minmax\(0, ?1fr\)/);
  assert.match(css, /\.stat-section \{[^}]*min-width:0/);
});
