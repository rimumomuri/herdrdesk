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

test('nested list items keep their indent', () => {
  assert.equal(html('- top\n  - inner'), '<ul><li>top</li><li class="md-indent-1">inner</li></ul>');
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
