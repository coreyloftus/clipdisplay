#!/bin/bash
# Build ClipDisplay.app and install it to /Applications, then relaunch it.
#
# - Builds a fresh .app via build-app.sh
# - Quits any running copy so the binary can be replaced cleanly
# - Copies the bundle into /Applications
# - Re-registers it with LaunchServices (so Spotlight/Raycast pick up changes)
# - Relaunches the installed copy
#
# Pass --login to also add it as a hidden Login Item (auto-launch at login).
set -euo pipefail
cd "$(dirname "$0")"

APP="ClipDisplay.app"
DEST="/Applications/$APP"

./build-app.sh

echo "==> Quitting any running ClipDisplay"
osascript -e 'quit app "ClipDisplay"' 2>/dev/null || true
sleep 1

echo "==> Installing to $DEST"
ditto "$APP" "$DEST"

echo "==> Registering with LaunchServices"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"

if [[ "${1:-}" == "--login" ]]; then
    echo "==> Ensuring Login Item"
    osascript <<'OSA' || true
tell application "System Events"
    if not (exists login item "ClipDisplay") then
        make login item at end with properties {path:"/Applications/ClipDisplay.app", hidden:true}
    end if
end tell
OSA
fi

echo "==> Launching"
open "$DEST"
echo "==> Done. ClipDisplay installed and running (check your menu bar)."
