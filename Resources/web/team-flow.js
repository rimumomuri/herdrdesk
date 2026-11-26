// Every flow running in a team at once, for the team room's rail. Pure: no DOM.
// A flow is one handoff chain (see buildChain) started from a party nobody in the team handed work to;
// someone working without any handoff is a flow of their own. Nobody appears in two flows.
import { buildChain } from './handoff-chain.js';

const FLOW_LIVE = new Set(['open', 'weak', 'unconfirmed', 'returning']);
const flowSame = (a, b) => Boolean(a && b) && a.address === b.address && (a.session === b.session || !a.session || !b.session);

// Who each node waits for: the next party it handed work to that has not come back yet.
export function markWaiting(chain) {
  const links = [...chain.links, ...chain.branches.flatMap(branch => branch.links)];
  for (const node of [...chain.nodes, ...chain.branches.flatMap(branch => branch.nodes)]) {
    node.waitingFor = links.find(link => link.from === node.address && link.kind !== 'back' && link.kind !== 'done')?.to || '';
  }
  return chain;
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
    // Coverage counts everyone in the flow, also those the folded display leaves out.
    for (const node of [...full.nodes, ...full.branches.flatMap(branch => branch.nodes)]) covered.push(node);
    const chain = collapse ? buildChain(handoffs, named(party), statusOf, now, { collapse }) : full;
    flows.push(markWaiting(chain));
  };
  parties.filter(party => !handedByTeam(party)).sort(rank).forEach(take);
  parties.sort(rank).forEach(take);   // what no root reached: a cycle, or a chain cut short
  return { flows: flows.slice(0, limit), hidden: Math.max(0, flows.length - limit) };
}
