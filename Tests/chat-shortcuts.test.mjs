import {test} from 'node:test';
import assert from 'node:assert/strict';
import {chatShortcutSegments} from '../Resources/web/chat-shortcuts.js';

test('chat shortcuts preserve labels, whitespace and surrounding punctuation',()=>{
  const text='[업무 기록](https://www.notion.so/team/123)\n(youtu.be/abc), [PR](https://github.com/org/repo/pull/2?name=(draft))';
  const items=chatShortcutSegments(text);
  assert.deepEqual(items.map(item=>typeof item==='string'?item:[item.label,item.kind,item.href]),[
    ['업무 기록','notion','https://www.notion.so/team/123'],'\n(',
    ['YouTube','youtube','https://youtu.be/abc'],'),',' ',
    ['PR','github','https://github.com/org/repo/pull/2?name=(draft)'],
  ]);
});

test('paths with spaces, file URLs and editor references resolve as local shortcuts',()=>{
  const items=chatShortcutSegments('"/Users/name/My Folder" `~/Docs/검증 보고.md:21` file:///Users/name/a%20b.md');
  assert.deepEqual(items.filter(item=>typeof item!=='string').map(item=>[item.kind,decodeURIComponent(item.href.slice('herdrdesk-path:'.length))]),[
    ['file','/Users/name/My Folder'],['file','~/Docs/검증 보고.md:21'],['file','/Users/name/a b.md'],
  ]);
});

test('unsupported schemes, untrusted HTML and fenced code stay literal',()=>{
  const text='<svg onload=x> [run](javascript:alert(1)) hc send https://user:pass@example.com file://another-mac/Users/name\n```sh\ncd /Users/name\n```';
  assert.deepEqual(chatShortcutSegments(text),[text]);
  assert.equal(chatShortcutSegments('https://www.notion.so.example.org/team')[0].kind,'web');
});


test('Markdown title strings do not become part of the shortcut destination',()=>{
  const links=chatShortcutSegments('[#332](https://github.com/owner/repo/pull/332 "https://github.com/owner/repo/pull/332") [Report](</Users/name/Work Reports> "Finder") `ACTION_REQUIRED`');
  assert.deepEqual(links.filter(item=>typeof item!=='string').map(item=>[item.kind,item.label,item.href]),[
    ['github','#332','https://github.com/owner/repo/pull/332'],
    ['file','Report','herdrdesk-path:%2FUsers%2Fname%2FWork%20Reports'],
    ['code','ACTION_REQUIRED',undefined],
  ]);
});
