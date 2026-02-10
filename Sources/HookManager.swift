// HookManager.swift
// Script hook execution for status change events.
// User-placed executables in ~/Library/Application Support/StatusBar/hooks/
// are fired on status events alongside existing webhooks.

import Foundation

// MARK: - Hook Event

enum HookEvent: String, CaseIterable {
    case onStatusChange = "on-status-change"
    case onRefresh = "on-refresh"
    case onSourceAdd = "on-source-add"
    case onSourceRemove = "on-source-remove"
}

// MARK: - Hook Manager

final class HookManager: @unchecked Sendable {
    static let shared = HookManager()

    let hooksDirectory: URL
    private let timeout: TimeInterval

    init(
        hooksDirectory: URL? = nil,
        timeout: TimeInterval = 30
    ) {
        if let dir = hooksDirectory {
            self.hooksDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            self.hooksDirectory =
                appSupport
                .appendingPathComponent("StatusBar")
                .appendingPathComponent("hooks")
        }
        self.timeout = timeout
    }

    // MARK: - Directory Management

    func ensureHooksDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: hooksDirectory.path) {
            try? fm.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Hook Discovery

    func discoverHooks() -> [URL] {
        let fm = FileManager.default
        guard
            let contents = try? fm.contentsOfDirectory(
                at: hooksDirectory,
                includingPropertiesForKeys: [.isExecutableKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        return contents.filter { url in
            var isExecutable: AnyObject?
            try? (url as NSURL).getResourceValue(&isExecutable, forKey: .isExecutableKey)
            return (isExecutable as? Bool) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Fire All Hooks

    func fireAll(
        event: HookEvent,
        environment: [String: String] = [:],
        jsonPayload: Data? = nil
    ) {
        let hooks = discoverHooks()
        guard !hooks.isEmpty else { return }

        for hook in hooks {
            Task.detached { [self] in
                _ = await self.execute(
                    script: hook,
                    event: event,
                    environment: environment,
                    jsonPayload: jsonPayload
                )
            }
        }
    }

    // MARK: - Execute Script

    @discardableResult
    func execute(
        script: URL,
        event: HookEvent,
        environment: [String: String] = [:],
        jsonPayload: Data? = nil
    ) async -> Int32 {
        let process = Process()
        process.executableURL = script

        var env = ProcessInfo.processInfo.environment
        env["STATUSBAR_EVENT"] = event.rawValue
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return -1
        }

        // Write JSON payload to stdin
        if let payload = jsonPayload {
            stdinPipe.fileHandleForWriting.write(payload)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        // Enforce timeout
        let timeoutSeconds = self.timeout
        return await withCheckedContinuation { continuation in
            let workItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeoutSeconds,
                execute: workItem
            )
            process.terminationHandler = { proc in
                workItem.cancel()
                continuation.resume(returning: proc.terminationStatus)
            }
        }
    }

    // MARK: - JSON Payload Builders

    static func buildStatusChangeJSON(
        sourceName: String, sourceURL: String, title: String, body: String
    ) -> Data? {
        let payload: [String: Any] = [
            "event": HookEvent.onStatusChange.rawValue,
            "source_name": sourceName,
            "source_url": sourceURL,
            "title": title,
            "body": body,
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    static func buildRefreshJSON(sourceCount: Int, worstLevel: String) -> Data? {
        let payload: [String: Any] = [
            "event": HookEvent.onRefresh.rawValue,
            "source_count": sourceCount,
            "worst_level": worstLevel,
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    static func buildSourceJSON(event: HookEvent, name: String, url: String) -> Data? {
        let payload: [String: Any] = [
            "event": event.rawValue,
            "source_name": name,
            "source_url": url,
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }
}
