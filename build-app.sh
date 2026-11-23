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

# Newer SDKs can need a toolchain plugin the installed tools lack; retry with older ones.
build_release() {
    swift build -c release 2>/dev/null && return 0
    local sdk
    for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.[0-9]*.sdk 2>/dev/null | sort -rV); do
        echo "==> retrying with $(basename "$sdk")"
        swift build -c release --sdk "$sdk" 2>/dev/null && return 0
    done
    return 1
}

echo "==> swift build -c release"
if build_release; then
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
# Stamp the build's commit so the app can tell when GitHub has a newer one.
if COMMIT=$(git rev-parse HEAD 2>/dev/null); then
    /usr/libexec/PlistBuddy -c "Add :GitCommit string $COMMIT" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc codesigning"
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
echo "    Run it with: open $APP   (or drop it in /Applications)"
