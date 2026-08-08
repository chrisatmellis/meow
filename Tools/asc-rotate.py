#!/usr/bin/env python3
"""Mints a fresh iOS distribution certificate and App Store profile.

The private key is generated here and never leaves this machine — Apple only ever
sees a certificate signing request, and only ever returns the public certificate.
That is what makes this possible without a Mac: the Mac's usual job in this dance
is running Keychain Access to produce the CSR, and openssl does it just as well.

    asc-rotate.py new DIR         mint a certificate + profile, write a .p12
    asc-rotate.py new DIR CERT_ID resume with a certificate already issued
    asc-rotate.py profile OUT     write the current App Store profile
    asc-rotate.py revoke ID       revoke one certificate, by its 10-character id

`new` is purely additive: it consumes one of the account's distribution
certificate slots and touches nothing that already exists. `revoke` is not, and
is deliberately a separate command that names exactly what it is destroying —
this account also signs another app, and revoking the wrong certificate would
break that app's releases with no warning until its next build.

Outputs go to a directory you name, never into the repository. The whole point
of running this is to have signing material that has never been committed.
"""
import base64
import importlib.util
import re
import os
import secrets
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("asc", os.path.join(HERE, "asc-preflight.py"))
asc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(asc)

BUNDLE_ID = "com.drinkmellis.meowroom"


def run(*args, **kwargs):
    proc = subprocess.run(args, capture_output=True, **kwargs)
    if proc.returncode != 0:
        raise SystemExit(f"{args[0]} failed:\n{proc.stderr.decode().strip()}")
    return proc.stdout


def token():
    c = asc.credentials()
    return asc.sign_jwt(c["ASC_KEY_FILE"], c["ASC_KEY_ID"], c["ASC_ISSUER_ID"])


