// StatusBarApp.swift
// A macOS menu bar app that monitors multiple Atlassian Statuspage-powered status pages.
// Features native glass UI, status change notifications, and optimized polling.
//
// Requirements: macOS 14+ (Sonoma), Swift 5.9+
//
// Build & Run:
//   ./build.sh
//   open ./build/StatusBar.app

import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Configuration

private let kDefaultRefreshInterval: TimeInterval = 300

private let kRefreshIntervalOptions: [(label: String, seconds: TimeInterval)] = [
    ("1 min", 60),
    ("2 min", 120),
    ("5 min", 300),
    ("10 min", 600),
    ("15 min", 900),
]

private let kDefaultSources = """
Anthropic\thttps://status.anthropic.com
GitHub\thttps://www.githubstatus.com
Cloudflare\thttps://www.cloudflarestatus.com
"""

private let kGitHubRepo = "alexnodeland/StatusBar"

// MARK: - Design System

enum Design {
    enum Typography {
        static let body = Font.system(size: 13)
        static let bodyMedium = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11)
        static let captionMedium = Font.system(size: 11, weight: .medium)
        static let captionSemibold = Font.system(size: 11, weight: .semibold)
        static let micro = Font.system(size: 10)
        static let mono = Font.system(size: 11, design: .monospaced)
    }

    enum Timing {
        static let hover = SwiftUI.Animation.easeOut(duration: 0.12)
        static let transition = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let expand = SwiftUI.Animation.easeInOut(duration: 0.2)
    }
}

// MARK: - Source Model

struct StatusSource: Identifiable, Equatable {
    let id: UUID
    var name: String
    var baseURL: String

    init(id: UUID = UUID(), name: String, baseURL: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func parse(lines: String) -> [StatusSource] {
        lines
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> StatusSource? in
                let raw = String(line).trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty, !raw.hasPrefix("#") else { return nil }
                let parts = raw.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                let url = parts[1].trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, url.hasPrefix("http") else { return nil }
                return StatusSource(name: name, baseURL: url)
            }
    }

    static func serialize(_ sources: [StatusSource]) -> String {
        sources.map { "\($0.name)\t\($0.baseURL)" }.joined(separator: "\n")
    }
}

// MARK: - API Models

struct SPPage: Codable, Equatable {
    let id: String
    let name: String
    let url: String
    let updatedAt: String
    let timeZone: String?
    enum CodingKeys: String, CodingKey {
        case id, name, url
        case updatedAt = "updated_at"
        case timeZone = "time_zone"
    }
}

struct SPStatus: Codable, Equatable {
    let indicator: String
    let description: String
}

struct SPComponent: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let status: String
    let description: String?
    let position: Int
    let groupId: String?
    enum CodingKeys: String, CodingKey {
        case id, name, status, description, position
        case groupId = "group_id"
    }
}

struct SPIncidentUpdate: Codable, Identifiable, Equatable {
    let id: String
    let status: String
    let body: String
    let createdAt: String
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case id, status, body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SPIncident: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let status: String
    let impact: String
    let createdAt: String
    let updatedAt: String
    let shortlink: String?
    let incidentUpdates: [SPIncidentUpdate]
    enum CodingKeys: String, CodingKey {
        case id, name, status, impact, shortlink
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case incidentUpdates = "incident_updates"
    }
}

struct SPSummary: Codable, Equatable {
    let page: SPPage
    let status: SPStatus
    let components: [SPComponent]
    let incidents: [SPIncident]

    init(page: SPPage, status: SPStatus, components: [SPComponent], incidents: [SPIncident]) {
        self.page = page
        self.status = status
        self.components = components
        self.incidents = incidents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = try container.decode(SPPage.self, forKey: .page)
        status = try container.decode(SPStatus.self, forKey: .status)
        components = try container.decodeIfPresent([SPComponent].self, forKey: .components) ?? []
        incidents = try container.decodeIfPresent([SPIncident].self, forKey: .incidents) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case page, status, components, incidents
    }
}

struct SPIncidentsResponse: Codable {
    let page: SPPage
    let incidents: [SPIncident]
}

// MARK: - incident.io API Models

struct IIOWidgetResponse: Codable {
    let ongoingIncidents: [IIOIncident]?
    let inProgressMaintenances: [IIOIncident]?
    let scheduledMaintenances: [IIOIncident]?
    enum CodingKeys: String, CodingKey {
        case ongoingIncidents = "ongoing_incidents"
        case inProgressMaintenances = "in_progress_maintenances"
        case scheduledMaintenances = "scheduled_maintenances"
    }
}

