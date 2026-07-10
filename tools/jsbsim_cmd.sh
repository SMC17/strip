#!/usr/bin/env bash
# Resolves JSBSim atmosphere queries for Strip subprocess protocol.
set -euo pipefail
if [[ "${1:-}" != "atmosphere" ]]; then
  exit 2
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsbsim' >/dev/null 2>&1; then
  exec python3 "${SCRIPT_DIR}/jsbsim_atmosphere.py" atmosphere
fi
if [[ -n "${STRIP_JSBSIM_SHIM:-}" && -x "${STRIP_JSBSIM_SHIM}" ]]; then
  exec "${STRIP_JSBSIM_SHIM}" atmosphere
fi
exit 127
