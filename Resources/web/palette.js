// Command palette (Cmd+K): jump to a conversation or computer, or run an action, by typing. Pure: no DOM.

const KIND_ORDER = { action: 0, chat: 1, computer: 2 };

/** items: [{id, kind:'action'|'chat'|'computer', label, detail}]. Every query word must appear in the name or detail. */
export function filterPalette(items, query, limit = 12) {
  const words = String(query || '').toLowerCase().split(/\s+/).filter(Boolean);
  const scored = [];
  items.forEach((item, index) => {
    const label = String(item.label || '').toLowerCase(), all = label + ' ' + String(item.detail || '').toLowerCase();
    if (!words.every(word => all.includes(word))) return;
    const score = !words.length ? 0 : label.startsWith(words[0]) ? 0 : label.includes(words[0]) ? 1 : 2;
    scored.push({ item, index, score });
  });
  scored.sort((a, b) => (words.length ? a.score - b.score : 0) || (KIND_ORDER[a.item.kind] ?? 3) - (KIND_ORDER[b.item.kind] ?? 3) || a.index - b.index);
  return scored.slice(0, limit).map(entry => entry.item);
}

/** The result list; `selected` is the highlighted index. */
export function paletteHTML(list, selected, copy, escape) {
  return list.map((item, index) => '<li role="option" aria-selected="' + (index === selected) + '" data-palette="' + escape(item.id) + '">'
    + '<span class="palette-kind">' + escape(copy('palette_' + item.kind)) + '</span><b>' + escape(item.label) + '</b>'
    + (item.detail ? '<small>' + escape(item.detail) + '</small>' : '') + '</li>').join('');
}
