import {test} from 'node:test';
import assert from 'node:assert/strict';
import {stickyScroll} from '../Resources/web/chat-scroll.js';

function fakeBox(height = 1000, view = 300) {
  const listeners = {};
  let top = height - view;
  const box = {scrollHeight:height, clientHeight:view,
    get scrollTop() { return top; },
    set scrollTop(value) { top = Math.max(0, Math.min(value, this.scrollHeight - this.clientHeight)); },   // as browsers clamp it
    addEventListener:(name, fn) => { (listeners[name] ||= []).push(fn); },
    fire:name => (listeners[name] || []).forEach(fn => fn()),
    userScroll(top) { this.scrollTop = top; this.fire('scroll'); },
    grow(by) { this.scrollHeight += by; }};
  return box;
}
const atBottom = box => box.scrollHeight - box.scrollTop - box.clientHeight;

test('while at the bottom, new content keeps the view at the bottom', () => {
  const box = fakeBox(); const s = stickyScroll(box);
  box.grow(200); s.contentChanged(true);
  assert.equal(atBottom(box), 0);
  assert.equal(s.state().unseen, false);
});

test('after scrolling up, new content leaves the view alone and shows the button with a new-message mark', () => {
  const box = fakeBox(); const states = [];
  const s = stickyScroll(box, {onState:state => states.push(state)});
  box.userScroll(100);
  assert.deepEqual(s.state(), {stuck:false, unseen:false});
  box.grow(200); s.contentChanged(true);
  assert.equal(box.scrollTop, 100);
  assert.deepEqual(s.state(), {stuck:false, unseen:true});
  assert.deepEqual(states.at(-1), {stuck:false, unseen:true});
});

test('a height change that is not a new message never marks unseen', () => {
  const box = fakeBox(); const s = stickyScroll(box);
  box.userScroll(100); box.grow(50); s.contentChanged(false);
  assert.equal(s.state().unseen, false);
});

test('toBottom (send, the button, a switched conversation) jumps down and sticks again', () => {
  const box = fakeBox(); const s = stickyScroll(box);
  box.userScroll(100); box.grow(200); s.contentChanged(true);
  s.toBottom();
  assert.equal(atBottom(box), 0);
  assert.deepEqual(s.state(), {stuck:true, unseen:false});
  box.grow(80); s.contentChanged(true);
  assert.equal(atBottom(box), 0);
});

test('scrolling back near the bottom by hand sticks again and clears the mark', () => {
  const box = fakeBox(); const s = stickyScroll(box);
  box.userScroll(100); box.grow(100); s.contentChanged(true);
  box.userScroll(box.scrollHeight - box.clientHeight - 20);
  assert.deepEqual(s.state(), {stuck:true, unseen:false});
});

test('an image that finishes loading keeps a stuck view at the bottom', () => {
  const box = fakeBox(); stickyScroll(box);
  box.grow(120); box.fire('load');
  assert.equal(atBottom(box), 0);
});
