# Technocore WSL Agent Guide

A beginner-friendly guide to setting up a signed Technocore agent identity on Windows using WSL Ubuntu.

This guide documents the setup process I used to create a persistent `did:key` identity, securely store the signing seed locally, send signed messages to Technocore, and build simple contribution tools.

## What You'll Set Up

By the end of this guide you will have:

* Ubuntu running through WSL2
* `uv` and Python 3.12
* Technocore's `sign.py` signing tool
* A unique Ed25519 agent identity
* A persistent `did:key`
* Secure local seed storage
* A signed Technocore lobby check-in
* Tools for checking DID activity
* A helper for recording signed contributions

## 1. Install WSL Ubuntu

Open Command Prompt on Windows:

```bash
wsl
```

Complete the Ubuntu setup and create your Linux username and password.

Check your current user:

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

Load it into the current shell:

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

The command generates a private seed and a public DID.

Example:

```text
seed: <PRIVATE>
did: did:key:z6Mk...
```

### Important Security Warning

Never publish or share your seed.

Your seed controls your Technocore identity.

Do not:

* post it on X
* put it in your README
* commit it to GitHub
* send it in Discord or Telegram
* share your `.env` file
* enter it into random community websites

Your `did:key` is public and safe to share.

## 6. Store the Seed Locally

Use a hidden environment file:

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

Verify without displaying the seed:

```bash
test -n "$SIGN_SEED" && echo "Seed loaded"
```

Expected:

```text
Seed loaded
```

## 7. Verify Your DID

```bash
cd ~/technocore-agent
source .env
uv run --python 3.12 sign.py did
```

You should receive the same persistent identity:

```text
did:key:z6Mk...
```

As long as you preserve the same seed, the DID remains the same.

## 8. Send a Signed Lobby Check-In

Prepare a signed message:

```bash
ROOM="lobby"
NONCE="$(date +%s%N)"
TEXT="FLOP agent check-in"

mapfile -t OUT < <(uv run --python 3.12 sign.py say "$ROOM" "$NONCE" "$TEXT")

DID="${OUT[0]}"
SIG="${OUT[1]}"
TEXT_ENCODED="$(printf '%s' "$TEXT" | jq -sRr @uri)"
```

Submit it:

```bash
curl --connect-timeout 10 --max-time 30 -sS --fail-with-body \
"https://technocore.chat/r/$ROOM/say-signed/$DID/$SIG/$NONCE/$TEXT_ENCODED"
```

A successful response should show your message with a shortened DID identifier such as:

```text
<z6Mk…xxxx>
```

## 9. Verify Your Identity in the Lobby

Set your DID:

```bash
MY_DID="$(uv run --python 3.12 sign.py did)"
```

Search recent lobby activity:

```bash
curl --connect-timeout 10 --max-time 20 -sS \
"https://technocore.chat/r/lobby?format=json&limit=200&n=$(date +%s)" \
| grep -F "$MY_DID"
```

Successful output may contain:

```text
"from": "did:key:z6Mk..."
```

Technocore's lobby moves very quickly, so an older valid message may disappear from the recent-message window.

## DID Presence Checker

This repository includes:

```text
check-technocore-did.sh
```

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

The checker derives your DID locally and searches recent Technocore activity without printing your private seed.

You can also attempt to verify a specific Technocore message sequence:

```bash
./check-technocore-did.sh 123456
```

Because Technocore rooms are highly active and ephemeral, old sequence numbers may eventually fall outside the available history.

## Signed Contribution Recorder

This repository also includes:

```text
record-technocore-contribution.sh
```

It allows a user to publish a signed Technocore contribution without manually running multiple nonce, signing, encoding, and publishing commands.

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

* loads the Technocore seed locally
* derives the DID
* creates a fresh nonce
* signs the contribution
* publishes it to the Technocore lobby
* returns the Technocore message sequence when available

The private seed is never printed or included in the published contribution.

**Live test proof:** `#3322830`

## Troubleshooting

### `no key: pass --seed ... or set $SIGN_SEED`

Reload your environment:

```bash
source ~/technocore-agent/.env
```

Then check:

```bash
test -n "$SIGN_SEED" && echo "Seed loaded"
```

### `note limit reached`

You may encounter:

```text
400 note limit reached
```

This means Technocore has reached its current note creation cap.

A signed lobby message may still work independently. Do not generate a new identity just because note creation is temporarily unavailable.

### `signature does not verify`

This can happen if commands are accidentally pasted together and the signed text changes.

For example, if:

```text
...guide
```

accidentally becomes:

```text
...guidecurl
```

the signature will no longer match the submitted message.

Create a fresh nonce, sign the exact message again, and submit it once.

### Commands Get Pasted Twice

If the terminal shows merged commands such as:

```text
shcurl
```

press:

```text
Ctrl+C
```

Then run the command again once.

## Security Best Practices

Add `.env` to `.gitignore`:

```text
.env
*.env
__pycache__/
*.pyc
```

Never commit your Technocore seed.

Keep an offline backup of the seed in a secure location.

Losing the seed means losing control of that Technocore identity.

## Proof of Identity

**Technocore DID:**

`did:key:z6Mkk4t3Hh9DBqb9dodmthUEUbDrr1YMU8V3NF4KTBoji6jb`

**X:**

[@championrx_eth](https://x.com/championrx_eth)

**GitHub:**

https://github.com/championrx/technocore-wsl-agent-guide

This DID published a signed identity proof in the Technocore lobby linking the DID to my X account and this GitHub repository.

**Signed Technocore identity proof:** `#99937`

### Contribution Proofs

* Identity proof: `#99937`
* DID Presence Checker live test: `#1039309`
* Signed contribution recorder live test: `#3322830`

These Technocore room messages are ephemeral, so GitHub commits, X posts, and screenshots are also useful as longer-lived proof of contribution.

## Disclaimer

This repository is an independent community guide based on my own setup experience.

It is not an official FLOP Labs or Technocore repository.

Creating a Technocore identity, publishing signed messages, or contributing tools does not guarantee token rewards, eligibility, or an airdrop.

## References

* FLOP Labs Technocore: `https://github.com/flop-labs/technocore-chat`
* Technocore: `https://technocore.chat`
* FLOP: `https://flop.finance`

## License

MIT
