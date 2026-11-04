#!/bin/bash
# Build Release, install to /Applications (one copy for every account on this Mac), launch.
# Creates the signing certificate on first run.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="/Applications/Shortty.app"
# ".noindex" keeps Spotlight/Raycast from listing the build copies next to the installed app.
DERIVED=".build.noindex"

Scripts/make-signing-cert.sh # no-op once the certificate exists

xcodebuild -project Shortty.xcodeproj -scheme Shortty -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED" -quiet build

# -u: with fast user switching, another account's Shortty may be running too.
pkill -u "$USER" -x Shortty 2>/dev/null || true
# Wait for it to exit; opening while it's still quitting fails with LaunchServices error -600.
for _ in $(seq 25); do pgrep -u "$USER" -x Shortty >/dev/null || break; sleep 0.2; done
mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
BUILT="$DERIVED/Build/Products/Release/Shortty.app"
ditto "$BUILT" "$APP" # keeps the build's fresh folder date (see project.yml)
chmod -R go+rX "$APP" # other accounts run this same copy
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Otherwise login items and `open` can launch a build copy, which has no Screen Recording grant.
for built in "$DERIVED"/Build/Products/*/Shortty.app; do "$LSREGISTER" -u "$built" 2>/dev/null || true; done
"$LSREGISTER" -f "$APP"
codesign -dr - "$APP" 2>&1 | grep designated
# Launch Services can still be registering the replaced bundle; error -600 means "try again in a moment".
for attempt in 1 2 3 4 5; do open "$APP" 2>/dev/null && break; sleep 0.5; done
sleep 1; pgrep -u "$USER" -x Shortty >/dev/null || { echo "Shortty did not start; run: open $APP"; exit 1; }
echo "Installed and launched $APP"
