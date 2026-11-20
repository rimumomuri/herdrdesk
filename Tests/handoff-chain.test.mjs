import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildChain, handoffCardsFor, handoffCardHTML, isDelegating } from '../Resources/web/handoff-chain.js';

const now = 1_800_000_100_000;
const p = (address, role) => ({ address, session: address === 'desk' ? 'desk' : '1:' + address, role });
const desk = p('desk', 'you'), lead = p('t1', 'lead'), prod = p('t2', 'prod'), qa = p('t3', 'qa'), ops = p('t4', 'ops');
const edge = (from, to, state = 'open', openedAt = now - 60_000) => ({ id: from.address + to.address, from, to, state, openedAt, updatedAt: openedAt, summary: 'x' });
const status = map => address => map[address] || 'idle';

test('chain follows open edges to the end', () => {
  const chain = buildChain({ edges: [edge(desk, lead), edge(lead, prod), edge(prod, qa)] }, lead, status({ t3: 'working' }), now);
  assert.deepEqual(chain.nodes.map(n => n.address), ['desk', 't1', 't2', 't3']);
  assert.deepEqual(chain.nodes.map(n => n.state), ['waiting', 'waiting', 'waiting', 'working']);
  assert.deepEqual(chain.links.map(l => l.kind), ['hold', 'hold', 'hold']);
  assert.deepEqual(chain.note, { key: 'chainWorking', name: 'qa' });
});

test('fresh edge is drawn as go and named in the note', () => {
  const chain = buildChain({ edges: [edge(lead, prod, 'open', now - 1_000)] }, lead, status({}), now);
  assert.equal(chain.links[0].kind, 'go');
  assert.deepEqual(chain.note, { key: 'chainDelegating', name: 'lead' });
});

test('chain stops at a cycle', () => {
  const chain = buildChain({ edges: [edge(lead, prod), edge(prod, lead)] }, lead, status({}), now);
  assert.deepEqual(chain.nodes.map(n => n.address), ['t1', 't2']);
});

test('returning edge yields back link and done node', () => {
  const chain = buildChain({ edges: [edge(lead, prod), edge(prod, qa, 'returning')] }, lead, status({}), now);
  assert.deepEqual(chain.links.map(l => l.kind), ['hold', 'back']);
  assert.equal(chain.nodes[2].state, 'done');
  assert.deepEqual(chain.note, { key: 'chainReturning', name: 'qa' });
});

test('weak and unconfirmed edges are drawn as weak', () => {
  const chain = buildChain({ edges: [edge(lead, prod, 'unconfirmed')] }, lead, status({}), now);
  assert.equal(chain.links[0].kind, 'weak');
  assert.equal(chain.nodes[1].state, 'unconfirmed');
});

test('branch picks working path and stacks others', () => {
  const chain = buildChain({ edges: [edge(lead, prod, 'open', now - 9_000), edge(lead, qa, 'open', now - 8_000), edge(lead, ops, 'open', now - 7_000)] },
    lead, status({ t2: 'working' }), now);
  assert.deepEqual(chain.nodes.map(n => n.address), ['t1', 't2']);
  assert.equal(chain.branches.length, 2);
  assert.equal(chain.branches[0].at, 0);
  assert.deepEqual(chain.branches.map(b => b.nodes[0].address).sort(), ['t3', 't4']);
});

test('long chain collapses middle', () => {
  const parties = Array.from({ length: 9 }, (_, i) => p('t' + (i + 1), 'r' + (i + 1)));
  const edges = parties.slice(0, -1).map((from, i) => edge(from, parties[i + 1]));
  const chain = buildChain({ edges }, parties[0], status({ t9: 'working' }), now);
  assert.equal(chain.nodes.length, 5);
  assert.equal(chain.hidden, 4);
  assert.equal(chain.hiddenAt, 2);
  assert.deepEqual(chain.nodes.map(n => n.address), ['t1', 't2', 't7', 't8', 't9']);
  assert.equal(chain.links.length, 4);
});

test('depth is capped at eight hops', () => {
  const parties = Array.from({ length: 12 }, (_, i) => p('t' + (i + 1), 'r' + (i + 1)));
  const edges = parties.slice(0, -1).map((from, i) => edge(from, parties[i + 1]));
  const chain = buildChain({ edges }, parties[0], status({}), now);
  assert.equal(chain.nodes.length + chain.hidden, 9);
});

test('no open edges and idle start gives null', () => {
  assert.equal(buildChain({ edges: [edge(prod, qa)] }, lead, status({}), now), null);
  assert.equal(buildChain(undefined, lead, status({}), now), null);
});

