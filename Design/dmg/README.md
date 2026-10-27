# Disk image window

What people see when they open `Shortty-X.Y.Z.dmg`: the app, an Applications shortcut, and `background.png` behind them.
`Scripts/make-dmg.sh` builds the image from these files.

| File | What it is |
|---|---|
| `background.html` | The artwork source, 660 × 400 points |
| `background.png`, `background@2x.png` | The rendered artwork, 1× and 2×; the script joins them into one Retina-ready TIFF |
| `preview.png` | How the window looks in light and dark mode (for reviewing only) |

Layout, shared with `Scripts/make-dmg.sh`: Finder draws the app icon centered at (165, 205) and Applications at
(495, 205), both 128 pt, with their names underneath (about y 272–294). Finder draws those names black in light mode
and white in dark mode, so the artwork puts a mid-tone tag behind them that both stay readable on.

After editing `background.html`, render both sizes with Chrome:

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
cd Design/dmg
"$CHROME" --headless --hide-scrollbars --window-size=660,400 --force-device-scale-factor=1 --screenshot="$PWD/background.png" "file://$PWD/background.html"
"$CHROME" --headless --hide-scrollbars --window-size=660,400 --force-device-scale-factor=2 --screenshot="$PWD/background@2x.png" "file://$PWD/background.html"
```
