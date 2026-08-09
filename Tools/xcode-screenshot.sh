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
BUNDLE_ID="com.drinkmellis.meowroom"
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

# A frame that is *entirely* one value is never a render of anything. Both ends:
# the first version of this checked only for white, having just been burned by
# four white frames, and promptly accepted four black ones instead. A blank window
# is whatever colour the window happens to be.
blank() {
  local f=$1
  [ -s "$f" ] || return 0
  local line clip dark
  line=$(python3 "$HERE/shot-stats.py" stats "$f" 2>/dev/null | awk 'NR==2 {print $3, $5}')
  [ -n "$line" ] || return 0
  clip=$(echo "$line" | cut -d' ' -f1)
  dark=$(echo "$line" | cut -d' ' -f2)
  awk -v c="$clip" -v d="$dark" 'BEGIN { exit !(c > 99.5 || d > 99.5) }'
}

shot_at_hour() {
  local hour=$1 label=$2
  echo "==> room at ${hour}:00 ($label)"
  # Freshen lastSeen so the "while you were away" sheet does not cover the room.
  python3 "$HERE/touch-save.py" "$CONTAINER/Library/Application Support/meowroom-save.json"
  SIMCTL_CHILD_MEOW_FORCE_HOUR="$hour" xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null || true

  # Wait for a frame with something in it, rather than for a fixed number of
  # seconds. The room builds every one of its textures and material maps at
  # launch, and these are Debug builds — unoptimised Swift over big float arrays
  # is far slower than the -O the harness uses. A fixed 18 second sleep captured
  # the blank window four times and produced four byte-identical white images,
  # which look exactly like an overexposed room and are not one.
  local waited=0
  while [ "$waited" -lt 90 ]; do
    sleep 6
    waited=$((waited + 6))
    xcrun simctl io "$UDID" screenshot "$OUT/$label.png" >/dev/null 2>&1 || true
    if ! blank "$OUT/$label.png"; then
      echo "    rendered after ${waited}s"
      break
    fi
  done

  # Diagnose only once the wait is actually over.
  #
  # This used to check `launchctl list` for the bundle id each time round and
  # break out if it did not find it. It gave a false negative on the night shot
  # and abandoned the poll after six seconds — while the log it then printed
  # showed the app running perfectly well. A liveness check that aborts the thing
  # it is checking is worse than no liveness check, and the whole point of a
  # timeout is that it is allowed to expire.
  if blank "$OUT/$label.png"; then
    echo "    !! still blank after ${waited}s — this shot is not a render"
    xcrun simctl spawn "$UDID" log show --last 150s --style compact \
      --predicate 'process == "Meow"' 2>/dev/null | tail -30
    local report
    report=$(ls -t "$HOME/Library/Logs/DiagnosticReports/"Meow* 2>/dev/null | head -1)
    [ -n "$report" ] && sed -n '1,40p' "$report"
  fi

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
