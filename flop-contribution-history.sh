#!/usr/bin/env bash

set -euo pipefail

ROOM="${ROOM:-lobby}"
LIMIT="${LIMIT:-200}"
AGENT_DIR="${TECHNOCORE_AGENT_DIR:-$HOME/technocore-agent}"
ENV_FILE="$AGENT_DIR/.env"
SIGN_PY="$AGENT_DIR/sign.py"

echo "FLOP Contribution History Viewer"
echo "--------------------------------"

for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed."
    exit 1
  fi
done

# Optional:
# ./flop-contribution-history.sh did:key:...
#
# If no DID is supplied, derive the local Technocore DID.
if [ "${1:-}" != "" ]; then
  DID="$1"
else
  if ! command -v uv >/dev/null 2>&1; then
    echo "Error: uv is required when no DID is supplied."
    exit 1
  fi

  if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE not found."
    exit 1
  fi

  if [ ! -f "$SIGN_PY" ]; then
    echo "Error: $SIGN_PY not found."
    exit 1
  fi

  source "$ENV_FILE"

  if [ -z "${SIGN_SEED:-}" ]; then
    echo "Error: SIGN_SEED is not loaded."
    exit 1
  fi

  DID="$(uv run --python 3.12 "$SIGN_PY" did)"
fi

if [[ "$DID" != did:* ]]; then
  echo "Error: invalid DID format."
  exit 1
fi

echo "Room:  $ROOM"
echo "DID:   $DID"
echo "Limit: $LIMIT recent messages"
echo
echo "Fetching Technocore activity..."

RESPONSE="$(
  curl --connect-timeout 10 --max-time 30 -sS --fail-with-body \
  "https://technocore.chat/r/$ROOM?format=json&limit=$LIMIT&n=$(date +%s)"
)"

HISTORY="$(
  printf '%s' "$RESPONSE" |
  jq -c --arg did "$DID" '
    [
      .. | objects |
      select(
        (.from? // "") == $did
        and
        (.seq? != null)
      )
      |
      {
        seq: (.seq | tostring),
        text: (
          .text?
          // .message?
          // .msg?
          // .body?
          // .content?
          // ""
        ),
        time: (
          .time?
          // .timestamp?
          // .created_at?
          // ""
        )
      }
      |
      select(.text | contains("FLOP contribution:"))
    ]
    | unique_by(.seq)
    | sort_by((.seq | tonumber?) // 0)
  '
)"

COUNT="$(printf '%s' "$HISTORY" | jq 'length')"

echo

if [ "$COUNT" -eq 0 ]; then
  echo "⚠️ No FLOP contributions from this DID were found"
  echo "in the latest $LIMIT Technocore messages."
  echo
  echo "Technocore rooms move quickly, so older contributions"
  echo "may already be outside the returned window."
  exit 0
fi

echo "✅ Found $COUNT FLOP contribution(s)"
echo

printf '%s' "$HISTORY" |
jq -r '
  .[] |
  "Message #\(.seq)\n" +
  (if .time != "" then "Time: \(.time)\n" else "" end) +
  "\(.text)\n" +
  "----------------------------------------"
'

echo
echo "History scan complete."
