#!/bin/sh
set -eu
STUDIO_TEST_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STUDIO_TEST_TEMP=$(mktemp -d)
trap 'rm -rf "$STUDIO_TEST_TEMP"' EXIT HUP INT TERM
cp "$STUDIO_TEST_ROOT/tests/remotion-maps.swift" "$STUDIO_TEST_TEMP/main.swift"
swiftc -suppress-warnings "$STUDIO_TEST_ROOT/source/RemotionMaps.swift" "$STUDIO_TEST_TEMP/main.swift" -o "$STUDIO_TEST_TEMP/check"
"$STUDIO_TEST_TEMP/check" "$STUDIO_TEST_TEMP/work" "$STUDIO_TEST_ROOT/source/remotion-map"
