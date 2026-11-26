// Handoff chain for the work-status rail: who handed what to whom, followed to the end.
// Pure: no DOM. Input is the `handoffs` snapshot the app sends ({edges, cards}).

const LIVE_EDGE = new Set(['open', 'weak', 'unconfirmed', 'returning']);
const MAX_DEPTH = 8, MAX_BRANCHES = 3, MAX_NODES = 6, GO_MS = 3000;

const EDGE_RANK = { returning: 2, open: 1, weak: 0, unconfirmed: 0 };
const sameParty = (a, b) => Boolean(a && b) && a.address === b.address
  && (a.session === b.session || !a.session || !b.session);

function linkKind(edge, now) {
  if (edge.state === 'returning') return 'back';
  if (edge.state === 'weak' || edge.state === 'unconfirmed') return 'weak';
  return now - edge.openedAt <= GO_MS ? 'go' : 'hold';
}

export function buildChain(handoffs, start, statusOf, now, { collapse = true } = {}) {
  if (!start) return null;
  const edges = (handoffs?.edges || []).filter(edge => LIVE_EDGE.has(edge.state));
  const outgoing = party => edges.filter(edge => sameParty(edge.from, party));
  const deskEdge = edges.find(edge => edge.from?.address === 'desk' && sameParty(edge.to, start));
  // Spec 8.4: shown while someone works, someone was handed work, or a result is coming back.
  if (deskEdge?.state !== 'returning' && !outgoing(start).length && statusOf(start.address) !== 'working') return null;

  const nodeState = party => {
    if (party.address === 'desk') return deskEdge?.state === 'returning' ? 'done' : 'waiting';
    if (statusOf(party.address) === 'working') return 'working';
    if (outgoing(party).some(edge => edge.state !== 'returning')) return 'waiting';
    if (edges.some(edge => edge.state === 'returning' && sameParty(edge.to, party))) return 'done';
    if (edges.some(edge => edge.state === 'unconfirmed' && sameParty(edge.to, party))) return 'unconfirmed';
    return 'idle';
  };
  const node = party => ({ address: party.address, session: party.session, role: party.role, state: nodeState(party) });
  const hasWork = (party, seen, depth = 0) => statusOf(party.address) === 'working'
    || (depth < MAX_DEPTH && outgoing(party).some(edge => !seen.has(edge.to.address)
      && hasWork(edge.to, new Set([...seen, edge.to.address]), depth + 1)));

  // Follows one path from `party`; `seen` stops cycles, `budget` caps the hops.
  const walk = (party, seen, budget) => {
    const nodes = [], links = [], forks = [];
    let current = party;
    while (nodes.length < budget) {
      const next = outgoing(current).filter(edge => !seen.has(edge.to.address));
      if (!next.length) break;
      const ranked = [...next].sort((a, b) => Number(hasWork(b.to, seen)) - Number(hasWork(a.to, seen))
        || (EDGE_RANK[b.state] ?? 0) - (EDGE_RANK[a.state] ?? 0) || b.updatedAt - a.updatedAt);
      const [main, ...rest] = ranked;
      if (rest.length) forks.push({ from: current, edges: rest, index: nodes.length });
      seen.add(main.to.address);
      links.push({ from: current.address, to: main.to.address, kind: linkKind(main, now) });
      nodes.push(node(main.to));
      current = main.to;
    }
    return { nodes, links, forks };
  };

  const seen = new Set([start.address]);
  const nodes = [], links = [];
  if (deskEdge) {
    nodes.push(node(deskEdge.from));
    links.push({ from: 'desk', to: start.address, kind: linkKind(deskEdge, now) });
  }
  const offset = nodes.length;
  nodes.push(node(start));
  const path = walk(start, seen, MAX_DEPTH);
  nodes.push(...path.nodes); links.push(...path.links);

  const branches = [];
  for (const fork of path.forks) for (const edge of fork.edges) {
    if (branches.length >= MAX_BRANCHES || seen.has(edge.to.address)) continue;
    const branchSeen = new Set([...seen, edge.to.address]);
    const rest = walk(edge.to, branchSeen, MAX_DEPTH - fork.index - 1);
    branches.push({ at: offset + fork.index, nodes: [node(edge.to), ...rest.nodes],
      links: [{ from: fork.from.address, to: edge.to.address, kind: linkKind(edge, now) }, ...rest.links] });
  }

  const note = chainNote([...nodes, ...branches.flatMap(b => b.nodes)], [...links, ...branches.flatMap(b => b.links)]);
  let hidden = 0, hiddenAt = -1;
  if (collapse && nodes.length > MAX_NODES) {
    hidden = nodes.length - 5; hiddenAt = 2;
    const keptLinks = [links[0], { from: nodes[1].address, to: nodes[nodes.length - 3].address, kind: 'hold' }, ...links.slice(-2)];
    nodes.splice(2, hidden);
    links.splice(0, links.length, ...keptLinks);
    for (const branch of branches) branch.at = Math.min(branch.at, 1);
  }
  return { nodes, links, branches, hidden, hiddenAt, note };
}

