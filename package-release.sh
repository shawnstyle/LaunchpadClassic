#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
codesign --verify --deep --strict "build/Launchpad Classic.app"
python3 - <<'PACKAGE'
from pathlib import Path
import hashlib, stat, zipfile
app = Path('build/Launchpad Classic.app')
version = '1.2.2'
out = Path('.build/releases') / ('v' + version + '-public')
out.mkdir(parents=True, exist_ok=True)
archive = out / ('Launchpad-Classic-' + version + '-macOS-arm64.zip')
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for path in sorted(app.rglob('*')):
        if path.is_symlink():
            raise SystemExit('Unexpected symbolic link in application bundle')
        if not path.is_file():
            continue
        relative = path.relative_to(app)
        if relative.parts[0] != 'Contents' or any(part.startswith('._') or part == '.DS_Store' for part in relative.parts):
            raise SystemExit('Unexpected metadata in application bundle')
        item = zipfile.ZipInfo((Path(app.name) / relative).as_posix(), date_time=(2020, 1, 1, 0, 0, 0))
        item.create_system = 3
        item.external_attr = (stat.S_IFREG | stat.S_IMODE(path.stat().st_mode)) << 16
        item.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(item, path.read_bytes())
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
(out / 'SHA256SUMS.txt').write_text(digest + '  ' + archive.name + '\n')
print(archive)
print('SHA-256: ' + digest)
PACKAGE
