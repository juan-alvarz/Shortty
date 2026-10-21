#!/bin/bash
# Build Release, install to /Applications, launch. Creates the signing certificate on first run.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.socialgoodsoftware.Shortty"
APP="/Applications/Shortty.app"
# ".noindex" keeps Spotlight/Raycast from listing the build copies next to the installed app.
DERIVED=".build.noindex"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if ! security find-identity -v -p codesigning | grep -q '"Shortty Dev"'; then
  Scripts/make-signing-cert.sh
  # Forget any grant tied to an old ad-hoc build so the next capture prompts cleanly once.
  tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

xcodebuild -project Shortty.xcodeproj -scheme Shortty -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED" -quiet build

pkill -x Shortty 2>/dev/null || true
# Wait for it to exit; opening while it's still quitting fails with LaunchServices error -600.
for _ in $(seq 25); do pgrep -x Shortty >/dev/null || break; sleep 0.2; done
rm -rf "$APP"
ditto "$DERIVED/Build/Products/Release/Shortty.app" "$APP"
# ditto keeps the build folder's original date; launchers and icon caches only refresh when it changes.
touch "$APP"
"$LSREGISTER" -f "$APP"
codesign -dr - "$APP" 2>&1 | grep designated
# Launch Services can still be registering the replaced bundle; error -600 means "try again in a moment".
for attempt in 1 2 3 4 5; do open "$APP" 2>/dev/null && break; sleep 0.5; done
sleep 1; pgrep -x Shortty >/dev/null || { echo "Shortty did not start; run: open $APP"; exit 1; }
echo "Installed and launched $APP"
