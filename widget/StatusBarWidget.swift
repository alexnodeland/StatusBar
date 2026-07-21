// StatusBarWidget.swift
// Desktop/Notification Center widget: the status overview at a glance.
// Reads the status cache the app maintains; refreshes on a timeline.

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: StatusCacheSnapshot?
}

struct WidgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: Date(), snapshot: StatusCache.readShared() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let entry = StatusEntry(date: Date(), snapshot: StatusCache.readShared())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
    }
}

extension StatusCacheSnapshot {
    static let placeholder = StatusCacheSnapshot(
        updatedAt: "",
        worst: "none",
        issueCount: 0,
        sources: [
            StatusCacheSource(
                name: "GitHub", url: "", indicator: "none",
                description: "All Systems Operational", group: nil, snoozed: false),
            StatusCacheSource(
                name: "Cloudflare", url: "", indicator: "minor",
                description: "Minor Service Outage", group: nil, snoozed: false),
            StatusCacheSource(
                name: "Anthropic", url: "", indicator: "none",
                description: "All Systems Operational", group: nil, snoozed: false),
        ]
    )
}

// MARK: - Shared bits

func widgetColor(_ indicator: String) -> Color {
    switch indicator {
    case "none": return .green
    case "minor": return .yellow
    case "major": return .orange
    case "critical": return .red
    default: return .gray
    }
}

struct WidgetTick: View {
    let indicator: String
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(widgetColor(indicator))
            .opacity(indicator == "none" ? 0.85 : 1)
            .frame(width: 4, height: indicator == "none" ? 10 : 14)
    }
}

// MARK: - Views

struct OverviewSmallView: View {
    let snapshot: StatusCacheSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(snapshot.sources.prefix(8).enumerated()), id: \.offset) { _, source in
                    WidgetTick(indicator: source.indicator)
                }
            }
            .frame(height: 14, alignment: .bottom)

            Spacer(minLength: 0)

            if snapshot.issueCount == 0 {
                Text("all systems\noperational")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("\(snapshot.issueCount) issue\(snapshot.issueCount == 1 ? "" : "s")")
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(widgetColor(snapshot.worst))
                Text(snapshot.worstSourceName ?? "")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct OverviewMediumView: View {
    let snapshot: StatusCacheSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(snapshot.sources.prefix(6).enumerated()), id: \.offset) { _, source in
                HStack(spacing: 8) {
                    Circle()
                        .fill(widgetColor(source.indicator))
                        .frame(width: 7, height: 7)
                    Text(source.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(source.indicator == "none" ? "ok" : source.indicator)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(
                            source.indicator == "none" ? Color.secondary : widgetColor(source.indicator))
                }
            }
            if snapshot.sources.count > 6 {
                Text("+ \(snapshot.sources.count - 6) more")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension StatusCacheSnapshot {
    var worstSourceName: String? {
        let rank = ["none": 0, "minor": 1, "major": 2, "critical": 3]
        return sources.max { (rank[$0.indicator] ?? -1) < (rank[$1.indicator] ?? -1) }?.name
    }
}

struct OverviewWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemMedium:
                    OverviewMediumView(snapshot: snapshot)
                default:
                    OverviewSmallView(snapshot: snapshot)
                }
            } else {
                VStack(spacing: 4) {
                    Text("○")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Launch StatusBar\nto start monitoring")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .containerBackground(for: .widget) {
            Color(red: 0.10, green: 0.11, blue: 0.13)
        }
    }
}

// MARK: - Widget

struct StatusOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StatusOverview", provider: WidgetTimelineProvider()) { entry in
            OverviewWidgetView(entry: entry)
        }
        .configurationDisplayName("Status Overview")
        .description("Every status page you care about, at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct StatusBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusOverviewWidget()
    }
}
