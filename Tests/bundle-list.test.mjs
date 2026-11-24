import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

test('every module app.js imports is in the bundle list, or the app loads blank', () => {
  const app = readFileSync(new URL('../Resources/web/app.js', import.meta.url), 'utf8');
  const bundler = readFileSync(new URL('../scripts/bundle-web.mjs', import.meta.url), 'utf8');
  const imported = [...app.matchAll(/from '\.\/([\w-]+\.js)'/g)].map(m => m[1]);
  const listed = new Set([...bundler.matchAll(/'([\w-]+\.js)'/g)].map(m => m[1]));
  assert.deepEqual(imported.filter(file => !listed.has(file)), []);
});
