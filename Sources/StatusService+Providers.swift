// StatusService+Providers.swift
// Provider detection and per-provider fetch + mapping (Atlassian, incident.io, Instatus, Gatus).

import Foundation

extension StatusService {

    // MARK: - Provider Detection

    func detectProvider(baseURL: String) async -> StatusProvider {
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
        if await isGatus(baseURL: baseURL) {
            return .gatus
        }
        return .incidentIO
    }

    private func isGatus(baseURL: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/endpoints/statuses?page=1&pageSize=1") else {
            return false
        }
        guard let (data, response) = try? await session.data(from: url),
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return false }
        return (try? JSONDecoder().decode([GatusEndpointStatus].self, from: data)) != nil
    }

    // MARK: - Atlassian Fetch

    func fetchSummary(baseURL: String) async throws -> SPSummary {
        try await withRetry {
            let url = URL(string: "\(baseURL)/api/v2/summary.json")!
            let (data, _) = try await self.session.data(from: url)
            return try JSONDecoder().decode(SPSummary.self, from: data)
        }
    }

    func fetchIncidents(baseURL: String) async throws -> [SPIncident] {
        try await withRetry {
            let url = URL(string: "\(baseURL)/api/v2/incidents.json")!
            let (data, _) = try await self.session.data(from: url)
            return try JSONDecoder().decode(SPIncidentsResponse.self, from: data).incidents
        }
    }

    // MARK: - incident.io Fetch + Mapping

    func fetchIncidentIO(baseURL: String) async throws -> (SPSummary, [SPIncident]) {
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
        let map = ["investigating": "major", "identified": "major", "monitoring": "minor", "resolved": "none", "postmortem": "none"]
        return map[status.lowercased(), default: "minor"]
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
        if indicator == "none" { return "All systems operational" }
        let suffix = incidentCount == 1 ? "" : "s"
        if indicator == "minor" || indicator == "major" {
            return "\(incidentCount) active incident\(suffix)"
        }
        return "Status unknown"
    }

    // MARK: - Instatus Fetch + Mapping

    func fetchInstatus(baseURL: String) async throws -> SPSummary {
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
        ["UP": "none", "HASISSUES": "minor", "UNDERMAINTENANCE": "minor"][status, default: "major"]
    }

    private func mapInstatusDescription(_ status: String) -> String {
        let map = ["UP": "All systems operational", "HASISSUES": "Experiencing issues", "UNDERMAINTENANCE": "Under maintenance"]
        return map[status, default: "Experiencing issues"]
    }

    private func mapInstatusComponentStatus(_ status: String) -> String {
        let map = [
            "OPERATIONAL": "operational",
            "DEGRADEDPERFORMANCE": "degraded_performance",
            "PARTIALOUTAGE": "partial_outage",
            "MAJOROUTAGE": "major_outage",
            "UNDERMAINTENANCE": "degraded_performance",
        ]
        return map[status, default: status.lowercased()]
    }

    // MARK: - Gatus Fetch + Mapping

    func fetchGatus(baseURL: String) async throws -> SPSummary {
        let pageSize = 100
        var endpoints: [GatusEndpointStatus] = []
        for page in 1...5 {
            let (data, _) = try await withRetry {
                let url = URL(string: "\(baseURL)/api/v1/endpoints/statuses?page=\(page)&pageSize=\(pageSize)")!
                return try await self.session.data(from: url)
            }
            let batch = try JSONDecoder().decode([GatusEndpointStatus].self, from: data)
            endpoints += batch
            if batch.count < pageSize { break }
        }
        return SPSummary.fromGatus(endpoints, baseURL: baseURL)
    }
}
