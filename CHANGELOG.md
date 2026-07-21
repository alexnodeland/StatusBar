# Changelog

All notable changes to StatusBar. Full release notes with downloads live on the
[GitHub Releases page](https://github.com/alexnodeland/StatusBar/releases).

## Unreleased

- Status cache file at `~/.cache/statusbar/status.json`, refreshed on
  every poll — the interface for terminal tooling
- Bundled `statusbar` CLI: status/list, `wait` (block until recovery),
  `prompt` glyph for status lines, and URL-scheme passthrough
- Per-repo scoping: a `.statusbar` file lists a project's upstream
  dependencies; `status` and `prompt` honor the nearest one
- App Intents for Shortcuts and Spotlight: Get Worst Status, Get Source
  Status, Refresh Sources
- Docs: terminal/prompt integration guides (starship, tmux, SketchyBar)
- Desktop widget: the status overview in Notification Center or on the
  desktop (small: tick strip + issue count; medium: source list)
- `statusbar version` / `--version` prints the app version
- Website: live coded renders for the widget, CLI, and status line on
  the landing and docs pages, plus a full CLI reference page

## v0.3.2 — 2026-07-20

- Menu bar icon defaults to the monochrome status symbol (check /
  warning / x by worst status) — native and readable at a glance
- New Settings → Menu Bar "Icon style" option: choose the brand tick
  strip instead; monochrome toggle now defaults on
- Fixed: menu bar colors never actually rendered (MenuBarExtra
  template flattening) — colored styles now display correctly
- Website: screenshots replaced with live, animated, subtly interactive
  code mocks; icon references versioned against stale caches

## v0.3.1 — 2026-07-20

- New app icon: the uptime tick strip on a graphite squircle
- Design pass matching the website: monospaced "data voice" for statuses,
  timestamps, uptime numbers, badges, URLs, and section headers
- Aggregate tick strip in the popover header — one tick per source
- Redesigned rows: status text never truncates; fixed-width aligned
  sparkline column with placeholder ticks while history fills
- Refreshed marketing screenshots and social card

## v0.3.0 — 2026-07-20

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
- Fixed: uptime treated minor degradation as downtime; only major/critical outages count as down now
- Added MIT LICENSE, privacy policy, and a reworked website with fresh screenshots

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
