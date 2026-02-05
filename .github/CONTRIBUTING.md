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
SourceState           — per-source fetch state (summary, incidents, loading, error, provider)
StatusProvider        — enum: .atlassian, .incidentIOCompat, .incidentIO, .instatus
StatusService         — @MainActor ObservableObject managing all sources concurrently
  ├─ detectProvider   — auto-detects provider by probing /api/v2/summary.json
  ├─ fetchSummary     — Atlassian Statuspage API
  ├─ fetchIncidentIO  — incident.io /proxy/widget fallback
  └─ fetchInstatus    — Instatus summary + components mapping
UpdateChecker         — checks GitHub Releases API for app updates (daily)
NotificationManager   — macOS notification delivery and permission handling
RootView              — state-driven navigation: list ↔ detail ↔ settings
  ├─ SourceListView   — aggregated header + scrollable source rows
  ├─ SourceDetailView — components, active incidents, recent incidents
  └─ SettingsView     — visual source management, preferences, updates
MenuBarLabel          — worst-status icon + issue count badge
```

## Supported Providers

The app auto-detects the provider for each source URL. No configuration needed.

| Provider | Detection | Status | Components | Incident History |
|----------|-----------|--------|------------|------------------|
| **Atlassian Statuspage** | `time_zone` in page object | Full | Full | Full with update timelines |
| **incident.io** (compat) | Atlassian-format API, no `time_zone` | Full | Full | Names and dates only (no details) |
| **incident.io** (fallback) | `/proxy/widget` | Derived from incidents | None | Ongoing only |
| **Instatus** | Page status as plain string (`UP`, `HASISSUES`) | Mapped | Full | Not available (requires auth) |

## API Endpoints

### Atlassian Statuspage

Uses the public [Statuspage API v2](https://developer.statuspage.io/) — no API key required:

- `GET /api/v2/summary.json` — overall status, components, active incidents
- `GET /api/v2/incidents.json` — full incident history

### incident.io

incident.io pages serve Atlassian-compatible endpoints (same as above). Falls back to:

- `GET /proxy/widget` — ongoing incidents and maintenances

### Instatus

- `GET /api/v2/summary.json` — page name and status (`UP`, `HASISSUES`, `UNDERMAINTENANCE`)
- `GET /api/v2/components.json` — component tree with status

## Roadmap — WidgetKit

- WidgetKit extension showing aggregated status or per-source widgets
- `TimelineProvider` with `IntentConfiguration` for source selection
- Shared data via App Groups between host app and widget extension
- Desktop widget with compact component grid
