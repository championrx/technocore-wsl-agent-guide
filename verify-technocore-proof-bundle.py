#!/usr/bin/env -S uv run --python 3.12
# /// script
# requires-python = ">=3.12"
# dependencies = ["cryptography"]
# ///
"""Verify a portable Technocore proof bundle using public data only."""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import re
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

B58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
B58_VALUES = {char: index for index, char in enumerate(B58_ALPHABET)}
ED25519_MULTICODEC = b"\xed\x01"


def decode_base58(value: str) -> bytes:
    number = 0
    try:
        for char in value:
            number = number * 58 + B58_VALUES[char]
    except KeyError as error:
        raise ValueError(f"invalid base58 character: {error.args[0]!r}") from None
    decoded = number.to_bytes((number.bit_length() + 7) // 8, "big") if number else b""
    return b"\x00" * (len(value) - len(value.lstrip("1"))) + decoded


def public_key_from_did(did: str) -> Ed25519PublicKey:
    prefix = "did:key:z"
    if not did.startswith(prefix):
        raise ValueError("did must be a base58btc did:key")
    decoded = decode_base58(did[len(prefix) :])
    if len(decoded) != 34 or not decoded.startswith(ED25519_MULTICODEC):
        raise ValueError("did:key is not an Ed25519 public key")
    return Ed25519PublicKey.from_public_bytes(decoded[2:])




def load_bundle(path: Path) -> dict[str, object]:
    def reject_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON field: {key}")
            result[key] = value
        return result

    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle, object_pairs_hook=reject_duplicates)
    if not isinstance(value, dict):
        raise ValueError("bundle must be a JSON object")
    return value


def verify(bundle: dict[str, object]) -> None:
    required = (
        "room", "did", "nonce", "signature", "exact_signed_text",
        "recorded_at", "contribution_url", "sequence",
    )
    for field in required:
        if not isinstance(bundle.get(field), str):
            raise ValueError(f"{field} must be a JSON string")

    room = bundle["room"]
    did = bundle["did"]
    nonce = bundle["nonce"]
    signature = bundle["signature"]
    text = bundle["exact_signed_text"]
    contribution_url = bundle["contribution_url"]
    sequence = bundle["sequence"]
    assert all(isinstance(value, str) for value in (
        room, did, nonce, signature, text, contribution_url, sequence,
    ))

    if not re.fullmatch(r"[0-9]{1,19}", nonce):
        raise ValueError("nonce must contain 1-19 ASCII digits")
    if sequence != "unknown" and not re.fullmatch(r"[0-9]+", sequence):
        raise ValueError("sequence must contain ASCII digits")

    if not text.endswith(f" | {contribution_url}"):
        raise ValueError("contribution_url does not match exact_signed_text")

    try:
        raw_signature = base64.b64decode(signature + "==", altchars=b"-_", validate=True)
    except (ValueError, binascii.Error) as error:
        raise ValueError("signature is not valid unpadded base64url") from error
    if len(raw_signature) != 64 or len(signature) != 86 or "=" in signature:
        raise ValueError("signature must be an unpadded 64-byte Ed25519 signature")

    canonical = f"{room}|{nonce}|{text}".encode("utf-8")
    try:
        public_key_from_did(did).verify(raw_signature, canonical)
    except InvalidSignature as error:
        raise ValueError("signature does not match the proof bundle contents and DID") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path, help="path to a Technocore proof bundle JSON file")
    args = parser.parse_args()
    try:
        verify(load_bundle(args.bundle))
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        print(f"INVALID: {error}")
        return 1
    print("VALID: proof bundle signature matches its DID and exact signed text")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
