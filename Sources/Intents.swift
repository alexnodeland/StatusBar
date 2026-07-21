// Intents.swift
// App Intents: StatusBar in Shortcuts, Spotlight, and personal automations.
// Reads the live service when the app is running, the status cache otherwise.

import AppIntents
import Foundation

// MARK: - Helpers

private func liveOrCachedSnapshot() async -> StatusCacheSnapshot? {
    if let service = AppRuntime.service {
        return await MainActor.run {
            StatusCache.snapshot(sources: service.sources, states: service.states)
        }
    }
    return StatusCache().read()
}

// MARK: - Get Worst Status

struct GetWorstStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Worst Status"
    static let description = IntentDescription(
        "The worst status level across all monitored sources: none, minor, major, critical, or unknown."
    )

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let snapshot = await liveOrCachedSnapshot()
        let worst = snapshot?.worst ?? "unknown"
        let issues = snapshot?.issueCount ?? 0
        let dialog: IntentDialog =
            issues == 0
            ? "All systems operational."
            : "\(issues) source\(issues == 1 ? "" : "s") with issues — worst is \(worst)."
        return .result(value: worst, dialog: dialog)
    }
}

// MARK: - Get Source Status

struct GetSourceStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Source Status"
    static let description = IntentDescription(
        "The current status of one monitored source, by name."
    )

    @Parameter(title: "Source name")
    var name: String

    static var parameterSummary: some ParameterSummary {
        Summary("Get status of \(\.$name)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let snapshot = await liveOrCachedSnapshot() else {
            throw IntentError.noData
        }
        guard
            let source = snapshot.sources.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            })
                ?? snapshot.sources.first(where: {
                    $0.name.lowercased().contains(name.lowercased())
                })
        else {
            throw IntentError.sourceNotFound(name)
        }
        return .result(
            value: source.indicator,
            dialog: "\(source.name): \(source.description)"
        )
    }
}

// MARK: - Refresh

struct RefreshSourcesIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Sources"
    static let description = IntentDescription("Refresh all monitored status pages now.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The intent runs in the app process; the service appears shortly
        // after a cold launch.
        for _ in 0..<30 where AppRuntime.service == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let service = AppRuntime.service else {
            throw IntentError.appNotRunning
        }
        await service.refreshAll()
        let issues = await MainActor.run { service.issueCount }
        let dialog: IntentDialog =
            issues == 0
            ? "Refreshed — all systems operational."
            : "Refreshed — \(issues) source\(issues == 1 ? "" : "s") with issues."
        return .result(dialog: dialog)
    }
}

// MARK: - Errors

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noData
    case sourceNotFound(String)
    case appNotRunning

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noData:
            return "No status data yet — launch StatusBar once."
        case .sourceNotFound(let name):
            return "No source matching “\(name)”."
        case .appNotRunning:
            return "StatusBar isn't running."
        }
    }
}

// MARK: - App Shortcuts (Spotlight phrases)

struct StatusBarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetWorstStatusIntent(),
            phrases: [
                "Get status in \(.applicationName)",
                "Is anything down in \(.applicationName)",
            ],
            shortTitle: "Worst Status",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: RefreshSourcesIntent(),
            phrases: ["Refresh \(.applicationName)"],
            shortTitle: "Refresh",
            systemImageName: "arrow.clockwise"
        )
    }
}
