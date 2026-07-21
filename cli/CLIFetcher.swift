// CLIFetcher.swift
// One-shot provider fetches for the CLI — works even when the app isn't
// running. Reuses the app's models and pure mappings.

import Foundation

struct CLIFetcher {
    let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    func fetch(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw FetchError.invalidURL }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }
        return data
    }

    /// Detects the provider and returns the live status for a base URL.
    func liveStatus(baseURL: String) async -> (indicator: String, description: String) {
        // Atlassian / incident.io-compat / Instatus all serve /api/v2/summary.json
        if let data = try? await fetch("\(baseURL)/api/v2/summary.json") {
            if let summary = try? JSONDecoder().decode(SPSummary.self, from: data) {
                return (summary.status.indicator, summary.status.description)
            }
            if let instatus = try? JSONDecoder().decode(InstatusSummary.self, from: data) {
                let summary = SPSummary.fromInstatus(instatus, components: [], baseURL: baseURL)
                return (summary.status.indicator, summary.status.description)
            }
        }
        // Gatus
        if let data = try? await fetch("\(baseURL)/api/v1/endpoints/statuses?page=1&pageSize=100"),
            let endpoints = try? JSONDecoder().decode([GatusEndpointStatus].self, from: data)
        {
            let summary = SPSummary.fromGatus(endpoints, baseURL: baseURL)
            return (summary.status.indicator, summary.status.description)
        }
        // incident.io widget fallback
        if let data = try? await fetch("\(baseURL)/proxy/widget"),
            let widget = try? JSONDecoder().decode(IIOWidgetResponse.self, from: data)
        {
            let (summary, _) = SPSummary.fromIncidentIOWidget(widget, baseURL: baseURL)
            return (summary.status.indicator, summary.status.description)
        }
        return ("unknown", "Unreachable")
    }
}
