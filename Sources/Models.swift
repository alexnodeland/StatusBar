// Models.swift
// Data models for StatusBar: sources, API responses, sort/filter enums, and per-source state.

import Foundation

// MARK: - Source Model

// MARK: - Alert Level

enum AlertLevel: String, Codable, CaseIterable {
    case all = "All Changes"
    case critical = "Critical Only"
    case none = "Muted"

    var minimumSeverity: Int {
        switch self {
        case .all: return 1
        case .critical: return 3
        case .none: return Int.max
        }
    }
}

// MARK: - Webhook Configuration

enum WebhookPlatform: String, Codable, CaseIterable {
    case slack, discord, teams, generic
}

struct WebhookConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var url: String
    var enabled: Bool
    var platform: WebhookPlatform

    init(id: UUID = UUID(), url: String, enabled: Bool = true, platform: WebhookPlatform = .generic) {
        self.id = id
        self.url = url
        self.enabled = enabled
        self.platform = platform
    }
}

// MARK: - Uptime Trend

struct UptimeTrend {
    let label: String
    let fraction: Double
    let checkpointCount: Int
}

// MARK: - Catalog Entry

struct CatalogEntry: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let category: String
}

struct StatusSource: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var baseURL: String
    var alertLevel: AlertLevel
    var group: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, alertLevel, group, sortOrder
    }

    init(id: UUID = UUID(), name: String, baseURL: String, alertLevel: AlertLevel = .all, group: String? = nil, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.alertLevel = alertLevel
        self.group = group
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let rawURL = try container.decode(String.self, forKey: .baseURL)
        baseURL = rawURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        alertLevel = try container.decodeIfPresent(AlertLevel.self, forKey: .alertLevel) ?? .all
        group = try container.decodeIfPresent(String.self, forKey: .group)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    static func decode(from json: String) -> [StatusSource] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([StatusSource].self, from: data)) ?? []
    }

    static func encodeToJSON(_ sources: [StatusSource]) -> String {
        guard let data = try? JSONEncoder().encode(sources),
            let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }

    static func encodeToPrettyJSON(_ sources: [StatusSource]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(sources)
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
                guard !name.isEmpty, validateSourceURL(url).isAcceptable else { return nil }
                return StatusSource(name: name, baseURL: url)
            }
    }

    static func serialize(_ sources: [StatusSource]) -> String {
        sources.map { "\($0.name)\t\($0.baseURL)" }.joined(separator: "\n")
    }
}

// MARK: - Configuration Export/Import

struct StatusBarConfig: Codable, Equatable {
    let version: Int
    let exportedAt: String
    var settings: ConfigSettings
    var sources: [StatusSource]
    var webhooks: [WebhookConfig]

    static let currentVersion = 1

    init(settings: ConfigSettings, sources: [StatusSource], webhooks: [WebhookConfig]) {
        self.version = Self.currentVersion
        self.exportedAt = ISO8601DateFormatter().string(from: Date())
        self.settings = settings
        self.sources = sources
        self.webhooks = webhooks
    }

    static func encode(_ config: StatusBarConfig) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(config)
    }

    static func decode(from data: Data) -> StatusBarConfig? {
        try? JSONDecoder().decode(StatusBarConfig.self, from: data)
    }
}

struct ConfigSettings: Codable, Equatable {
    var refreshInterval: Double
    var notificationsEnabled: Bool
    var defaultAlertLevel: String
    var autoCheckForUpdates: Bool

    init(
        refreshInterval: Double = 300,
        notificationsEnabled: Bool = true,
        defaultAlertLevel: String = AlertLevel.all.rawValue,
        autoCheckForUpdates: Bool = true
    ) {
        self.refreshInterval = refreshInterval
        self.notificationsEnabled = notificationsEnabled
        self.defaultAlertLevel = defaultAlertLevel
        self.autoCheckForUpdates = autoCheckForUpdates
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
    case manual = "Manual"

    var systemImage: String {
        switch self {
        case .alphabetical: return "textformat.abc"
        case .latest: return "clock"
        case .status: return "circle.fill"
        case .manual: return "hand.draw"
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

// MARK: - Status Provider

enum StatusProvider: Equatable {
    case atlassian
    case incidentIOCompat  // incident.io pages serving Atlassian-compatible API (no update details)
    case incidentIO  // pure incident.io fallback via /proxy/widget
    case instatus
}

// MARK: - Status History

struct StatusCheckpoint: Codable, Equatable {
    let date: Date
    let indicator: String
}

// MARK: - Per-Source State

struct SourceState: Equatable {
    var summary: SPSummary?
    var recentIncidents: [SPIncident] = []
    var isLoading: Bool = false
    var lastError: String?
    var lastRefresh: Date?
    var provider: StatusProvider?
    var isStale: Bool = false
    var lastSuccessfulRefresh: Date?

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
