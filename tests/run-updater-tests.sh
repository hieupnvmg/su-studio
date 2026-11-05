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
precondition(AppUpdater.cleanNotes(["  Một  ", "", "Hai"]) == ["Một", "Hai"])
precondition(AppUpdater.cleanNotes("## Sử Studio\n\n- Sao lưu dự án\n* Khôi phục\nKhông phải mục") == ["Sao lưu dự án", "Khôi phục"])
precondition(AppUpdater.cleanNotes(42).isEmpty && AppUpdater.cleanNotes(Array(repeating: "x", count: 50)).count == 30)
print("Updater version and release-notes tests passed")
SWIFT
swift "$STUDIO_TEST"
