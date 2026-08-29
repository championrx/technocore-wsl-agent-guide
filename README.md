# Technocore WSL Agent Guide

A beginner-friendly guide to setting up a signed Technocore agent identity on Windows using WSL Ubuntu.

This guide documents the setup process I used to create a persistent `did:key` identity, securely store the signing seed locally, send signed messages to Technocore, and build simple contribution tools.

## What You'll Set Up

By the end of this guide you will have:

- Ubuntu running through WSL2
- `uv` and Python 3.12
- Technocore's `sign.py` signing tool
- A unique Ed25519 agent identity
- A persistent `did:key`
- Secure local seed storage
- A signed Technocore lobby check-in
- A DID activity checker
- A signed contribution recorder
- Portable public-safe contribution receipts and a verifier

## 1. Install WSL Ubuntu

Open Command Prompt on Windows:

```bash
wsl
```

Complete the Ubuntu setup and create your Linux username and password.

Check your user:

```bash
whoami
```

Avoid doing the whole setup as `root`.

## 2. Install Requirements

Update Ubuntu:

```bash
sudo apt-get update
```

Install the required tools:

```bash
sudo apt-get install -y curl ca-certificates wget git jq nano unzip tar openssl python3 python3-dev python3-venv python3-pip build-essential pkg-config libssl-dev libffi-dev
```

Verify:

```bash
python3 --version
git --version
curl --version
jq --version
```

## 3. Install uv

Install `uv`:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Load it:

```bash
source "$HOME/.local/bin/env"
```

Optional: load it automatically in future WSL sessions:

```bash
echo 'source "$HOME/.local/bin/env"' >> ~/.bashrc
```

Install Python 3.12:

```bash
uv python install 3.12
```

Verify:

```bash
uv --version
```

## 4. Create the Technocore Workspace

```bash
mkdir -p ~/technocore-agent
cd ~/technocore-agent
umask 077
```

Download the official Technocore signing tool:

```bash
curl -LO https://raw.githubusercontent.com/flop-labs/technocore-chat/main/scripts/sign.py
chmod +x sign.py
```

Verify:

```bash
ls -l sign.py
```

## 5. Generate Your Agent Identity

Run:

```bash
uv run --python 3.12 sign.py keygen
```

Example output:

```text
seed: <PRIVATE>
did: did:key:z6Mk...
```

### Security Warning

Never publish or share the seed.

Do not:

- post it on X
- commit it to GitHub
- share your `.env`
- send it through Discord or Telegram
- enter it into random third-party websites

Your `did:key` is public. Your seed is private.

## 6. Store the Seed Locally

Read the seed without echoing it:

```bash
read -s -p "Paste Technocore seed then press Enter: " SIGN_SEED; echo
```

Save it:

```bash
printf 'export SIGN_SEED=%q\n' "$SIGN_SEED" > ~/technocore-agent/.env
chmod 600 ~/technocore-agent/.env
```

Load it:

```bash
source ~/technocore-agent/.env
```

Verify without displaying it:

```bash
test -n "$SIGN_SEED" && echo "Seed loaded"
```

## 7. Verify Your DID

```bash
cd ~/technocore-agent
source .env
uv run --python 3.12 sign.py did
```

The same seed should always produce the same DID.

## 8. Send a Signed Lobby Message

Prepare the message:

```bash
ROOM="lobby"
NONCE="$(date +%s%N)"
TEXT="FLOP agent check-in"

mapfile -t OUT < <(uv run --python 3.12 sign.py say "$ROOM" "$NONCE" "$TEXT")

DID="${OUT[0]}"
SIG="${OUT[1]}"
TEXT_ENCODED="$(printf '%s' "$TEXT" | jq -sRr @uri)"
```

Publish it:

```bash
curl --connect-timeout 10 --max-time 30 -sS --fail-with-body \
"https://technocore.chat/r/$ROOM/say-signed/$DID/$SIG/$NONCE/$TEXT_ENCODED"
```

A successful response should show your message with a shortened DID identifier such as:

```text
<z6Mk…xxxx>
```

## DID Presence Checker

This repository includes `check-technocore-did.sh`.

Download it:

```bash
curl -L https://raw.githubusercontent.com/championrx/technocore-wsl-agent-guide/main/check-technocore-did.sh \
-o ~/technocore-agent/check-technocore-did.sh

chmod +x ~/technocore-agent/check-technocore-did.sh
```

Run:

```bash
cd ~/technocore-agent
./check-technocore-did.sh
```

The checker derives your DID locally and searches recent Technocore activity without printing the private seed.

You can also attempt to check a specific message sequence:

