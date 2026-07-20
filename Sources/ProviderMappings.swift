// ProviderMappings.swift
// Pure mappings from provider-specific API models into the common SPSummary model.

import Foundation

// MARK: - incident.io Mapping

extension SPSummary {
    static func fromIncidentIOWidget(_ widget: IIOWidgetResponse, baseURL: String) -> (summary: SPSummary, incidents: [SPIncident]) {
        let allIncidents =
            (widget.ongoingIncidents ?? [])
            + (widget.inProgressMaintenances ?? [])

        let mappedIncidents = allIncidents.map { inc -> SPIncident in
            let id = inc.id ?? UUID().uuidString
            let name = inc.name ?? "Unknown incident"
            let status = inc.status ?? "investigating"
            let impact = deriveIncidentIOImpact(from: status)
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

        let indicator = deriveIncidentIOIndicator(from: allIncidents)
        let description = deriveIncidentIODescription(from: indicator, incidentCount: allIncidents.count)

        let summary = SPSummary(
            page: SPPage(id: baseURL, name: baseURL, url: baseURL, updatedAt: "", timeZone: nil),
            status: SPStatus(indicator: indicator, description: description),
            components: [],
            incidents: mappedIncidents
        )

        return (summary, mappedIncidents)
    }
}

func deriveIncidentIOImpact(from status: String) -> String {
    let map = ["investigating": "major", "identified": "major", "monitoring": "minor", "resolved": "none", "postmortem": "none"]
    return map[status.lowercased(), default: "minor"]
}

func deriveIncidentIOIndicator(from incidents: [IIOIncident]) -> String {
    if incidents.isEmpty { return "none" }
    for inc in incidents {
        let s = (inc.status ?? "").lowercased()
        if s == "investigating" || s == "identified" { return "major" }
    }
    return "minor"
}

func deriveIncidentIODescription(from indicator: String, incidentCount: Int) -> String {
    if indicator == "none" { return "All systems operational" }
    let suffix = incidentCount == 1 ? "" : "s"
    if indicator == "minor" || indicator == "major" {
        return "\(incidentCount) active incident\(suffix)"
    }
    return "Status unknown"
}

// MARK: - Instatus Mapping

extension SPSummary {
    static func fromInstatus(_ instatus: InstatusSummary, components: [InstatusComponent], baseURL: String) -> SPSummary {
        SPSummary(
            page: SPPage(id: baseURL, name: instatus.page.name, url: instatus.page.url, updatedAt: "", timeZone: nil),
            status: SPStatus(
                indicator: mapInstatusPageStatus(instatus.page.status),
                description: mapInstatusDescription(instatus.page.status)
            ),
            components: flattenInstatusComponents(components),
            incidents: []
        )
    }
}

func flattenInstatusComponents(_ components: [InstatusComponent]) -> [SPComponent] {
    var pos = 0
    return flattenInstatusComponents(components, position: &pos)
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

func mapInstatusPageStatus(_ status: String) -> String {
    ["UP": "none", "HASISSUES": "minor", "UNDERMAINTENANCE": "minor"][status, default: "major"]
}

func mapInstatusDescription(_ status: String) -> String {
    let map = ["UP": "All systems operational", "HASISSUES": "Experiencing issues", "UNDERMAINTENANCE": "Under maintenance"]
    return map[status, default: "Experiencing issues"]
}

func mapInstatusComponentStatus(_ status: String) -> String {
    let map = [
        "OPERATIONAL": "operational",
        "DEGRADEDPERFORMANCE": "degraded_performance",
        "PARTIALOUTAGE": "partial_outage",
        "MAJOROUTAGE": "major_outage",
        "UNDERMAINTENANCE": "degraded_performance",
    ]
    return map[status, default: status.lowercased()]
}

// MARK: - Gatus Mapping

extension SPSummary {
    static func fromGatus(_ endpoints: [GatusEndpointStatus], baseURL: String) -> SPSummary {
        let components = endpoints.enumerated().map { index, endpoint -> SPComponent in
            let status: String
            if let latest = endpoint.latestResult {
                status = latest.success ? "operational" : "major_outage"
            } else {
                status = "unknown"
            }
            return SPComponent(
                id: endpoint.key ?? endpoint.name,
                name: endpoint.displayName,
                status: status,
                description: nil,
                position: index,
                groupId: nil
            )
        }

        let checked = endpoints.filter { $0.latestResult != nil }
        let downCount = checked.filter { $0.latestResult?.success == false }.count

        let indicator: String
        let description: String
        if checked.isEmpty || downCount == 0 {
            indicator = "none"
            description = "All systems operational"
        } else if downCount == checked.count {
            indicator = "critical"
            description = "All \(checked.count) endpoints down"
        } else {
            indicator = "major"
            description = "\(downCount) of \(checked.count) endpoints down"
        }

        return SPSummary(
            page: SPPage(id: baseURL, name: baseURL, url: baseURL, updatedAt: "", timeZone: nil),
            status: SPStatus(indicator: indicator, description: description),
            components: components,
            incidents: []
        )
    }
}
