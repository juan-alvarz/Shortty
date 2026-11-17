#!/usr/bin/env bash
# Release build → ~/.local/bin/shortty, with its launcher entries and icon, then restarts it.
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release
"$HOME/.local/bin/shortty" quit 2>/dev/null || true
install -Dm755 target/release/shortty "$HOME/.local/bin/shortty"
apps="$HOME/.local/share/applications"
# Absolute paths, so launchers work whatever their PATH is.
for entry in packaging/*.desktop; do
  install -d "$apps"
  sed "s|^Exec=shortty|Exec=$HOME/.local/bin/shortty|" "$entry" > "$apps/$(basename "$entry")"
done
install -Dm644 ../Design/AppIcon.svg "$HOME/.local/share/icons/hicolor/scalable/apps/com.shortty.Shortty.svg"
update-desktop-database -q "$apps" || true
gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
pkill -x shortty 2>/dev/null || true # a build copy still running
setsid "$HOME/.local/bin/shortty" >/dev/null 2>&1 < /dev/null &
echo "Installed ~/.local/bin/shortty"
