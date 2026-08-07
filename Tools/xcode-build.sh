#!/usr/bin/env bash
#
# Builds the app with xcodebuild and prints a compact, paste-friendly report.
# Requires a Mac with Xcode. Full log is kept so nothing is lost.
#
#   ./Tools/xcode-build.sh            build for the simulator (no signing needed)
#   ./Tools/xcode-build.sh device     build for a real device (needs a signing team)

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/.." && pwd)"
LOG="${TMPDIR:-/tmp}/meow-build.log"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. This script needs a Mac with Xcode installed." >&2
  exit 127
fi

if [ "${1:-simulator}" = "device" ]; then
  DESTINATION='generic/platform=iOS'
  EXTRA=()
else
  DESTINATION='generic/platform=iOS Simulator'
  # The simulator does not need a signing identity.
  EXTRA=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")
fi

echo "==> xcodebuild ($DESTINATION)"
echo "    full log: $LOG"
echo

cd "$PROJECT"
xcodebuild \
  -project Meow.xcodeproj \
  -scheme Meow \
  -configuration Debug \
  -destination "$DESTINATION" \
  "${EXTRA[@]}" \
  build > "$LOG" 2>&1
STATUS=$?

# Compact report: unique diagnostics, project-relative paths, no Xcode noise.
report() {
  grep -E "(error|warning): " "$LOG" \
    | sed "s|$PROJECT/||g" \
    | sed 's|^/[^ ]*/DerivedData/[^ ]*||' \
    | sort -u
}

ERRORS=$(report | grep -c "error: ")
WARNINGS=$(report | grep -c "warning: ")

if [ "$STATUS" -eq 0 ]; then
  echo "BUILD SUCCEEDED  ($WARNINGS warnings)"
  [ "$WARNINGS" -gt 0 ] && { echo; report | grep "warning: " | head -40; }
  echo
  echo "Next: open Meow.xcodeproj in Xcode and press Run, or"
  echo "  xcrun simctl boot 'iPhone 16' && open -a Simulator"
  exit 0
fi

echo "BUILD FAILED  ($ERRORS errors, $WARNINGS warnings)"
echo
echo "----- paste everything below this line -----"
report | grep "error: " | head -60
echo
echo "----- context for the first few errors -----"
grep -B2 -A6 "error: " "$LOG" | sed "s|$PROJECT/||g" | head -80
echo "----- end -----"
exit 1
