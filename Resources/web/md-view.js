// A Markdown file shown in the app: headings, lists, quotes, code, rules and tables. Pure: no DOM.
// Raw HTML is never interpreted; `inline` renders a line's text (escaped, with links), `escapeText` escapes code.

const mdTableRule = /^:?-{3,}:?$/;
function mdCells(line) {
  const trimmed = line.trim();
  if (!trimmed.startsWith('|') || !trimmed.endsWith('|') || trimmed.length < 2) return [];
  return trimmed.slice(1, -1).split(/(?<!\\)\|/).map(cell => cell.trim().replace(/\\\|/g, '|'));
}
const mdListItem = /^( *)(?:([-*+])|(\d{1,9})[.)])[ \t]+(.*)$/;

// `[label](docs/x.md)` points next to the document; rewrite it to an absolute path the chat shortcuts understand.
function mdResolveLinks(line, base) {
  return line.split(/(`[^`\n]*`)/).map((part, index) => index % 2 ? part : part.replace(/\[([^\n\[\]]+)\]\(([^\s()<>]+)\)/g, (whole, label, target) => {
    if (/^(?:[a-z][\w+.-]*:|\/|~\/|#)/i.test(target)) return whole;
    let relative = target.replace(/[?#].*$/, '');
    try { relative = decodeURIComponent(relative); } catch { return whole; }
    const parts = base.split('/');
    for (const piece of relative.split('/')) {
      if (piece === '..') { if (parts.length > 1) parts.pop(); }
      else if (piece && piece !== '.') parts.push(piece);
    }
    const path = parts.join('/');
    return path.startsWith('/') && !/[<>\n]/.test(path) ? '[' + label + '](<' + path + '>)' : whole;
  })).join('');
}

/** `base` is the folder that holds the document, for relative links. */
export function markdownDocumentHTML(text, renderInline, escapeText, base = '') {
  const inline = value => renderInline(base ? mdResolveLinks(value, base) : value);
  const lines = String(text ?? '').replace(/\r\n?/g, '\n').split('\n');
  const out = [];
  let para = [], quote = [], list = null;
  const flushPara = () => { if (para.length) { out.push('<p>' + inline(para.join('\n')) + '</p>'); para = []; } };
  const flushQuote = () => { if (quote.length) { out.push('<blockquote>' + markdownDocumentHTML(quote.join('\n'), renderInline, escapeText, base) + '</blockquote>'); quote = []; } };
  const flushList = () => { if (list) { out.push('<' + list.tag + '>' + list.items.join('') + '</' + list.tag + '>'); list = null; } };
  const flush = () => { flushPara(); flushQuote(); flushList(); };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const fence = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (fence) {
      flush();
      const code = [];
      for (i++; i < lines.length; i++) {
        const close = lines[i].match(/^ {0,3}(`{3,}|~{3,})\s*$/);
        if (close && close[1][0] === fence[1][0] && close[1].length >= fence[1].length) break;
        code.push(lines[i]);
      }
      out.push('<pre><code>' + escapeText(code.join('\n')) + '</code></pre>');
      continue;
    }
    if (!line.trim()) { flush(); continue; }
    const quoted = line.match(/^ {0,3}> ?(.*)$/);
    if (quoted) { flushPara(); flushList(); quote.push(quoted[1]); continue; }
    flushQuote();
    const heading = line.match(/^ {0,3}(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$/);
    if (heading) { flush(); out.push('<h' + heading[1].length + '>' + inline(heading[2]) + '</h' + heading[1].length + '>'); continue; }
    if (/^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$/.test(line)) { flush(); out.push('<hr>'); continue; }
    const header = mdCells(line), rule = mdCells(lines[i + 1] ?? '');
    if (header.length >= 2 && rule.length === header.length && rule.every(cell => mdTableRule.test(cell))) {
      flush();
      const rows = [];
      for (i += 2; i < lines.length && mdCells(lines[i]).length === header.length; i++) rows.push(mdCells(lines[i]));
      i--;
      const cells = (items, tag) => items.map(value => '<' + tag + (tag === 'th' ? ' scope="col"' : '') + '>' + inline(value) + '</' + tag + '>').join('');
      out.push('<div class="chat-table"><table><thead><tr>' + cells(header, 'th') + '</tr></thead><tbody>'
        + rows.map(row => '<tr>' + cells(row, 'td') + '</tr>').join('') + '</tbody></table></div>');
      continue;
    }
    const item = line.match(mdListItem);
    if (item) {
      flushPara();
      const tag = item[2] ? 'ul' : 'ol';
      if (list && list.tag !== tag && item[1].length === 0) flushList();
      if (!list) list = { tag, items: [] };
      const depth = Math.min(3, Math.floor(item[1].length / 2));
      const body = item[4].replace(/^\[([ xX])\][ \t]+/, (_, mark) => (mark === ' ' ? '☐ ' : '☑ '));
      list.items.push('<li' + (depth ? ' class="md-indent-' + depth + '"' : '') + '>' + inline(body) + '</li>');
      continue;
    }
    if (list && /^ {2,}\S/.test(line)) { list.items[list.items.length - 1] = list.items.at(-1).replace(/<\/li>$/, '\n' + inline(line.trim()) + '</li>'); continue; }
    flushList();
    para.push(line);
  }
  flush();
  return out.join('');
}
