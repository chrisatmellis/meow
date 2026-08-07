#!/usr/bin/env bash
#
# Runs the app in a simulator and captures screenshots at several times of day.
# Requires a Mac with Xcode. Output lands in ./screenshots.
#
# The clock is pinned with MEOW_FORCE_HOUR (a debug-only hook), and a ready-made
# save is dropped into the app container so it boots straight into the room
# rather than the character creator.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/.." && pwd)"
BUNDLE_ID="com.meowroom.Meow"
OUT="$PROJECT/screenshots"
DERIVED="${TMPDIR:-/tmp}/meow-dd"
DEVJSON="${TMPDIR:-/tmp}/meow-simdevices.json"

command -v xcodebuild >/dev/null 2>&1 || { echo "error: needs Xcode" >&2; exit 127; }

mkdir -p "$OUT"
cd "$PROJECT"

echo "==> picking a simulator"
xcrun simctl list devices available --json > "$DEVJSON"
PICK=$(python3 "$HERE/pick-simulator.py" devices "$DEVJSON")
UDID=$(echo "$PICK" | cut -d' ' -f1)
DEVNAME=$(echo "$PICK" | cut -d' ' -f2-)
CREATED=0

if [ -z "$UDID" ]; then
  echo "    no pre-made device; creating one"
  RUNTIME=$(python3 "$HERE/pick-simulator.py" runtime "$DEVJSON")
  for TYPE in iPhone-17-Pro iPhone-17 iPhone-16-Pro iPhone-16 iPhone-15-Pro iPhone-15; do
    if UDID=$(xcrun simctl create meow-ci "com.apple.CoreSimulator.SimDeviceType.$TYPE" "$RUNTIME" 2>/dev/null); then
      DEVNAME="$TYPE"; CREATED=1; break
    fi
    UDID=""
  done
fi

# A UDID is a UUID. Anything else means simctl handed back an error message.
case "$UDID" in
  [0-9A-Fa-f]*-*-*-*-*) ;;
  *) echo "error: could not obtain a simulator (got: '$UDID')" >&2
     xcrun simctl list devices available | head -40 >&2
     exit 1 ;;
esac
echo "    device:  $DEVNAME"
echo "    udid:    $UDID"

cleanup() {
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  if [ "$CREATED" = "1" ]; then xcrun simctl delete "$UDID" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

echo "==> building"
if ! xcodebuild -project Meow.xcodeproj -scheme Meow -configuration Debug \
     -destination "id=$UDID" -derivedDataPath "$DERIVED" \
     build > "${TMPDIR:-/tmp}/meow-sim-build.log" 2>&1; then
  echo "build failed:"
  grep -E "error: " "${TMPDIR:-/tmp}/meow-sim-build.log" | sort -u | head -40
  exit 1
fi

APP=$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || { echo "error: no .app produced" >&2; exit 1; }
echo "    app: $APP"

echo "==> booting"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

# First launch creates the data container; with no save the app opens the creator.
echo "==> character creator"
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null || true
sleep 15
xcrun simctl io "$UDID" screenshot "$OUT/01-creator.png" >/dev/null 2>&1 || true
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
mkdir -p "$CONTAINER/Library/Application Support"
cp "$HERE/ci-save.json" "$CONTAINER/Library/Application Support/meowroom-save.json"
echo "    seeded save into $CONTAINER"

shot_at_hour() {
  local hour=$1 label=$2
  echo "==> room at ${hour}:00 ($label)"
  # Freshen lastSeen so the "while you were away" sheet does not cover the room.
  python3 "$HERE/touch-save.py" "$CONTAINER/Library/Application Support/meowroom-save.json"
  SIMCTL_CHILD_MEOW_FORCE_HOUR="$hour" xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null || true
  sleep 18
  xcrun simctl io "$UDID" screenshot "$OUT/$label.png" >/dev/null 2>&1 || true
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 2
}

shot_at_hour 6  "02-dawn"
shot_at_hour 12 "03-midday"
shot_at_hour 18 "04-golden-hour"
shot_at_hour 22 "05-night"

echo
echo "==> captured:"
ls -la "$OUT"
