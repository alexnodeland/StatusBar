# Changelog

All notable changes to StatusBar. Full release notes with downloads live on the
[GitHub Releases page](https://github.com/alexnodeland/StatusBar/releases).

## Unreleased

- Edit a source's name and URL without losing its history
- Snooze notifications per source (1h / 8h / 24h)
- First-run welcome screen with starting-point choices
- Search the source list
- Menu bar options: hide the issue count, monochrome icon
- Rebindable global hotkey (default ⌃⌥S), can be disabled
- Rename groups and ungroup all members
- Webhook labels and real delivery feedback on test sends
- Release notes shown in Settings → Updates when an update is available
- Export/import confirmation feedback in Settings → Data
- Release builds now also ship as a DMG
- Fixed: `statusbar://settings` did nothing until the popover was first opened

## v0.2.1 — 2026-07-20

- Fixed recovery notifications never firing
- "New sources notify at" default alert level is now applied
- Correct minimum macOS version (26) in app metadata and docs
- Safer auto-update install (atomic swap), fetch-layer hardening, retry hygiene
- Release workflow signing/notarization steps now run when secrets are configured
- Removed broken AWS catalog entry; many doc corrections

## v0.2.0 — 2026-07-20

- Gatus support: monitor self-hosted [Gatus](https://gatus.io) instances with automatic detection

## v0.1.4 — 2026-02-11

- Homebrew cask distribution, DX improvements, richer webhook formatting

## v0.1.3 — 2026-02-10

- Scriptability: shell hooks, `statusbar://` URL scheme, AppleScript dictionary

## v0.1.2 — 2026-02-10

- JSON config export/import with version tracking

## v0.1.1 — 2026-02-05

- Status history, sparklines, and uptime percentages

## v0.1.0 — 2026-02-04

- Initial release: multi-provider status monitoring from the menu bar
