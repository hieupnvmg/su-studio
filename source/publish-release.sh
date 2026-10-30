#!/bin/sh
set -eu
STUDIO_SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$STUDIO_SOURCE/.."
git diff --quiet
git diff --cached --quiet
STUDIO_VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw source/Info.plist)
sh source/package-dmg.sh
git tag "v$STUDIO_VERSION"
git push origin HEAD "v$STUDIO_VERSION"
python3 - "$STUDIO_VERSION" <<'PYJSON'
import sys,json,hashlib
from pathlib import Path
v=sys.argv[1];p=Path('Su-Studio-'+v+'-Universal.zip')
Path('latest.json').write_text(json.dumps({'version':v,'url':'https://github.com/hieupnvmg/su-studio/releases/download/v'+v+'/'+p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'size':p.stat().st_size})+'\n')
PYJSON
gh release create "v$STUDIO_VERSION" "Su-Studio-$STUDIO_VERSION-Universal.zip" "Su-Studio-$STUDIO_VERSION-Team-Test-Universal.dmg" latest.json --title "Sử Studio $STUDIO_VERSION" --notes 'Bản cập nhật Sử Studio cho macOS.'
