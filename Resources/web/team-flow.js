// Every flow running in a team at once, for the team room's rail. Pure: no DOM.
// A flow is one handoff chain (see buildChain) started from a party nobody in the team handed work to;
// someone working without any handoff is a flow of their own. Nobody appears in two flows.
import { buildChain } from './handoff-chain.js';

const FLOW_LIVE = new Set(['open', 'weak', 'unconfirmed', 'returning']);
const flowSame = (a, b) => Boolean(a && b) && a.address === b.address && (a.session === b.session || !a.session || !b.session);

// Who each node waits for: someone it handed work to that has not come back yet, from the edges themselves
// (a folded chain's links skip people). Someone in the same flow comes first.
const WAITING = new Set(['open', 'weak', 'unconfirmed']);
export function markWaiting(chain, edges = []) {
  const nodes = [...chain.nodes, ...chain.branches.flatMap(branch => branch.nodes)];
  for (const node of nodes) {
    const out = edges.filter(edge => WAITING.has(edge.state) && edge.from?.address === node.address && (node.address === 'desk' || flowSame(edge.from, node)));
    node.waitingFor = (out.find(edge => nodes.some(other => flowSame(other, edge.to))) || out[0])?.to.address || '';
  }
  return chain;
}

// The chain cut before the first person another flow already shows (no folding: such cuts are short).
function trimCovered(chain, covered) {
  const taken = node => node.address !== 'desk' && covered.some(seen => flowSame(seen, node));
  const cut = chain.nodes.findIndex((node, index) => index > 0 && taken(node));
  const nodes = cut < 0 ? chain.nodes : chain.nodes.slice(0, cut);
  const links = cut < 0 ? chain.links : chain.links.slice(0, cut - 1);
  const branches = chain.branches.filter(branch => branch.at < nodes.length && !taken(branch.nodes[0]))
    .map(branch => { const stop = branch.nodes.findIndex(taken); return stop < 0 ? branch : { ...branch, nodes: branch.nodes.slice(0, stop), links: branch.links.slice(0, stop) }; });
  return { ...chain, nodes, links, branches, hidden: 0, hiddenAt: -1 };
}

export function teamFlows(handoffs, members, statusOf, now, { limit = 3, collapse = true } = {}) {
  const inTeam = party => members.some(member => flowSame(member, party));
  const edges = (handoffs?.edges || []).filter(edge => FLOW_LIVE.has(edge.state) && (inTeam(edge.from) || inTeam(edge.to)));
  const parties = [];
  const add = party => { if (party && party.address !== 'desk' && !parties.some(seen => flowSame(seen, party))) parties.push(party); };
  edges.forEach(edge => { add(edge.from); add(edge.to); });
  members.filter(member => statusOf(member.address, member.session) === 'working').forEach(add);
  const named = party => members.find(member => flowSame(member, party)) || party;
  const handedByTeam = party => edges.some(edge => flowSame(edge.to, party) && edge.from?.address !== 'desk');
  const fromDesk = party => edges.some(edge => flowSame(edge.to, party) && edge.from?.address === 'desk');
  const recent = party => Math.max(0, ...edges.filter(edge => flowSame(edge.from, party) || flowSame(edge.to, party)).map(edge => edge.updatedAt || 0));
  const rank = (a, b) => Number(fromDesk(b)) - Number(fromDesk(a)) || recent(b) - recent(a);

  const flows = [], covered = [];
  const take = party => {
    if (covered.some(seen => flowSame(seen, party))) return;
    const full = buildChain(handoffs, named(party), statusOf, now, { collapse: false });
    if (!full) return;
    const everyone = chain => [...chain.nodes, ...chain.branches.flatMap(branch => branch.nodes)];
    const overlaps = everyone(full).some((node, index) => index > 0 && node.address !== 'desk' && covered.some(seen => flowSame(seen, node)));
    const chain = overlaps ? trimCovered(full, covered) : collapse ? buildChain(handoffs, named(party), statusOf, now, { collapse }) : full;
    // Coverage counts everyone in the flow, also those the folded display leaves out.
    covered.push(...everyone(overlaps ? chain : full));
    flows.push(markWaiting(chain, handoffs?.edges || []));
  };
  parties.filter(party => !handedByTeam(party)).sort(rank).forEach(take);
  parties.sort(rank).forEach(take);   // what no root reached: a cycle, or a chain cut short
  return { flows: flows.slice(0, limit), hidden: Math.max(0, flows.length - limit) };
}
