#! /usr/bin/env bash
# Attach trajectory.evidence/receipt.json into a stax-experiment verdict --evidence string.
set -euo pipefail
REC="${1:-trajectory.evidence/receipt.json}"
ID="${2:?usage: attach_receipt_evidence.sh <receipt.json> <exp-id> [result]}"
RESULT="${3:-confirmed}"

if [[ ! -f "$REC" ]]; then
  echo "missing receipt: $REC" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  DIGEST=$(jq -r '.content_sha256 // empty' "$REC")
  SCHEMA=$(jq -r '.schema // empty' "$REC")
else
  DIGEST=$(grep -o '"content_sha256":"[^"]*"' "$REC" | head -1 | sed 's/.*"content_sha256":"\([^"]*\)".*/\1/')
  SCHEMA=$(grep -o '"schema":"[^"]*"' "$REC" | head -1 | sed 's/.*"schema":"\([^"]*\)".*/\1/')
fi

ABS=$(realpath "$REC")
EVIDENCE="receipt_path=${ABS} content_sha256=${DIGEST} schema=${SCHEMA}"
exec stax-experiment verdict --id "$ID" --result "$RESULT" --evidence "$EVIDENCE"
