#!/usr/bin/env bash
# Fetch the Flight Review public fixed-wing ULog used for px4-public-fixedwing-export.csv
set -euo pipefail
UUID="${1:-0316157c-5f88-433b-8bab-c690fd0b24fb}"
EXPECT_SHA="${2:-c618ae05cffefff1fe1428fea4086e4772f3d9cd9ae0249cca15eda3bfebad9c}"
DIR="${STRIP_FLIGHT_LOG_CACHE:-$HOME/.cache/strip/flight-logs}"
mkdir -p "$DIR"
OUT="$DIR/px4-public-fixedwing-${UUID%%-*}.ulg"
# keep stable name for provenance
OUT="$DIR/px4-public-fixedwing-0316157c.ulg"
URL="https://logs.px4.io/download?log=${UUID}"
if [[ -f "$OUT" ]]; then
  GOT=$(sha256sum "$OUT" | awk '{print $1}')
  if [[ "$GOT" == "$EXPECT_SHA" ]]; then
    echo "cached ok $OUT"
    exit 0
  fi
fi
curl -fsL -o "$OUT.partial" "$URL"
mv "$OUT.partial" "$OUT"
GOT=$(sha256sum "$OUT" | awk '{print $1}')
if [[ "$GOT" != "$EXPECT_SHA" ]]; then
  echo "sha256 mismatch: got $GOT want $EXPECT_SHA" >&2
  exit 1
fi
echo "fetched $OUT"
echo "convert: python3 tools/ulog_to_strip_csv.py $OUT -o fixtures/validation/flight-test/px4-public-fixedwing-export.csv"
