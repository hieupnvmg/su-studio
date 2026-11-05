#!/bin/sh
set -eu
STUDIO_TEST_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STUDIO_TEST_TEMP=$(mktemp -d)
trap 'rm -rf "$STUDIO_TEST_TEMP"' EXIT HUP INT TERM
cp "$STUDIO_TEST_ROOT/tests/archive-media.swift" "$STUDIO_TEST_TEMP/main.swift"
swiftc -suppress-warnings "$STUDIO_TEST_ROOT/source/ArchiveMedia.swift" "$STUDIO_TEST_TEMP/main.swift" -o "$STUDIO_TEST_TEMP/check" -framework AVFoundation
"$STUDIO_TEST_TEMP/check" "$STUDIO_TEST_TEMP"