function chainNote(nodes, links) {
  const role = address => nodes.find(n => n.address === address)?.role || '';
  const back = links.findLast(link => link.kind === 'back');
  if (back) return { key: 'chainReturning', name: role(back.to) };
  const go = links.findLast(link => link.kind === 'go');
  if (go) return { key: 'chainDelegating', name: role(go.from) };
  const working = nodes.findLast(n => n.state === 'working');
  if (working) return { key: 'chainWorking', name: working.role };
  return { key: 'chainWaitingAll', name: nodes[0]?.role || '' };
}

export function handoffCardsFor(handoffs, addresses, { withDesk = true } = {}) {
  const wanted = new Set(addresses);
  return (handoffs?.cards || []).filter(card => wanted.has(card.from?.address) || wanted.has(card.to?.address))
    .filter(card => withDesk || (card.from?.address !== 'desk' && card.to?.address !== 'desk'))
    .sort((a, b) => a.at - b.at);
}

import { messageTag, tagHTML } from './message-tags.js';

const CARD_BADGE = { assign: 'cardAssign', reply: 'cardReply', progress: 'cardProgress', message: 'cardMessage', pending: 'cardMessage' };

/** A dense report as one sentence per line: break after 。．！？ and after . ! ? followed by a space. Dots inside
 *  numbers, file names and links stay; code (fenced or indented) and indentation stay as written. No rewording. */
export function readableBody(text) {
  let fence = false;
  return String(text ?? '').split('\n').map(line => {
    if (/^ {0,3}(```|~~~)/.test(line)) { fence = !fence; return line; }
    if (fence || /^( {4}|\t)/.test(line)) return line;
    return line.replace(/([。．！？])[ \t]*(?=\S)/g, '$1\n').replace(/([.!?])[ \t]+(?=\S)/g, '$1\n');
  }).join('\n');
}

/** One handoff card for the chat: sender → receiver, badge, time, first two lines of the body. */
export function handoffCardHTML(card, nameOf, portraitOf, escape, copy, timeOf) {
  let body = String(card.body || '').trim();
  if (body.startsWith('[HerdrDesk lineage ')) body = body.slice(body.indexOf('\n') + 1).trim();
  const kind = CARD_BADGE[card.kind] ? card.kind : 'message';
  const side = party => '<span class="hc-face">' + portraitOf(party) + '</span><b class="hc-name">' + escape(nameOf(party)) + '</b>';
  const tag = messageTag('card:' + kind);
  return '<div class="hc-card" data-kind="' + escape(kind) + '" data-tag="' + escape(tag) + '" data-record-id="' + escape(card.id) + '">'
    + '<div class="hc-head">' + tagHTML(tag, copy, escape) + side(card.from) + '<span class="hc-arrow" aria-hidden="true"></span>' + side(card.to)
    + '<small class="msg-time">' + escape(timeOf(card.at)) + '</small></div>'
    + '<div class="hc-body" data-lines="2">' + escape(readableBody(body)) + '</div></div>';
}

/** Handed work to someone and has not had it back yet (open, weak or unconfirmed outgoing edge). */
export function isDelegating(handoffs, party) {
  // Only a confirmed handoff is asserted; weak and unconfirmed ones stay dotted lines on the rail.
  return (handoffs?.edges || []).some(edge => edge.state === 'open' && sameParty(edge.from, party));
}
