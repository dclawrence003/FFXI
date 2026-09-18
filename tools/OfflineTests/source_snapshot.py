"""Fingerprint public source used by an offline run; no installed files read."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
result = subprocess.run(['git', '-C', str(root), 'ls-files', '-z', '--cached',
                         '--others', '--exclude-standard'], capture_output=True, check=True)
files = {}
for name in sorted(set(result.stdout.decode('utf-8').split('\0')) - {''}):
    if not name.startswith(('addons/', 'patches/', 'tools/', '.github/')):
        continue
    path = root / name
    if path.is_symlink():
        raise RuntimeError(f'Source symlink needs explicit treatment: {name}')
    if path.is_file():
        files[name] = hashlib.sha256(path.read_bytes()).hexdigest()
commit = subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'],
                        capture_output=True, text=True, check=True).stdout.strip()
manifest = {'format': 'ffxi-offline-source-snapshot-v1', 'commit': commit,
            'files_sha256': files, 'installed_files_read': False}
Path(sys.argv[1]).write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
