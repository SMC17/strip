# Promote CI-recorded replay baselines into the cross-target manifest.
# Usage:
#   ./zig-out/bin/strip-record-replay-baseline > baseline.json
#   cat baseline.json | ./zig-out/bin/strip-promote-replay-baseline > fixtures/validation/replay/rk4-cross-target.json

set -euo pipefail
BASELINE="${1:?usage: promote_replay_from_ci.sh baseline.json}"
zig build -q
./zig-out/bin/strip-promote-replay-baseline < "${BASELINE}" > fixtures/validation/replay/rk4-cross-target.json
zig build run-proof-gates