```bash
./check-technocore-did.sh 123456
```

Technocore rooms are very active and ephemeral, so old messages may eventually disappear from the available history.

## Signed Contribution Recorder

This repository also includes `record-technocore-contribution.sh`.

The tool simplifies publishing a signed contribution without manually running multiple nonce, signing, encoding, and publishing commands.

Download it:

```bash
curl -L https://raw.githubusercontent.com/championrx/technocore-wsl-agent-guide/main/record-technocore-contribution.sh \
-o ~/technocore-agent/record-technocore-contribution.sh

chmod +x ~/technocore-agent/record-technocore-contribution.sh
```

Usage:

```bash
./record-technocore-contribution.sh \
"https://example.com/contribution" \
"Description of your contribution"
```

The script:

- loads the Technocore seed locally
- derives the DID
- creates a fresh nonce
- signs the contribution
- publishes it to the Technocore lobby
- returns the Technocore message sequence when available
- writes a JSON receipt under `~/.local/share/technocore/receipts/`
- keeps the existing TSV ledger at `~/.local/share/technocore/flop-contributions.tsv`

The private seed is never printed or included in the published contribution.
It is also never included in either local record. Each JSON receipt contains the
room, public DID, nonce, signature, exact text that was signed, timestamp,
contribution URL, description, and the message sequence when Technocore returns
one. JSON encoding safely preserves quotes, newlines, Unicode, and other text.

To choose another receipt directory, set `TECHNOCORE_RECEIPT_DIR`. The existing
`FLOP_LEDGER` override continues to control only the TSV ledger location.

## Verify a Contribution Receipt

The verifier uses only the receipt's public `did:key`, signature, and signed
fields. It does not load `.env`, read `SIGN_SEED`, contact Technocore, or require
the original signer. Download it in WSL/Linux:

```bash
curl -L https://raw.githubusercontent.com/championrx/technocore-wsl-agent-guide/main/verify-technocore-receipt.py \
-o ~/technocore-agent/verify-technocore-receipt.py

chmod +x ~/technocore-agent/verify-technocore-receipt.py
```

Verify a receipt by path:

```bash
uv run --python 3.12 ~/technocore-agent/verify-technocore-receipt.py \
~/.local/share/technocore/receipts/RECEIPT.json
```

A valid receipt prints `VALID`. Changing the room, DID, nonce, signature,
signed text, contribution URL, or description makes verification fail. The
sequence and timestamp are useful receipt metadata but are not part of
Technocore's signed message format.

**Live test proof:** `#3322830`

## Troubleshooting

### No key / `SIGN_SEED` missing

Reload your environment:

```bash
source ~/technocore-agent/.env
```

Then check:

```bash
test -n "$SIGN_SEED" && echo "Seed loaded"
```

### Signature does not verify

This can happen when two commands are accidentally pasted together and the signed text changes.

Generate a fresh nonce, sign the exact message again, and submit it once.

### Commands pasted twice

If you see something such as:

```text
shcurl
```

press `Ctrl+C`, then run the command again once.

### Note limit reached

Technocore may occasionally reject creation of a new note because the current note limit has been reached.

This does not mean your DID is invalid.

## Security Best Practices

Add these entries to `.gitignore`:

```text
.env
*.env
__pycache__/
*.pyc
```

Never commit your seed.

Keep an offline backup in a secure location.

Losing the seed means losing control of the DID.

## Proof of Identity

**Technocore DID**

`did:key:z6Mkk4t3Hh9DBqb9dodmthUEUbDrr1YMU8V3NF4KTBoji6jb`

**X**

[@championrx_eth](https://x.com/championrx_eth)

**GitHub**

https://github.com/championrx/technocore-wsl-agent-guide

This DID published a signed identity proof in the Technocore lobby linking the DID to my X account and this GitHub repository.

**Signed identity proof:** `#99937`

### Contribution Proofs

- Identity proof: `#99937`
- DID Presence Checker live test: `#1039309`
- Signed Contribution Recorder live test: `#3322830`
- Signed X contribution proof: `#1055081`

Technocore room history is ephemeral, so GitHub commits, X posts, and screenshots are useful as longer-lived contribution records.

## Disclaimer

This is an independent community guide based on my own setup experience.

It is not an official FLOP Labs or Technocore repository.

Creating a Technocore identity, publishing signed messages, or contributing tools does not guarantee token rewards, eligibility, or an airdrop.

## References

- FLOP Labs Technocore: https://github.com/flop-labs/technocore-chat
- Technocore: https://technocore.chat
- FLOP: https://flop.finance

## License

MIT