struct IIOIncident: Codable {
    let id: String?
    let name: String?
    let status: String?
    let lastUpdateMessage: String?
    let affectedComponents: [IIOComponent]?
    let createdAt: String?
    let updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case id, name, status
        case lastUpdateMessage = "last_update_message"
        case affectedComponents = "affected_components"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct IIOComponent: Codable {
    let id: String?
    let name: String?
}

// MARK: - Instatus API Models

struct InstatusSummary: Codable {
    let page: InstatusPage
}

struct InstatusPage: Codable {
    let name: String
    let url: String
    let status: String
}

struct InstatusComponentsResponse: Codable {
    let components: [InstatusComponent]
}

struct InstatusComponent: Codable {
    let id: String
    let name: String
    let description: String?
    let status: String
    let order: Int
    let isParent: Bool
    let children: [InstatusComponent]
}

// MARK: - GitHub Release Model

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let htmlUrl: String
    let assets: [GitHubAsset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlUrl = "html_url"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

// MARK: - Sort & Filter

enum SourceSortOrder: String, CaseIterable {
    case alphabetical = "Name"
    case latest = "Latest"
    case status = "Status"

    var systemImage: String {
        switch self {
        case .alphabetical: return "textformat.abc"
        case .latest: return "clock"
        case .status: return "circle.fill"
        }
    }
}

enum SourceStatusFilter: String, CaseIterable {
    case all = "All"
    case operational = "Operational"
    case minor = "Minor"
    case major = "Major"
    case critical = "Critical"

    var indicator: String? {
        switch self {
        case .all: return nil
        case .operational: return "none"
        case .minor: return "minor"
        case .major: return "major"
        case .critical: return "critical"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "circle.grid.2x2"
        case .operational: return "checkmark.circle.fill"
        case .minor: return "exclamationmark.triangle.fill"
        case .major: return "exclamationmark.octagon.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Per-Source State

struct SourceState: Equatable {
    var summary: SPSummary?
    var recentIncidents: [SPIncident] = []
    var isLoading: Bool = false
    var lastError: String?
    var lastRefresh: Date?
    var provider: StatusProvider?

    var indicator: String { summary?.status.indicator ?? "unknown" }
    var statusDescription: String { summary?.status.description ?? "Loading\u{2026}" }

    var indicatorSeverity: Int {
        switch indicator {
        case "none": return 0
        case "minor": return 1
        case "major": return 2
        case "critical": return 3
        default: return -1
        }
    }

    var topLevelComponents: [SPComponent] {
        (summary?.components ?? [])
            .filter { $0.groupId == nil }
            .sorted { $0.position < $1.position }
    }

    var activeIncidents: [SPIncident] {
        summary?.incidents ?? []
    }
}

// MARK: - Notification Manager

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @AppStorage("notificationsEnabled") var notificationsEnabled = true

    private override init() {
        super.init()
        // Set delegate and categories immediately — these don't require NSApp
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                DispatchQueue.main.async {
                    NSApp?.activate(ignoringOtherApps: true)
                }
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }

    private func registerCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW",
            title: "View Details",
            options: .foreground
        )
        let category = UNNotificationCategory(
            identifier: "STATUS_CHANGE",
            actions: [viewAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func sendStatusChange(source: String, url: String, title: String, body: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "STATUS_CHANGE"
        content.userInfo = ["source": source, "url": url]

        let request = UNNotificationRequest(
            identifier: "\(source)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}

// MARK: - Status Provider

enum StatusProvider: Equatable {
    case atlassian
    case incidentIOCompat  // incident.io pages serving Atlassian-compatible API (no update details)
    case incidentIO        // pure incident.io fallback via /proxy/widget
    case instatus
}

// MARK: - Status Service

@MainActor
final class StatusService: ObservableObject {
    @Published var sources: [StatusSource] = []
    @Published var states: [UUID: SourceState] = [:]

    @AppStorage("statusSourceLines") private var storedLines: String = kDefaultSources
    @AppStorage("refreshInterval") var refreshInterval: Double = kDefaultRefreshInterval

    private var refreshTimer: Timer?
    private var previousIndicators: [UUID: String] = [:]
    private var providerCache: [UUID: StatusProvider] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    init() {
        sources = StatusSource.parse(lines: storedLines)
        if sources.isEmpty {
            sources = StatusSource.parse(lines: kDefaultSources)
            storedLines = kDefaultSources
        }
        // Ensure notification delegate is wired before any refresh sends notifications
        _ = NotificationManager.shared
        Task { await refreshAll() }
        startTimer()
    }

    // MARK: - Aggregate Status

    var worstIndicator: String {
        let worst = states.values.max(by: { $0.indicatorSeverity < $1.indicatorSeverity })
        return worst?.indicator ?? "none"
    }

    var issueCount: Int {
        states.values.filter { $0.indicator != "none" && $0.indicator != "unknown" }.count
    }

    var anyLoading: Bool {
        states.values.contains { $0.isLoading }
    }

    var menuBarIcon: String {
        iconForIndicator(worstIndicator)
    }

    var menuBarColor: Color {
        colorForIndicator(worstIndicator)
    }

    // MARK: - Timer

    func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAll()
            }
        }
    }

    // MARK: - Fetching

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask { await self.refresh(source: source) }
            }
        }
    }

    func refresh(source: StatusSource) async {
        states[source.id, default: SourceState()].isLoading = true
        states[source.id]?.lastError = nil

        do {
            let provider: StatusProvider
            if let cached = providerCache[source.id] {
                provider = cached
            } else {
                provider = await detectProvider(baseURL: source.baseURL)
                providerCache[source.id] = provider
            }

            let summary: SPSummary
            let incidents: [SPIncident]
            switch provider {
            case .atlassian, .incidentIOCompat:
                async let s = fetchSummary(baseURL: source.baseURL)
                async let i = fetchIncidents(baseURL: source.baseURL)
                (summary, incidents) = try await (s, i)
            case .incidentIO:
                (summary, incidents) = try await fetchIncidentIO(baseURL: source.baseURL)
            case .instatus:
                summary = try await fetchInstatus(baseURL: source.baseURL)
                incidents = []
            }

            let newIndicator = summary.status.indicator
            let oldIndicator = previousIndicators[source.id]

            states[source.id]?.summary = summary
            states[source.id]?.recentIncidents = incidents
            states[source.id]?.provider = provider
            states[source.id]?.lastRefresh = Date()

            // Notify on status changes, including initial load if non-operational
            let newSev = severityFor(newIndicator)
            if let old = oldIndicator, old != newIndicator {
                let oldSev = severityFor(old)
                if newSev > oldSev {
                    NotificationManager.shared.sendStatusChange(
                        source: source.name,
                        url: source.baseURL,
                        title: "\(source.name) \u{2014} Status Degraded",
                        body: summary.status.description
                    )
                } else if newSev < oldSev && newIndicator == "none" {
                    NotificationManager.shared.sendStatusChange(
                        source: source.name,
                        url: source.baseURL,
                        title: "\(source.name) \u{2014} Recovered",
                        body: "All systems operational"
                    )
                }
            } else if oldIndicator == nil && newSev > 0 {
                NotificationManager.shared.sendStatusChange(
                    source: source.name,
                    url: source.baseURL,
                    title: "\(source.name) \u{2014} Active Incident",
                    body: summary.status.description
                )
            }

            previousIndicators[source.id] = newIndicator
        } catch {
            providerCache.removeValue(forKey: source.id)
            states[source.id]?.lastError = error.localizedDescription
        }

        states[source.id]?.isLoading = false
    }

    private func fetchSummary(baseURL: String) async throws -> SPSummary {
        let url = URL(string: "\(baseURL)/api/v2/summary.json")!
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(SPSummary.self, from: data)
    }

    private func fetchIncidents(baseURL: String) async throws -> [SPIncident] {
        let url = URL(string: "\(baseURL)/api/v2/incidents.json")!
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(SPIncidentsResponse.self, from: data).incidents
    }

    private func severityFor(_ indicator: String) -> Int {
        switch indicator {
        case "none": return 0
        case "minor": return 1
        case "major": return 2
        case "critical": return 3
        default: return -1
        }
    }

    // MARK: - Provider Detection

    private func detectProvider(baseURL: String) async -> StatusProvider {
        guard let url = URL(string: "\(baseURL)/api/v2/summary.json") else {
            return .incidentIO
        }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                // Try Atlassian-format first (has status.indicator object)
                if let summary = try? JSONDecoder().decode(SPSummary.self, from: data) {
                    // Atlassian pages include time_zone; incident.io compat pages don't
                    return summary.page.timeZone != nil ? .atlassian : .incidentIOCompat
                }
                // Try Instatus (has page.status as a plain string like "UP")
                if let _ = try? JSONDecoder().decode(InstatusSummary.self, from: data) {
                    return .instatus
                }
            }
        } catch {}
        return .incidentIO
    }

