import { readFileSync, writeFileSync } from 'node:fs';

const folder = new URL('../Resources/web/', import.meta.url);
const files = ['locale.js', 'model.js', 'waiting-inbox.js', 'lineage.js', 'message-tags.js', 'trouble.js', 'sound-rules.js', 'computers.js', 'handoff-chain.js', 'team-flow.js', 'chat-sections.js', 'task-board.js', 'chat-questions.js', 'composer.js', 'motion.js', 'chat-scroll.js', 'compatibility.js', 'keys.js', 'terminal-view.js', 'portrait.js', 'herd-face.js', 'chat-shortcuts.js', 'chat-markdown.js', 'md-view.js', 'role-look.js', 'chat-images.js', 'recovery.js', 'triage.js', 'palette.js', 'sheep.js', 'companion.js', 'app.js'];
const bundle = (list, out) => writeFileSync(new URL(out, folder), '(() => {\n"use strict";\n' + list.map(file => readFileSync(new URL(file, folder), 'utf8')
  .replace(/^import .*;\n/gm, '')
  .replace(/^export /gm, '')).join('\n') + '\n})();\n');
bundle(files, 'bundle.js');
// The floating companion window: its own small page, never app.js.
bundle(['sheep.js', 'portrait.js', 'herd-face.js', 'companion-page.js'], 'companion-bundle.js');
