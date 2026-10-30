# Tasks

## 1. Settings

- [x] 1.1 Move the icon, name and version into the top of `GeneralSettingsView` and remove the About tab; verify in the `settings-general.png` snapshot
- [x] 1.2 Make the version a link to `releases/tag/v<version>`; verify with a self-check on the URL

## 2. Integration checks

- [x] 2.1 Run `Scripts/selfcheck.sh` and the Swift 6 `xcodebuild` type-check; verify both pass
- [x] 2.2 Run `openspec validate about-in-general --strict`; verify it passes

## Workflow follow-up

- Archive the change.
