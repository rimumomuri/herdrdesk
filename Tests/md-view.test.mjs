import {test} from 'node:test';
import assert from 'node:assert/strict';
import {markdownDocumentHTML} from '../Resources/web/md-view.js';

const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const inline = s => esc(s).replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
const html = text => markdownDocumentHTML(text, inline, esc);

test('headings, paragraphs and rules', () => {
  assert.equal(html('# Title\n\nSome **bold**\ntext\n\n---\n### Small'),
    '<h1>Title</h1><p>Some <strong>bold</strong>\ntext</p><hr><h3>Small</h3>');
});

test('bullet and numbered lists, with task boxes', () => {
  assert.equal(html('- one\n* two\n\n1. a\n2) b\n- [x] done\n- [ ] todo'),
    '<ul><li>one</li><li>two</li></ul><ol><li>a</li><li>b</li></ol><ul><li>☑ done</li><li>☐ todo</li></ul>');
});

test('nested lists sit inside their parent item and keep its numbering', () => {
  assert.equal(html('- top\n  - inner'), '<ul><li>top<ul><li>inner</li></ul></li></ul>');
  assert.equal(html('1. Build\n   - Install\n   - Compile\n2. Deploy'),
    '<ol><li>Build<ul><li>Install</li><li>Compile</li></ul></li><li>Deploy</li></ol>');
});

test('code fences are escaped and not parsed', () => {
  assert.equal(html('```js\n# not a heading\n<b>x</b>\n```'), '<pre><code># not a heading\n&lt;b&gt;x&lt;/b&gt;</code></pre>');
});

test('an unclosed fence runs to the end', () => {
  assert.equal(html('~~~\na\nb'), '<pre><code>a\nb</code></pre>');
});

test('block quotes and tables', () => {
  assert.equal(html('> quoted\n> more\n\n| a | b |\n|---|---|\n| 1 | 2 |'),
    '<blockquote><p>quoted\nmore</p></blockquote><div class="chat-table"><table><thead><tr><th scope="col">a</th><th scope="col">b</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table></div>');
});

test('raw HTML in the document is shown as text', () => {
  assert.equal(html('<script>alert(1)</script>'), '<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>');
});

test('a hash that belongs to the heading stays; a closing sequence goes', () => {
  assert.equal(html('# C#\n## Title ##'), '<h1>C#</h1><h2>Title</h2>');
});

test('relative links resolve against the document folder', () => {
  const out = markdownDocumentHTML('See [config](docs/config.md), [up](../README.md#top), [web](https://a.b), [abs](/x/y.md), `[c](d.md)`',
    s => esc(s), esc, '/Users/me/project/notes');
  assert.equal(out, '<p>See [config](&lt;/Users/me/project/notes/docs/config.md&gt;), [up](&lt;/Users/me/project/README.md&gt;), [web](https://a.b), [abs](/x/y.md), `[c](d.md)`</p>');
});

test('wrapped, titled and parenthesised relative links become real shortcuts', async () => {
  const {chatShortcutSegments} = await import('../Resources/web/chat-shortcuts.js');
  const links = text => chatShortcutSegments(text).filter(part => typeof part !== 'string').map(part => decodeURIComponent(part.href.replace('herdrdesk-path:', '')));
  const render = s => JSON.stringify(links(s));
  const out = markdownDocumentHTML('[a](<docs/my plan.md>) [b](docs/plan.md "Plan") [c](docs/plan(v2).md)', render, esc, '/Users/me/p');
  assert.equal(out, '<p>' + JSON.stringify(['/Users/me/p/docs/my plan.md', '/Users/me/p/docs/plan.md', '/Users/me/p/docs/plan(v2).md']) + '</p>');
});

test('an ordered list stays one list across blank lines and keeps its first number', () => {
  assert.equal(html('1. First\n\n2. Second\n\n3. Third'), '<ol><li>First</li><li>Second</li><li>Third</li></ol>');
  assert.equal(html('3. Third\n4. Fourth\n\nAfter'), '<ol start="3"><li>Third</li><li>Fourth</li></ol><p>After</p>');
});
