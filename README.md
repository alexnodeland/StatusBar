<div align="center">

<img src="docs/icon.png" width="120" alt="StatusBar icon">

# StatusBar

### Is it down, or is it you?

**Every status page you care about — the services you depend on and the infrastructure you run — in one macOS menu bar icon.**

Auto-detects [Atlassian Statuspage](https://www.atlassian.com/software/statuspage) · [incident.io](https://incident.io) · [Instatus](https://instatus.com) · self-hosted [Gatus](https://gatus.io)

<br>

[![Download for macOS](https://img.shields.io/badge/⬇%C2%A0_Download_for_macOS-0A7C3F?style=for-the-badge)](https://github.com/alexnodeland/StatusBar/releases/latest)
[![Website](https://img.shields.io/badge/🌐%C2%A0_Website-1B1D22?style=for-the-badge)](https://alexnodeland.github.io/StatusBar/)
[![Support](https://img.shields.io/badge/♥%C2%A0_Support-%242.99-FF5A76?style=for-the-badge)](https://ournature.gumroad.com/l/statusbar)

<img src="https://img.shields.io/badge/macOS-26%2B-blue" alt="macOS 26+">
<img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License"></a>
<a href="https://github.com/alexnodeland/StatusBar/actions/workflows/ci.yml"><img src="https://github.com/alexnodeland/StatusBar/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/alexnodeland/StatusBar/releases/latest"><img src="https://img.shields.io/github/v/release/alexnodeland/StatusBar" alt="GitHub Release"></a>

<br>

<img src="docs/tick-divider.svg" width="260" alt="">

<br>

<img src="docs/screenshots/source_list.png" width="380" alt="StatusBar popover: grouped sources with live statuses and aligned tick sparklines, one Cloudflare incident highlighted">&nbsp;&nbsp;<img src="docs/screenshots/event_details.png" width="380" alt="Source detail: active incident card, per-component statuses, and mono uptime badges">

<sub>Free & open source · zero telemetry · no Dock icon · no Electron</sub>

</div>

<br>

## The whole story in four colors

Every provider's status vocabulary maps onto the same four levels — the menu bar icon always shows the worst one, so one glance answers the question.

| | | |
|:---:|:---|:---|
| 🟢 | `operational` | All systems normal. The icon stays a quiet checkmark. |
| 🟡 | `degraded` | Performance issues. Worth a glance, not a page. |
| 🟠 | `partial outage` | Some services affected. Notifications fire. |
| 🔴 | `major outage` | Significant disruption. You already know why the graphs fell over. |

## Install

### Homebrew

```bash
brew tap alexnodeland/tap
brew install --cask statusbar
```

### Direct download

1. Grab `StatusBar-vX.Y.Z.dmg` (or the `.zip`) from the [latest release](https://github.com/alexnodeland/StatusBar/releases/latest)
2. Drag `StatusBar.app` to `/Applications`
3. Remove quarantine: `xattr -cr /Applications/StatusBar.app`

Universal binary — Apple Silicon and Intel. Updates arrive via `brew upgrade`, or let the app update itself.

## Features

🟢 **Monitoring** — the menu bar icon reflects the worst status across all sources, with an optional issue-count badge and a choice of icon styles (status symbol or the brand tick strip, monochrome or color). Drill into any source for components, incident timelines, and 24h/7d/30d uptime with per-check sparklines.

📋 **Sources** — add, edit, group, search, sort, and filter; snooze noisy sources for an hour or a day. Bulk import/export as JSON — the full configuration export bundles settings, sources, and webhooks into one versioned file. Sources refresh concurrently on a configurable interval (1–15 min).

🔔 **Notifications** — native macOS alerts on status changes and recoveries, with per-source alert levels and a first-run welcome that starts you with popular picks or your own list.

📣 **Webhooks** — push status changes to Slack (Block Kit), Discord (embeds), Microsoft Teams (Adaptive Cards), or any JSON endpoint — with per-webhook labels and real delivery feedback on test sends.

⌨️ **At your fingertips** — a rebindable global hotkey (default `⌃⌥S`), a `statusbar://` URL scheme, script hooks, and a full AppleScript dictionary. Runs as a pure menu bar agent.

<div align="center"><br><img src="docs/tick-divider.svg" width="260" alt=""><br><br></div>

## Sources

The app ships with three default sources:

| Name | URL |
|------|-----|
| Anthropic | `https://status.anthropic.com` |
| GitHub | `https://www.githubstatus.com` |
| Cloudflare | `https://www.cloudflarestatus.com` |

Open **Settings** and click **+** to add more, or browse the built-in catalog. The app auto-detects the provider — no configuration needed.

<details>
<summary>Example sources</summary>

| Service | Provider | URL |
|---------|----------|-----|
| Atlassian | Atlassian Statuspage | `https://status.atlassian.com` |
| Datadog | Atlassian Statuspage | `https://status.datadoghq.com` |
| Linear | incident.io | `https://linearstatus.com` |
| Notion | Atlassian Statuspage | `https://status.notion.so` |
| Zed | Instatus | `https://status.zed.dev` |
| Deno | Instatus | `https://denostatus.com` |
| Gatus demo | Gatus | `https://status.twin.sh` |

</details>

> **Note:** Incident history detail varies by provider. Atlassian Statuspage sources include full incident timelines. incident.io and Instatus sources may have limited or unavailable incident details due to provider API restrictions. Gatus sources report per-endpoint health (each endpoint appears as a component) but have no incident history.

Sources are persisted as JSON via `@AppStorage` and survive restarts. Use **Settings → Data** to export/import a full configuration (settings, sources, webhooks) or sources only.

## URL Scheme

Control the app from anywhere using `statusbar://` URLs:

```bash
open "statusbar://open"                                          # Show popover
open "statusbar://open?source=GitHub"                            # Navigate to source
open "statusbar://refresh"                                       # Refresh all sources
open "statusbar://add?url=https://status.openai.com&name=OpenAI" # Add a source
open "statusbar://remove?name=GitHub"                            # Remove a source
open "statusbar://settings"                                      # Open settings
open "statusbar://settings?tab=webhooks"                         # Open settings tab
```

Works with Terminal, browsers, Raycast, Alfred, macOS Shortcuts, and anything that can open URLs.

## Script Hooks

Place executable scripts in `~/Library/Application Support/StatusBar/hooks/` and they run automatically on status events. Use **Settings → Hooks → Add Example Hook** to create a starter script.

**Events:**

| Event | When |
|-------|------|
| `on-status-change` | A source's status severity changes (e.g. none → major) |
| `on-refresh` | All sources finish refreshing |
| `on-source-add` | A new source is added |
| `on-source-remove` | A source is removed |

**Environment variables:**

| Variable | Events |
|----------|--------|
| `STATUSBAR_EVENT` | All |
| `STATUSBAR_SOURCE_NAME` | status-change, add, remove |
| `STATUSBAR_SOURCE_URL` | status-change, add, remove |
| `STATUSBAR_TITLE` / `STATUSBAR_BODY` | status-change |
| `STATUSBAR_SOURCE_COUNT` / `STATUSBAR_WORST_LEVEL` | refresh |

A full JSON payload is also piped to stdin. Scripts can be any language (bash, python, etc.) — just add a shebang and make them executable. 30-second timeout per execution.

<details>
<summary>Example hook</summary>

```bash
#!/bin/bash
# Log status changes to a file
[ "$STATUSBAR_EVENT" = "on-status-change" ] || exit 0

LOG="$HOME/Library/Logs/StatusBar/hooks.log"
mkdir -p "$(dirname "$LOG")"
echo "[$(date)] $STATUSBAR_SOURCE_NAME: $STATUSBAR_TITLE" >> "$LOG"
```

</details>

## AppleScript

StatusBar exposes a full scripting dictionary for AppleScript and JXA (JavaScript for Automation). Open Script Editor → File → Open Dictionary → StatusBar to browse it.

```applescript
tell application "StatusBar"
    get name of every source           -- list source names
    get status of source "GitHub"      -- "none" / "minor" / "major" / "critical" / "unknown"
    get worst status                   -- aggregate worst status
    get issue count                    -- number of sources with issues

    refresh                            -- trigger immediate refresh
    add source "https://status.openai.com" named "OpenAI"
    remove source "OpenAI"
end tell
```

Works from Terminal too:

```bash
osascript -e 'tell application "StatusBar" to get name of every source'
osascript -e 'tell application "StatusBar" to get worst status'
osascript -e 'tell application "StatusBar" to refresh'
```

<details>
<summary>Source properties</summary>

| Property | Type | Description |
|----------|------|-------------|
| `id` | text | Unique identifier (UUID) |
| `name` | text | Display name |
| `url` | text | Base URL of the status page |
| `status` | text | Current indicator (`none`, `minor`, `major`, `critical`, `unknown`) |
| `status description` | text | Human-readable status |
| `alert level` | text | Alert level setting |
| `group` | text | Group name (empty string if ungrouped) |

</details>

## Development

```bash
make setup                            # One-time: brew bundle + git hooks
make build                            # Dev build
make test                             # Run tests
make check                            # Full CI check (lint + format + test)
make release                          # Release build (universal binary + DMG + ZIP)
```

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for build instructions, architecture overview, and roadmap.

<br>

<div align="center">

<img src="docs/tick-divider.svg" width="260" alt="">

<br>

**StatusBar is free and open source.**
If it saves you a tab — or an incident call — you can [support development on Gumroad](https://ournature.gumroad.com/l/statusbar) for $2.99.

[Changelog](CHANGELOG.md) · [Privacy](PRIVACY.md) <sub>(zero telemetry)</sub> · [Issues](https://github.com/alexnodeland/StatusBar/issues) · [alex@ournature.studio](mailto:alex@ournature.studio)

<sub>Built with SwiftUI · MIT licensed</sub>

</div>
