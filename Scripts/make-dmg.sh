#!/bin/bash
# Package Shortty as a styled, compressed disk image: build/Shortty-<version>.dmg
# The window shows the app and an Applications shortcut over Design/dmg/background.png.
#
#   Scripts/make-dmg.sh                    # Release build first (same signing as install.sh)
#   Scripts/make-dmg.sh path/to/Shortty.app  # package an app you already built
#
# macOS only (hdiutil, tiffutil, Finder). Finder lays out the window, so it opens briefly.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Shortty"
VERSION=$(sed -nE 's/.*CFBundleShortVersionString: "([^"]+)".*/\1/p' project.yml)
OUT="build/$NAME-$VERSION.dmg"
ART="Design/dmg"

# Window and icon layout, in points. Must match the artwork in Design/dmg (660 × 400).
WIDTH=660
HEIGHT=400
ICON_SIZE=128
APP_X=165
APPS_X=495
ICONS_Y=205

if [ $# -ge 1 ]; then
  APP="$1"
else
  DERIVED=".build.noindex"
  Scripts/make-signing-cert.sh # no-op once the certificate exists
  xcodebuild -project Shortty.xcodeproj -scheme Shortty -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED" -quiet build
  APP="$DERIVED/Build/Products/Release/$NAME.app"
fi
[ -d "$APP" ] || { echo "No app at $APP"; exit 1; }

# Finder finds the disk by its name, so a second "Shortty" disk would get the other one styled.
[ -e "/Volumes/$NAME" ] && { echo "Eject the mounted $NAME disk first (/Volumes/$NAME)"; exit 1; }

WORK=$(mktemp -d)
# On failure, also detach the writable image so it isn't left mounted.
trap '[ -n "${DEVICE:-}" ] && hdiutil detach -force "$DEVICE" >/dev/null 2>&1; rm -rf "$WORK"' EXIT

# What the disk shows: the app, a link to /Applications, and the hidden background.
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
# One TIFF with both resolutions, so Retina screens get the sharp version.
tiffutil -cathidpicheck "$ART/background.png" "$ART/background@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null

# Lay the window out on a writable image, then compress it.
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg" >/dev/null
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | awk '/Apple_HFS/ { print $1 }')
VOLUME="/Volumes/$NAME"

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 200 + $WIDTH, 120 + $HEIGHT}
    set options to the icon view options of container window
    set arrangement of options to not arranged
    set icon size of options to $ICON_SIZE
    set text size of options to 13
    set background picture of options to file ".background:background.tiff"
    set position of item "$NAME.app" of container window to {$APP_X, $ICONS_Y}
    set position of item "Applications" of container window to {$APPS_X, $ICONS_Y}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

# The app icon as the disk icon (SetFile comes with the Xcode command line tools).
# After the Finder pass: done before it, the icon was missing from the finished image.
if [ -f "$VOLUME/$NAME.app/Contents/Resources/AppIcon.icns" ] && command -v SetFile >/dev/null; then
  cp "$VOLUME/$NAME.app/Contents/Resources/AppIcon.icns" "$VOLUME/.VolumeIcon.icns"
  SetFile -a C "$VOLUME"
fi

chmod -Rf go-w "$VOLUME" || true
sync
hdiutil detach "$DEVICE" >/dev/null
mkdir -p build
rm -f "$OUT"
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
echo "Made $OUT"
