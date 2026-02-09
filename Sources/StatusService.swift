// StatusService.swift
// Networking, provider detection, state management, and source CRUD.

import SwiftUI

// MARK: - Status Service

@MainActor
final class StatusService: ObservableObject {
    @Published var sources: [StatusSource] = []
    @Published var states: [UUID: SourceState] = [:]
    @Published var history: [UUID: [StatusCheckpoint]] = [:]

    @AppStorage("statusSourceLines") private var storedLines: String = kDefaultSources
    @AppStorage("refreshInterval") var refreshInterval: Double = kDefaultRefreshInterval

    private var refreshTimer: Timer?
    private var previousIndicators: [UUID: String] = [:]
    private var providerCache: [UUID: StatusProvider] = [:]

    @AppStorage("statusHistory") private var storedHistory: String = "{}"

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    init() {
        loadHistory()
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
            states[source.id]?.isStale = false
            states[source.id]?.lastSuccessfulRefresh = Date()

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
            recordCheckpoint(sourceID: source.id, indicator: newIndicator)
        } catch {
            providerCache.removeValue(forKey: source.id)
            states[source.id]?.lastError = error.localizedDescription
            if states[source.id]?.summary != nil {
                states[source.id]?.isStale = true
            }
        }

        states[source.id]?.isLoading = false
    }

    private func fetchSummary(baseURL: String) async throws -> SPSummary {
        try await withRetry {
            let url = URL(string: "\(baseURL)/api/v2/summary.json")!
            let (data, _) = try await self.session.data(from: url)
            return try JSONDecoder().decode(SPSummary.self, from: data)
        }
    }

    private func fetchIncidents(baseURL: String) async throws -> [SPIncident] {
        try await withRetry {
            let url = URL(string: "\(baseURL)/api/v2/incidents.json")!
            let (data, _) = try await self.session.data(from: url)
            return try JSONDecoder().decode(SPIncidentsResponse.self, from: data).incidents
        }
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
            let (data, response) = try await withRetry {
                try await self.session.data(from: url)
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                // Try Atlassian-format first (has status.indicator object)
                if let summary = try? JSONDecoder().decode(SPSummary.self, from: data) {
                    // Atlassian pages include time_zone; incident.io compat pages don't
                    return summary.page.timeZone != nil ? .atlassian : .incidentIOCompat
                }
                // Try Instatus (has page.status as a plain string like "UP")
                if (try? JSONDecoder().decode(InstatusSummary.self, from: data)) != nil {
                    return .instatus
                }
            }
        } catch {}
        return .incidentIO
    }

    // MARK: - incident.io Fetch + Mapping

    private func fetchIncidentIO(baseURL: String) async throws -> (SPSummary, [SPIncident]) {
        let (data, _) = try await withRetry {
            let url = URL(string: "\(baseURL)/proxy/widget")!
            return try await self.session.data(from: url)
        }
        let widget = try JSONDecoder().decode(IIOWidgetResponse.self, from: data)

        let allIncidents =
            (widget.ongoingIncidents ?? [])
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
                updates.append(
                    SPIncidentUpdate(
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
        let (summaryData, _) = try await withRetry {
            let summaryURL = URL(string: "\(baseURL)/api/v2/summary.json")!
            return try await self.session.data(from: summaryURL)
        }
        let instatus = try JSONDecoder().decode(InstatusSummary.self, from: summaryData)

        var components: [SPComponent] = []
        if let compURL = URL(string: "\(baseURL)/api/v2/components.json") {
            if let (compData, compResp) = try? await session.data(from: compURL),
                let compHTTP = compResp as? HTTPURLResponse, compHTTP.statusCode == 200,
                let parsed = try? JSONDecoder().decode(InstatusComponentsResponse.self, from: compData)
            {
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
            history.removeValue(forKey: oldID)
        }
        saveHistory()

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
        history.removeValue(forKey: id)
        saveHistory()
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

    // MARK: - Status History

    private func loadHistory() {
        guard let data = storedHistory.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [StatusCheckpoint]].self, from: data)
        else { return }
        history = [:]
        for (key, value) in decoded {
            if let uuid = UUID(uuidString: key) {
                history[uuid] = value
            }
        }
    }

    private func saveHistory() {
        var stringKeyed: [String: [StatusCheckpoint]] = [:]
        for (key, value) in history {
            stringKeyed[key.uuidString] = value
        }
        if let data = try? JSONEncoder().encode(stringKeyed),
           let json = String(data: data, encoding: .utf8) {
            storedHistory = json
        }
    }

    private func recordCheckpoint(sourceID: UUID, indicator: String) {
        var checkpoints = history[sourceID] ?? []
        checkpoints.append(StatusCheckpoint(date: Date(), indicator: indicator))
        if checkpoints.count > 30 {
            checkpoints = Array(checkpoints.suffix(30))
        }
        history[sourceID] = checkpoints
        saveHistory()
    }
}
