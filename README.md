# StatusBar — Multi-Source macOS Menu Bar Status Monitor

A single-file SwiftUI menu bar app that monitors multiple [Atlassian Statuspage](https://www.atlassian.com/software/statuspage)-powered status pages simultaneously.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)

## Features

- **Worst-status icon** — menu bar icon reflects the worst status across all sources (green → yellow → orange → red), with a numeric badge showing how many sources have issues
- **Source list** — overview of all monitored pages with color-coded indicators and active incident badges
- **Drill-down detail** — tap any source to see components, active incidents, and recent incident history with expandable update timelines
- **Configurable sources** — line-delimited `Name | URL` format, editable in the settings view
- **Auto-refresh** — polls all sources every 5 minutes (configurable in source)
- **Concurrent fetching** — all sources refresh in parallel via Swift concurrency
- **No Dock icon** — runs as a pure menu bar agent (`LSUIElement`)

## Quick Start

```bash
chmod +x build.sh
./build.sh
open ./build/StatusBar.app
```

Or compile directly:

```bash
swiftc StatusBarApp.swift -parse-as-library -o StatusBar -framework SwiftUI -framework AppKit -target arm64-apple-macosx13.0
./StatusBar
```

## Default Sources

```
Anthropic | https://status.anthropic.com
GitHub | https://www.githubstatus.com
Cloudflare | https://www.cloudflarestatus.com
```

## Adding Sources

Click the **gear icon** → edit the source list. Format is one source per line:

```
Name | URL
```

Lines starting with `#` are treated as comments and ignored. Any Atlassian Statuspage-powered URL works. Some examples:

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

Everything lives in a single `StatusBarApp.swift` (~780 lines):

```
StatusSource          — name + URL, parsed from line-delimited text
SourceState           — per-source fetch state (summary, incidents, loading, error)
StatusService         — @MainActor ObservableObject managing all sources concurrently
RootView              — state-driven navigation: list ↔ detail ↔ settings
  ├─ SourceListView   — aggregated header + scrollable source rows
  ├─ SourceDetailView — components, active incidents, recent incidents
  └─ SettingsView     — TextEditor for line-delimited source config
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
