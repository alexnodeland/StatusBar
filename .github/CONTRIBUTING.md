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
StatusSnapshot        — timestamped status check for history tracking
SourceState           — per-source fetch state (summary, incidents, loading, error, provider, history)
StatusProvider        — enum: .atlassian, .incidentIOCompat, .incidentIO, .instatus
StatusService         — @MainActor ObservableObject managing all sources concurrently
  ├─ detectProvider   — auto-detects provider by probing /api/v2/summary.json
  ├─ withRetry        — exponential backoff retry (3 attempts, 1s/2s/4s delays)
  ├─ fetchSummary     — Atlassian Statuspage API
  ├─ fetchIncidentIO  — incident.io /proxy/widget fallback
  └─ fetchInstatus    — Instatus summary + components mapping
UpdateChecker         — checks GitHub Releases API for app updates (daily)
NotificationManager   — macOS notification delivery and permission handling
RootView              — state-driven navigation: list ↔ detail ↔ settings
  ├─ SourceListView   — aggregated header + scrollable source rows
  ├─ SourceDetailView — components, active incidents, sparkline, recent incidents
  ├─ StatusSparkline  — visual history bar chart with uptime percentage
  └─ SettingsView     — visual source management, preferences, URL validation, updates
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

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+R` | Refresh all sources |
| `Cmd+,` | Open settings |
| `Esc` | Go back (detail → list, settings → list) |

## Network Resilience

All fetch operations use automatic retry with exponential backoff:

- **3 attempts** per request with delays of 1s, 2s, 4s between retries
- On failure after retries, last-known-good data is preserved and marked as **stale**
- Stale data displays with a clock badge and "(stale)" status suffix
- Provider detection cache is cleared on failure to allow re-detection on next success

## Status History

Each source tracks the last 30 status check results. The detail view shows:

- **Sparkline bar chart** — color-coded bars (green/yellow/orange/red) with height proportional to severity
- **Uptime percentage** — ratio of operational checks to total checks
- History resets when the app restarts (in-memory only)

## Roadmap — WidgetKit

- WidgetKit extension showing aggregated status or per-source widgets
- `TimelineProvider` with `IntentConfiguration` for source selection
- Shared data via App Groups between host app and widget extension
- Desktop widget with compact component grid
