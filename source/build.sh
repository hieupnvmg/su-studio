#!/bin/sh
set -eu
STUDIO_SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STUDIO_APP="$STUDIO_SOURCE/../HistoryStudio.app"
if /usr/bin/pgrep -x HistoryStudio >/dev/null; then
    echo "Đóng Sử Studio trước khi cập nhật. Không ghi đè app đang chạy vì sẽ làm lỗi quyền Keychain." >&2
    exit 78
fi
STUDIO_WORK="$STUDIO_SOURCE/../.build"
mkdir -p "$STUDIO_WORK"
STUDIO_TEMP=$(mktemp -d "$STUDIO_WORK/studio-build.XXXXXX")
trap 'rm -rf "$STUDIO_TEMP"' EXIT HUP INT TERM
STUDIO_BUILD="$STUDIO_TEMP/HistoryStudio.app"
mkdir -p "$STUDIO_BUILD/Contents/MacOS" "$STUDIO_BUILD/Contents/Resources"
swiftc -target "$(uname -m)-apple-macos13.0" "$STUDIO_SOURCE/Main.swift" "$STUDIO_SOURCE/CredentialStore.swift" "$STUDIO_SOURCE/CodexConnection.swift" "$STUDIO_SOURCE/AssistantPlan.swift" "$STUDIO_SOURCE/AssistantProgress.swift" "$STUDIO_SOURCE/PlenXProbe.swift" "$STUDIO_SOURCE/ElevenLabsProbe.swift" "$STUDIO_SOURCE/ElevenLabsTTS.swift" "$STUDIO_SOURCE/NarrationPlayer.swift" "$STUDIO_SOURCE/AppUpdater.swift" "$STUDIO_SOURCE/Timeline.swift" -o "$STUDIO_BUILD/Contents/MacOS/HistoryStudio" -framework Cocoa -framework WebKit -framework Security -framework AVFoundation -framework AVKit
cp "$STUDIO_SOURCE/visual-bible.js" "$STUDIO_BUILD/Contents/Resources/"
cp "$STUDIO_SOURCE/auto-tags.js" "$STUDIO_BUILD/Contents/Resources/"
cp "$STUDIO_SOURCE/media-studio.js" "$STUDIO_BUILD/Contents/Resources/"
cp "$STUDIO_SOURCE/Info.plist" "$STUDIO_BUILD/Contents/Info.plist"
cp "$STUDIO_SOURCE/base.css" "$STUDIO_SOURCE/ui.css" "$STUDIO_SOURCE/ui.js" "$STUDIO_BUILD/Contents/Resources/"
cp "$STUDIO_SOURCE/index.html" "$STUDIO_SOURCE/assistant.js" "$STUDIO_SOURCE/assistant-progress.js" "$STUDIO_SOURCE/model-picker.js" "$STUDIO_SOURCE/native-editor.js" "$STUDIO_SOURCE/tts.js" "$STUDIO_SOURCE/reference-images.js" "$STUDIO_SOURCE/updater.js" "$STUDIO_SOURCE/tts-batch.js" "$STUDIO_SOURCE/narration-player.js" "$STUDIO_SOURCE/script-import.js" "$STUDIO_SOURCE/demo.json" "$STUDIO_SOURCE/import_storyboard.py" "$STUDIO_BUILD/Contents/Resources/"
cp -R "$STUDIO_SOURCE/assets" "$STUDIO_BUILD/Contents/Resources/"
cp "$STUDIO_SOURCE/assets/AppIcon.icns" "$STUDIO_BUILD/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$STUDIO_BUILD"
codesign --verify --deep --strict "$STUDIO_BUILD"
if /usr/bin/pgrep -x HistoryStudio >/dev/null; then
    echo "Sử Studio vừa được mở. Đóng app và chạy build lại để cập nhật an toàn." >&2
    exit 78
fi
if [ -d "$STUDIO_APP" ]; then mv "$STUDIO_APP" "$STUDIO_TEMP/previous.app"; fi
if ! mv "$STUDIO_BUILD" "$STUDIO_APP"; then
    if [ -d "$STUDIO_TEMP/previous.app" ]; then mv "$STUDIO_TEMP/previous.app" "$STUDIO_APP"; fi
    exit 1
fi
