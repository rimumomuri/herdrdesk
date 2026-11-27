// The companion's hover stat panel. Pure: no DOM.

const statText = text => String(text ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** Sections of {kind, title, count, rows: [{name, meta}], more}: a heading with its count, then one line per agent. */
export function statPanelHTML(stats) {
  return '<div class="stat-panel">' + stats.map(section => '<section class="stat-section" data-kind="' + statText(section.kind) + '">'
    + '<header><span class="stat-dot" aria-hidden="true"></span>' + statText(section.title) + '<b>' + Number(section.count || 0) + '</b></header>'
    + (section.rows || []).map(row => '<div class="stat-row"><span>' + statText(row.name) + '</span><time>' + statText(row.meta) + '</time></div>').join('')
    + (section.more ? '<div class="stat-more">' + statText(section.more) + '</div>' : '') + '</section>').join('') + '</div>';
}
