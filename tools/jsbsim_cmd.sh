#!/usr/bin/env bash
# Resolves JSBSim subprocess queries for Strip protocol (atmosphere + fixed-wing).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBCMD="${1:-}"
case "${SUBCMD}" in
  atmosphere)
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsbsim' >/dev/null 2>&1; then
      exec python3 "${SCRIPT_DIR}/jsbsim_atmosphere.py" atmosphere
    fi
    if [[ -n "${STRIP_JSBSIM_SHIM:-}" && -x "${STRIP_JSBSIM_SHIM}" ]]; then
      exec "${STRIP_JSBSIM_SHIM}" atmosphere
    fi
    ;;
  fixed-wing)
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsbsim' >/dev/null 2>&1; then
      exec python3 "${SCRIPT_DIR}/jsbsim_fixed_wing.py" fixed-wing
    fi
    if [[ -n "${STRIP_JSBSIM_SHIM:-}" && -x "${STRIP_JSBSIM_SHIM}" ]]; then
      exec "${STRIP_JSBSIM_SHIM}" fixed-wing
    fi
    ;;
  coefficients)
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsbsim' >/dev/null 2>&1; then
      exec python3 "${SCRIPT_DIR}/jsbsim_coefficients.py" coefficients
    fi
    ;;
esac
exit 127
