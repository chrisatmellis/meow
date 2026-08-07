#!/usr/bin/env python3
"""Checks the App Store Connect setup before anything slow depends on it.

Every problem this catches would otherwise surface twenty minutes into an
archive, as a signing or upload error that says nothing about which piece is
actually missing. Here they surface in a couple of seconds, named.

    asc-preflight.py --key AuthKey.p8 --key-id ABCD123456 \
                     --issuer 1a2b3c4d-... --team ABCDE12345 \
                     --bundle com.example.app

Signing uses the openssl binary rather than a Python crypto package: it is
already on every runner, needs no install step, and cannot break because a
wheel failed to build.
"""
import argparse
import base64
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """ECDSA signatures come out of openssl as DER; JWS wants raw r||s."""
    if not der or der[0] != 0x30:
        raise ValueError("not a DER SEQUENCE")
    # Skip SEQUENCE tag and its length (short or long form).
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)

    def integer(pos):
        if der[pos] != 0x02:
            raise ValueError("expected DER INTEGER")
        length = der[pos + 1]
        value = der[pos + 2:pos + 2 + length]
        return value.lstrip(b"\x00").rjust(32, b"\x00"), pos + 2 + length

    r, i = integer(i)
    s, _ = integer(i)
    return r + s


def sign_jwt(key_path: str, key_id: str, issuer: str) -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": issuer, "iat": now, "exp": now + 900,
               "aud": "appstoreconnect-v1"}
    signing_input = (b64url(json.dumps(header, separators=(",", ":")).encode())
                     + "." +
                     b64url(json.dumps(payload, separators=(",", ":")).encode()))
    proc = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(), capture_output=True)
    if proc.returncode != 0:
        raise SystemExit(f"openssl could not sign with that key:\n"
                         f"{proc.stderr.decode().strip()}")
    return signing_input + "." + b64url(der_to_raw(proc.stdout))


def get(path: str, token: str):
    req = urllib.request.Request(f"{API}/{path}",
                                 headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(body)
        except ValueError:
            return e.code, {"raw": body[:400]}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--key", required=True)
    p.add_argument("--key-id", required=True)
    p.add_argument("--issuer", required=True)
    p.add_argument("--team", required=True)
    p.add_argument("--bundle", required=True)
    a = p.parse_args()

    problems = []

    # --- Shapes first. These need no network and catch most paste errors.
    pem = open(a.key).read()
    if "BEGIN PRIVATE KEY" not in pem:
        problems.append("the .p8 is not a PEM private key — check it pasted whole, "
                        "BEGIN/END lines included")
    if not re.fullmatch(r"[A-Z0-9]{10}", a.key_id):
        problems.append(f"key id {a.key_id!r} is not 10 uppercase alphanumerics")
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", a.issuer):
        problems.append(f"issuer id {a.issuer!r} is not a UUID — this is the one at "
                        "the top of the Integrations page, not the key's own id")
    if not re.fullmatch(r"[A-Z0-9]{10}", a.team):
        problems.append(f"team id {a.team!r} is not 10 uppercase alphanumerics")
    if problems:
        for m in problems:
            print(f"  ✗ {m}")
        return 1
    print("  ✓ all four values are the right shape")

    # --- Then whether Apple accepts them.
    token = sign_jwt(a.key, a.key_id, a.issuer)
    status, body = get("apps?limit=200", token)
    if status == 401:
        print("  ✗ Apple rejected the key (401). The key id and issuer id are each "
              "valid on their own but must come from the same account, and the key "
              "must not have been revoked.")
        return 1
    if status != 200:
        print(f"  ✗ App Store Connect returned {status}: "
              f"{json.dumps(body)[:300]}")
        return 1
    print("  ✓ Apple accepted the key")

    apps = {app["attributes"]["bundleId"]: app["attributes"].get("name", "?")
            for app in body.get("data", [])}
    if a.bundle in apps:
        print(f"  ✓ app record exists: {apps[a.bundle]!r} → {a.bundle}")
        print("\nEverything needed is in place. Uploads can go ahead.")
        return 0

    print(f"  ✗ no app record for {a.bundle}")
    print("\n    An app record cannot be created through the API — Apple only "
          "allows it in the\n    App Store Connect UI. Apps → + → New App, and "
          "pick this bundle id.")
    if apps:
        print("\n    Records that do exist on this account:")
        for bundle, name in sorted(apps.items()):
            print(f"      {name}  →  {bundle}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
