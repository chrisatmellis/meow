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

command -v xcodebuild >/dev/null 2>&1 || { echo "error: needs Xcode" >&2; exit 127; }

mkdir -p "$OUT"
cd "$PROJECT"

echo "==> picking a simulator"
RUNTIME=$(xcrun simctl list runtimes --json | python3 -c '
import json,sys
rs=[r for r in json.load(sys.stdin)["runtimes"]
    if r.get("isAvailable") and "iOS" in r.get("name","")]
rs.sort(key=lambda r: r.get("version",""))
print(rs[-1]["identifier"] if rs else "")')
DEVTYPE=$(xcrun simctl list devicetypes --json | python3 -c '
import json,sys
ds=[d for d in json.load(sys.stdin)["devicetypes"]
    if "iPhone" in d["name"] and "SE" not in d["name"] and "mini" not in d["name"]]
print(ds[-1]["identifier"] if ds else "")')
[ -n "$RUNTIME" ] && [ -n "$DEVTYPE" ] || { echo "error: no iOS simulator runtime found" >&2; exit 1; }
echo "    runtime: $RUNTIME"
echo "    device:  $DEVTYPE"

xcrun simctl delete meow-ci >/dev/null 2>&1 || true
UDID=$(xcrun simctl create meow-ci "$DEVTYPE" "$RUNTIME")
echo "    udid:    $UDID"

cleanup() {
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> building"
xcodebuild -project Meow.xcodeproj -scheme Meow -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" \
  build > "${TMPDIR:-/tmp}/meow-sim-build.log" 2>&1 || {
    echo "build failed:"; grep -E "error: " "${TMPDIR:-/tmp}/meow-sim-build.log" | sort -u | head -40; exit 1; }

APP=$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || { echo "error: no .app produced" >&2; exit 1; }
echo "    app: $APP"

echo "==> booting"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

# First launch creates the data container; the app opens on the character creator.
echo "==> character creator"
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
sleep 14
xcrun simctl io "$UDID" screenshot "$OUT/01-creator.png" >/dev/null 2>&1
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

# Seed a save so subsequent launches go straight into the room.
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
mkdir -p "$CONTAINER/Library/Application Support"
cp "$HERE/ci-save.json" "$CONTAINER/Library/Application Support/meowroom-save.json"
echo "    seeded save into $CONTAINER"

shot_at_hour() {
  local hour=$1 label=$2
  echo "==> room at ${hour}:00 ($label)"
  # Refresh lastSeen so the away-log sheet does not cover the room.
  python3 - "$CONTAINER/Library/Application Support/meowroom-save.json" <<'PY'
import json, sys, datetime
p = sys.argv[1]
d = json.load(open(p))
d["lastSeen"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump(d, open(p, "w"))
PY
  SIMCTL_CHILD_MEOW_FORCE_HOUR="$hour" xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
  sleep 18
  xcrun simctl io "$UDID" screenshot "$OUT/$label.png" >/dev/null 2>&1
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
