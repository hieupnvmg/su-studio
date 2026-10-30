#!/bin/sh
set -eu
STUDIO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$STUDIO_ROOT/.build"
STUDIO_TEST=$(mktemp "$STUDIO_ROOT/.build/updater-test.XXXXXX.swift")
trap 'rm -f "$STUDIO_TEST"' EXIT HUP INT TERM
cat "$STUDIO_ROOT/source/AppUpdater.swift" > "$STUDIO_TEST"
cat >> "$STUDIO_TEST" <<'SWIFT'
precondition(AppUpdater.newer("v0.2.1", than: "0.2.0"))
precondition(AppUpdater.newer("0.10.0", than: "0.2.1"))
precondition(!AppUpdater.newer("0.2.1", than: "0.2.1"))
precondition(!AppUpdater.newer("0.1.0", than: "0.2.1"))
precondition(!AppUpdater.newer("bad", than: "0.1.0"))
precondition(!AppUpdater.newer("1.0.0-beta", than: "0.1.0"))
print("Updater version tests passed")
SWIFT
swift "$STUDIO_TEST"
