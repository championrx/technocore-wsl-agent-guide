#!/usr/bin/env -S uv run --python 3.12
# /// script
# requires-python = ">=3.12"
# dependencies = ["cryptography"]
# ///
"""Verify a Technocore contribution receipt using public data only."""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import re
import unicodedata
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

B58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
B58_VALUES = {char: index for index, char in enumerate(B58_ALPHABET)}
ED25519_MULTICODEC = b"\xed\x01"
INVISIBLE_CATEGORIES = {"Cc", "Cf", "Cs", "Co", "Zl", "Zp"}


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


def swept(text: str) -> str:
    """Mirror the text normalization used by sign.py and Technocore."""
    return "".join(
        " " if unicodedata.category(char) in INVISIBLE_CATEGORIES else char
        for char in text
    ).strip()


def load_receipt(path: Path) -> dict[str, object]:
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
        raise ValueError("receipt must be a JSON object")
    return value


def verify(receipt: dict[str, object]) -> None:
    required = (
        "room", "did", "nonce", "signature", "exact_signed_text",
        "recorded_at", "contribution_url", "description",
    )
    for field in required:
        if not isinstance(receipt.get(field), str):
            raise ValueError(f"{field} must be a JSON string")

    room = receipt["room"]
    did = receipt["did"]
    nonce = receipt["nonce"]
    signature = receipt["signature"]
    text = receipt["exact_signed_text"]
    contribution_url = receipt["contribution_url"]
    description = receipt["description"]
    assert all(isinstance(value, str) for value in (
        room, did, nonce, signature, text, contribution_url, description,
    ))

    if not re.fullmatch(r"[0-9]{1,19}", nonce):
        raise ValueError("nonce must contain 1-19 ASCII digits")
    if "sequence" in receipt and (
        not isinstance(receipt["sequence"], int) or isinstance(receipt["sequence"], bool)
        or receipt["sequence"] < 0
    ):
        raise ValueError("sequence must be a non-negative JSON integer")

    expected_text = swept(f"FLOP contribution: {description} | {contribution_url}")
    if text != expected_text:
        raise ValueError("description or contribution_url does not match exact_signed_text")

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
        raise ValueError("signature does not match the receipt contents and DID") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path, help="path to a contribution receipt JSON file")
    args = parser.parse_args()
    try:
        verify(load_receipt(args.receipt))
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        print(f"INVALID: {error}")
        return 1
    print("VALID: receipt signature matches its DID and exact signed text")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
