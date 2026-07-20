// StatusService+Providers.swift
// Provider detection and per-provider network fetches. Pure response→SPSummary
// mapping lives in ProviderMappings.swift.

import Foundation

extension StatusService {

    // MARK: - Shared Fetch

    /// Fetches a URL and returns its body, throwing typed errors for bad URLs
    /// and non-2xx responses so `withRetry` can skip retries on terminal failures.
    private func fetchData(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw FetchError.invalidURL }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }
        return data
    }

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
        guard let data = try? await fetchData("\(baseURL)/api/v1/endpoints/statuses?page=1&pageSize=1") else {
            return false
        }
        return (try? JSONDecoder().decode([GatusEndpointStatus].self, from: data)) != nil
    }

    // MARK: - Atlassian Fetch

    func fetchSummary(baseURL: String) async throws -> SPSummary {
        let data = try await withRetry {
            try await self.fetchData("\(baseURL)/api/v2/summary.json")
        }
        return try JSONDecoder().decode(SPSummary.self, from: data)
    }

    func fetchIncidents(baseURL: String) async throws -> [SPIncident] {
        let data = try await withRetry {
            try await self.fetchData("\(baseURL)/api/v2/incidents.json")
        }
        return try JSONDecoder().decode(SPIncidentsResponse.self, from: data).incidents
    }

    // MARK: - incident.io Fetch

    func fetchIncidentIO(baseURL: String) async throws -> (SPSummary, [SPIncident]) {
        let data = try await withRetry {
            try await self.fetchData("\(baseURL)/proxy/widget")
        }
        let widget = try JSONDecoder().decode(IIOWidgetResponse.self, from: data)
        return SPSummary.fromIncidentIOWidget(widget, baseURL: baseURL)
    }

    // MARK: - Instatus Fetch

    func fetchInstatus(baseURL: String) async throws -> SPSummary {
        let summaryData = try await withRetry {
            try await self.fetchData("\(baseURL)/api/v2/summary.json")
        }
        let instatus = try JSONDecoder().decode(InstatusSummary.self, from: summaryData)

        var components: [InstatusComponent] = []
        if let compData = try? await fetchData("\(baseURL)/api/v2/components.json"),
            let parsed = try? JSONDecoder().decode(InstatusComponentsResponse.self, from: compData)
        {
            components = parsed.components
        }

        return SPSummary.fromInstatus(instatus, components: components, baseURL: baseURL)
    }

    // MARK: - Gatus Fetch

    func fetchGatus(baseURL: String) async throws -> SPSummary {
        let pageSize = 100
        var endpoints: [GatusEndpointStatus] = []
        for page in 1...5 {
            let data = try await withRetry {
                try await self.fetchData("\(baseURL)/api/v1/endpoints/statuses?page=\(page)&pageSize=\(pageSize)")
            }
            let batch = try JSONDecoder().decode([GatusEndpointStatus].self, from: data)
            endpoints += batch
            if batch.count < pageSize { break }
        }
        // Older Gatus versions ignore pagination params and return everything on
        // every page — dedupe by key so those instances don't produce duplicates.
        var seen = Set<String>()
        let unique = endpoints.filter { seen.insert($0.key ?? $0.displayName).inserted }
        return SPSummary.fromGatus(unique, baseURL: baseURL)
    }
}
