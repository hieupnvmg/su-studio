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
gh release create "v$STUDIO_VERSION" "Su-Studio-$STUDIO_VERSION-Universal.zip" "Su-Studio-$STUDIO_VERSION-Team-Test-Universal.dmg" --title "Sử Studio $STUDIO_VERSION" --notes 'Bản cập nhật Sử Studio cho macOS.'
