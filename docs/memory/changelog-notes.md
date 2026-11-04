# Changelog notes

Critical changes only: behavior users notice, data or settings formats, architecture moves. Newest first.

- **2026-11-03** · OpenSpec removed (`openspec/`, its skills and commands). Project memory lives in `docs/memory/`.
- **2026-11-03** · Install target is `/Applications/Shortty.app` for every account. `install.sh --profile-only` is gone; delete old `~/Applications/Shortty.app` copies.
- **2026-11-03** · New setting: UserDefaults `historyLimit` (Int, 1–50, default 20) replaces the fixed 20-capture history.
- **2026-11-03** · Editor: marquee selects only fully enclosed items, pictures included. Double-click empty space with Select starts text. Unreadable history captures show a red "!".
- **2026-10-29** · Settings: the About tab is gone. The icon, name and version (linked to its release notes) head General.
- **2026-10-29** · Dragging from Recent captures hands over a rendered PNG with the edits, not the raw capture file.
- **2026-10-28** · Steps gained an optional `tip` (saved edits). Edits saved before that still decode.
- **2026-10-24** · History format: `<timestamp>.png`, plus `<timestamp>.json` (Codable `SavedEdits`) and `<timestamp>.preview.png` when edited, in `~/Library/Caches/com.shortty.Shortty/History`.
- **2026-10-23** · No capture shortcuts by default; the user records each one.
- **2026-10-22** · Bundle id is `com.shortty.Shortty` (was `com.socialgoodsoftware…`). This moved the defaults domain and reset the Screen Recording grant.
