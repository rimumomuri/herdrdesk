#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
files = []
for path in sorted(root.rglob('*')):
    if not path.is_file():
        continue
    relative = path.relative_to(root)
    if any(part in {'evidence', '.build', '.swiftpm', 'xcuserdata', '.DS_Store'} for part in relative.parts):
        continue
    files.append({'path': str(relative), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
(root / 'evidence/source-manifest.json').write_text(json.dumps({'algorithm': 'SHA256', 'files': files}, indent=2)+'\n')
