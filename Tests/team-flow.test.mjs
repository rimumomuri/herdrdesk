import assert from 'node:assert/strict';
import { test } from 'node:test';
import { teamFlows } from '../Resources/web/team-flow.js';

const now = 1_800_000_100_000;
const p = (address, role) => ({ address, session: address === 'desk' ? 'desk' : '1:' + address, role });
const desk = p('desk', 'you'), lead = p('t1', 'lead'), prod = p('t2', 'prod'), qa = p('t3', 'qa'), ops = p('t4', 'ops'), art = p('t5', 'art');
const edge = (from, to, state = 'open', at = now - 60_000) => ({ id: from.address + to.address, from, to, state, openedAt: at, updatedAt: at, summary: 'x', signal: 'flow' });
const status = map => address => map[address] || 'idle';
const team = [lead, prod, qa, ops, art];
const addresses = flow => flow.nodes.map(n => n.address).concat(flow.branches.flatMap(b => b.nodes.map(n => n.address)));

test('a report flow inside the team shows without anything from the desk', () => {
  const { flows } = teamFlows({ edges: [edge(lead, prod)] }, team, status({ t1: 'working', t2: 'working' }), now);
  assert.equal(flows.length, 1);
  assert.deepEqual(addresses(flows[0]), ['t1', 't2']);
});

test('separate flows each get a row, the one from the desk first', () => {
  const { flows } = teamFlows({ edges: [edge(lead, prod, 'open', now - 10_000), edge(desk, ops, 'open', now - 50_000), edge(ops, qa)] },
    team, status({ t2: 'working', t3: 'working' }), now);
  assert.deepEqual(flows.map(addresses), [['desk', 't4', 't3'], ['t1', 't2']]);
});

test('someone working alone is its own flow, and nobody appears twice', () => {
  const { flows } = teamFlows({ edges: [edge(lead, prod)] }, team, status({ t2: 'working', t5: 'working' }), now);
  assert.deepEqual(flows.map(addresses), [['t1', 't2'], ['t5']]);
});

test('a node waiting on the next one says who it waits for', () => {
  const { flows } = teamFlows({ edges: [edge(desk, lead), edge(lead, prod)] }, team, status({ t2: 'working' }), now);
  const [you, l, worker] = flows[0].nodes;
  assert.equal(you.waitingFor, 't1');
  assert.equal(l.waitingFor, 't2');
  assert.equal(worker.waitingFor, '');
});

test('edges outside the team are ignored, and nothing live means no flows', () => {
  const stranger = p('t9', 'other');
  assert.deepEqual(teamFlows({ edges: [edge(stranger, p('t8', 'x'))] }, team, status({}), now).flows, []);
  assert.deepEqual(teamFlows({ edges: [] }, team, status({}), now).flows, []);
});

test('more than three flows are folded into a count', () => {
  const { flows, hidden } = teamFlows({ edges: [] }, team, status({ t1: 'working', t2: 'working', t3: 'working', t4: 'working', t5: 'working' }), now);
  assert.equal(flows.length, 3);
  assert.equal(hidden, 2);
});

test('a long chain folded for display is still one flow', () => {
  const chainOf = Array.from({ length: 8 }, (_, i) => p('t' + (10 + i), 'r' + i));
  const edges = chainOf.slice(1).map((to, i) => edge(chainOf[i], to));
  const { flows } = teamFlows({ edges }, chainOf, status({ t17: 'working' }), now);
  assert.equal(flows.length, 1);
  assert.ok(flows[0].hidden > 0);
});

test('two flows into the same worker show the worker once; the other sender still says who it waits for', () => {
  const { flows } = teamFlows({ edges: [edge(lead, qa, 'open', now - 10_000), edge(prod, qa, 'open', now - 20_000)] }, team, status({ t3: 'working' }), now);
  assert.deepEqual(flows.map(addresses), [['t1', 't3'], ['t2']]);
  assert.equal(flows[1].nodes[0].waitingFor, 't3');
});

test('folding a long chain does not change who a node waits for', () => {
  const chainOf = Array.from({ length: 8 }, (_, i) => p('t' + (10 + i), 'r' + i));
  const edges = chainOf.slice(1).map((to, i) => edge(chainOf[i], to));
  const { flows } = teamFlows({ edges }, chainOf, status({ t17: 'working' }), now);
  assert.equal(flows[0].nodes[1].address, 't11');
  assert.equal(flows[0].nodes[1].waitingFor, 't12');
});

test('a coordinator outside the team does not pull in another team’s people', () => {
  const hq = p('t20', 'hq'), other = p('t21', 'other-lead');
  const { flows } = teamFlows({ edges: [edge(hq, lead), edge(hq, other)] }, team, status({ t1: 'working', t21: 'working' }), now);
  assert.deepEqual(flows.map(addresses), [['t20', 't1']]);
});
