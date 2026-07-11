#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${STRIP_PX4_IMAGE:-jonasvautherin/px4-gazebo-headless:1.14.0}"
NAME="${STRIP_PX4_NAME:-strip-px4-sitl}"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --network host -e HEADLESS=1 "$IMG" >/dev/null
echo "waiting for px4 mavlink ports..."
for i in $(seq 1 90); do
  if ss -uln | rg -q ':13030|:14280|:14580'; then break; fi
  sleep 2
done
BIN="$ROOT/zig-out/bin/strip-mavlink-sitl"
[[ -x "$BIN" ]] || (cd "$ROOT" && zig build)
sleep 5
"$BIN" udp --host 127.0.0.1 --port 13030 || "$BIN" udp --host 127.0.0.1
