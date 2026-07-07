#!/bin/bash
# Build ClipDisplay.app from the SwiftPM executable — no Xcode required.
#
# Prefers `swift build -c release`; falls back to compiling directly with
# swiftc if the SwiftPM manifest can't be built (some CLT installs ship a
# stale PackageDescription private interface that breaks all manifests).
set -euo pipefail
cd "$(dirname "$0")"

APP="ClipDisplay.app"
BINARY=""

echo "==> swift build -c release"
if swift build -c release 2>/dev/null; then
    BINARY=".build/release/ClipDisplay"
else
    echo "==> SwiftPM manifest failed to build; falling back to direct swiftc"
    mkdir -p .build/direct
    swiftc -O Sources/ClipDisplay/*.swift -o .build/direct/ClipDisplay
    BINARY=".build/direct/ClipDisplay"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/ClipDisplay"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> Ad-hoc codesigning"
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
echo "    Run it with: open $APP   (or drop it in /Applications)"
