import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {recoveryBarHTML, recoverySettingsHTML} from '../Resources/web/recovery.js';

const copy = key => key + ' {n}';
const escape = text => String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const report = (roles, applied = false) => ({at: 't1', applied, ready: roles.every(r => r.action === 'skip'),
  resumable: roles.filter(r => ['resume', 'create'].includes(r.action)).length,
  attention: roles.filter(r => !['skip', 'resume', 'create', 'submitted'].includes(r.action)).length, roles});

test('nothing to recover shows nothing', () => {
  assert.equal(recoveryBarHTML({enabled: false}, {}, copy, escape), '');
  assert.equal(recoveryBarHTML({enabled: true, saved: 3}, {}, copy, escape), '');
  assert.equal(recoveryBarHTML({enabled: true, report: report([{title: 'A', action: 'skip', reason: ''}])}, {}, copy, escape), '');
});

test('conversations left behind offer one recovery button with the count', () => {
  const html = recoveryBarHTML({enabled: true, report: report([{title: 'A', action: 'resume'}, {title: 'B', action: 'create'}, {title: 'C', action: 'skip'}])}, {}, copy, escape);
  assert.match(html, /data-recovery="confirm"/);
  assert.match(html, /recoveryPending/);
  assert.match(html, /<b>2<\/b>/);
});

test('the first click asks once before anything starts', () => {
  const html = recoveryBarHTML({enabled: true, report: report([{title: 'A', action: 'resume'}])}, {confirming: true}, copy, escape);
  assert.match(html, /data-recovery="restore"/);
  assert.match(html, /data-recovery="cancel"/);
  assert.match(html, /<li>A<\/li>/);
});

test('while it runs the bar says so and offers no button', () => {
  const html = recoveryBarHTML({enabled: true, busy: 'restoring', report: report([{title: 'A', action: 'resume'}])}, {}, copy, escape);
  assert.match(html, /recoveryRestoring/);
  assert.doesNotMatch(html, /<button/);
});

test('afterwards it says what came back and what still needs a look, with the reason', () => {
  const done = recoveryBarHTML({enabled: true, report: report([{title: 'A', action: 'skip'}], true)}, {}, copy, escape);
  assert.match(done, /recoveryDone/);
  assert.match(done, /data-recovery="dismiss"/);
  assert.equal(recoveryBarHTML({enabled: true, report: report([{title: 'A', action: 'skip'}], true)}, {dismissed: 't1'}, copy, escape), '');
  const partly = recoveryBarHTML({enabled: true, report: report([{title: 'A', action: 'skip'}, {title: 'B<', action: 'blocked', reason: 'its working folder is missing'}], true)}, {}, copy, escape);
  assert.match(partly, /recoveryAttention/);
  assert.match(partly, /B&lt; · its working folder is missing/);
});

test('a failed check says so', () => {
  assert.match(recoveryBarHTML({enabled: true, error: 'Herdr Core did not answer'}, {}, copy, escape), /Herdr Core did not answer/);
});

test('settings show the automatic save and a check button', () => {
  const html = recoverySettingsHTML({enabled: true, saved: 13, savedAt: '2026-11-27T04:38:00Z'}, copy, escape, () => '13:38');
  assert.match(html, /recoveryAutoSaved/);
  assert.match(html, /13/);
  assert.match(html, /13:38/);
  assert.match(html, /data-recovery="check"/);
  assert.equal(recoverySettingsHTML({enabled: false}, copy, escape, () => ''), '');
});

test('the page has a place for the bar and the settings line, and the bundle includes the module', () => {
  const html = readFileSync(new URL('../Resources/web/index.html', import.meta.url), 'utf8');
  assert.match(html, /id="recoveryBar"/);
  assert.match(html, /id="recoverySettings"/);
  const bundle = readFileSync(new URL('../scripts/bundle-web.mjs', import.meta.url), 'utf8');
  assert.match(bundle, /recovery\.js/);
});
