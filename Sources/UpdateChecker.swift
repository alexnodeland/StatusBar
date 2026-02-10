// UpdateChecker.swift
// Checks GitHub Releases API for app updates.
// When Sparkle.framework is available, delegates to SPUStandardUpdaterController.

import SwiftUI

#if canImport(Sparkle)
import Sparkle
#endif

// MARK: - Update Checker

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var latestVersion: String?
    @Published var isUpdateAvailable = false
    @Published var downloadURL: String?
    @Published var releaseURL: String?
    @Published var isChecking = false
    @Published var isAutoUpdating = false
    @Published var lastCheckError: String?
    @Published var lastCheckDate: Date?
    @AppStorage("autoCheckForUpdates") var autoCheckEnabled = true
    @AppStorage("autoUpdateEnabled") var autoUpdateEnabled = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var nightlyTimer: Timer?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    init() {
        Task { await checkForUpdates() }
        if autoCheckEnabled {
            startNightlyTimer()
        }
    }

    func startNightlyTimer() {
        nightlyTimer?.invalidate()
        nightlyTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForUpdates()
            }
        }
    }

    func stopNightlyTimer() {
        nightlyTimer?.invalidate()
        nightlyTimer = nil
    }

    func checkForUpdates() async {
        isChecking = true
        lastCheckError = nil

        do {
            let url = URL(string: "https://api.github.com/repos/\(kGitHubRepo)/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                lastCheckError = "Server returned status \(code)"
                isChecking = false
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion =
                release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            latestVersion = remoteVersion
            releaseURL = release.htmlUrl

            if let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) {
                downloadURL = asset.browserDownloadUrl
            }

            let wasAvailable = isUpdateAvailable
            isUpdateAvailable = compareVersions(currentVersion, remoteVersion) == .orderedAscending
            lastCheckDate = Date()

            if isUpdateAvailable && !wasAvailable {
                NotificationManager.shared.sendStatusChange(
                    source: "StatusBar",
                    url: releaseURL ?? "https://github.com/\(kGitHubRepo)/releases/latest",
                    title: "StatusBar Update Available",
                    body: "Version \(remoteVersion) is available (current: \(currentVersion))"
                )

                if autoUpdateEnabled {
                    await performAutoUpdate()
                }
            }
        } catch {
            lastCheckError = error.localizedDescription
        }

        isChecking = false
    }

    func performAutoUpdate() async {
        guard let urlString = downloadURL, let url = URL(string: urlString) else {
            lastCheckError = "No download URL for auto-update"
            return
        }

        isAutoUpdating = true
        defer { isAutoUpdating = false }

        do {
            // Download zip to temp directory
            let (tempZipURL, response) = try await session.download(for: URLRequest(url: url))
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                lastCheckError = "Download failed with status \(code)"
                return
            }

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("StatusBarUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let zipDest = tempDir.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: tempZipURL, to: zipDest)

            // Unzip
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", zipDest.path, "-d", tempDir.path]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else {
                lastCheckError = "Unzip failed"
                try? FileManager.default.removeItem(at: tempDir)
                return
            }

            // Find .app in extracted contents
            let contents = try FileManager.default.contentsOfDirectory(
                at: tempDir, includingPropertiesForKeys: nil)
            guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                lastCheckError = "No .app found in update archive"
                try? FileManager.default.removeItem(at: tempDir)
                return
            }

            // Replace current app
            let currentAppPath = Bundle.main.bundlePath
            let currentAppURL = URL(fileURLWithPath: currentAppPath)
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: currentAppURL, resultingItemURL: &trashedURL)
            try FileManager.default.moveItem(at: newApp, to: currentAppURL)

            // Clean up temp directory
            try? FileManager.default.removeItem(at: tempDir)

            // Relaunch
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            relaunch.arguments = ["-n", currentAppPath]
            try relaunch.run()

            NSApplication.shared.terminate(nil)
        } catch {
            lastCheckError = "Auto-update failed: \(error.localizedDescription)"
        }
    }

    func openReleasePage() {
        let urlString = releaseURL ?? "https://github.com/\(kGitHubRepo)/releases/latest"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func openDownload() {
        if let urlString = downloadURL ?? releaseURL,
            let url = URL(string: urlString)
        {
            NSWorkspace.shared.open(url)
        }
    }

    /// Whether the app is using Sparkle for updates instead of GitHub Releases.
    var usesSparkle: Bool {
        #if canImport(Sparkle)
        return true
        #else
        return false
        #endif
    }
}

// MARK: - Sparkle Integration

#if canImport(Sparkle)
extension UpdateChecker {
    func setupSparkle() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Sparkle manages its own update lifecycle from here.
        _ = controller
    }
}
#endif
