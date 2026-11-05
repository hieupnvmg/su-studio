#!/bin/sh
set -eu
STUDIO_SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$STUDIO_SOURCE/.."
git diff --quiet
git diff --cached --quiet
STUDIO_VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw source/Info.plist)
# Release notes come from source/changelog.js; refuse to release a version without them.
STUDIO_NOTES=$(mktemp)
trap 'rm -f "$STUDIO_NOTES"' EXIT HUP INT TERM
python3 - "$STUDIO_VERSION" "$STUDIO_NOTES" <<'PYNOTES'
import sys,json
from pathlib import Path
v,out=sys.argv[1],sys.argv[2]
text=Path('source/changelog.js').read_text()
data=json.loads(text.split('const appChangelog=',1)[1].split('];',1)[0]+']')
entry=next((e for e in data if e['version']==v),None)
if not entry or not entry.get('items') or not entry.get('date'):
    sys.exit('source/changelog.js needs an entry for '+v+' with a date and at least one item')
lines=['## '+entry.get('title') if entry.get('title') else '## Sử Studio '+v,'']+['- '+i for i in entry['items']]
lines+=['','Cập nhật trong app: Cài đặt & kết nối → Cập nhật Sử Studio. Cài mới: tải file .dmg bên dưới.']
Path(out).write_text('\n'.join(lines)+'\n')
PYNOTES
sh source/package-dmg.sh
git tag "v$STUDIO_VERSION"
git push origin HEAD "v$STUDIO_VERSION"
python3 - "$STUDIO_VERSION" <<'PYJSON'
import sys,json,hashlib
from pathlib import Path
v=sys.argv[1];p=Path('Su-Studio-'+v+'-Universal.zip')
data=json.loads(Path('source/changelog.js').read_text().split('const appChangelog=',1)[1].split('];',1)[0]+']')
entry=next(e for e in data if e['version']==v)
Path('latest.json').write_text(json.dumps({'version':v,'url':'https://github.com/hieupnvmg/su-studio/releases/download/v'+v+'/'+p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'size':p.stat().st_size,'title':entry.get('title',''),'notes':entry['items']},ensure_ascii=False)+'\n')
PYJSON
gh release create "v$STUDIO_VERSION" "Su-Studio-$STUDIO_VERSION-Universal.zip" "Su-Studio-$STUDIO_VERSION-Team-Test-Universal.dmg" latest.json --title "Sử Studio $STUDIO_VERSION" --notes-file "$STUDIO_NOTES"
