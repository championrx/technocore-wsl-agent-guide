#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <receipt.json>"
  exit 1
fi

RECEIPT="$1"

if [ ! -f "$RECEIPT" ]; then
  echo "Receipt not found: $RECEIPT"
  exit 1
fi

for cmd in jq sha256sum python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing dependency: $cmd"
    exit 1
  }
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="$SCRIPT_DIR/verify-technocore-receipt.py"

if [ ! -x "$VERIFIER" ]; then
  echo "Verifier not found or not executable: $VERIFIER"
  exit 1
fi

VERIFY_OUTPUT="$(python3 "$VERIFIER" "$RECEIPT")"

if [[ "$VERIFY_OUTPUT" != VALID:* ]]; then
  echo "$VERIFY_OUTPUT"
  echo "Receipt verification failed."
  exit 1
fi

SEQ="$(jq -r '.sequence // "unknown"' "$RECEIPT")"
ROOM="$(jq -r '.room' "$RECEIPT")"
NONCE="$(jq -r '.nonce' "$RECEIPT")"
DID="$(jq -r '.did' "$RECEIPT")"
URL="$(jq -r '.contribution_url' "$RECEIPT")"
TEXT="$(jq -r '.exact_signed_text' "$RECEIPT")"
SIGNATURE="$(jq -r '.signature' "$RECEIPT")"
RECORDED_AT="$(jq -r '.recorded_at' "$RECEIPT")"
RECEIPT_SHA256="$(sha256sum "$RECEIPT" | awk '{print $1}')"

OUT_DIR="${TECHNOCORE_PROOF_DIR:-$HOME/.local/share/technocore/proofs}"
mkdir -p "$OUT_DIR"

BASENAME="technocore-proof-${SEQ}"
OUT_FILE="$OUT_DIR/${BASENAME}.json"

jq -n \
  --arg sequence "$SEQ" \
  --arg room "$ROOM" \
  --arg nonce "$NONCE" \
  --arg did "$DID" \
  --arg contribution_url "$URL" \
  --arg exact_signed_text "$TEXT" \
  --arg signature "$SIGNATURE" \
  --arg recorded_at "$RECORDED_AT" \
  --arg verification "$VERIFY_OUTPUT" \
  --arg receipt_sha256 "$RECEIPT_SHA256" \
  '{
    sequence: $sequence,
    room: $room,
    nonce: $nonce,
    did: $did,
    contribution_url: $contribution_url,
    exact_signed_text: $exact_signed_text,
    signature: $signature,
    recorded_at: $recorded_at,
    verification: $verification,
    receipt_sha256: $receipt_sha256
  }' > "$OUT_FILE"

echo "Proof bundle created successfully."
echo "Sequence: $SEQ"
echo "DID: $DID"
echo "Verification: $VERIFY_OUTPUT"
echo "Bundle: $OUT_FILE"