    // MARK: - incident.io Fetch + Mapping

    private func fetchIncidentIO(baseURL: String) async throws -> (SPSummary, [SPIncident]) {
        let url = URL(string: "\(baseURL)/proxy/widget")!
        let (data, _) = try await session.data(from: url)
        let widget = try JSONDecoder().decode(IIOWidgetResponse.self, from: data)

        let allIncidents = (widget.ongoingIncidents ?? [])
            + (widget.inProgressMaintenances ?? [])

        let mappedIncidents = allIncidents.map { inc -> SPIncident in
            let id = inc.id ?? UUID().uuidString
            let name = inc.name ?? "Unknown incident"
            let status = inc.status ?? "investigating"
            let impact = deriveImpact(from: status)
            let created = inc.createdAt ?? ""
            let updated = inc.updatedAt ?? ""

            var updates: [SPIncidentUpdate] = []
            if let msg = inc.lastUpdateMessage, !msg.isEmpty {
                updates.append(SPIncidentUpdate(
                    id: "\(id)-update",
                    status: status,
                    body: msg,
                    createdAt: updated,
                    updatedAt: updated
                ))
            }

            return SPIncident(
                id: id,
                name: name,
                status: status,
                impact: impact,
                createdAt: created,
                updatedAt: updated,
                shortlink: nil,
                incidentUpdates: updates
            )
        }

        let indicator = deriveIndicator(from: allIncidents)
        let description = deriveDescription(from: indicator, incidentCount: allIncidents.count)

        let summary = SPSummary(
            page: SPPage(id: baseURL, name: baseURL, url: baseURL, updatedAt: "", timeZone: nil),
            status: SPStatus(indicator: indicator, description: description),
            components: [],
            incidents: mappedIncidents
        )

        return (summary, mappedIncidents)
    }

    private func deriveImpact(from status: String) -> String {
        switch status.lowercased() {
        case "investigating", "identified": return "major"
        case "monitoring": return "minor"
        case "resolved", "postmortem": return "none"
        default: return "minor"
        }
    }

    private func deriveIndicator(from incidents: [IIOIncident]) -> String {
        if incidents.isEmpty { return "none" }
        for inc in incidents {
            let s = (inc.status ?? "").lowercased()
            if s == "investigating" || s == "identified" { return "major" }
        }
        return "minor"
    }

