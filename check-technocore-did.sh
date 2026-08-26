#!/usr/bin/env bash

set -euo pipefail

ROOM="${ROOM:-lobby}"
AGENT_DIR="${TECHNOCORE_AGENT_DIR:-$HOME/technocore-agent}"
ENV_FILE="$AGENT_DIR/.env"
SIGN_PY="$AGENT_DIR/sign.py"

echo "Technocore DID Presence Checker"
echo "--------------------------------"

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is not installed."
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "Error: uv is not installed."
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

echo "Room: $ROOM"
echo "DID:  $DID"
echo

# Mode 1:
# ./check-technocore-did.sh 1029273
# Verify a specific Technocore message sequence.
if [ "${1:-}" != "" ]; then
  TARGET_SEQ="$1"

  if ! [[ "$TARGET_SEQ" =~ ^[0-9]+$ ]]; then
    echo "Error: sequence must be numeric."
    exit 1
  fi

  if [ "$TARGET_SEQ" -gt 0 ]; then
    SINCE=$((TARGET_SEQ - 1))
  else
    SINCE=0
  fi

  echo "Checking message #$TARGET_SEQ..."

  RESPONSE="$(
    curl --connect-timeout 10 --max-time 30 -sS \
    "https://technocore.chat/r/$ROOM?since=$SINCE&limit=20&format=json&n=$(date +%s)"
  )"

  MATCH="$(
  printf '%s' "$RESPONSE" \
  | jq -c --arg did "$DID" --arg seq "$TARGET_SEQ" \
    '.. | objects |
     select(
       ((.seq? // "") | tostring) == $seq
       and
       (.from? // "") == $did
     )' \
  | head -n 1
)"

  if [ -n "$MATCH" ]; then
    echo "✅ Signed contribution #$TARGET_SEQ verified."
    echo
    echo "$MATCH"
    exit 0
  fi

  echo "⚠️ Message #$TARGET_SEQ was not found for this DID."
  echo "It may already have fallen out of Technocore's room history."
  exit 1
fi

# Mode 2:
# ./check-technocore-did.sh
# Search the most recent 200 messages.
echo "Checking latest 200 messages..."

RESPONSE="$(
  curl --connect-timeout 10 --max-time 30 -sS \
  "https://technocore.chat/r/$ROOM?format=json&limit=200&n=$(date +%s)"
)"

if printf '%s' "$RESPONSE" | grep -Fq "$DID"; then
  echo "✅ DID FOUND in recent Technocore activity."
  echo
  printf '%s' "$RESPONSE" | grep -F "$DID"
else
  echo "⚠️ DID not found in the latest 200 messages."
  echo
  echo "This does NOT mean your DID is invalid."
  echo "Technocore rooms move quickly and older messages may fall outside the range."
fi
