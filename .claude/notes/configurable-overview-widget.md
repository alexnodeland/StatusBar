# Configurable Overview Widget — Recovery Notes

## Feature Description

Convert `StatusOverviewWidget` from `StaticConfiguration` (shows all sources, no user config) to `AppIntentConfiguration` (user selects/reorders sources via `ConfigureOverviewIntent`). Also adds deep linking from widget tap → source list view.

**Diff stat:** 8 files changed, +83 insertions, -14 deletions

## Files Changed

### 1. `Widget/WidgetHelpers.swift` — Add `indicatorPriority()` helper

Insert **before** `widgetSourceURL`:

```swift
func indicatorPriority(_ indicator: String) -> Int {
    switch indicator {
    case "critical": return 3
    case "major": return 2
    case "minor": return 1
    case "none": return 0
    default: return -1
    }
}
```

### 2. `Sources/Constants.swift` — Add notification name

Add after `statusBarNavigateToSettingsTab`:

```swift
static let statusBarNavigateToSourceList = Notification.Name("statusBarNavigateToSourceList")
```

### 3. `Widget/WidgetViews.swift` — Update deep link URL

**Old:**
```swift
.widgetURL(URL(string: "statusbar://open")!)
```

**New:**
```swift
.widgetURL(URL(string: "statusbar://open?view=services")!)
```

### 4. `Widget/StatusBarTimelineProvider.swift` — Three changes

#### 4a. Convert `StatusOverviewProvider` to `AppIntentTimelineProvider`

**Old:**
```swift
// MARK: - Overview Provider (StaticConfiguration)

struct StatusOverviewProvider: TimelineProvider {
    typealias Entry = StatusOverviewEntry

    func placeholder(in context: Context) -> StatusOverviewEntry {
        StatusOverviewEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusOverviewEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusOverviewEntry>) -> Void) {
        let entry = currentEntry()
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func currentEntry() -> StatusOverviewEntry {
        guard let snapshot = SharedStatusSnapshot.read() else {
            return StatusOverviewEntry.placeholder
        }
        return StatusOverviewEntry(
            date: snapshot.lastUpdated,
            sources: snapshot.sources,
            worstIndicator: snapshot.worstIndicator,
            issueCount: snapshot.issueCount,
            lastUpdated: snapshot.lastUpdated
        )
    }
}
```

**New:**
```swift
// MARK: - Overview Provider (AppIntentConfiguration)

struct StatusOverviewProvider: AppIntentTimelineProvider {
    typealias Intent = ConfigureOverviewIntent
    typealias Entry = StatusOverviewEntry

    func placeholder(in context: Context) -> StatusOverviewEntry {
        StatusOverviewEntry.placeholder
    }

    func snapshot(for configuration: ConfigureOverviewIntent, in context: Context) async -> StatusOverviewEntry {
        currentEntry(for: configuration)
    }

    func timeline(for configuration: ConfigureOverviewIntent, in context: Context) async -> Timeline<StatusOverviewEntry> {
        let entry = currentEntry(for: configuration)
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    private func currentEntry(for configuration: ConfigureOverviewIntent) -> StatusOverviewEntry {
        guard let snapshot = SharedStatusSnapshot.read() else {
            return StatusOverviewEntry.placeholder
        }

        let filteredSources: [SharedSourceSnapshot]
        if let selected = configuration.sources, !selected.isEmpty {
            let selectedIDs = selected.map(\.id)
            filteredSources = selectedIDs.compactMap { id in
                snapshot.sources.first { $0.id == id }
            }
        } else {
            filteredSources = snapshot.sources
        }

        let worstIndicator = filteredSources.reduce("none") { worst, source in
            indicatorPriority(source.indicator) > indicatorPriority(worst) ? source.indicator : worst
        }
        let issueCount = filteredSources.reduce(0) { $0 + $1.activeIncidentCount }

        return StatusOverviewEntry(
            date: snapshot.lastUpdated,
            sources: filteredSources,
            worstIndicator: worstIndicator,
            issueCount: issueCount,
            lastUpdated: snapshot.lastUpdated
        )
    }
}
```

