#!/usr/bin/env python3
"""
DropDial License Key Generator
==============================
Uses ECDSA P-256 (secp256r1) to generate cryptographically signed license keys.

Usage:
    # First time: generate key pair
    python keygen.py --init

    # Generate a license key for a customer
    python keygen.py --email buyer@example.com --name "John Doe"

    # Verify a license key (for testing)
    python keygen.py --verify "DD-eyJ..."

The private key (keys/private.pem) must NEVER be shared or committed to Git.
The public key (keys/public.b64) is embedded inside the DropDial Mac and Windows apps.
"""

import argparse
import base64
import json
import os
import sys
from datetime import datetime, timezone

from cryptography.hazmat.primitives.asymmetric import ec, utils
from cryptography.hazmat.primitives import hashes, serialization

KEYS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "keys")
PRIVATE_KEY_PATH = os.path.join(KEYS_DIR, "private.pem")
PUBLIC_KEY_PATH = os.path.join(KEYS_DIR, "public.b64")


def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def b64url_decode(s: str) -> bytes:
    s += "=" * (4 - len(s) % 4)
    return base64.urlsafe_b64decode(s)


def generate_keypair():
    """Generate a new ECDSA P-256 key pair and save to disk."""
    os.makedirs(KEYS_DIR, exist_ok=True)

    if os.path.exists(PRIVATE_KEY_PATH):
        print(f"⚠️  Private key already exists at: {PRIVATE_KEY_PATH}")
        print("   Delete it manually if you want to regenerate (this invalidates ALL existing licenses).")
        sys.exit(1)

    private_key = ec.generate_private_key(ec.SECP256R1())

    # Save private key (PEM)
    pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    with open(PRIVATE_KEY_PATH, "wb") as f:
        f.write(pem)
    os.chmod(PRIVATE_KEY_PATH, 0o600)

    # Save public key as x963 (uncompressed point: 04 || X || Y, 65 bytes) in Base64
    public_key = private_key.public_key()
    x963 = public_key.public_bytes(
        encoding=serialization.Encoding.X962,
        format=serialization.PublicFormat.UncompressedPoint,
    )
    pub_b64 = base64.b64encode(x963).decode("ascii")
    with open(PUBLIC_KEY_PATH, "w") as f:
        f.write(pub_b64)

    print("✅ Key pair generated successfully!")
    print(f"   Private key: {PRIVATE_KEY_PATH}")
    print(f"   Public key:  {PUBLIC_KEY_PATH}")
    print()
    print(f"📋 Public key (embed in apps):")
    print(f"   {pub_b64}")
    print()
    print("⚠️  IMPORTANT: NEVER share or commit the private key!")
    print("   Add 'licensing/keys/' to your .gitignore immediately.")


def load_private_key():
    if not os.path.exists(PRIVATE_KEY_PATH):
        print("❌ No private key found. Run: python keygen.py --init")
        sys.exit(1)
    with open(PRIVATE_KEY_PATH, "rb") as f:
        return serialization.load_pem_private_key(f.read(), password=None)


def load_public_key_b64():
    if not os.path.exists(PUBLIC_KEY_PATH):
        print("❌ No public key found. Run: python keygen.py --init")
        sys.exit(1)
    with open(PUBLIC_KEY_PATH) as f:
        return f.read().strip()


def generate_license(email: str, name: str, tier: str = "pro"):
    """Generate a signed license key for a customer."""
    private_key = load_private_key()

    payload = {
        "e": email,
        "n": name,
        "t": tier,
        "d": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
    }
    payload_json = json.dumps(payload, separators=(",", ":"), sort_keys=True)
    payload_bytes = payload_json.encode("utf-8")

    # Sign with ECDSA P-256 + SHA-256
    der_sig = private_key.sign(payload_bytes, ec.ECDSA(hashes.SHA256()))

    # Convert DER signature to raw r||s format (64 bytes)
    r, s = utils.decode_dss_signature(der_sig)
    raw_sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")

    # Format: DD-<base64url(payload)>.<base64url(raw_signature)>
    license_key = f"DD-{b64url_encode(payload_bytes)}.{b64url_encode(raw_sig)}"

    print("=" * 60)
    print("✅ License Key Generated!")
    print("=" * 60)
    print(f"  Customer: {name} <{email}>")
    print(f"  Tier:     {tier}")
    print(f"  Date:     {payload['d']}")
    print()
    print(f"  License Key:")
    print(f"  {license_key}")
    print("=" * 60)

    return license_key


def verify_license(license_key: str):
    """Verify a license key using the public key."""
    pub_b64 = load_public_key_b64()
    x963 = base64.b64decode(pub_b64)
    public_key = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), x963)

    if not license_key.startswith("DD-"):
        print("❌ Invalid key format (must start with DD-)")
        return False

    body = license_key[3:]  # strip "DD-"
    parts = body.split(".")
    if len(parts) != 2:
        print("❌ Invalid key format (expected payload.signature)")
        return False

    payload_bytes = b64url_decode(parts[0])
    raw_sig = b64url_decode(parts[1])

    if len(raw_sig) != 64:
        print(f"❌ Invalid signature length ({len(raw_sig)}, expected 64)")
        return False

    # Convert raw r||s back to DER
    r = int.from_bytes(raw_sig[:32], "big")
    s = int.from_bytes(raw_sig[32:], "big")
    der_sig = utils.encode_dss_signature(r, s)

    try:
        public_key.verify(der_sig, payload_bytes, ec.ECDSA(hashes.SHA256()))
        payload = json.loads(payload_bytes)
        print("✅ License key is VALID!")
        print(f"   Email: {payload.get('e')}")
        print(f"   Name:  {payload.get('n')}")
        print(f"   Tier:  {payload.get('t')}")
        print(f"   Date:  {payload.get('d')}")
        return True
    except Exception as e:
        print(f"❌ License key is INVALID: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="DropDial License Key Generator")
    parser.add_argument("--init", action="store_true", help="Generate a new ECDSA P-256 key pair")
    parser.add_argument("--email", type=str, help="Customer email address")
    parser.add_argument("--name", type=str, help="Customer name")
    parser.add_argument("--tier", type=str, default="pro", help="License tier (default: pro)")
    parser.add_argument("--verify", type=str, help="Verify a license key")
    args = parser.parse_args()

    if args.init:
        generate_keypair()
    elif args.verify:
        verify_license(args.verify)
    elif args.email and args.name:
        generate_license(args.email, args.name, args.tier)
    else:
        parser.print_help()
        print("\nExamples:")
        print('  python keygen.py --init                              # Generate key pair')
        print('  python keygen.py --email buyer@mail.com --name "Jo"  # Generate license')
        print('  python keygen.py --verify "DD-eyJ..."                # Verify license')


if __name__ == "__main__":
    main()