    private func deriveDescription(from indicator: String, incidentCount: Int) -> String {
        switch indicator {
        case "none": return "All systems operational"
        case "minor": return "\(incidentCount) active incident\(incidentCount == 1 ? "" : "s")"
        case "major": return "\(incidentCount) active incident\(incidentCount == 1 ? "" : "s")"
        default: return "Status unknown"
        }
    }

    // MARK: - Instatus Fetch + Mapping

    private func fetchInstatus(baseURL: String) async throws -> SPSummary {
        let summaryURL = URL(string: "\(baseURL)/api/v2/summary.json")!
        let (summaryData, _) = try await session.data(from: summaryURL)
        let instatus = try JSONDecoder().decode(InstatusSummary.self, from: summaryData)

        var components: [SPComponent] = []
        if let compURL = URL(string: "\(baseURL)/api/v2/components.json") {
            if let (compData, compResp) = try? await session.data(from: compURL),
               let compHTTP = compResp as? HTTPURLResponse, compHTTP.statusCode == 200,
               let parsed = try? JSONDecoder().decode(InstatusComponentsResponse.self, from: compData) {
                components = flattenInstatusComponents(parsed.components)
            }
        }

        let indicator = mapInstatusPageStatus(instatus.page.status)
        let description = mapInstatusDescription(instatus.page.status)

        return SPSummary(
            page: SPPage(id: baseURL, name: instatus.page.name, url: instatus.page.url, updatedAt: "", timeZone: nil),
            status: SPStatus(indicator: indicator, description: description),
            components: components,
            incidents: []
        )
    }

    private func flattenInstatusComponents(_ components: [InstatusComponent], position: inout Int) -> [SPComponent] {
        var result: [SPComponent] = []
        for comp in components {
            let mapped = SPComponent(
                id: comp.id,
                name: comp.name,
                status: mapInstatusComponentStatus(comp.status),
                description: comp.description,
                position: position,
                groupId: nil
            )
            position += 1
            result.append(mapped)
            if !comp.children.isEmpty {
                result += flattenInstatusComponents(comp.children, position: &position)
            }
        }
        return result
    }

    private func flattenInstatusComponents(_ components: [InstatusComponent]) -> [SPComponent] {
        var pos = 0
        return flattenInstatusComponents(components, position: &pos)
    }

    private func mapInstatusPageStatus(_ status: String) -> String {
        switch status {
        case "UP": return "none"
        case "HASISSUES": return "minor"
        case "UNDERMAINTENANCE": return "minor"
        default: return "major"
        }
    }

    private func mapInstatusDescription(_ status: String) -> String {
        switch status {
        case "UP": return "All systems operational"
        case "HASISSUES": return "Experiencing issues"
        case "UNDERMAINTENANCE": return "Under maintenance"
        default: return "Experiencing issues"
        }
    }

    private func mapInstatusComponentStatus(_ status: String) -> String {
        switch status {
        case "OPERATIONAL": return "operational"
        case "DEGRADEDPERFORMANCE": return "degraded_performance"
        case "PARTIALOUTAGE": return "partial_outage"
        case "MAJOROUTAGE": return "major_outage"
        case "UNDERMAINTENANCE": return "degraded_performance"
        default: return status.lowercased()
        }
    }

    // MARK: - Source Management

    func applySources(from lines: String) {
        let parsed = StatusSource.parse(lines: lines)
        guard !parsed.isEmpty else { return }

        let newIDs = Set(parsed.map(\.id))
        for oldID in states.keys where !newIDs.contains(oldID) {
            states.removeValue(forKey: oldID)
            previousIndicators.removeValue(forKey: oldID)
            providerCache.removeValue(forKey: oldID)
        }

        sources = parsed
        storedLines = lines
        Task { await refreshAll() }
    }

    func addSource(name: String, baseURL: String) {
        let source = StatusSource(name: name, baseURL: baseURL)
        sources.append(source)
        storedLines = StatusSource.serialize(sources)
        Task { await refresh(source: source) }
    }

    func removeSource(id: UUID) {
        sources.removeAll { $0.id == id }
        states.removeValue(forKey: id)
        previousIndicators.removeValue(forKey: id)
        providerCache.removeValue(forKey: id)
        storedLines = StatusSource.serialize(sources)
    }

    func exportSourcesTSV() -> String {
        StatusSource.serialize(sources)
    }

    func importSourcesTSV(_ tsv: String) {
        let parsed = StatusSource.parse(lines: tsv)
        guard !parsed.isEmpty else { return }
        applySources(from: StatusSource.serialize(parsed))
    }

    func resetToDefaults() {
        applySources(from: kDefaultSources)
    }

    var serializedSources: String {
        StatusSource.serialize(sources)
    }

    func state(for source: StatusSource) -> SourceState {
        states[source.id] ?? SourceState()
    }
}

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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
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

// MARK: - Date Helpers

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let isoFormatterNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private let displayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

private func parseDate(_ str: String) -> Date? {
    isoFormatter.date(from: str) ?? isoFormatterNoFrac.date(from: str)
}

private func formatDate(_ str: String) -> String {
    guard let d = parseDate(str) else { return str }
    return displayFormatter.string(from: d)
}

private func relativeDate(_ str: String) -> String {
    guard let d = parseDate(str) else { return str }
    return relativeFormatter.localizedString(for: d, relativeTo: Date())
}

