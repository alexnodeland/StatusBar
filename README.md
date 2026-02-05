<p align="center">
  <img src="icon.png" width="128" alt="StatusBar icon">
</p>

<h1 align="center">StatusBar</h1>

<p align="center">
  A single-file SwiftUI menu bar app that monitors multiple <a href="https://www.atlassian.com/software/statuspage">Atlassian Statuspage</a>-powered status pages simultaneously.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange" alt="Swift 5.9+">
  <a href="https://github.com/alexnodeland/StatusBar/releases/latest"><img src="https://img.shields.io/github/v/release/alexnodeland/StatusBar" alt="GitHub Release"></a>
</p>

## Features

- **Worst-status icon** — menu bar icon reflects the worst status across all sources (green → yellow → orange → red), with a numeric badge showing how many sources have issues
- **Source list** — overview of all monitored pages with color-coded indicators and active incident badges
- **Drill-down detail** — tap any source to see components, active incidents, and recent incident history with expandable update timelines
- **Visual source management** — add sources with **+**, remove with **−**, or bulk import/export as TSV files
- **Automatic refresh** — polls all sources on a configurable interval (1–15 min) with concurrent fetching via Swift concurrency
- **Check for updates** — queries GitHub Releases for new versions, with optional automatic daily checks
- **Status change notifications** — native macOS notifications when a source's status changes, with a toggle to disable
- **Launch at login** — toggle in Settings, backed by `SMAppService`
- **No Dock icon** — runs as a pure menu bar agent (`LSUIElement`)

## Download

Grab the latest release from the [Releases page](https://github.com/alexnodeland/StatusBar/releases/latest).

1. Download `StatusBar-vX.Y.Z-universal.zip`
2. Extract the ZIP
3. Drag `StatusBar.app` to `/Applications`
4. On first launch, right-click → **Open** to bypass Gatekeeper (the app is ad-hoc signed, not notarized)

The universal binary runs natively on both Apple Silicon and Intel Macs.

## Build from Source

```bash
chmod +x build.sh
./build.sh
open ./build/StatusBar.app
```

Or compile directly:

```bash
swiftc StatusBarApp.swift -parse-as-library -o StatusBar -framework SwiftUI -framework AppKit -target arm64-apple-macosx14.0
./StatusBar
```

## Default Sources

```
Anthropic | https://status.anthropic.com
GitHub | https://www.githubstatus.com
Cloudflare | https://www.cloudflarestatus.com
```

## Adding Sources

Open **Settings** and click the **+** button to add a source by name and URL. Remove any source with the red **−** button. You can also import and export source lists as TSV files.

Any Atlassian Statuspage-powered URL works:

| Service | URL |
|---------|-----|
| Anthropic / Claude | `https://status.anthropic.com` |
| GitHub | `https://www.githubstatus.com` |
| Cloudflare | `https://www.cloudflarestatus.com` |
| Atlassian | `https://status.atlassian.com` |
| Datadog | `https://status.datadoghq.com` |
| Vercel | `https://www.vercel-status.com` |
| Linear | `https://linearstatus.com` |
| Notion | `https://status.notion.so` |

Sources are persisted via `@AppStorage` (UserDefaults) and survive restarts.

## Architecture

Everything lives in a single `StatusBarApp.swift`:

```
StatusSource          — name + URL model with TSV serialization
 SourceState           — per-source fetch state (summary, incidents, loading, error)
StatusService         — @MainActor ObservableObject managing all sources concurrently
UpdateChecker         — checks GitHub Releases API for app updates (daily)
NotificationManager   — macOS notification delivery and permission handling
RootView              — state-driven navigation: list ↔ detail ↔ settings
  ├─ SourceListView   — aggregated header + scrollable source rows
  ├─ SourceDetailView — components, active incidents, recent incidents
  └─ SettingsView     — visual source management, preferences, updates
MenuBarLabel          — worst-status icon + issue count badge
```

## API

Uses the public [Statuspage API v2](https://developer.statuspage.io/) endpoints per source:

- `GET /api/v2/summary.json` — overall status, components, active incidents
- `GET /api/v2/incidents.json` — full incident history

No API key required for public status pages.

## Roadmap (v2 → WidgetKit)

- WidgetKit extension showing aggregated status or per-source widgets
- `TimelineProvider` with `IntentConfiguration` for source selection
- Shared data via App Groups between host app and widget extension
- Desktop widget with compact component grid