def mint(outdir: str, cert_id: str | None = None):
    """Mints a certificate, or resumes with one that already exists.

    Resumable on purpose. Apple permits exactly one current iOS Distribution
    certificate, so a crash after the certificate is issued but before the .p12 is
    built would otherwise leave the only slot occupied by a certificate whose
    private key is sitting in a temp directory — recoverable, but only if the tool
    lets you say "use that one".
    """
    os.makedirs(outdir, exist_ok=True)
    key_path = os.path.join(outdir, "signing.key")
    csr_path = os.path.join(outdir, "signing.csr")
    p12_path = os.path.join(outdir, "signing.p12")
    der_path = os.path.join(outdir, "signing.cer")
    pem_path = os.path.join(outdir, "signing.pem")

    t = token()

    if cert_id:
        if not os.path.exists(key_path):
            raise SystemExit(f"resuming needs the private key at {key_path}; "
                             "without it the certificate is unusable and has to be revoked")
        status, body = asc.get(f"certificates/{cert_id}", t)
        if status != 200:
            raise SystemExit(f"no certificate {cert_id} ({status})")
        cert_der = base64.b64decode(body["data"]["attributes"]["certificateContent"])
        print(f"  reusing certificate {cert_id}  {body['data']['attributes']['name']!r}")
    else:
        # Apple wants RSA 2048 for distribution certificates.
        run("openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
            "-keyout", key_path, "-out", csr_path,
            "-subj", "/CN=Meow Room CI/O=Mellis Craft Inc./C=GB")
        os.chmod(key_path, 0o600)

        status, body = asc.request("POST", "certificates", t, {
            "data": {"type": "certificates",
                     "attributes": {"certificateType": "IOS_DISTRIBUTION",
                                    "csrContent": open(csr_path).read()}}})
        if status not in (200, 201):
            raise SystemExit(f"could not create a certificate ({status}):\n"
                             f"{body}\n\n"
                             "If this says you already have a current distribution "
                             "certificate, one has to be revoked first — check which "
                             "app uses it before you do.")
        cert_id = body["data"]["id"]
        cert_der = base64.b64decode(body["data"]["attributes"]["certificateContent"])
        print(f"  certificate {cert_id}  {body['data']['attributes']['name']!r}")

    open(der_path, "wb").write(cert_der)
    run("openssl", "x509", "-inform", "DER", "-in", der_path, "-out", pem_path)

    # The identity name codesign will report, which the export options plist has
    # to match exactly. Read it back from the certificate rather than guessing.
    # OpenSSL 3 prints "CN = value" with spaces; older builds print "CN=value".
    # Matching only the tight form silently produced no identity at all.
    subject = run("openssl", "x509", "-in", pem_path, "-noout", "-subject").decode()
    match = re.search(r"CN\s*=\s*([^,/\n]+)", subject)
    if not match:
        raise SystemExit(f"could not read a common name out of: {subject.strip()}")
    common_name = match.group(1).strip()

    password = secrets.token_urlsafe(24)
    # Legacy PKCS#12 encryption on purpose. OpenSSL 3 defaults to AES-256 with
    # SHA-256, and macOS `security import` cannot read that — it fails with a
    # message about the password being wrong, which sends you looking in entirely
    # the wrong place. This cost a build cycle to find once already.
    run("openssl", "pkcs12", "-export",
        "-inkey", key_path, "-in", pem_path,
        "-out", p12_path, "-passout", f"pass:{password}",
        "-legacy", "-certpbe", "PBE-SHA1-3DES", "-keypbe", "PBE-SHA1-3DES",
        "-macalg", "sha1", "-name", common_name)
    os.chmod(p12_path, 0o600)

    # A profile bound to the new certificate. Apple requires profile names to be
    # unique on the account, so this is suffixed rather than reused.
    status, body = asc.get(f"bundleIds?filter[identifier]={BUNDLE_ID}", t)
    bundle_uid = body["data"][0]["id"]

    profile_name = f"Meow Room App Store CI {secrets.token_hex(3)}"
    status, body = asc.request("POST", "profiles", t, {
        "data": {"type": "profiles",
                 "attributes": {"name": profile_name,
                                "profileType": "IOS_APP_STORE"},
                 "relationships": {
                     "bundleId": {"data": {"type": "bundleIds", "id": bundle_uid}},
                     "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}})
    if status not in (200, 201):
        raise SystemExit(f"could not create a profile ({status}):\n{body}")
    profile_id = body["data"]["id"]
    print(f"  profile     {profile_id}  {profile_name!r}")

    p12_b64 = base64.b64encode(open(p12_path, "rb").read()).decode()
    open(os.path.join(outdir, "p12.base64.txt"), "w").write(p12_b64)
    open(os.path.join(outdir, "p12.password.txt"), "w").write(password)
    open(os.path.join(outdir, "summary.txt"), "w").write(
        f"certificate id   {cert_id}\n"
        f"signing identity {common_name}\n"
        f"profile id       {profile_id}\n"
        f"profile name     {profile_name}\n")

    print(f"\n  signing identity: {common_name}")
    print(f"  p12 is {len(p12_b64)} base64 characters, written to {outdir}/p12.base64.txt")
    print(f"  password written to {outdir}/p12.password.txt")


def fetch_profile(outpath: str):
    """Writes the current App Store provisioning profile for this app.

    Fetched at build time rather than stored as a secret. A provisioning profile
    is not really secret — a copy is embedded in every build Apple ships — and
    keeping it out of the secret list means one less thing to paste, and one less
    thing to remember to update when the certificate changes.

    Picks the newest ACTIVE profile, so re-running asc-rotate.py leaves the build
    pointing at the new one with nothing else to do.
    """
    t = token()
    status, body = asc.get("profiles?limit=200", t)
    if status != 200:
        raise SystemExit(f"could not list profiles ({status})")

    best = None
    for d in body.get("data", []):
        a = d["attributes"]
        if a.get("profileType") != "IOS_APP_STORE" or a.get("profileState") != "ACTIVE":
            continue
        s2, b2 = asc.get(f"profiles/{d['id']}/bundleId", t)
        if b2.get("data", {}).get("attributes", {}).get("identifier") != BUNDLE_ID:
            continue
        if best is None or a["expirationDate"] > best[1]["expirationDate"]:
            best = (d["id"], a)

    if best is None:
        raise SystemExit(f"no active App Store profile for {BUNDLE_ID}. "
                         "Run `asc-rotate.py new` to mint one.")
    profile_id, attrs = best
    open(outpath, "wb").write(base64.b64decode(attrs["profileContent"]))
    print(attrs["name"])


def revoke(cert_id: str):
    t = token()
    status, body = asc.get(f"certificates/{cert_id}", t)
    if status != 200:
        raise SystemExit(f"no certificate {cert_id} ({status})")
    a = body["data"]["attributes"]
    print(f"revoking {a['certificateType']}  {a['name']!r}  expires {a['expirationDate']}")
    status, body = asc.request("DELETE", f"certificates/{cert_id}", t)
    if status not in (200, 204):
        raise SystemExit(f"could not revoke ({status}): {body}")
    print("revoked")


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "new":
        mint(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    elif len(sys.argv) > 2 and sys.argv[1] == "profile":
        fetch_profile(sys.argv[2])
    elif len(sys.argv) > 2 and sys.argv[1] == "revoke":
        revoke(sys.argv[2])
    else:
        print(__doc__)
        raise SystemExit(2)
