#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "[platform-check] host build"
zig build >/dev/null

echo "[platform-check] macOS cross-build"
zig build -Dtarget=x86_64-macos >/dev/null

echo "[platform-check] Windows cross-build"
zig build -Dtarget=x86_64-windows-gnu >/dev/null

echo "[platform-check] ok"
