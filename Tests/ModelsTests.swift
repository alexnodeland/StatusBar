import XCTest
import Foundation

// MARK: - ModelsTests

final class ModelsTests: XCTestCase {

    // MARK: - StatusSource

    func testStatusSourceInitTrimsTrailingSlash() {
        let source = StatusSource(name: "Test", baseURL: "https://example.com/")
        XCTAssertEqual(source.baseURL, "https://example.com")
    }

    func testStatusSourceParseValid() {
        let input = "Anthropic\thttps://status.anthropic.com\nGitHub\thttps://www.githubstatus.com"
        let sources = StatusSource.parse(lines: input)
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources[0].name, "Anthropic")
        XCTAssertEqual(sources[0].baseURL, "https://status.anthropic.com")
        XCTAssertEqual(sources[1].name, "GitHub")
    }

    func testStatusSourceParseSkipsComments() {
        let input = "# This is a comment\nAcme\thttps://status.acme.com"
        let sources = StatusSource.parse(lines: input)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].name, "Acme")
    }

    func testStatusSourceParseEmptyReturnsEmpty() {
        XCTAssertEqual(StatusSource.parse(lines: "").count, 0)
        XCTAssertEqual(StatusSource.parse(lines: "\n\n").count, 0)
    }

    func testStatusSourceParseMalformed() {
        // No tab separator
        XCTAssertEqual(StatusSource.parse(lines: "no-tab-here").count, 0)
        // Empty name
        XCTAssertEqual(StatusSource.parse(lines: "\thttps://example.com").count, 0)
    }

    func testStatusSourceParseNonHTTP() {
        XCTAssertEqual(StatusSource.parse(lines: "Test\tftp://example.com").count, 0)
        XCTAssertEqual(StatusSource.parse(lines: "Test\tnot-a-url").count, 0)
    }

    func testStatusSourceSerialize() {
        let sources = [
            StatusSource(name: "A", baseURL: "https://a.com"),
            StatusSource(name: "B", baseURL: "https://b.com"),
        ]
        let result = StatusSource.serialize(sources)
        XCTAssertEqual(result, "A\thttps://a.com\nB\thttps://b.com")
    }

    func testStatusSourceRoundTrip() {
        let original = [
            StatusSource(name: "Test1", baseURL: "https://test1.com"),
            StatusSource(name: "Test2", baseURL: "https://test2.com/"),
        ]
        let serialized = StatusSource.serialize(original)
        let parsed = StatusSource.parse(lines: serialized)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].name, "Test1")
        XCTAssertEqual(parsed[0].baseURL, "https://test1.com")
        XCTAssertEqual(parsed[1].name, "Test2")
        XCTAssertEqual(parsed[1].baseURL, "https://test2.com")
    }

    // MARK: - Atlassian Models

    func testSPSummaryDecodeFullFixture() {
        let data = loadFixture("atlassian_summary.json")
        let summary = try! JSONDecoder().decode(SPSummary.self, from: data)
        XCTAssertEqual(summary.page.id, "kctbh9vrtdwd")
        XCTAssertEqual(summary.page.name, "GitHub")
        XCTAssertEqual(summary.page.timeZone, "Etc/UTC")
        XCTAssertEqual(summary.status.indicator, "minor")
        XCTAssertEqual(summary.status.description, "Minor Service Outage")
        XCTAssertEqual(summary.components.count, 3)
        XCTAssertEqual(summary.incidents.count, 1)
    }

    func testSPSummaryDecodeMissingArraysDefaultToEmpty() {
        let json = """
        {
            "page": {"id":"p1","name":"Test","url":"https://test.com","updated_at":"2024-01-01T00:00:00Z"},
            "status": {"indicator":"none","description":"All good"}
        }
        """.data(using: .utf8)!
        let summary = try! JSONDecoder().decode(SPSummary.self, from: json)
        XCTAssertEqual(summary.components.count, 0)
        XCTAssertEqual(summary.incidents.count, 0)
    }

    func testSPPageCodingKeys() {
        let json = """
        {"id":"p1","name":"Test","url":"https://test.com","updated_at":"2024-01-01T00:00:00Z","time_zone":"US/Pacific"}
        """.data(using: .utf8)!
        let page = try! JSONDecoder().decode(SPPage.self, from: json)
        XCTAssertEqual(page.updatedAt, "2024-01-01T00:00:00Z")
        XCTAssertEqual(page.timeZone, "US/Pacific")
    }

    func testSPComponentCodingKeys() {
        let json = """
        {"id":"c1","name":"API","status":"operational","description":null,"position":1,"group_id":"g1"}
        """.data(using: .utf8)!
        let component = try! JSONDecoder().decode(SPComponent.self, from: json)
        XCTAssertEqual(component.groupId, "g1")
        XCTAssertEqual(component.position, 1)
    }

    func testSPIncidentWithUpdates() {
        let data = loadFixture("atlassian_summary.json")
        let summary = try! JSONDecoder().decode(SPSummary.self, from: data)
        let incident = summary.incidents[0]
        XCTAssertEqual(incident.id, "inc1")
        XCTAssertEqual(incident.name, "Elevated error rates")
        XCTAssertEqual(incident.status, "investigating")
        XCTAssertEqual(incident.impact, "minor")
        XCTAssertEqual(incident.shortlink, "https://stspg.io/abc123")
        XCTAssertEqual(incident.incidentUpdates.count, 1)
        XCTAssertEqual(incident.incidentUpdates[0].body, "We are investigating elevated error rates.")
    }

    func testSPIncidentsResponse() {
        let data = loadFixture("atlassian_incidents.json")
        let response = try! JSONDecoder().decode(SPIncidentsResponse.self, from: data)
        XCTAssertEqual(response.page.id, "kctbh9vrtdwd")
        XCTAssertEqual(response.incidents.count, 2)
        XCTAssertEqual(response.incidents[0].id, "inc1")
        XCTAssertEqual(response.incidents[1].id, "inc2")
        XCTAssertEqual(response.incidents[1].incidentUpdates.count, 2)
    }

    // MARK: - incident.io Models

    func testIIOWidgetResponseDecode() {
        let data = loadFixture("incidentio_widget.json")
        let widget = try! JSONDecoder().decode(IIOWidgetResponse.self, from: data)
        XCTAssertEqual(widget.ongoingIncidents?.count, 1)
        XCTAssertEqual(widget.inProgressMaintenances?.count, 1)
        XCTAssertEqual(widget.scheduledMaintenances?.count, 1)
        XCTAssertEqual(widget.ongoingIncidents?[0].name, "API degradation")
        XCTAssertEqual(widget.ongoingIncidents?[0].affectedComponents?.count, 2)
    }

    func testIIOWidgetResponseEmptyJSON() {
        let json = "{}".data(using: .utf8)!
        let widget = try! JSONDecoder().decode(IIOWidgetResponse.self, from: json)
        XCTAssertNil(widget.ongoingIncidents)
        XCTAssertNil(widget.inProgressMaintenances)
        XCTAssertNil(widget.scheduledMaintenances)
    }

    func testIIOIncidentOptionalFields() {
        let json = """
        {"id":"x","name":null,"status":null,"last_update_message":null,"affected_components":null,"created_at":null,"updated_at":null}
        """.data(using: .utf8)!
        let incident = try! JSONDecoder().decode(IIOIncident.self, from: json)
        XCTAssertEqual(incident.id, "x")
        XCTAssertNil(incident.name)
        XCTAssertNil(incident.status)
        XCTAssertNil(incident.lastUpdateMessage)
        XCTAssertNil(incident.affectedComponents)
    }

    // MARK: - Instatus Models

    func testInstatusSummaryDecode() {
        let data = loadFixture("instatus_summary.json")
        let summary = try! JSONDecoder().decode(InstatusSummary.self, from: data)
        XCTAssertEqual(summary.page.name, "Acme Status")
        XCTAssertEqual(summary.page.url, "https://status.acme.com")
        XCTAssertEqual(summary.page.status, "UP")
    }

    func testInstatusComponentsDecode() {
        let data = loadFixture("instatus_components.json")
        let response = try! JSONDecoder().decode(InstatusComponentsResponse.self, from: data)
        XCTAssertEqual(response.components.count, 2)
        XCTAssertEqual(response.components[0].name, "API")
        XCTAssertTrue(response.components[0].isParent)
        XCTAssertEqual(response.components[1].name, "Dashboard")
        XCTAssertEqual(response.components[1].status, "MAJOROUTAGE")
    }

    func testInstatusNestedChildren() {
        let data = loadFixture("instatus_components.json")
        let response = try! JSONDecoder().decode(InstatusComponentsResponse.self, from: data)
        let apiComp = response.components[0]
        XCTAssertEqual(apiComp.children.count, 2)
        XCTAssertEqual(apiComp.children[0].name, "REST API")
        XCTAssertEqual(apiComp.children[1].name, "GraphQL API")
        XCTAssertEqual(apiComp.children[1].status, "DEGRADEDPERFORMANCE")
        XCTAssertEqual(apiComp.children[0].children.count, 0)
    }

    // MARK: - GitHub Models

    func testGitHubReleaseFullFixture() {
        let data = loadFixture("github_release.json")
        let release = try! JSONDecoder().decode(GitHubRelease.self, from: data)
        XCTAssertEqual(release.tagName, "v1.2.3")
        XCTAssertEqual(release.name, "Release v1.2.3")
        XCTAssertEqual(release.htmlUrl, "https://github.com/alexnodeland/StatusBar/releases/tag/v1.2.3")
        XCTAssertEqual(release.assets.count, 2)
        XCTAssertEqual(release.assets[0].name, "StatusBar-v1.2.3.zip")
        XCTAssertTrue(release.assets[0].browserDownloadUrl.contains("v1.2.3"))
    }

    func testGitHubReleaseOptionalNameEmptyAssets() {
        let json = """
        {"tag_name":"v0.1.0","name":null,"html_url":"https://example.com","assets":[]}
        """.data(using: .utf8)!
        let release = try! JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.tagName, "v0.1.0")
        XCTAssertNil(release.name)
        XCTAssertEqual(release.assets.count, 0)
    }

    // MARK: - Enums: SourceSortOrder

    func testSourceSortOrderRawValues() {
        XCTAssertEqual(SourceSortOrder.alphabetical.rawValue, "Name")
        XCTAssertEqual(SourceSortOrder.latest.rawValue, "Latest")
        XCTAssertEqual(SourceSortOrder.status.rawValue, "Status")
    }

    func testSourceSortOrderSystemImages() {
        XCTAssertEqual(SourceSortOrder.alphabetical.systemImage, "textformat.abc")
        XCTAssertEqual(SourceSortOrder.latest.systemImage, "clock")
        XCTAssertEqual(SourceSortOrder.status.systemImage, "circle.fill")
    }

    // MARK: - Enums: SourceStatusFilter

    func testSourceStatusFilterIndicators() {
        XCTAssertNil(SourceStatusFilter.all.indicator)
        XCTAssertEqual(SourceStatusFilter.operational.indicator, "none")
        XCTAssertEqual(SourceStatusFilter.minor.indicator, "minor")
        XCTAssertEqual(SourceStatusFilter.major.indicator, "major")
        XCTAssertEqual(SourceStatusFilter.critical.indicator, "critical")
    }

    func testSourceStatusFilterSystemImages() {
        XCTAssertEqual(SourceStatusFilter.all.systemImage, "circle.grid.2x2")
        XCTAssertEqual(SourceStatusFilter.operational.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(SourceStatusFilter.minor.systemImage, "exclamationmark.triangle.fill")
        XCTAssertEqual(SourceStatusFilter.major.systemImage, "exclamationmark.octagon.fill")
        XCTAssertEqual(SourceStatusFilter.critical.systemImage, "xmark.octagon.fill")
    }

    // MARK: - SourceState

    func testSourceStateDefaultIndicator() {
        let state = SourceState()
        XCTAssertEqual(state.indicator, "unknown")
        XCTAssertEqual(state.indicatorSeverity, -1)
        XCTAssertNil(state.summary)
    }

    func testSourceStateIndicatorFromSummary() {
        let summary = SPSummary(
            page: SPPage(id: "p", name: "P", url: "https://p.com", updatedAt: "", timeZone: nil),
            status: SPStatus(indicator: "major", description: "Major outage"),
            components: [],
            incidents: []
        )
        var state = SourceState()
        state.summary = summary
        XCTAssertEqual(state.indicator, "major")
        XCTAssertEqual(state.indicatorSeverity, 2)
    }

    func testSourceStateSeverityValues() {
        func severity(for indicator: String) -> Int {
            let summary = SPSummary(
                page: SPPage(id: "p", name: "P", url: "https://p.com", updatedAt: "", timeZone: nil),
                status: SPStatus(indicator: indicator, description: ""),
                components: [],
                incidents: []
            )
            var state = SourceState()
            state.summary = summary
            return state.indicatorSeverity
        }
        XCTAssertEqual(severity(for: "none"), 0)
        XCTAssertEqual(severity(for: "minor"), 1)
        XCTAssertEqual(severity(for: "major"), 2)
        XCTAssertEqual(severity(for: "critical"), 3)
        XCTAssertEqual(severity(for: "garbage"), -1)
    }

    func testSourceStateTopLevelComponents() {
        let components = [
            SPComponent(id: "g1", name: "Group", status: "operational", description: nil, position: 2, groupId: nil),
            SPComponent(id: "c1", name: "Child", status: "operational", description: nil, position: 1, groupId: "g1"),
            SPComponent(id: "c2", name: "TopLevel", status: "degraded_performance", description: nil, position: 1, groupId: nil),
        ]
        let summary = SPSummary(
            page: SPPage(id: "p", name: "P", url: "https://p.com", updatedAt: "", timeZone: nil),
            status: SPStatus(indicator: "none", description: "OK"),
            components: components,
            incidents: []
        )
        var state = SourceState()
        state.summary = summary
        let topLevel = state.topLevelComponents
        // Should filter out child (groupId != nil) and sort by position
        XCTAssertEqual(topLevel.count, 2)
        XCTAssertEqual(topLevel[0].id, "c2")  // position 1
        XCTAssertEqual(topLevel[1].id, "g1")  // position 2
    }

    func testSourceStateStatusDescription() {
        let state = SourceState()
        XCTAssertEqual(state.statusDescription, "Loading\u{2026}")

        let summary = SPSummary(
            page: SPPage(id: "p", name: "P", url: "https://p.com", updatedAt: "", timeZone: nil),
            status: SPStatus(indicator: "none", description: "All systems operational"),
            components: [],
            incidents: []
        )
        var stateWithSummary = SourceState()
        stateWithSummary.summary = summary
        XCTAssertEqual(stateWithSummary.statusDescription, "All systems operational")
    }

    func testSourceStateActiveIncidents() {
        let incidents = [
            SPIncident(id: "i1", name: "Inc 1", status: "investigating", impact: "minor",
                       createdAt: "", updatedAt: "", shortlink: nil, incidentUpdates: []),
            SPIncident(id: "i2", name: "Inc 2", status: "resolved", impact: "none",
                       createdAt: "", updatedAt: "", shortlink: nil, incidentUpdates: []),
        ]
        let summary = SPSummary(
            page: SPPage(id: "p", name: "P", url: "https://p.com", updatedAt: "", timeZone: nil),
            status: SPStatus(indicator: "minor", description: "Minor"),
            components: [],
            incidents: incidents
        )
        var state = SourceState()
        state.summary = summary
        XCTAssertEqual(state.activeIncidents.count, 2)
        XCTAssertEqual(state.activeIncidents[0].id, "i1")
    }

}
