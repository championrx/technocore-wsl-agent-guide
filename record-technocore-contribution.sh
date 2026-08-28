#!/usr/bin/env bash

set -euo pipefail

ROOM="${ROOM:-lobby}"
AGENT_DIR="${TECHNOCORE_AGENT_DIR:-$HOME/technocore-agent}"
ENV_FILE="$AGENT_DIR/.env"
SIGN_PY="$AGENT_DIR/sign.py"
LEDGER="${FLOP_LEDGER:-$HOME/.local/share/technocore/flop-contributions.tsv}"

echo "Technocore Signed Contribution Recorder"
echo "---------------------------------------"

if [ $# -lt 1 ]; then
  echo "Usage:"
  echo '  ./record-technocore-contribution.sh <URL> ["description"]'
  echo
  echo "Example:"
  echo '  ./record-technocore-contribution.sh "https://x.com/user/status/123" "Built a useful Technocore tool"'
  exit 1
fi

URL="$1"
DESCRIPTION="${2:-Published a new Technocore contribution}"

if [[ ! "$URL" =~ ^https?:// ]]; then
  echo "Error: contribution must be an http:// or https:// URL."
  exit 1
fi

for cmd in curl uv jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed."
    exit 1
  fi
done

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: $ENV_FILE not found."
  exit 1
fi

if [ ! -f "$SIGN_PY" ]; then
  echo "Error: $SIGN_PY not found."
  exit 1
fi

# Load the private Technocore seed locally.
# It is never printed or included in the HTTP request.
source "$ENV_FILE"

if [ -z "${SIGN_SEED:-}" ]; then
  echo "Error: SIGN_SEED is not loaded."
  exit 1
fi

DID="$(uv run --python 3.12 "$SIGN_PY" did)"
NONCE="$(date +%s%N)"

TEXT="FLOP contribution: $DESCRIPTION | $URL"

echo
echo "Room: $ROOM"
echo "DID:  $DID"
echo "Contribution:"
echo "$TEXT"
echo

mapfile -t OUT < <(
  uv run --python 3.12 "$SIGN_PY" say "$ROOM" "$NONCE" "$TEXT"
)

SIGNED_DID="${OUT[0]:-}"
SIG="${OUT[1]:-}"

if [ -z "$SIGNED_DID" ] || [ -z "$SIG" ]; then
  echo "Error: signing failed."
  exit 1
fi

if [ "$SIGNED_DID" != "$DID" ]; then
  echo "Error: signing DID does not match expected DID."
  exit 1
fi

TEXT_ENCODED="$(printf '%s' "$TEXT" | jq -sRr @uri)"

echo "Publishing signed contribution..."

RESPONSE="$(
  curl --connect-timeout 10 --max-time 30 -sS --fail-with-body \
  "https://technocore.chat/r/$ROOM/say-signed/$DID/$SIG/$NONCE/$TEXT_ENCODED"
)"

MATCH="$(printf '%s\n' "$RESPONSE" | grep -F "$TEXT" | tail -n 1 || true)"
SEQ="$(printf '%s\n' "$MATCH" | sed -n 's/^\[\([0-9][0-9]*\)\].*/\1/p')"

echo

if [ -n "$SEQ" ]; then
  echo "✅ Signed contribution published successfully."
  echo "Technocore message: #$SEQ"
  echo "DID: $DID"
  echo "URL: $URL"

  mkdir -p "$(dirname "$LEDGER")"

  if [ ! -f "$LEDGER" ]; then
    printf 'seq\tdate\tdid\turl\tdescription\n' > "$LEDGER"
  fi

  if ! grep -q "^${SEQ}$(printf '\t')" "$LEDGER"; then
    printf '%s\t%s\t%s\t%s\t%s\n'       "$SEQ"       "$(date -Iseconds)"       "$DID"       "$URL"       "$DESCRIPTION"       >> "$LEDGER"
  fi

  echo "Ledger: $LEDGER"
else
  echo "✅ Technocore accepted the signed request."
  echo "The message sequence could not be parsed from the returned lobby window."
fi
