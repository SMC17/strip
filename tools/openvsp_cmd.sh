#!/usr/bin/env bash
# Resolves OpenVSP mesh export for Strip conformance gates.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" != "export" ]]; then
  exit 2
fi
if [[ -n "${OPENSP_CMD:-}" && -x "${OPENSP_CMD}" ]]; then
  exec python3 "${SCRIPT_DIR}/openvsp_export.py" export
fi
exec python3 "${SCRIPT_DIR}/openvsp_export.py" export
