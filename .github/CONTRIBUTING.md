# Contributing

## Build from Source

```bash
chmod +x build.sh
./build.sh
open ./build/StatusBar.app
```

Or compile directly:

```bash
swiftc StatusBarApp.swift -parse-as-library -o StatusBar \
  -framework SwiftUI -framework AppKit \
  -target arm64-apple-macosx14.0
./StatusBar
```

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

Uses the public [Statuspage API v2](https://developer.statuspage.io/) endpoints per source — no API key required:

- `GET /api/v2/summary.json` — overall status, components, active incidents
- `GET /api/v2/incidents.json` — full incident history

## Roadmap — WidgetKit

- WidgetKit extension showing aggregated status or per-source widgets
- `TimelineProvider` with `IntentConfiguration` for source selection
- Shared data via App Groups between host app and widget extension
- Desktop widget with compact component grid