// MARK: - Indicator Helpers

private func iconForIndicator(_ indicator: String) -> String {
    switch indicator {
    case "none": return "checkmark.circle.fill"
    case "minor": return "exclamationmark.triangle.fill"
    case "major": return "exclamationmark.octagon.fill"
    case "critical": return "xmark.octagon.fill"
    default: return "questionmark.circle"
    }
}

private func colorForIndicator(_ indicator: String) -> Color {
    switch indicator {
    case "none": return .green
    case "minor": return .yellow
    case "major": return .orange
    case "critical": return .red
    default: return .secondary
    }
}

private func colorForComponentStatus(_ status: String) -> Color {
    switch status {
    case "operational": return .green
    case "degraded_performance": return .yellow
    case "partial_outage": return .orange
    case "major_outage": return .red
    default: return .secondary
    }
}

private func labelForComponentStatus(_ status: String) -> String {
    switch status {
    case "operational": return "Operational"
    case "degraded_performance": return "Degraded"
    case "partial_outage": return "Partial Outage"
    case "major_outage": return "Major Outage"
    default: return status
    }
}

// MARK: - Version Comparison

private func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
    let aParts = a.split(separator: ".").compactMap { Int($0) }
    let bParts = b.split(separator: ".").compactMap { Int($0) }
    let count = max(aParts.count, bParts.count)
    for i in 0..<count {
        let aVal = i < aParts.count ? aParts[i] : 0
        let bVal = i < bParts.count ? bParts[i] : 0
        if aVal < bVal { return .orderedAscending }
        if aVal > bVal { return .orderedDescending }
    }
    return .orderedSame
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

// MARK: - Hover Effect

struct HoverEffect: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering in
                withAnimation(Design.Timing.hover) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverEffect())
    }
}

// MARK: - Button Style

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Design.Typography.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isPressed ?
                          Color.primary.opacity(0.1) :
                          Color.primary.opacity(0.05))
            )
    }
}

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }
}

// MARK: - Root View

struct RootView: View {
    @ObservedObject var service: StatusService
    @ObservedObject var updateChecker: UpdateChecker
    @State private var selectedSourceID: UUID?
    @State private var showSettings = false

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .popover, blendingMode: .behindWindow)

            VStack(spacing: 0) {
                if let sourceID = selectedSourceID,
                   let source = service.sources.first(where: { $0.id == sourceID }) {
                    SourceDetailView(
                        source: source,
                        state: service.state(for: source),
                        onRefresh: { Task { await service.refresh(source: source) } },
                        onBack: { withAnimation(Design.Timing.transition) { selectedSourceID = nil } }
                    )
                } else if showSettings {
                    SettingsView(
                        service: service,
                        updateChecker: updateChecker,
                        onBack: { withAnimation(Design.Timing.transition) { showSettings = false } }
                    )
                } else {
                    SourceListView(
                        service: service,
                        updateChecker: updateChecker,
                        onSelect: { id in withAnimation(Design.Timing.transition) { selectedSourceID = id } },
                        onSettings: { withAnimation(Design.Timing.transition) { showSettings = true } }
                    )
                }
            }
        }
        .frame(width: 380, height: 520)
    }
}

// MARK: - Source List View

struct SourceListView: View {
    @ObservedObject var service: StatusService
    @ObservedObject var updateChecker: UpdateChecker
    let onSelect: (UUID) -> Void
    let onSettings: () -> Void

    @State private var sortOrder: SourceSortOrder = .alphabetical
    @State private var statusFilter: SourceStatusFilter = .all
    @State private var sortAscending: Bool = true

