// StatusService.swift
// Networking, provider detection, state management, and source CRUD.

import SwiftUI

// MARK: - Status Service

@MainActor
final class StatusService: ObservableObject {
    @Published var sources: [StatusSource] = []
    @Published var states: [UUID: SourceState] = [:]
    @Published var history: [UUID: [StatusCheckpoint]] = [:]

    @AppStorage("statusSourcesJSON") private var storedSourcesJSON: String = ""
    @AppStorage("refreshInterval") var refreshInterval: Double = kDefaultRefreshInterval

    private var refreshTimer: Timer?
    private var previousIndicators: [UUID: String] = [:]
    private var providerCache: [UUID: StatusProvider] = [:]

    let historyStore = HistoryStore()
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
        historyStore.load()
        // Migrate legacy @AppStorage history to file-based store
        let legacyHistory = storedHistory
        if legacyHistory != "{}" && !legacyHistory.isEmpty {
            historyStore.migrateFromAppStorage(legacyHistory)
            storedHistory = "{}"
        }
        // Prune checkpoints older than 30 days
        historyStore.pruneOlderThan(Date().addingTimeInterval(-30 * 24 * 60 * 60))
        history = historyStore.data
        loadSources()
        // Ensure notification delegate is wired before any refresh sends notifications
        _ = NotificationManager.shared
        Task { await refreshAll() }
        startTimer()
    }

    private func loadSources() {
        let json = storedSourcesJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("[") {
            let decoded = StatusSource.decode(from: json)
            if !decoded.isEmpty {
                sources = decoded
                return
            }
        }
        sources = kDefaultSources
        persistSources()
    }

    private func persistSources() {
        storedSourcesJSON = StatusSource.encodeToJSON(sources)
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
        HookManager.shared.fireAll(
            event: .onRefresh,
            environment: [
                "STATUSBAR_SOURCE_COUNT": "\(sources.count)",
                "STATUSBAR_WORST_LEVEL": worstIndicator,
            ],
            jsonPayload: HookManager.buildRefreshJSON(
                sourceCount: sources.count, worstLevel: worstIndicator
            )
        )
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

            // Notify on status changes, gated by alert level
            notifyIfNeeded(
                source: source, summary: summary,
                newIndicator: newIndicator, oldIndicator: oldIndicator
            )

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

    private func notifyIfNeeded(
        source: StatusSource, summary: SPSummary,
        newIndicator: String, oldIndicator: String?
    ) {
        let newSev = severityFor(newIndicator)
        guard newSev >= source.alertLevel.minimumSeverity else { return }

        let name = source.name
        let desc = summary.status.description

        if let old = oldIndicator, old != newIndicator {
            let oldSev = severityFor(old)
            if newSev > oldSev {
                sendNotification(
                    source: source, title: "\(name) \u{2014} Status Degraded",
                    body: desc, summary: summary, event: "degraded"
                )
            } else if newSev < oldSev && newIndicator == "none" {
                sendNotification(
                    source: source, title: "\(name) \u{2014} Recovered",
                    body: "All systems operational", summary: summary, event: "recovered"
                )
            }
        } else if oldIndicator == nil && newSev > 0 {
            sendNotification(
                source: source, title: "\(name) \u{2014} Active Incident",
                body: desc, summary: summary, event: "incident"
            )
        }
    }

    private func sendNotification(
        source: StatusSource, title: String, body: String,
        summary: SPSummary, event: String
    ) {
        NotificationManager.shared.sendStatusChange(
            source: source.name, url: source.baseURL, title: title, body: body
        )

        let affectedComponents = summary.components
            .filter { $0.status != "operational" }
            .map(\.name)

        let webhookEvent = WebhookEvent(
            source: source.name,
            title: title,
            body: body,
            severity: summary.status.indicator,
            event: event,
            url: source.baseURL,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            components: affectedComponents
        )

        Task.detached {
            await WebhookManager.shared.sendAll(event: webhookEvent)
        }
        HookManager.shared.fireAll(
            event: .onStatusChange,
            environment: [
                "STATUSBAR_SOURCE_NAME": source.name,
                "STATUSBAR_SOURCE_URL": source.baseURL,
                "STATUSBAR_TITLE": title,
                "STATUSBAR_BODY": body,
            ],
            jsonPayload: HookManager.buildStatusChangeJSON(
                sourceName: source.name, sourceURL: source.baseURL,
                title: title, body: body
            )
        )
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

    func applySources(_ newSources: [StatusSource]) {
        guard !newSources.isEmpty else { return }

        let newIDs = Set(newSources.map(\.id))
        for oldID in states.keys where !newIDs.contains(oldID) {
            states.removeValue(forKey: oldID)
            previousIndicators.removeValue(forKey: oldID)
            providerCache.removeValue(forKey: oldID)
            historyStore.removeSource(oldID)
        }
        history = historyStore.data

        sources = newSources
        persistSources()
        Task { await refreshAll() }
    }

    func addSource(name: String, baseURL: String, group: String? = nil) {
        let source = StatusSource(name: name, baseURL: baseURL, group: group, sortOrder: sources.count)
        sources.append(source)
        persistSources()
        Task { await refresh(source: source) }
        HookManager.shared.fireAll(
            event: .onSourceAdd,
            environment: [
                "STATUSBAR_SOURCE_NAME": name,
                "STATUSBAR_SOURCE_URL": baseURL,
            ],
            jsonPayload: HookManager.buildSourceJSON(
                event: .onSourceAdd, name: name, url: baseURL
            )
        )
    }

    func findSource(named name: String) -> StatusSource? {
        sources.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    func removeSource(id: UUID) {
        let removedName = sources.first(where: { $0.id == id })?.name ?? ""
        let removedURL = sources.first(where: { $0.id == id })?.baseURL ?? ""
        sources.removeAll { $0.id == id }
        states.removeValue(forKey: id)
        previousIndicators.removeValue(forKey: id)
        providerCache.removeValue(forKey: id)
        historyStore.removeSource(id)
        history = historyStore.data
        persistSources()
        if !removedName.isEmpty {
            HookManager.shared.fireAll(
                event: .onSourceRemove,
                environment: [
                    "STATUSBAR_SOURCE_NAME": removedName,
                    "STATUSBAR_SOURCE_URL": removedURL,
                ],
                jsonPayload: HookManager.buildSourceJSON(
                    event: .onSourceRemove, name: removedName, url: removedURL
                )
            )
        }
    }

    func updateAlertLevel(sourceID: UUID, level: AlertLevel) {
        guard let idx = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[idx].alertLevel = level
        persistSources()
    }

    func setGroup(sourceID: UUID, group: String?) {
        guard let idx = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[idx].group = group
        persistSources()
    }

    func moveSources(from offsets: IndexSet, to destination: Int) {
        sources.move(fromOffsets: offsets, toOffset: destination)
        for i in sources.indices {
            sources[i].sortOrder = i
        }
        persistSources()
    }

    // MARK: - JSON Export/Import

    func exportSourcesJSON() -> Data? {
        StatusSource.encodeToPrettyJSON(sources)
    }

    func importSourcesJSON(_ data: Data) -> Bool {
        let decoded = StatusSource.decode(from: String(data: data, encoding: .utf8) ?? "")
        guard !decoded.isEmpty else { return false }
        applySources(decoded)
        return true
    }

    func exportConfigJSON() -> Data? {
        let defaults = UserDefaults.standard
        let settings = ConfigSettings(
            refreshInterval: refreshInterval,
            notificationsEnabled: defaults.object(forKey: "notificationsEnabled") as? Bool ?? true,
            defaultAlertLevel: defaults.string(forKey: "defaultAlertLevel") ?? AlertLevel.all.rawValue,
            autoCheckForUpdates: defaults.object(forKey: "autoCheckForUpdates") as? Bool ?? true
        )
        let webhooks = WebhookManager.shared.configs
        let config = StatusBarConfig(settings: settings, sources: sources, webhooks: webhooks)
        return StatusBarConfig.encode(config)
    }

    func importConfigJSON(_ data: Data) -> Bool {
        guard let config = StatusBarConfig.decode(from: data) else { return false }

        // Apply settings
        refreshInterval = config.settings.refreshInterval
        UserDefaults.standard.set(config.settings.notificationsEnabled, forKey: "notificationsEnabled")
        UserDefaults.standard.set(config.settings.defaultAlertLevel, forKey: "defaultAlertLevel")
        UserDefaults.standard.set(config.settings.autoCheckForUpdates, forKey: "autoCheckForUpdates")
        startTimer()

        // Apply webhooks
        let manager = WebhookManager.shared
        for existing in manager.configs {
            manager.removeConfig(id: existing.id)
        }
        for webhook in config.webhooks {
            manager.addConfig(webhook)
        }

        // Apply sources (triggers refresh)
        applySources(config.sources)
        return true
    }

    var hasWebhooks: Bool {
        !WebhookManager.shared.configs.isEmpty
    }

    func resetToDefaults() {
        applySources(kDefaultSources)
    }

    func state(for source: StatusSource) -> SourceState {
        states[source.id] ?? SourceState()
    }

    // MARK: - Status History

    private func recordCheckpoint(sourceID: UUID, indicator: String) {
        historyStore.record(sourceID: sourceID, indicator: indicator)
        history = historyStore.data
    }
}
