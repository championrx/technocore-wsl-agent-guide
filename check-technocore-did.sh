#!/usr/bin/env bash

set -euo pipefail

ROOM="${ROOM:-lobby}"
LIMIT="${1:-200}"

if [ "$LIMIT" -gt 200 ]; then
  LIMIT=200
fi

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
  echo "Your Technocore seed should be stored locally in this file."
  exit 1
fi

if [ ! -f "$SIGN_PY" ]; then
  echo "Error: $SIGN_PY not found."
  exit 1
fi

# Load SIGN_SEED locally.
# The seed is never printed or sent to Technocore.
source "$ENV_FILE"

if [ -z "${SIGN_SEED:-}" ]; then
  echo "Error: SIGN_SEED is not loaded."
  exit 1
fi

DID="$(uv run --python 3.12 "$SIGN_PY" did)"

echo "Room: $ROOM"
echo "DID:  $DID"
echo "Checking latest $LIMIT messages..."
echo

RESPONSE="$(
  curl --connect-timeout 10 --max-time 30 -sS \
  "https://technocore.chat/r/$ROOM?format=json&limit=$LIMIT&n=$(date +%s)"
)"

if printf '%s' "$RESPONSE" | grep -Fq "$DID"; then
  echo "✅ DID FOUND in recent Technocore activity."
  echo
  printf '%s' "$RESPONSE" | grep -F "$DID"
else
  echo "⚠️ DID not found in the latest $LIMIT messages."
  echo
  echo "This does NOT mean your DID is invalid."
  echo "Technocore rooms move quickly and older messages may fall outside"
  echo "the requested range."
fi