    private var filteredAndSortedSources: [StatusSource] {
        let filtered: [StatusSource]
        if let indicator = statusFilter.indicator {
            filtered = service.sources.filter { source in
                service.state(for: source).indicator == indicator
            }
        } else {
            filtered = service.sources
        }

        switch sortOrder {
        case .alphabetical:
            return filtered.sorted {
                let ascending = $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                return sortAscending ? ascending : !ascending
            }
        case .latest:
            return filtered.sorted { a, b in
                let dateA = service.state(for: a).lastRefresh ?? .distantPast
                let dateB = service.state(for: b).lastRefresh ?? .distantPast
                let ascending = dateA > dateB
                return sortAscending ? ascending : !ascending
            }
        case .status:
            return filtered.sorted { a, b in
                let sevA = service.state(for: a).indicatorSeverity
                let sevB = service.state(for: b).indicatorSeverity
                if sevA != sevB {
                    let ascending = sevA > sevB
                    return sortAscending ? ascending : !ascending
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().opacity(0.5)
            sourceList
            Divider().opacity(0.5)
            footerSection
        }
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: service.menuBarIcon)
                .font(.title2)
                .foregroundStyle(service.menuBarColor)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                Text("Status Monitor")
                    .font(Design.Typography.bodyMedium)
                Group {
                    if service.issueCount == 0 {
                        Text("All systems operational")
                    } else {
                        Text("\(service.issueCount) source\(service.issueCount == 1 ? "" : "s") with issues")
                    }
                }
                .font(Design.Typography.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if service.anyLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }

            sortMenuButton
            filterMenuButton

            Button {
                Task { await service.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(Design.Typography.body)
            }
            .buttonStyle(.borderless)
            .help("Refresh all")
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private var isSortActive: Bool { sortOrder != .alphabetical || !sortAscending }
    private var isFilterActive: Bool { statusFilter != .all }

    private var sortMenuButton: some View {
        Menu {
            Picker("Sort By", selection: $sortOrder) {
                ForEach(SourceSortOrder.allCases, id: \.self) { order in
                    Label(order.rawValue, systemImage: order.systemImage)
                        .tag(order)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("Direction", selection: $sortAscending) {
                Label("Ascending", systemImage: "arrow.up").tag(true)
                Label("Descending", systemImage: "arrow.down").tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(Design.Typography.caption)
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(isSortActive ? .white : .secondary)
        .background(
            Circle()
                .fill(isSortActive ? Color.accentColor : Color.clear)
                .frame(width: 22, height: 22)
        )
        .contentShape(Circle())
        .help("Sort options")
    }

    private var filterMenuButton: some View {
        Menu {
            Picker("Filter", selection: $statusFilter) {
                ForEach(SourceStatusFilter.allCases, id: \.self) { filter in
                    Label(filter.rawValue, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(Design.Typography.caption)
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(isFilterActive ? .white : .secondary)
        .background(
            Circle()
                .fill(isFilterActive ? Color.accentColor : Color.clear)
                .frame(width: 22, height: 22)
        )
        .contentShape(Circle())
        .help("Filter options")
    }

    private var sourceList: some View {
        ScrollView {
            let sources = filteredAndSortedSources
            if sources.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .symbolRenderingMode(.hierarchical)
                    Text("No sources match filter")
                        .font(Design.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(sources) { source in
                        SourceRow(source: source, state: service.state(for: source))
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(source.id) }
                    }
                }
                .padding(8)
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Group {
                if statusFilter == .all {
                    Text("\(service.sources.count) source\(service.sources.count == 1 ? "" : "s")")
                } else {
                    Text("\(filteredAndSortedSources.count) of \(service.sources.count) source\(service.sources.count == 1 ? "" : "s")")
                }
            }
            .font(Design.Typography.micro)
            .foregroundStyle(.quaternary)

            Spacer()

            Button(action: onSettings) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gear")
                        .font(Design.Typography.caption)
                    if updateChecker.isUpdateAvailable {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(.borderless)
            .help(updateChecker.isUpdateAvailable ? "Settings — Update available" : "Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(Design.Typography.micro)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .help("Quit StatusBar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Source Row

struct SourceRow: View {
    let source: StatusSource
    let state: SourceState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconForIndicator(state.indicator))
                .font(Design.Typography.body)
                .foregroundStyle(colorForIndicator(state.indicator))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(Design.Typography.bodyMedium)
                    .lineLimit(1)

                if let error = state.lastError {
                    Text(error)
                        .font(Design.Typography.micro)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else {
                    Text(state.statusDescription)
                        .font(Design.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            let activeCount = state.activeIncidents.count
            if activeCount > 0 {
                Text("\(activeCount)")
                    .font(Design.Typography.micro.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(colorForIndicator(state.indicator))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorForIndicator(state.indicator).opacity(0.15), in: Capsule())
            }

            if state.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12)
            }

            Image(systemName: "chevron.right")
                .font(Design.Typography.micro)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(state.indicatorSeverity > 0
                      ? colorForIndicator(state.indicator).opacity(0.06)
                      : Color.clear)
        )
        .hoverHighlight()
    }
}

// MARK: - Source Detail View

struct SourceDetailView: View {
    let source: StatusSource
    let state: SourceState
    let onRefresh: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider().opacity(0.5)

            if state.isLoading && state.summary == nil {
                loadingView
            } else if let error = state.lastError, state.summary == nil {
                errorView(error)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !state.activeIncidents.isEmpty {
                            activeIncidentsSection
                        }
                        componentsSection
                        recentIncidentsSection
                    }
                    .padding(12)
                }
            }

            Divider().opacity(0.5)
            detailFooter
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(Design.Typography.body)
            }
            .buttonStyle(.borderless)
            .help("Back")

            Image(systemName: iconForIndicator(state.indicator))
                .font(.title3)
                .foregroundStyle(colorForIndicator(state.indicator))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(Design.Typography.bodyMedium)
                Text(state.statusDescription)
                    .font(Design.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if state.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(Design.Typography.body)
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Sections

    private var activeIncidentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Active Incidents", systemImage: "exclamationmark.triangle.fill")
                .font(Design.Typography.captionSemibold)
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)

            ForEach(state.activeIncidents) { incident in
                IncidentCard(incident: incident, isActive: true)
            }
        }
    }

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Components")
                .font(Design.Typography.captionSemibold)
                .foregroundStyle(.secondary)

            if state.topLevelComponents.isEmpty {
                Text("No components reported")
                    .font(Design.Typography.micro)
                    .foregroundStyle(.tertiary)
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(state.topLevelComponents.enumerated()), id: \.element.id) { index, component in
                            ComponentRow(component: component)
                            if index < state.topLevelComponents.count - 1 {
                                Divider().opacity(0.3).padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private var providerLimitationNotice: String? {
        switch state.provider {
        case .instatus:
            return "Incident history is not available for this status page provider"
        case .incidentIO, .incidentIOCompat:
            return "Incident details are not available for this status page provider"
        default:
            return nil
        }
    }

    private var recentIncidentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Incidents")
                .font(Design.Typography.captionSemibold)
                .foregroundStyle(.secondary)

            let incidents = Array(state.recentIncidents.prefix(10))
            if let notice = providerLimitationNotice {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(Design.Typography.micro)
                    Text(notice)
                        .font(Design.Typography.micro)
                }
                .foregroundStyle(.tertiary)
                .padding(.vertical, 4)
            }

            if incidents.isEmpty {
                if providerLimitationNotice == nil {
                    Text("No recent incidents")
                        .font(Design.Typography.micro)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                }
            } else {
                ForEach(incidents) { incident in
                    IncidentCard(incident: incident, isActive: false)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading status\u{2026}")
                .font(Design.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text("Failed to load status")
                .font(Design.Typography.bodyMedium)
            Text(message)
                .font(Design.Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRefresh)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailFooter: some View {
        HStack {
            if let last = state.lastRefresh {
                Text("Updated \(relativeFormatter.localizedString(for: last, relativeTo: Date()))")
                    .font(Design.Typography.micro)
                    .foregroundStyle(.quaternary)
            }
            Spacer()
            Button {
                if let url = URL(string: source.baseURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open Status Page", systemImage: "arrow.up.forward")
                    .font(Design.Typography.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Component Row

struct ComponentRow: View {
    let component: SPComponent

    var body: some View {
        HStack {
            Circle()
                .fill(colorForComponentStatus(component.status))
                .frame(width: 7, height: 7)
            Text(component.name)
                .font(Design.Typography.caption)
                .foregroundStyle(.primary)
            Spacer()
            Text(labelForComponentStatus(component.status))
                .font(Design.Typography.micro)
                .foregroundStyle(colorForComponentStatus(component.status))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .hoverHighlight()
    }
}

// MARK: - Incident Card

struct IncidentCard: View {
    let incident: SPIncident
    let isActive: Bool
    @State private var isExpanded = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(impactColor)
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(incident.name)
                            .font(Design.Typography.captionMedium)
                            .lineLimit(isExpanded ? nil : 2)

                        HStack(spacing: 6) {
                            Text(statusBadge)
                                .font(Design.Typography.micro.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(statusBadgeColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(statusBadgeColor)

                            Text(relativeDate(incident.updatedAt))
                                .font(Design.Typography.micro)
                                .foregroundStyle(.quaternary)
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation(Design.Timing.expand) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(Design.Typography.micro)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }

                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(incident.incidentUpdates.prefix(5)) { update in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(update.status.capitalized)
                                        .font(Design.Typography.micro.weight(.semibold))
                                    Spacer()
                                    Text(formatDate(update.createdAt))
                                        .font(Design.Typography.micro)
                                        .foregroundStyle(.quaternary)
                                }
                                Text(update.body)
                                    .font(Design.Typography.micro)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                            .padding(6)
                            .background(
                                Color.primary.opacity(0.03),
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                        }

                        if let link = incident.shortlink, let url = URL(string: link) {
                            Button("View on Status Page") {
                                NSWorkspace.shared.open(url)
                            }
                            .font(Design.Typography.micro)
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.leading, 14)
                    .transition(.opacity)
                }
            }
            .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? impactColor.opacity(0.3) : Color.clear, lineWidth: 0.5)
        )
    }

    private var impactColor: Color {
        switch incident.impact {
        case "none": return .green
        case "minor": return .yellow
        case "major": return .orange
        case "critical": return .red
        default: return .secondary
        }
    }

    private var statusBadge: String {
        switch incident.status {
        case "investigating": return "Investigating"
        case "identified": return "Identified"
        case "monitoring": return "Monitoring"
        case "resolved": return "Resolved"
        case "postmortem": return "Postmortem"
        default: return incident.status.capitalized
        }
    }

    private var statusBadgeColor: Color {
        switch incident.status {
        case "investigating": return .red
        case "identified": return .orange
        case "monitoring": return .blue
        case "resolved": return .green
        case "postmortem": return .purple
        default: return .secondary
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var service: StatusService
    @ObservedObject var updateChecker: UpdateChecker
    let onBack: () -> Void
    @State private var launchAtLogin = false
    @State private var showingAddSource = false
    @State private var newSourceName = ""
    @State private var newSourceURL = ""
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader
            Divider().opacity(0.5)
            sourceListSection
            Spacer()
            Divider().opacity(0.5)

            HStack {
                Text("Refresh interval")
                    .font(Design.Typography.caption)
                Spacer()
                Picker("", selection: $service.refreshInterval) {
                    ForEach(kRefreshIntervalOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: service.refreshInterval) {
                    service.startTimer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.5)

            Toggle(isOn: $launchAtLogin) {
                Text("Launch at login")
                    .font(Design.Typography.caption)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onChange(of: launchAtLogin) {
                do {
                    if launchAtLogin {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin.toggle()
                }
            }

            Divider().opacity(0.5)

            Toggle(isOn: $notificationsEnabled) {
                Text("Notifications")
                    .font(Design.Typography.caption)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.5)
            updateSection
            Divider().opacity(0.5)
            settingsFooter
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var sourceListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Status Pages")
                    .font(Design.Typography.captionSemibold)
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    importSources()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(Design.Typography.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Import from TSV")

                Button {
                    exportSources()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(Design.Typography.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Export as TSV")

                Button {
                    withAnimation(Design.Timing.expand) {
                        showingAddSource.toggle()
                        newSourceName = ""
                        newSourceURL = ""
                    }
                } label: {
                    Image(systemName: showingAddSource ? "xmark.circle.fill" : "plus.circle.fill")
                        .font(Design.Typography.body)
                        .foregroundStyle(showingAddSource ? .secondary : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .help(showingAddSource ? "Cancel" : "Add source")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if showingAddSource {
                addSourceForm
            }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(service.sources) { source in
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(Design.Timing.expand) {
                                    service.removeSource(id: source.id)
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(Design.Typography.body)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove source")

                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.name)
                                    .font(Design.Typography.captionMedium)
                                    .lineLimit(1)
                                Text(source.baseURL)
                                    .font(Design.Typography.micro)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .hoverHighlight()
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var addSourceForm: some View {
        VStack(spacing: 6) {
            TextField("Name", text: $newSourceName)
                .font(Design.Typography.caption)
                .textFieldStyle(.roundedBorder)

            TextField("URL (e.g. https://status.example.com)", text: $newSourceURL)
                .font(Design.Typography.caption)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Add") {
                    let name = newSourceName.trimmingCharacters(in: .whitespaces)
                    let url = newSourceURL.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty, url.hasPrefix("http") else { return }
                    withAnimation(Design.Timing.expand) {
                        service.addSource(name: name, baseURL: url)
                        showingAddSource = false
                        newSourceName = ""
                        newSourceURL = ""
                    }
                }
                .font(Design.Typography.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(
                    newSourceName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    !newSourceURL.trimmingCharacters(in: .whitespaces).hasPrefix("http")
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func exportSources() {
        let panel = NSSavePanel()
        panel.title = "Export Status Pages"
        panel.nameFieldStringValue = "status-pages.tsv"
        panel.allowedContentTypes = [.tabSeparatedText]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            let tsv = service.exportSourcesTSV()
            try? tsv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func importSources() {
        let panel = NSOpenPanel()
        panel.title = "Import Status Pages"
        panel.allowedContentTypes = [.tabSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            if let tsv = try? String(contentsOf: url, encoding: .utf8) {
                service.importSourcesTSV(tsv)
            }
        }
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    if let url = URL(string: "https://github.com/\(kGitHubRepo)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    if let img = NSImage(contentsOfFile: Bundle.main.path(forResource: "github", ofType: "png") ?? "") {
                        Image(nsImage: { img.isTemplate = true; return img }())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                    }
                }
                .buttonStyle(.borderless)
                .help("View on GitHub")

                Text("Version")
                    .font(Design.Typography.caption)
                Text(updateChecker.currentVersion)
                    .font(Design.Typography.mono)
                    .foregroundStyle(.secondary)

                if updateChecker.isUpdateAvailable {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption2)
                    Text("Update available")
                        .font(Design.Typography.micro)
                        .foregroundStyle(Color.accentColor)
                } else if updateChecker.lastCheckDate != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                    Text("Up to date")
                        .font(Design.Typography.micro)
                        .foregroundStyle(.green)
                }

                Button {
                    Task { await updateChecker.checkForUpdates() }
                } label: {
                    if updateChecker.isChecking {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(updateChecker.isChecking)

                Spacer()

                Toggle(isOn: $updateChecker.autoCheckEnabled) {
                    Text("Check automatically")
                        .font(Design.Typography.micro)
                }
                    .toggleStyle(.checkbox)
                    .onChange(of: updateChecker.autoCheckEnabled) {
                        if updateChecker.autoCheckEnabled {
                            updateChecker.startNightlyTimer()
                        } else {
                            updateChecker.stopNightlyTimer()
                        }
                    }
                .help("Check for Updates")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if updateChecker.isUpdateAvailable, let latest = updateChecker.latestVersion {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Version \(latest) available")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Button("Download") {
                        updateChecker.openDownload()
                    }
                    .font(Design.Typography.caption)
                    .buttonStyle(GlassButtonStyle())
                }
                .padding(8)
                .padding(.horizontal, 4)
                .background(
                    Color.accentColor.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if let error = updateChecker.lastCheckError {
                Text(error)
                    .font(Design.Typography.micro)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(Design.Typography.body)
            }
            .buttonStyle(.borderless)
            .help("Back")

            Image(systemName: "gear")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
            Text("Settings")
                .font(Design.Typography.bodyMedium)
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private var settingsFooter: some View {
        HStack {
            Button("Reset to Defaults") {
                service.resetToDefaults()
            }
            .font(Design.Typography.caption)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(Design.Typography.micro)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .help("Quit StatusBar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @ObservedObject var service: StatusService

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: service.menuBarIcon)
            if service.issueCount > 0 {
                Text("\(service.issueCount)")
                    .font(.caption2.monospacedDigit())
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestPermission()
    }
}

// MARK: - App Entry Point

@main
struct StatusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var service = StatusService()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        MenuBarExtra {
            RootView(service: service, updateChecker: updateChecker)
        } label: {
            MenuBarLabel(service: service)
        }
        .menuBarExtraStyle(.window)
    }
}
