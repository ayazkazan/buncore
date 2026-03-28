#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

./zig-out/bin/bpm2 kill >/dev/null 2>&1 || true
pkill -9 -f "$ROOT/zig-out/bin/bpm2d" >/dev/null 2>&1 || true
pkill -9 -f "$ROOT/fixtures/test-app.ts" >/dev/null 2>&1 || true
pkill -9 -f "$ROOT/fixtures/worker.ts" >/dev/null 2>&1 || true
pkill -9 -f "fixtures/test-app.ts" >/dev/null 2>&1 || true
pkill -9 -f "fixtures/worker.ts" >/dev/null 2>&1 || true
rm -f "$HOME/.bpm2/daemon.json" "$HOME/.bpm2/state.json"

echo "[smoke] build"
zig build >/dev/null

echo "[smoke] start worker instances"
./zig-out/bin/bpm2 start fixtures/worker.ts --name worker --instances 2 >/dev/null
sleep 2
./zig-out/bin/bpm2 list

echo "[smoke] all-target operations"
./zig-out/bin/bpm2 restart all >/dev/null 2>&1
sleep 2
./zig-out/bin/bpm2 flush all >/dev/null 2>&1

echo "[smoke] save/stop/resurrect"
./zig-out/bin/bpm2 save >/dev/null 2>&1
./zig-out/bin/bpm2 stop worker-0 >/dev/null 2>&1
./zig-out/bin/bpm2 resurrect >/dev/null 2>&1
sleep 2
./zig-out/bin/bpm2 list

echo "[smoke] watch restart"
./zig-out/bin/bpm2 start fixtures/test-app.ts --name watch-app --watch --watch-path fixtures >/dev/null 2>&1
sleep 2
BEFORE="$(./zig-out/bin/bpm2 info watch-app 2>&1 | awk '/PID:/ {print $2}')"
touch fixtures/test-app.ts
sleep 3
AFTER="$(./zig-out/bin/bpm2 info watch-app 2>&1 | awk '/PID:/ {print $2}')"
if [[ "$BEFORE" == "$AFTER" ]]; then
  echo "watch did not restart process" >&2
  exit 1
fi

echo "[smoke] heap/profile"
./zig-out/bin/bpm2 heap watch-app >/dev/null 2>&1
./zig-out/bin/bpm2 heap-analyze watch-app >/dev/null 2>&1
./zig-out/bin/bpm2 profile watch-app --duration 1 >/dev/null 2>&1

echo "[smoke] dashboard"
./zig-out/bin/bpm2 dashboard
curl --max-time 3 -s http://127.0.0.1:9716/api/processes >/dev/null

echo "[smoke] shutdown"
./zig-out/bin/bpm2 kill >/dev/null 2>&1
sleep 1
if ps -ef | grep -v grep | grep -E "bpm2d|fixtures/test-app.ts|fixtures/worker.ts" >/dev/null; then
  echo "process cleanup failed" >&2
  exit 1
fi

echo "[smoke] ok"
