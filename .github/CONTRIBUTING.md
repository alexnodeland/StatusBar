# Contributing

## Build from Source

```bash
make build
open ./build/StatusBar.app
```

Or directly via the build script:

```bash
./build.sh
open ./build/StatusBar.app
```

## Development

All common tasks are available via `make`:

```bash
make help          # Show all targets
make build         # Dev build (arm64, fast)
make release       # Release build (universal binary + ZIP)
make test          # Run unit tests
make lint          # Run SwiftLint
make format        # Auto-format code with swift-format
make format-check  # Check formatting without modifying files
make check         # Run lint + format check + tests (CI target)
make clean         # Remove build artifacts
make install       # Build and copy .app to /Applications
```

### Prerequisites

- macOS 14+ with Xcode Command Line Tools
- [SwiftLint](https://github.com/realm/SwiftLint): `brew install swiftlint`
- [swift-format](https://github.com/swiftlang/swift-format): `brew install swift-format`

### Running Tests

Tests are compiled with `swiftc` into an XCTest bundle and run via `xcrun xctest`. The test suite covers models, helpers, and constants — no running app or network access required.

```bash
make test
```

Test files live in `Tests/` alongside JSON fixtures in `Tests/Fixtures/`. Test discovery is automatic via `xcrun xctest`.

### Code Quality

The project uses SwiftLint for style enforcement and swift-format for consistent formatting. CI runs `make check` on every push to `main` and every pull request.

Before submitting a PR:

```bash
make check         # Runs lint, format check, and tests
```

To auto-fix formatting:

```bash
make format        # Applies swift-format changes in-place
```

## Architecture

Source code lives in `Sources/`, split by responsibility:

```
Sources/
├── StatusBarApp.swift        — @main entry point, AppDelegate, MenuBarLabel, URL scheme handling
├── Constants.swift           — config values, Design enum (typography + timing), Notification.Names
├── Models.swift              — StatusSource, API models, StatusProvider, sort/filter enums, SourceState
├── Helpers.swift             — date formatters/functions, indicator color/icon mappers, compareVersions
├── StatusService.swift       — @MainActor ObservableObject managing all sources concurrently
│   ├─ detectProvider         — auto-detects provider by probing /api/v2/summary.json
│   ├─ fetchSummary           — Atlassian Statuspage API
│   ├─ fetchIncidentIO        — incident.io /proxy/widget fallback
│   └─ fetchInstatus          — Instatus summary + components mapping
├── HookManager.swift         — script hook discovery, execution with timeout, env vars + JSON stdin
├── URLSchemeHandler.swift    — statusbar:// URL route parsing and source name derivation
├── NotificationManager.swift — macOS notification delivery and permission handling
├── WebhookManager.swift      — outbound webhook delivery (Slack, Discord, Teams, generic)
├── UpdateChecker.swift       — checks GitHub Releases API for app updates (daily)
├── SharedComponents.swift    — VisualEffectBackground, HoverEffect, GlassButtonStyle, GlassCard
├── RootView.swift            — root navigation, source navigation via NotificationCenter
├── SourceListView.swift      — SourceListView, SourceRow
├── SourceDetailView.swift    — SourceDetailView, ComponentRow, IncidentCard
└── SettingsWindow.swift      — native settings window with sidebar tabs (incl. Hooks tab)
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
