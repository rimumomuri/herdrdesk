// Agent faces: a lead is a sheep that keeps its mouth closed and opens it to hold the agents it has handed
// work to; a card worker is simply its engine's character (Claude or Codex). Pure: no DOM.

// Lead sheet: 3 rows (Claude, Codex, mixed) x 3 frames (closed, asleep, open with an empty mouth), 418-unit cells.
const HERD_LEADS = { href: 'icons/herd-leads-v1.png', size: 1254, cell: 418, crop: [20, 25, 380] };
const HERD_FRAMES = ['closed', 'sleep', 'open'];
// Agent sheet: Claude on the left, Codex on the right, in 1774x887 units.
const HERD_AGENTS = { href: 'icons/herd-agents-v1.png', width: 1774, height: 887,
  view: { claude: '124 158 640 640', codex: '1006 141 640 640' } };
const HERD_ENGINES = ['claude', 'codex'];
// Where agents sit inside the open mouth (cell units), by how many there are.
const HERD_SLOTS = [
  [],
  [[140, 196, 84]],
  [[112, 205, 66], [184, 212, 66]],
  [[118, 200, 56], [180, 200, 56], [150, 240, 56]],
  [[116, 196, 52], [174, 196, 52], [122, 244, 52], [180, 244, 52]],
];

/** A worker spawned for a task card ("<team>-<role>-<n>", or a spawned session with a team role). */
export function isCardWorker(labels) {
  if (/-(planner|builder|verifier|researcher|designer|user-tester)-\d+$/.test(labels?.['recovery.role'] || '')) return true;
  return Boolean(labels?.['task.spawned'] && labels?.['team.role'] && labels['team.role'] !== 'lead');
}

export const leadFrame = ({ mouth = [], resting = false }) => mouth.length ? 'open' : resting ? 'sleep' : 'closed';

/** 0 Claude, 1 Codex (also for anything else), 2 mixed: the mouth holds both engines. */
export function leadRow(engine, mouth = []) {
  if (mouth.includes('claude') && mouth.includes('codex')) return 2;
  return engine === 'claude' ? 0 : 1;
}

/** Up to four agents; past four, three agents and a "more" mark in the last place. */
export function mouthSlots(count) {
  const shown = Math.min(count, 4);
  return HERD_SLOTS[shown].map(([x, y, size], index) => ({ x, y, size, more: count > 4 && index === 3 }));
}

const herdEngine = engine => HERD_ENGINES.includes(engine) ? engine : 'codex';
const herdAgentImage = (engine, x, y, size, extra = '') =>
  '<svg' + extra + ' x="' + x + '" y="' + y + '" width="' + size + '" height="' + size + '" viewBox="' + HERD_AGENTS.view[engine] + '">'
  + '<image href="' + HERD_AGENTS.href + '" width="' + HERD_AGENTS.width + '" height="' + HERD_AGENTS.height + '"/></svg>';

/** `mouth`: engines of the agents the lead is waiting on; `fresh`: how many of them just went in (they get the swallow motion). */
export function leadFaceHTML({ engine = 'codex', mouth = [], resting = false, fresh = 0 } = {}) {
  const frame = leadFrame({ mouth, resting }), row = leadRow(engine, mouth), column = HERD_FRAMES.indexOf(frame);
  const left = column * HERD_LEADS.cell, top = row * HERD_LEADS.cell, [cx, cy, side] = HERD_LEADS.crop;
  const slots = mouthSlots(mouth.length);
  const inside = slots.map((slot, index) => slot.more
    ? '<g class="herd-mouth-more">' + [0, 1, 2].map(dot => '<circle cx="' + (left + slot.x + 10 + dot * 16) + '" cy="' + (top + slot.y + slot.size / 2) + '" r="5.5" fill="#f4efe6"/>').join('') + '</g>'
    : herdAgentImage(herdEngine(mouth[index]), left + slot.x, top + slot.y, slot.size,
      ' class="herd-mouth-agent"' + (index >= slots.length - fresh ? ' data-new="true"' : ''))).join('');
  return '<span class="agent-portrait" data-face="lead" data-frame="' + frame + '" data-row="' + row + '" data-sleep="' + (frame === 'sleep') + '" aria-hidden="true">'
    + '<svg viewBox="' + (left + cx) + ' ' + (top + cy) + ' ' + side + ' ' + side + '" focusable="false"><g class="herd-body">'
    + '<image href="' + HERD_LEADS.href + '" width="' + HERD_LEADS.size + '" height="' + HERD_LEADS.size + '"/>' + inside + '</g></svg></span>';
}

export function agentFaceHTML({ engine = 'codex', resting = false } = {}) {
  const shown = herdEngine(engine);
  return '<span class="agent-portrait" data-face="agent" data-engine="' + shown + '" data-sleep="' + Boolean(resting) + '" aria-hidden="true">'
    + '<svg viewBox="' + HERD_AGENTS.view[shown] + '" focusable="false"><g class="herd-body">'
    + '<image href="' + HERD_AGENTS.href + '" width="' + HERD_AGENTS.width + '" height="' + HERD_AGENTS.height + '"/></g></svg></span>';
}
