#!/usr/bin/env bash
#
# Archive and upload a build to TestFlight, from a Mac.
#
# Same steps as .github/workflows/testflight.yml, in the same order, so a failure
# means the same thing in both places. CI is the normal path; this is for when you
# want a build without waiting on a runner.
#
#   ./Tools/testflight.sh              # next build number after what is live
#   ./Tools/testflight.sh 12           # a specific build number
#
# Needs the same five values the workflow gets from repository secrets, exported
# into the environment:
#
#   APP_STORE_CONNECT_KEY_P8        the .p8 file's contents
#   APP_STORE_CONNECT_KEY_ID        the 10-character key id
#   APP_STORE_CONNECT_ISSUER_ID     the issuer UUID
#   APPLE_SIGNING_P12_BASE64        base64 of the signing certificate
#   APPLE_SIGNING_P12_PASSWORD      its password
#
# They are not in the repository. They used to be, which was a deliberate trade
# while it was private; a public repository has a public history, so that trade is
# off. Tools/asc-rotate.py mints fresh ones.
#
# Takes about ten minutes, most of it the archive. Apple then takes another five
# to fifteen to process the build before it appears in TestFlight.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/.." && pwd)"
cd "$PROJECT"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "error: this needs a Mac — xcodebuild only exists there." >&2
  echo "The rest of the project verifies anywhere: ./Tools/linux-verify/verify.sh" >&2
  exit 1
fi
command -v xcodebuild >/dev/null || { echo "error: xcodebuild not found. Install Xcode." >&2; exit 1; }

TEAM_ID=KJ9NJ2M7C6
BUNDLE_ID=com.drinkmellis.meowroom

for v in APP_STORE_CONNECT_KEY_P8 APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID \
         APPLE_SIGNING_P12_BASE64 APPLE_SIGNING_P12_PASSWORD; do
  [ -n "${!v:-}" ] || { echo "error: $v is not set. See the header of this script." >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" ~/private_keys/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8' EXIT

# --- Build number -----------------------------------------------------------
#
# Every upload needs a number App Store Connect has not seen. A duplicate is only
# rejected after the whole archive is built, which is ten minutes to find out
# about a one-line problem, so ask Apple first.
BUILD="${1:-}"
if [ -z "$BUILD" ]; then
  echo "==> asking App Store Connect for the latest build number"
  LATEST="$(python3 Tools/asc-preflight.py latest-build 2>/dev/null || true)"
  if [[ "$LATEST" =~ ^[0-9]+$ ]]; then
    BUILD=$((LATEST + 1))
  else
    BUILD="$(date +%s)"
    echo "    could not read it; using a timestamp instead"
  fi
fi
echo "==> building as build $BUILD"

# --- Authentication key -----------------------------------------------------
mkdir -p ~/private_keys
printf '%s\n' "$APP_STORE_CONNECT_KEY_P8" > ~/private_keys/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8
chmod 600 ~/private_keys/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8
grep -q "BEGIN PRIVATE KEY" ~/private_keys/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8 \
  || { echo "error: APP_STORE_CONNECT_KEY_P8 is not a PEM private key." >&2; exit 1; }

# --- Archive ----------------------------------------------------------------
#
# Unsigned, with the export step doing the signing. Signing here instead fails on
# an account with no registered devices: archiving asks for an iOS App
# Development profile, and those are built from a device list. App Store
# distribution profiles carry no device list at all.
echo "==> archiving (this is the slow part)"
xcodebuild archive \
  -project Meow.xcodeproj \
  -scheme Meow \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$WORK/Meow.xcarchive" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  > "$WORK/archive.log" 2>&1 || {
    echo "--- archive failed ---" >&2
    grep -E "error:" "$WORK/archive.log" | sort -u | head -40 >&2
    echo "full log: $WORK/archive.log" >&2
    trap - EXIT
    exit 1; }

# --- Signing identity -------------------------------------------------------
#
# Into a throwaway keychain, so this never touches the login keychain and never
# leaves a certificate behind on the machine.
echo "==> installing the signing identity into a temporary keychain"
KC="$WORK/build.keychain"
KC_PASS="$(uuidgen)"
ORIGINAL_DEFAULT="$(security default-keychain | tr -d ' "')"
restore_keychain() {
  security list-keychains -d user -s login.keychain-db >/dev/null 2>&1 || true
  [ -n "$ORIGINAL_DEFAULT" ] && security default-keychain -s "$ORIGINAL_DEFAULT" >/dev/null 2>&1 || true
}
trap 'restore_keychain; rm -rf "$WORK" ~/private_keys/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8' EXIT

security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings -lut 3600 "$KC"
security unlock-keychain -p "$KC_PASS" "$KC"
echo "$APPLE_SIGNING_P12_BASE64" | base64 --decode > "$WORK/signing.p12"
security import "$WORK/signing.p12" -k "$KC" -P "$APPLE_SIGNING_P12_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security
rm -f "$WORK/signing.p12"
# Without this the private key prompts for permission on first use.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" > /dev/null
security list-keychains -d user -s "$KC" login.keychain-db
security default-keychain -s "$KC"
security find-identity -v -p codesigning "$KC"

# Read the identity off the certificate rather than storing its name: a name that
# has drifted from the certificate fails at the very last step.
IDENTITY=$(security find-identity -v -p codesigning "$KC" | sed -n 's/.*"\(.*\)"/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "error: no codesigning identity in the p12" >&2; exit 1; }

# The profile comes from App Store Connect, so rotating the certificate needs
# nothing changed here.
PROFILES="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILES"
PROFILE_NAME=$(python3 Tools/asc-rotate.py profile "$PROFILES/meowroom.mobileprovision")
echo "profile: $PROFILE_NAME"

# --- Export and upload ------------------------------------------------------
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>teamID</key><string>$TEAM_ID</string>
<key>uploadSymbols</key><true/>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>$IDENTITY</string>
<key>provisioningProfiles</key><dict>
  <key>$BUNDLE_ID</key><string>$PROFILE_NAME</string>
</dict>
</dict></plist>
PLIST

# No -allowProvisioningUpdates: everything it would fetch is already here, and
# asking for it puts Apple's cloud signing service back in the path — which this
# key is not permitted to use.
echo "==> exporting and uploading"
xcodebuild -exportArchive \
  -archivePath "$WORK/Meow.xcarchive" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$WORK/export" \
  -authenticationKeyPath ~/private_keys/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8 \
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
  > "$WORK/export.log" 2>&1 || {
    echo "--- export failed ---" >&2
    grep -E "error:|Error Domain" "$WORK/export.log" | sort -u | head -40 >&2
    echo "full log: $WORK/export.log" >&2
    cp "$WORK/export.log" "$PROJECT/export.log" 2>/dev/null || true
    exit 1; }

echo ""
echo "uploaded build $BUILD to App Store Connect."
echo "Apple takes 5-15 minutes to process it, then it appears in TestFlight."
