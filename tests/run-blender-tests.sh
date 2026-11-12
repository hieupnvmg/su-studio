#!/bin/sh
set -eu
STUDIO_TEST_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STUDIO_TEST_TEMP=$(mktemp -d)
trap 'rm -rf "$STUDIO_TEST_TEMP"' EXIT HUP INT TERM
# The driver's script checker runs with plain Python; Blender itself is not needed.
python3 "$STUDIO_TEST_ROOT/tests/blender-script-check.py" "$STUDIO_TEST_ROOT/source/blender_render.py"
FAKE="$STUDIO_TEST_TEMP/Blender.app"; mkdir -p "$FAKE/Contents/MacOS"
cp "$STUDIO_TEST_ROOT/tests/fixtures/fake-blender.sh" "$FAKE/Contents/MacOS/Blender"; chmod +x "$FAKE/Contents/MacOS/Blender"
cp "$STUDIO_TEST_ROOT/tests/blender-render.swift" "$STUDIO_TEST_TEMP/main.swift"
swiftc -suppress-warnings "$STUDIO_TEST_ROOT/source/BlenderRender.swift" "$STUDIO_TEST_TEMP/main.swift" -o "$STUDIO_TEST_TEMP/check" -framework Cocoa -framework AVFoundation
mkdir -p "$STUDIO_TEST_TEMP/work"
"$STUDIO_TEST_TEMP/check" "$STUDIO_TEST_TEMP/work" "$FAKE" "$STUDIO_TEST_ROOT/source/blender_render.py"
# Both build paths must ship the driver script and the Swift renderer.
grep -q 'blender_render.py' "$STUDIO_TEST_ROOT/source/build.sh"
grep -q 'BlenderRender.swift' "$STUDIO_TEST_ROOT/source/build.sh"
grep -q 'blender_render.py' "$STUDIO_TEST_ROOT/source/package-dmg.sh"
echo "Blender packaging check passed: build.sh and package-dmg.sh ship the driver"
