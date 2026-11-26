import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readableBody } from '../Resources/web/handoff-chain.js';

test('a dense report breaks into one sentence per line', () => {
  assert.equal(readableBody('同DogRow実型の合成だけ補完。bundle確認→正常exit0、原v4不変。'), '同DogRow実型の合成だけ補完。\nbundle確認→正常exit0、原v4不変。');
  assert.equal(readableBody('25자입니다. UI입력을 분리해주세요. 끝'), '25자입니다.\nUI입력을 분리해주세요.\n끝');
  assert.equal(readableBody('Done? Yes! Next step'), 'Done?\nYes!\nNext step');
});

test('numbers, file names and links keep their dots', () => {
  const text = 'PR-INPUT.ja.md 및 v0.1.2 확인, http://127.0.0.1:61417/ 열림';
  assert.equal(readableBody(text), text);
});

test('existing line breaks stay and no blank lines pile up', () => {
  assert.equal(readableBody('첫 줄.\n둘째 줄。 셋째'), '첫 줄.\n둘째 줄。\n셋째');
  assert.equal(readableBody(''), '');
});

test('code keeps its indentation and fenced blocks are left alone', () => {
  assert.equal(readableBody('Run this. Then:\nif ready:\n    deploy()'), 'Run this.\nThen:\nif ready:\n    deploy()');
  assert.equal(readableBody('```\na. b. c\n```\nDone. Next'), '```\na. b. c\n```\nDone.\nNext');
});
