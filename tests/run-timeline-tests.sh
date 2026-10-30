#!/bin/sh
set -eu
STUDIO_TEST_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STUDIO_TEST_TEMP=$(mktemp -d)
trap 'rm -rf "$STUDIO_TEST_TEMP"' EXIT HUP INT TERM
mkdir -p "$STUDIO_TEST_TEMP/assets"
cp "$STUDIO_TEST_ROOT/tests/timeline-export.swift" "$STUDIO_TEST_TEMP/main.swift"
python3 - "$STUDIO_TEST_TEMP/assets/voice.wav" <<'PY'
import wave,math,struct,sys
with wave.open(sys.argv[1],'wb') as w:
 w.setparams((1,2,44100,44100,'NONE','not compressed'))
 w.writeframes(b''.join(struct.pack('<h',int(math.sin(i*2*math.pi*440/44100)*1000)) for i in range(44100)))
PY
swiftc -suppress-warnings "$STUDIO_TEST_ROOT/source/Timeline.swift" "$STUDIO_TEST_TEMP/main.swift" -o "$STUDIO_TEST_TEMP/check" -framework Cocoa -framework AVFoundation -framework AVKit
"$STUDIO_TEST_TEMP/check" "$STUDIO_TEST_TEMP"
