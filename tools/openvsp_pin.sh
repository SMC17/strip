#!/usr/bin/env bash
# Reproduce (or check) the OpenVSP 3.42.0 real-export mesh digest pin without CI.
#
#   tools/openvsp_pin.sh            # check: export, digest, compare with the pin
#   tools/openvsp_pin.sh --update   # rewrite openvsp_cmd_mesh_digest in the fixture
#
# Downloads the pinned Ubuntu 24.04 deb, verifies its SHA-256, extracts it
# (no dpkg -i), runs tools/openvsp_box_wing.vspscript with the headless
# `vspscript` binary (or `vsp` under xvfb-run when STRIP_OPENVSP_GUI=1, as CI
# does), refuses any OpenVSP API error, and digests the STL with the Strip Zig
# mesh digest. Needs: curl, dpkg-deb, sha256sum, zig 0.16, and the runtime libs
# the deb links (libcminpack1; plus libglew2.2 / libglu1-mesa / xvfb for `vsp`).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${STRIP_OPENVSP_WORK:-${TMPDIR:-/tmp}/strip-openvsp-3.42.0}"
DEB_URL="https://openvsp.org/download.php?file=zips/old/linux/OpenVSP-3.42.0-Ubuntu-24.04_amd64.deb"
DEB_SHA="53c02bca9ed3c14b1d2c62f5c1f4a0783a3de71d577a7f9e396fd022bc7bc262"
PIN="$ROOT/fixtures/validation/openvsp/export-conformance.json"
mkdir -p "$WORK"
if [[ ! -f "$WORK/openvsp.deb" ]]; then curl -fsSL -o "$WORK/openvsp.deb" "$DEB_URL"; fi
echo "$DEB_SHA  $WORK/openvsp.deb" | sha256sum -c - >/dev/null
[[ -d "$WORK/root/opt/OpenVSP" ]] || dpkg-deb -x "$WORK/openvsp.deb" "$WORK/root"
BIN="$WORK/root/opt/OpenVSP/vspscript"
RUN=("$BIN")
if [[ "${STRIP_OPENVSP_GUI:-0}" == "1" ]]; then BIN="$WORK/root/opt/OpenVSP/vsp"; RUN=(xvfb-run -a "$BIN"); fi
missing="$(ldd "$BIN" | grep 'not found' || true)"
if [[ -n "$missing" ]]; then echo "missing shared libraries for $BIN:"; echo "$missing"; exit 2; fi

STL="$WORK/strip-openvsp-pin.stl"
rm -f "$STL"
sed "s#__OUTPUT_PATH__#$STL#" "$ROOT/tools/openvsp_box_wing.vspscript" > "$WORK/pin.vspscript"
set +e
OUT="$(cd "$WORK" && "${RUN[@]}" -script "$WORK/pin.vspscript" 2>&1)"
RC=$?
set -e
if [[ $RC -ne 0 ]]; then echo "$OUT" | tail -5; echo "openvsp exited $RC: refusing to pin"; exit 1; fi
if grep -q "Error Code:\|strip_vsp_api_error:" <<<"$OUT"; then echo "$OUT" | grep "Error Code:\|strip_vsp_api_error:"; echo "OpenVSP API errors: refusing to pin"; exit 1; fi
grep -q "strip_vsp_export_ok" <<<"$OUT" || { echo "$OUT"; echo "export marker missing"; exit 1; }
[[ -s "$STL" ]] || { echo "no STL written"; exit 1; }
echo "openvsp exit code: $RC (marker present, 0 API errors)"

(cd "$ROOT" && zig build -Doptimize=ReleaseSafe >/dev/null)
DIGEST="$("$ROOT/zig-out/bin/strip-mesh-digest" "$STL" | head -n1)"
"$ROOT/zig-out/bin/strip-mesh-digest" "$STL" | tail -n +2
EXPECTED="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["openvsp_cmd_mesh_digest"])' "$PIN")"
echo "digest:   $DIGEST"
echo "pinned:   $EXPECTED"
if [[ "${1:-}" == "--update" && "$DIGEST" != "$EXPECTED" ]]; then
  python3 - "$PIN" "$EXPECTED" "$DIGEST" <<'PY'
import sys
from pathlib import Path
p, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
p.write_text(p.read_text().replace(old, new))
PY
  sed -i "s/$EXPECTED/$DIGEST/" "$ROOT/apps/strip_verify.zig"
  echo "pin updated (fixture + apps/strip_verify.zig)"
elif [[ "$DIGEST" != "$EXPECTED" ]]; then
  echo "MISMATCH"; exit 1
else
  echo "pin matches"
fi
