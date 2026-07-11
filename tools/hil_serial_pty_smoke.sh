#!/usr/bin/env bash
# Real serial/UART HIL over a socat PTY pair (no USB dongle required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
A="${STRIP_HIL_PTY_A:-/tmp/strip-hil-a}"
B="${STRIP_HIL_PTY_B:-/tmp/strip-hil-b}"
rm -f "$A" "$B"
socat -d -d pty,raw,echo=0,link="$A" pty,raw,echo=0,link="$B" >/tmp/strip-hil-socat.log 2>&1 &
SOCAT_PID=$!
cleanup() { kill "$SOCAT_PID" 2>/dev/null || true; rm -f "$A" "$B"; }
trap cleanup EXIT
sleep 0.3
test -e "$A" && test -e "$B"

BIN_HIL="$ROOT/zig-out/bin/strip-hil-bench"
BIN_TRAJ="$ROOT/zig-out/bin/strip-trajectory"
[[ -x "$BIN_HIL" ]] || (cd "$ROOT" && zig build)

"$BIN_HIL" serve --serial "$A" --once &
SERV_PID=$!
sleep 0.2
"$BIN_HIL" run --serial "$B"
kill "$SERV_PID" 2>/dev/null || true
wait "$SERV_PID" 2>/dev/null || true

# Also fold into trajectory JSONL
"$BIN_HIL" serve --serial "$A" --once &
SERV_PID=$!
sleep 0.2
"$BIN_TRAJ" hil-stream --serial "$B" --out "$ROOT/trajectory.evidence"
kill "$SERV_PID" 2>/dev/null || true
wait "$SERV_PID" 2>/dev/null || true
echo "serial_pty_hil_ok"
