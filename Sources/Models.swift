// Models.swift
// Data models for StatusBar: sources, API responses, sort/filter enums, and per-source state.

import Foundation

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

// MARK: - Status Provider

enum StatusProvider: Equatable {
    case atlassian
    case incidentIOCompat  // incident.io pages serving Atlassian-compatible API (no update details)
    case incidentIO        // pure incident.io fallback via /proxy/widget
    case instatus
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
