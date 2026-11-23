import {test} from 'node:test';
import assert from 'node:assert/strict';
import {sendBlocked, deferredSaver} from '../Resources/web/composer.js';

test('send is blocked without text or files, while files load, or while a message is sending', () => {
  const base = {inputDisabled:false, text:'hi', files:0, loadingFiles:0, sending:false};
  assert.equal(sendBlocked(base), false);
  assert.equal(sendBlocked({...base, text:'  '}), true);
  assert.equal(sendBlocked({...base, text:'', files:1}), false);
  assert.equal(sendBlocked({...base, loadingFiles:1}), true);
  assert.equal(sendBlocked({...base, sending:true}), true);
  assert.equal(sendBlocked({...base, inputDisabled:true}), true);
});

function fakeTimers() {
  let next = 1; const pending = new Map();
  return {set:(fn) => { const id = next++; pending.set(id, fn); return id; }, clear:id => pending.delete(id),
          run:() => { const fns = [...pending.values()]; pending.clear(); fns.forEach(fn => fn()); }, count:() => pending.size};
}

test('typing schedules one save; many keystrokes write once with the latest drafts', () => {
  const timers = fakeTimers(); const writes = [];
  const saver = deferredSaver(() => writes.push('saved'), 400, timers);
  saver.schedule(); saver.schedule(); saver.schedule();
  assert.equal(timers.count(), 1);
  assert.deepEqual(writes, []);
  timers.run();
  assert.deepEqual(writes, ['saved']);
});

test('flush writes a pending save right away and only once', () => {
  const timers = fakeTimers(); const writes = [];
  const saver = deferredSaver(() => writes.push('saved'), 400, timers);
  saver.flush();
  assert.deepEqual(writes, [], 'nothing pending, nothing written');
  saver.schedule(); saver.flush();
  assert.deepEqual(writes, ['saved']);
  timers.run();
  assert.deepEqual(writes, ['saved']);
});
