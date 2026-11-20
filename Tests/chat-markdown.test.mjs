import {test} from 'node:test';
import assert from 'node:assert/strict';
import {chatMarkdownBlocks} from '../Resources/web/chat-markdown.js';

test('structured table rows preserve escaped pipes and neighboring text',()=>{
  assert.deepEqual(chatMarkdownBlocks('Before\n\n| PR | 판단 |\n|---|:---:|\n| #332 | 수정 \\| 필요 |\n\nAfter'),[
    {text:'Before\n'}, {header:['PR','판단'],rows:[['#332','수정 | 필요']]}, {text:'\nAfter'},
  ]);
});

test('a flattened PR table is restored only when its column count is consistent',()=>{
  const table='\\| PR | 판단 | 이유 | |---|---|---| | [#332](https://github.com/a/b/pull/332 "https://github.com/a/b/pull/332") | 수정 필요 | 누락 확인 |';
  assert.equal(chatMarkdownBlocks(table)[0].rows[0][1],'수정 필요');
  const ambiguous=table.replace(' | 누락 확인','');
  assert.deepEqual(chatMarkdownBlocks(ambiguous),[{text:ambiguous}]);
});

test('pipe-delimited code remains text',()=>{
  const example='```\n| PR | 판단 |\n|---|---|\n| #332 | 수정 필요 |\n```';
  assert.deepEqual(chatMarkdownBlocks(example),[{text:example}]);
});

test('a Codex memory citation footer is not shown',()=>{
  const footer='\n\n<oai-mem-citation>\n<citation_entries>\nMEMORY.md:3-3|note=[kept]\n</citation_entries>\n<rollout_ids>\n01a196ab\n</rollout_ids>\n</oai-mem-citation>';
  assert.deepEqual(chatMarkdownBlocks('OK를 기록했습니다.'+footer),[{text:'OK를 기록했습니다.'}]);
  assert.deepEqual(chatMarkdownBlocks('끝났습니다.\n<oai-mem-citation>\n<citation_entries>\nMEMORY.md:1-1'),[{text:'끝났습니다.'}]);
});
