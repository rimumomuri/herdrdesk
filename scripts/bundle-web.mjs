import { readFileSync, writeFileSync } from 'node:fs';

const folder = new URL('../Resources/web/', import.meta.url);
const files = ['locale.js', 'model.js', 'waiting-inbox.js', 'lineage.js', 'message-tags.js', 'sound-rules.js', 'computers.js', 'handoff-chain.js', 'chat-sections.js', 'task-board.js', 'chat-questions.js', 'composer.js', 'motion.js', 'chat-scroll.js', 'compatibility.js', 'keys.js', 'terminal-view.js', 'portrait.js', 'chat-shortcuts.js', 'chat-markdown.js', 'chat-images.js', 'app.js'];
const bundled = files.map(file => readFileSync(new URL(file, folder), 'utf8')
  .replace(/^import .*;\n/gm, '')
  .replace(/^export /gm, '')).join('\n');
writeFileSync(new URL('bundle.js', folder), '(() => {\n"use strict";\n'+bundled+'\n})();\n');
