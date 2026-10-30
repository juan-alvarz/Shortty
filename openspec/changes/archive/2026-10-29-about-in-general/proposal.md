# Proposal

## Why

The About tab holds only the icon, name and version, a whole tab for one line. Moving it into General removes a tab,
and turning the version into a link gives a direct path to what changed in the installed version.

## What Changes

- The app icon, name and version move to the top of Settings → General; the About tab is removed.
- The version is a link to that version's GitHub release notes (`releases/tag/v<version>`).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-settings`: the About tab requirement becomes an app identity header in General with a release notes link.

## Impact

- `Shortty/Settings/SettingsView.swift`, `Scripts/SelfCheck/main.swift`.
