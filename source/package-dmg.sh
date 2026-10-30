#!/bin/sh
set -eu
STUDIO_SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STUDIO_ROOT=$(CDPATH= cd -- "$STUDIO_SOURCE/.." && pwd)
STUDIO_VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$STUDIO_SOURCE/Info.plist")
mkdir -p "$STUDIO_ROOT/.build"
STUDIO_TEMP=$(mktemp -d "$STUDIO_ROOT/.build/dmg.XXXXXX")
trap 'rm -rf "$STUDIO_TEMP"' EXIT HUP INT TERM
STUDIO_APP="$STUDIO_TEMP/image/HistoryStudio.app"
mkdir -p "$STUDIO_APP/Contents/MacOS" "$STUDIO_APP/Contents/Resources"
cp "$STUDIO_SOURCE/Info.plist" "$STUDIO_APP/Contents/Info.plist"
cp "$STUDIO_SOURCE/base.css" "$STUDIO_SOURCE/ui.css" "$STUDIO_SOURCE/ui.js" "$STUDIO_APP/Contents/Resources/"
cp "$STUDIO_SOURCE"/*.js "$STUDIO_SOURCE/index.html" "$STUDIO_SOURCE/demo.json" "$STUDIO_SOURCE/import_storyboard.py" "$STUDIO_APP/Contents/Resources/"
cp -R "$STUDIO_SOURCE/assets" "$STUDIO_APP/Contents/Resources/"
cp "$STUDIO_SOURCE/assets/AppIcon.icns" "$STUDIO_APP/Contents/Resources/AppIcon.icns"
for STUDIO_ARCH in arm64 x86_64; do
    swiftc -target "$STUDIO_ARCH-apple-macos13.0" "$STUDIO_SOURCE"/*.swift -o "$STUDIO_TEMP/HistoryStudio-$STUDIO_ARCH" -framework Cocoa -framework WebKit -framework Security -framework AVFoundation
done
xcrun lipo -create "$STUDIO_TEMP/HistoryStudio-arm64" "$STUDIO_TEMP/HistoryStudio-x86_64" -output "$STUDIO_APP/Contents/MacOS/HistoryStudio"
codesign --force --sign - "$STUDIO_APP"
codesign --verify --deep --strict "$STUDIO_APP"
STUDIO_ZIP="$STUDIO_ROOT/Su-Studio-$STUDIO_VERSION-Universal.zip"
STUDIO_DMG="$STUDIO_ROOT/Su-Studio-$STUDIO_VERSION-Team-Test-Universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$STUDIO_APP" "$STUDIO_ZIP"
ln -s /Applications "$STUDIO_TEMP/image/Applications"
cp "$STUDIO_ROOT/HUONG-DAN-TEAM-TEST.txt" "$STUDIO_TEMP/image/HUONG-DAN-TEAM-TEST.txt"
hdiutil create -volname "Su Studio $STUDIO_VERSION" -srcfolder "$STUDIO_TEMP/image" -format UDZO -ov "$STUDIO_DMG"
hdiutil verify "$STUDIO_DMG"
shasum -a 256 "$STUDIO_ZIP" > "$STUDIO_ZIP.sha256"
shasum -a 256 "$STUDIO_DMG" > "$STUDIO_DMG.sha256"
