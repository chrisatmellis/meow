#!/usr/bin/env bash
#
# Headless verification for the Meow engine.
#
# Xcode is the only way to build the real app, but the parts most likely to be
# wrong — the solar clock, the cat's decision making, the procedural meshes, the
# IK, the offline catch-up — are plain Swift. This script compiles the whole
# project against hand-written stand-ins for the Apple frameworks and runs an
# assertion suite plus a behavioural profile, on any machine with a Swift
# toolchain (including Linux CI).
#
#   ./verify.sh              assertions
#   ./verify.sh --profile    simulate whole days and print how the cat spends them
#
# See README.md for what this does and does not prove.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/../.." && pwd)"
BUILD="${MEOW_VERIFY_BUILD:-${TMPDIR:-/tmp}/meow-verify}"
MODULES="$BUILD/modules"
STAGE="$BUILD/stage"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "error: swiftc not found on PATH." >&2
  echo "Install a Swift toolchain (https://swift.org/download) or run from Xcode's:" >&2
  echo "  export PATH=\$(xcrun --find swiftc | xargs dirname):\$PATH" >&2
  exit 127
fi

mkdir -p "$MODULES"

echo "==> building framework stand-ins"
for name in CoreGraphics QuartzCore UIKit SceneKit AVFoundation UserNotifications SwiftUI; do
  swiftc -emit-module -emit-library \
    -module-name "$name" \
    -emit-module-path "$MODULES/$name.swiftmodule" \
    -o "$MODULES/lib$name.so" \
    -I "$MODULES" -L "$MODULES" -swift-version 5 \
    "$HERE/Shims/$name/$name.swift" || exit 1
done

echo "==> staging sources"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -r "$PROJECT/MeowRoom" "$STAGE/"
cp "$HERE/Harness/main.swift" "$HERE/Harness/profile.swift" "$STAGE/"

# Objective-C interop does not exist off-Apple, so rewrite the two constructs
# that need it. Nothing else about the sources is changed.
python3 - "$STAGE" <<'PY'
import os, re, sys
stage = sys.argv[1]

def strip_selectors(src):
    out, i = [], 0
    while True:
        j = src.find('#selector(', i)
        if j < 0:
            out.append(src[i:]); break
        out.append(src[i:j])
        k, depth = j + len('#selector('), 1
        while k < len(src) and depth:
            if src[k] == '(': depth += 1
            elif src[k] == ')': depth -= 1
            k += 1
        out.append('Selector("sel")'); i = k
    return ''.join(out)

for root, _, files in os.walk(stage):
    for f in files:
        if not f.endswith('.swift'):
            continue
        p = os.path.join(root, f)
        s = open(p).read()
        s = strip_selectors(s)
        s = re.sub(r'@objc\s+', '', s)
        s = re.sub(r'@main\s*\n', '', s)
        open(p, 'w').write(s)
PY

echo "==> compiling"
cd "$STAGE"
FILES=$(find MeowRoom -name '*.swift' | sort)
if ! swiftc -swift-version 5 -O -I "$MODULES" -L "$MODULES" \
     -lCoreGraphics -lQuartzCore -lUIKit -lSceneKit \
     -lAVFoundation -lUserNotifications -lSwiftUI \
     -Xlinker -rpath -Xlinker "$MODULES" \
     -o "$STAGE/meowverify" main.swift profile.swift $FILES 2>&1 \
     | sed "s#^MeowRoom/#$PROJECT/MeowRoom/#"; then
  exit 1
fi
[ -x "$STAGE/meowverify" ] || exit 1

echo "==> running"
exec "$STAGE/meowverify" "$@"
