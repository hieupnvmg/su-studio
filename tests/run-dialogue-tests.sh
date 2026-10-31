#!/bin/sh
set -eu
STUDIO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STUDIO_TEMP=$(mktemp -d)
trap 'rm -rf "$STUDIO_TEMP"' EXIT HUP INT TERM
cp "$STUDIO_ROOT/tests/dialogue.swift" "$STUDIO_TEMP/main.swift"
swiftc "$STUDIO_ROOT/source/ElevenLabsTTS.swift" "$STUDIO_TEMP/main.swift" -o "$STUDIO_TEMP/check"
"$STUDIO_TEMP/check"
