// UpdateChecker.swift
// Checks GitHub Releases API for app updates.

import SwiftUI

// MARK: - Update Checker

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var latestVersion: String?
    @Published var isUpdateAvailable = false
    @Published var downloadURL: String?
    @Published var releaseURL: String?
    @Published var isChecking = false
    @Published var lastCheckError: String?
    @Published var lastCheckDate: Date?
    @AppStorage("autoCheckForUpdates") var autoCheckEnabled = true

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
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                lastCheckError = "Server returned status \(code)"
                isChecking = false
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion = release.tagName.hasPrefix("v")
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
            }
        } catch {
            lastCheckError = error.localizedDescription
        }

        isChecking = false
    }

    func openReleasePage() {
        let urlString = releaseURL ?? "https://github.com/\(kGitHubRepo)/releases/latest"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func openDownload() {
        if let urlString = downloadURL ?? releaseURL,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
