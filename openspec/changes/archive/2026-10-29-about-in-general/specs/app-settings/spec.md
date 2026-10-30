# Spec Delta

## REMOVED Requirements

### Requirement: About tab
**Reason**: A tab for one line; the same content moves into General.
**Migration**: The icon, name and version are at the top of Settings → General.

## ADDED Requirements

### Requirement: App identity in General
Settings → General SHALL start with the app icon, name and installed version. The version SHALL be a link that opens the GitHub release notes for exactly that version.

#### Scenario: Open the release notes
- **WHEN** the user clicks "Version 1.3.5" in Settings → General
- **THEN** the browser opens https://github.com/juan-alvarz/Shortty/releases/tag/v1.3.5

#### Scenario: No About tab
- **WHEN** the user opens Settings
- **THEN** it has the General and Shortcuts tabs only
