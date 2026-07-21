// StatusCache.swift
// Machine-readable status snapshot written on every refresh.
// Terminal tools (the statusbar CLI, prompt segments, SketchyBar, tmux)
// read this file instead of talking to the app.

import Foundation

// MARK: - Cache Model

struct StatusCacheSource: Codable, Equatable {
    let name: String
    let url: String
    let indicator: String
    let description: String
    let group: String?
    let snoozed: Bool
}

struct StatusCacheSnapshot: Codable, Equatable {
    let updatedAt: String
    let worst: String
    let issueCount: Int
    let sources: [StatusCacheSource]

    static let version = 1
}

// MARK: - Cache Writer / Reader

struct StatusCache {
    /// Default location: `~/.cache/statusbar/status.json` — the terminal-tool
    /// convention, stable for prompt integrations.
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache")
            .appendingPathComponent("statusbar")
            .appendingPathComponent("status.json")
    }

    let fileURL: URL

    init(fileURL: URL = StatusCache.defaultURL) {
        self.fileURL = fileURL
    }

    func write(_ snapshot: StatusCacheSnapshot) {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        do {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            // Atomic: write to a temp file, then rename over the target
            let tempURL = dir.appendingPathComponent(UUID().uuidString + ".tmp")
            try data.write(to: tempURL)
            _ = try fm.replaceItemAt(fileURL, withItemAt: tempURL)
        } catch {
            #if DEBUG
                print("StatusCache: failed to write: \(error)")
            #endif
        }
    }

    func read() -> StatusCacheSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(StatusCacheSnapshot.self, from: data)
    }

    static func snapshot(sources: [StatusSource], states: [UUID: SourceState]) -> StatusCacheSnapshot {
        let cacheSources = sources.map { source -> StatusCacheSource in
            let state = states[source.id] ?? SourceState()
            return StatusCacheSource(
                name: source.name,
                url: source.baseURL,
                indicator: state.indicator,
                description: state.statusDescription,
                group: source.group,
                snoozed: source.isSnoozed
            )
        }
        let worst =
            states.values.max(by: { $0.indicatorSeverity < $1.indicatorSeverity })?.indicator ?? "unknown"
        let issues = states.values.filter { $0.indicator != "none" && $0.indicator != "unknown" }.count
        return StatusCacheSnapshot(
            updatedAt: isoFormatterNoFrac.string(from: Date()),
            worst: worst,
            issueCount: issues,
            sources: cacheSources
        )
    }
}
