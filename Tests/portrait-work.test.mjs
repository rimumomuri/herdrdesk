import assert from 'node:assert/strict';
import { test } from 'node:test';
import { portraitArtwork, withWorkTool, sheepStyles, sheepCoats, sheepAccessories } from '../Resources/web/portrait.js';

test('working portrait gets a hammer inside the portrait and a working flag', () => {
  const html = withWorkTool(portraitArtwork('codex', true));
  assert.match(html, /^<span class="agent-portrait" data-working /);
  assert.match(html, /<\/svg><svg class="hr-tool"[^]*<\/svg><\/span>$/);
  assert.equal((html.match(/class="hr-tool"/g) || []).length, 1);
});

test('empty or non-portrait markup is left alone', () => {
  assert.equal(withWorkTool(''), '');
  assert.equal(withWorkTool('<span class="avatar">A</span>'), '<span class="avatar">A</span>');
});

test('a sleeping portrait keeps its open mouth in a group the UI can hide', () => {
  const html = portraitArtwork('neutral', false, 'lamb', 'cream', false, 'none', true);
  assert.match(html, /data-sleep="true"/);
  assert.match(html, /<g class="portrait-mouth-open">/);
  assert.match(html, /class="portrait-zz"/);
  assert.match(portraitArtwork('codex', false), /data-sleep="false"/);
});

test('a working orbit runs faster and leaves a trail', () => {
  const html = portraitArtwork('neutral', true, 'marshmallow');
  assert.match(html, /dur="1.4s"/);
  assert.match(html, /class="portrait-trail"/);
});

test('approved default artwork uses one atlas row per provider and three state viewports', () => {
  const codex = portraitArtwork('codex', true);
  const claude = portraitArtwork('claude', true);
  for (const html of [codex, claude]) {
    assert.match(html, /data-artwork="minimal-v5"/);
    assert.equal((html.match(/class="portrait-frame /g) || []).length, 3);
    assert.match(html, /icons\/sheep-minimal-v5.png/);
    assert.match(html, /class="portrait-frame portrait-frame-sleep"/);
    assert.match(html, /class="portrait-frame portrait-frame-wake"/);
  }
  assert.match(codex, /data-atlas-row="0"/);
  assert.match(claude, /data-atlas-row="1"/);
  assert.doesNotMatch(portraitArtwork('neutral', true), /data-artwork="minimal-v5"/);
});

test('every saved customization uses the approved face, including the reported purple twin horns', () => {
  for (const provider of ['codex','claude']) for (const style of sheepStyles) for (const coat of sheepCoats.keys()) for (const accessory of sheepAccessories) {
    const html=portraitArtwork(provider,false,style,coat,false,accessory,true);
    assert.ok(html.includes('data-artwork="minimal-v5"'),[provider,style,coat,accessory].join('/'));
    assert.ok(html.includes('data-sheep="'+style+'"'));
    assert.ok(html.includes('data-coat="'+coat+'"'));
    assert.ok(html.includes('data-accessory="'+accessory+'"'));
  }
  const purpleTwin=portraitArtwork('codex',false,'twin','electric',false,'none');
  assert.match(purpleTwin,/portrait-coat-layer/);
  assert.match(purpleTwin,/portrait-style-layer/);
  assert.match(withWorkTool(purpleTwin), /data-working/);
});
