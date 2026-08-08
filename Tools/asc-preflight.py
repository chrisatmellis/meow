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
import os
import json
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.drinkmellis.meowroom"


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


def request(method: str, path: str, token: str, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{API}/{path}", data=data, method=method,
        headers={"Authorization": f"Bearer {token}",
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, {"raw": raw[:400]}


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


def credentials():
    """The App Store Connect key, from the environment.

    These used to be committed in `ci/`, which was a deliberate trade at the time —
    the repository was private and it removed the need for a Mac. Going public ends
    that trade: git history is public too, so a committed key is a published key
    no matter what the current tree looks like.

    `APP_STORE_CONNECT_KEY_P8` carries the key's text, because that is the form a
    CI secret and a phone clipboard can both hold. It is written to a file only
    because openssl signs from a file.
    """
    values = {
        "ASC_KEY_ID": os.environ.get("APP_STORE_CONNECT_KEY_ID", ""),
        "ASC_ISSUER_ID": os.environ.get("APP_STORE_CONNECT_ISSUER_ID", ""),
    }

    pem = os.environ.get("APP_STORE_CONNECT_KEY_P8", "")
    if pem.strip():
        # NamedTemporaryFile with delete=False: openssl needs a path, and the
        # process may outlive any context manager we could wrap this in.
        handle = tempfile.NamedTemporaryFile("w", suffix=".p8", delete=False)
        handle.write(pem.replace("\\n", "\n"))
        handle.close()
        os.chmod(handle.name, 0o600)
        values["ASC_KEY_FILE"] = handle.name
    elif os.environ.get("ASC_KEY_FILE"):
        values["ASC_KEY_FILE"] = os.environ["ASC_KEY_FILE"]
    else:
        raise SystemExit(
            "No App Store Connect key in the environment.\n"
            "  APP_STORE_CONNECT_KEY_P8        the .p8 file's contents\n"
            "  APP_STORE_CONNECT_KEY_ID        the 10-character key id\n"
            "  APP_STORE_CONNECT_ISSUER_ID     the issuer UUID\n"
            "In CI these come from repository secrets; locally, export them.")

    missing = [k for k, v in values.items() if not v]
    if missing:
        raise SystemExit(f"missing from the environment: {', '.join(sorted(missing))}")
    return values


def latest_build() -> int:
    """The highest build number App Store Connect has seen for this app.

    Asked before archiving rather than after. A duplicate build number is only
    rejected at upload, which is ten minutes of archive to find out about a
    one-line problem.
    """
    c = credentials()
    token = sign_jwt(c["ASC_KEY_FILE"], c["ASC_KEY_ID"], c["ASC_ISSUER_ID"])
    status, body = get("apps?limit=200", token)
    if status != 200:
        raise SystemExit(f"App Store Connect returned {status}")
    app_id = next((app["id"] for app in body.get("data", [])
                   if app["attributes"]["bundleId"] == BUNDLE_ID), None)
    if app_id is None:
        raise SystemExit(f"no app record for {BUNDLE_ID}")
    status, body = get(f"builds?filter[app]={app_id}&limit=200", token)
    if status != 200:
        raise SystemExit(f"App Store Connect returned {status}")
    numbers = []
    for build in body.get("data", []):
        version = build["attributes"].get("version")
        if version and version.isdigit():
            numbers.append(int(version))
    return max(numbers, default=0)


def build_status():
    """What App Store Connect thinks of the recent builds, and of the test groups.

    Written because "TestFlight will not let me add a group" is not an error
    message — App Store Connect simply omits the control, so the reason has to be
    asked for rather than read. `internalBuildState` is the field that actually
    says why: PROCESSING, MISSING_EXPORT_COMPLIANCE, READY_FOR_BETA_TESTING and
    so on.
    """
    c = credentials()
    token = sign_jwt(c["ASC_KEY_FILE"], c["ASC_KEY_ID"], c["ASC_ISSUER_ID"])

    status, body = get("apps?limit=200", token)
    app_id = next((a["id"] for a in body.get("data", [])
                   if a["attributes"]["bundleId"] == BUNDLE_ID), None)
    if app_id is None:
        raise SystemExit(f"no app record for {BUNDLE_ID}")

    print("builds")
    status, body = get(f"builds?filter[app]={app_id}&limit=5"
                       f"&include=buildBetaDetail,betaGroups", token)
    if status != 200:
        raise SystemExit(f"builds returned {status}: {json.dumps(body)[:300]}")

    included = {(i["type"], i["id"]): i for i in body.get("included", [])}
    for b in body.get("data", []):
        a = b["attributes"]
        print(f"  build {a.get('version'):>4}  processing={a.get('processingState')}"
              f"  expired={a.get('expired')}"
              f"  encryption_declared={a.get('usesNonExemptEncryption')}")

        detail_ref = b.get("relationships", {}).get("buildBetaDetail", {}).get("data")
        if detail_ref:
            d = included.get((detail_ref["type"], detail_ref["id"]), {}).get("attributes", {})
            print(f"            internal={d.get('internalBuildState')}"
                  f"  external={d.get('externalBuildState')}")

        groups = b.get("relationships", {}).get("betaGroups", {}).get("data") or []
        names = [included.get(("betaGroups", g["id"]), {}).get("attributes", {}).get("name", g["id"])
                 for g in groups]
        print(f"            groups={names or '(none)'}")

    print("\ngroups")
    status, body = get(f"betaGroups?filter[app]={app_id}&limit=50", token)
    if not body.get("data"):
        print("  (none) — there is no tester group to add a build to yet.")
    for g in body.get("data", []):
        a = g["attributes"]
        s2, testers = get(f"betaGroups/{g['id']}/betaTesters?limit=200", token)
        print(f"  {a.get('name')!r}  internal={a.get('isInternalGroup')}"
              f"  allBuilds={a.get('hasAccessToAllBuilds')}"
              f"  testers={len(testers.get('data', []))}")

    print("\ntesters on the account")
    status, body = get("betaTesters?limit=200", token)
    for t in body.get("data", [])[:20]:
        a = t["attributes"]
        print(f"  {a.get('email')}  state={a.get('state')}")
    if not body.get("data"):
        print("  (none)")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "build-status":
        build_status()
        return 0

    # One positional mode, so the common "what build number is next" question
    # needs no flags at all — it reads the key straight from the environment.
    if len(sys.argv) > 1 and sys.argv[1] == "latest-build":
        print(latest_build())
        return 0

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
