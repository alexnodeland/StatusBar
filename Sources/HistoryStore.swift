// HistoryStore.swift
// Persistent file-based storage for status history checkpoints.

import Foundation

@MainActor
final class HistoryStore {
    private let fileURL: URL
    var data: [UUID: [StatusCheckpoint]] = [:]
    private var saveTimer: Timer?
    private static let saveDebounceInterval: TimeInterval = 5.0

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = appSupport
                .appendingPathComponent("StatusBar")
                .appendingPathComponent("history.json")
        }
    }

    // MARK: - Recording

    func record(sourceID: UUID, indicator: String) {
        var checkpoints = data[sourceID] ?? []
        checkpoints.append(StatusCheckpoint(date: Date(), indicator: indicator))
        data[sourceID] = checkpoints
        save()
    }

    // MARK: - Queries

    func checkpoints(for sourceID: UUID, since: Date) -> [StatusCheckpoint] {
        guard let all = data[sourceID] else { return [] }
        return all.filter { $0.date >= since }
    }

    func uptimeFraction(for sourceID: UUID, since: Date) -> Double {
        let recent = checkpoints(for: sourceID, since: since)
        guard !recent.isEmpty else { return 1.0 }
        let operational = recent.filter { $0.indicator == "none" }.count
        return Double(operational) / Double(recent.count)
    }

    // MARK: - Cleanup

    func removeSource(_ id: UUID) {
        data.removeValue(forKey: id)
        save()
    }

    func pruneOlderThan(_ date: Date) {
        var changed = false
        for (id, checkpoints) in data {
            let filtered = checkpoints.filter { $0.date >= date }
            if filtered.count != checkpoints.count {
                data[id] = filtered.isEmpty ? nil : filtered
                changed = true
            }
        }
        if changed {
            save()
        }
    }

    // MARK: - Persistence

    func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        do {
            let rawData = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([String: [StatusCheckpoint]].self, from: rawData)
            var result: [UUID: [StatusCheckpoint]] = [:]
            for (key, value) in decoded {
                if let uuid = UUID(uuidString: key) {
                    result[uuid] = value
                }
            }
            data = result
        } catch {
            // Corrupt file — start fresh
            data = [:]
        }
    }

    func save() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: Self.saveDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.writeToDisk()
            }
        }
    }

    func flushToDisk() {
        saveTimer?.invalidate()
        saveTimer = nil
        writeToDisk()
    }

    private func writeToDisk() {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        do {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            var stringKeyed: [String: [StatusCheckpoint]] = [:]
            for (key, value) in data {
                stringKeyed[key.uuidString] = value
            }
            let encoded = try JSONEncoder().encode(stringKeyed)
            // Atomic write: write to temp file, then rename
            let tempURL = dir.appendingPathComponent(UUID().uuidString + ".tmp")
            try encoded.write(to: tempURL)
            _ = try fm.replaceItemAt(fileURL, withItemAt: tempURL)
        } catch {
            // Best-effort — log in debug
            #if DEBUG
            print("HistoryStore: failed to write: \(error)")
            #endif
        }
    }

    // MARK: - Migration from @AppStorage

    func migrateFromAppStorage(_ json: String) {
        guard let rawData = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [StatusCheckpoint]].self, from: rawData)
        else { return }
        for (key, value) in decoded {
            if let uuid = UUID(uuidString: key) {
                var existing = data[uuid] ?? []
                existing.append(contentsOf: value)
                data[uuid] = existing
            }
        }
        flushToDisk()
    }
}