#### 4b. Add `ConfigureOverviewIntent` struct

Insert **before** `SelectSourceIntent`:

```swift
struct ConfigureOverviewIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Configure Overview"
    static let description: IntentDescription = "Choose which status sources to display and their order"

    @Parameter(title: "Sources")
    var sources: [WidgetSourceEntity]?

    init() {
        self.sources = nil
    }

    init(sources: [WidgetSourceEntity]) {
        self.sources = sources
    }
}
```

### 5. `Widget/StatusBarWidget.swift` — Switch to `AppIntentConfiguration`

**Old:**
```swift
StaticConfiguration(kind: kind, provider: StatusOverviewProvider()) { entry in
    StatusOverviewWidgetEntryView(entry: entry)
        .containerBackground(for: .widget) {
            ContainerRelativeShape()
                .fill(widgetColorForIndicator(entry.worstIndicator).opacity(0.08))
        }
}
.configurationDisplayName("Status Overview")
.description("Shows the aggregate status of all monitored services.")
```

**New:**
```swift
AppIntentConfiguration(
    kind: kind,
    intent: ConfigureOverviewIntent.self,
    provider: StatusOverviewProvider()
) { entry in
    StatusOverviewWidgetEntryView(entry: entry)
        .containerBackground(for: .widget) {
            ContainerRelativeShape()
                .fill(widgetColorForIndicator(entry.worstIndicator).opacity(0.08))
        }
}
.configurationDisplayName("Status Overview")
.description("Shows the aggregate status of monitored services. Select and reorder sources to customize.")
```

### 6. `Sources/URLSchemeHandler.swift` — Three edits

#### 6a. Add `.openServices` route case

```swift
case open
case openServices      // ← NEW
case openSource(String)
```

#### 6b. Update `parseOpen` to handle `view=services`

**Old:**
```swift
private static func parseOpen(_ queryItems: [URLQueryItem]) -> URLRoute {
    if let sourceName = queryValue("source", from: queryItems), !sourceName.isEmpty {
        return .openSource(sourceName)
    }
    return .open
}
```

**New:**
```swift
private static func parseOpen(_ queryItems: [URLQueryItem]) -> URLRoute {
    if let sourceName = queryValue("source", from: queryItems), !sourceName.isEmpty {
        return .openSource(sourceName)
    }
    if let view = queryValue("view", from: queryItems), view == "services" {
        return .openServices
    }
    return .open
}
```

#### 6c. Add execution handler for `.openServices`

Insert after `case .open: showPopover()`:

```swift
case .openServices:
    showPopover()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        NotificationCenter.default.post(name: .statusBarNavigateToSourceList, object: nil)
    }
```

### 7. `Sources/RootView.swift` — Add `.onReceive` handler

Add after the existing `.onReceive` for `statusBarNavigateToSource`:

```swift
.onReceive(NotificationCenter.default.publisher(for: .statusBarNavigateToSourceList)) { _ in
    withAnimation(
        reduceMotionAnimation(Design.Timing.transition, reduceMotion: reduceMotion)
    ) {
        destination = .sourceList
    }
}
```

### 8. `Tests/URLSchemeHandlerTests.swift` — Add test case

Insert before `testParseOpenWithEncodedSource`:

```swift
func testParseOpenWithServicesView() {
    let url = URL(string: "statusbar://open?view=services")!
    XCTAssertEqual(URLRoute.parse(url), .openServices)
}
```

## Critical Build Error & Fix

First build fails with:

```
appintentsmetadataprocessor error: Encountered a non-optional type for parameter: sources.
Conformance to the following AppIntent protocols requires all parameter types to be optional:
AppIntents.WidgetConfigurationIntent
```

**Fix:** `@Parameter` types in `WidgetConfigurationIntent` MUST be optional:
- `var sources: [WidgetSourceEntity]` → `var sources: [WidgetSourceEntity]?`
- `init()` sets `self.sources = nil` (not `[]`)
- Filtering uses `if let selected = configuration.sources, !selected.isEmpty` with `else` branch
