import Foundation
import XCTest

// MARK: - ProviderMappingTests

final class ProviderMappingTests: XCTestCase {

    // MARK: - incident.io Mapping

    func testFromIncidentIOWidgetFixture() throws {
        let widget = try JSONDecoder().decode(IIOWidgetResponse.self, from: loadFixture("incidentio_widget.json"))
        let (summary, incidents) = SPSummary.fromIncidentIOWidget(widget, baseURL: "https://status.example.com")

        // Ongoing + in-progress maintenances are included; scheduled are not
        XCTAssertEqual(incidents.count, 2)
        XCTAssertEqual(summary.status.indicator, "major")  // "investigating" present
        XCTAssertEqual(summary.status.description, "2 active incidents")
        XCTAssertEqual(summary.page.id, "https://status.example.com")

        let api = incidents[0]
        XCTAssertEqual(api.id, "iio-1")
        XCTAssertEqual(api.impact, "major")
        XCTAssertEqual(api.incidentUpdates.count, 1)
        XCTAssertEqual(api.incidentUpdates[0].body, "We are investigating API issues.")

        let maintenance = incidents[1]
        XCTAssertEqual(maintenance.impact, "minor")  // "monitoring"
    }

    func testFromIncidentIOWidgetEmpty() throws {
        let widget = try JSONDecoder().decode(IIOWidgetResponse.self, from: Data("{}".utf8))
        let (summary, incidents) = SPSummary.fromIncidentIOWidget(widget, baseURL: "https://s.example.com")
        XCTAssertEqual(incidents.count, 0)
        XCTAssertEqual(summary.status.indicator, "none")
        XCTAssertEqual(summary.status.description, "All systems operational")
    }

    func testDeriveIncidentIOImpact() {
        XCTAssertEqual(deriveIncidentIOImpact(from: "investigating"), "major")
        XCTAssertEqual(deriveIncidentIOImpact(from: "Identified"), "major")
        XCTAssertEqual(deriveIncidentIOImpact(from: "monitoring"), "minor")
        XCTAssertEqual(deriveIncidentIOImpact(from: "resolved"), "none")
        XCTAssertEqual(deriveIncidentIOImpact(from: "postmortem"), "none")
        XCTAssertEqual(deriveIncidentIOImpact(from: "something-else"), "minor")
    }

    func testDeriveIncidentIOIndicator() {
        XCTAssertEqual(deriveIncidentIOIndicator(from: []), "none")
        let monitoring = IIOIncident(
            id: "a", name: "A", status: "monitoring", lastUpdateMessage: nil,
            affectedComponents: nil, createdAt: nil, updatedAt: nil)
        XCTAssertEqual(deriveIncidentIOIndicator(from: [monitoring]), "minor")
        let investigating = IIOIncident(
            id: "b", name: "B", status: "investigating", lastUpdateMessage: nil,
            affectedComponents: nil, createdAt: nil, updatedAt: nil)
        XCTAssertEqual(deriveIncidentIOIndicator(from: [monitoring, investigating]), "major")
    }

    // MARK: - Instatus Mapping

    func testFromInstatusFixture() throws {
        let instatus = try JSONDecoder().decode(InstatusSummary.self, from: loadFixture("instatus_summary.json"))
        let comps = try JSONDecoder().decode(InstatusComponentsResponse.self, from: loadFixture("instatus_components.json"))
        let summary = SPSummary.fromInstatus(instatus, components: comps.components, baseURL: "https://status.acme.com")

        XCTAssertEqual(summary.page.name, "Acme Status")
        XCTAssertEqual(summary.status.indicator, "none")  // "UP"
        XCTAssertEqual(summary.status.description, "All systems operational")

        // Nested children are flattened depth-first with sequential positions
        XCTAssertEqual(summary.components.map(\.id), ["ic1", "ic1a", "ic1b", "ic2"])
        XCTAssertEqual(summary.components.map(\.position), [0, 1, 2, 3])
        XCTAssertEqual(summary.components[2].status, "degraded_performance")
        XCTAssertEqual(summary.components[3].status, "major_outage")
        XCTAssertEqual(summary.incidents.count, 0)
    }

    func testMapInstatusPageStatus() {
        XCTAssertEqual(mapInstatusPageStatus("UP"), "none")
        XCTAssertEqual(mapInstatusPageStatus("HASISSUES"), "minor")
        XCTAssertEqual(mapInstatusPageStatus("UNDERMAINTENANCE"), "minor")
        XCTAssertEqual(mapInstatusPageStatus("SOMETHINGELSE"), "major")
    }

    func testMapInstatusDescription() {
        XCTAssertEqual(mapInstatusDescription("UP"), "All systems operational")
        XCTAssertEqual(mapInstatusDescription("HASISSUES"), "Experiencing issues")
        XCTAssertEqual(mapInstatusDescription("UNDERMAINTENANCE"), "Under maintenance")
        XCTAssertEqual(mapInstatusDescription("UNKNOWN"), "Experiencing issues")
    }

    func testMapInstatusComponentStatus() {
        XCTAssertEqual(mapInstatusComponentStatus("OPERATIONAL"), "operational")
        XCTAssertEqual(mapInstatusComponentStatus("DEGRADEDPERFORMANCE"), "degraded_performance")
        XCTAssertEqual(mapInstatusComponentStatus("PARTIALOUTAGE"), "partial_outage")
        XCTAssertEqual(mapInstatusComponentStatus("MAJOROUTAGE"), "major_outage")
        XCTAssertEqual(mapInstatusComponentStatus("UNDERMAINTENANCE"), "degraded_performance")
        XCTAssertEqual(mapInstatusComponentStatus("NEWSTATUS"), "newstatus")
    }

    // MARK: - Fetch Error Retryability

    func testFetchErrorRetryability() {
        XCTAssertFalse(FetchError.invalidURL.isRetryable)
        XCTAssertFalse(FetchError.httpStatus(404).isRetryable)
        XCTAssertFalse(FetchError.httpStatus(429).isRetryable)
        XCTAssertTrue(FetchError.httpStatus(500).isRetryable)
        XCTAssertTrue(FetchError.httpStatus(503).isRetryable)
    }

    func testIsRetryableErrorClassification() {
        XCTAssertFalse(isRetryableError(FetchError.invalidURL))
        XCTAssertFalse(
            isRetryableError(
                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))))
        XCTAssertTrue(isRetryableError(URLError(.timedOut)))
        XCTAssertTrue(isRetryableError(FetchError.httpStatus(502)))
    }

    func testWithRetryDoesNotRetryTerminalErrors() async {
        var attempts = 0
        do {
            _ = try await withRetry(maxAttempts: 3, baseDelay: 0.001, maxDelay: 0.001) { () -> Int in
                attempts += 1
                throw FetchError.httpStatus(404)
            }
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(error as? FetchError, .httpStatus(404))
        }
        XCTAssertEqual(attempts, 1)
    }

    func testWithRetryRetriesTransientErrors() async {
        var attempts = 0
        do {
            _ = try await withRetry(maxAttempts: 3, baseDelay: 0.001, maxDelay: 0.001) { () -> Int in
                attempts += 1
                throw FetchError.httpStatus(500)
            }
            XCTFail("Expected throw")
        } catch {}
        XCTAssertEqual(attempts, 3)
    }
}