test('working start with nothing delegated shows a single node', () => {
  const chain = buildChain({ edges: [] }, lead, status({ t1: 'working' }), now);
  assert.deepEqual(chain.nodes.map(n => n.state), ['working']);
});

test('cards for a set of addresses come back in time order', () => {
  const cards = [{ id: 'b', at: 2, from: prod, to: qa }, { id: 'a', at: 1, from: lead, to: prod }, { id: 'c', at: 3, from: ops, to: qa }];
  assert.deepEqual(handoffCardsFor({ cards }, ['t1', 't2']).map(c => c.id), ['a', 'b']);
});

test('collapse can be turned off for an expanded rail', () => {
  const parties = Array.from({ length: 9 }, (_, i) => p('t' + (i + 1), 'r' + (i + 1)));
  const edges = parties.slice(0, -1).map((from, i) => edge(from, parties[i + 1]));
  const chain = buildChain({ edges }, parties[0], status({}), now, { collapse: false });
  assert.equal(chain.nodes.length, 9);
  assert.equal(chain.hidden, 0);
});

test('a weak edge never takes the main line from a live or returning one', () => {
  const chain = buildChain({ edges: [edge(lead, prod, 'returning', now - 90_000), edge(lead, ops, 'weak', now - 10_000)] }, lead, status({}), now);
  assert.equal(chain.nodes[1].address, 't2');
  assert.equal(chain.branches[0].nodes[0].address, 't4');
});

test('the note reports activity inside a branch', () => {
  const chain = buildChain({ edges: [edge(lead, prod, 'open', now - 90_000), edge(lead, qa, 'returning', now - 80_000)] }, lead, status({ t2: 'working' }), now);
  assert.equal(chain.nodes[1].address, 't2');
  assert.deepEqual(chain.note, { key: 'chainReturning', name: 'qa' });
});

const esc = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const cardArgs = [party => party.role, () => '<i class="face"></i>', esc, key => '[' + key + ']', () => '22:21'];

test('card strips headers and escapes', () => {
  const html = handoffCardHTML({ id: 'c1', at: 1, kind: 'assign', from: lead, to: prod,
    body: '[HerdrDesk lineage {"x":1}]\n<b>x</b> line1\nline2\nline3' }, ...cardArgs);
  assert.ok(!html.includes('lineage'));
  assert.ok(html.includes('&lt;b&gt;x&lt;/b&gt; line1'));
  assert.ok(html.includes('data-lines="2"'));
  assert.ok(html.includes('[tagHandoff]'));
  assert.ok(html.includes('data-kind="assign"'));
  assert.ok(html.indexOf('lead') < html.indexOf('prod'));
});

test('card tag follows its kind', () => {
  for (const [kind, key] of [['reply', 'tagResult'], ['progress', 'tagProgress'], ['message', 'tagAddon'], ['pending', 'tagAddon']]) {
    assert.ok(handoffCardHTML({ id: 'c', at: 1, kind, from: prod, to: lead, body: 'b' }, ...cardArgs).includes('[' + key + ']'), kind);
  }
});

test('an agent with an open outgoing edge is delegating', () => {
  const handoffs = { edges: [edge(lead, prod), edge(prod, qa, 'returning'), edge(ops, qa, 'weak')] };
  assert.equal(isDelegating(handoffs, lead), true);
  assert.equal(isDelegating(handoffs, prod), false);
  assert.equal(isDelegating(handoffs, ops), false);
  assert.equal(isDelegating({ edges: [edge(lead, prod, 'unconfirmed')] }, lead), false);
  assert.equal(isDelegating(handoffs, qa), false);
  assert.equal(isDelegating(undefined, lead), false);
});

test('an open desk edge alone does not show the rail while the target is idle', () => {
  assert.equal(buildChain({ edges: [edge(desk, lead)] }, lead, status({}), now), null);
  assert.ok(buildChain({ edges: [edge(desk, lead, 'returning')] }, lead, status({}), now));
  assert.ok(buildChain({ edges: [edge(desk, lead)] }, lead, status({ t1: 'working' }), now));
});

test('room cards can leave out the user\'s own sends', () => {
  const cards = [{ id: 'mine', at: 1, from: desk, to: lead }, { id: 'agents', at: 2, from: lead, to: prod }];
  assert.deepEqual(handoffCardsFor({ cards }, ['t1'], { withDesk: false }).map(c => c.id), ['agents']);
  assert.deepEqual(handoffCardsFor({ cards }, ['t1']).map(c => c.id), ['mine', 'agents']);
});
