import Foundation
import XCTest

// MARK: - StatusCacheTests

final class StatusCacheTests: XCTestCase {

    private func tempCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("statusbar-cache-tests-\(UUID().uuidString)")
            .appendingPathComponent("status.json")
    }

    @MainActor
    func testSnapshotFromSourcesAndStates() {
        let ok = StatusSource(name: "GitHub", baseURL: "https://www.githubstatus.com")
        let bad = StatusSource(
            name: "Cloudflare", baseURL: "https://www.cloudflarestatus.com", group: "Cloud",
            snoozedUntil: Date().addingTimeInterval(3600)
        )
        var okState = SourceState()
        okState.summary = SPSummary(
            page: SPPage(id: "p", name: "GitHub", url: "u", updatedAt: "", timeZone: nil),
            status: SPStatus(indicator: "none", description: "All Systems Operational"),
            components: [], incidents: []
        )
        var badState = SourceState()
        badState.summary = SPSummary(
            page: SPPage(id: "p2", name: "Cloudflare", url: "u2", updatedAt: "", timeZone: nil),
            status: SPStatus(indicator: "minor", description: "Minor Service Outage"),
            components: [], incidents: []
        )

        let snapshot = StatusCache.snapshot(
            sources: [ok, bad],
            states: [ok.id: okState, bad.id: badState]
        )

        XCTAssertEqual(snapshot.worst, "minor")
        XCTAssertEqual(snapshot.issueCount, 1)
        XCTAssertEqual(snapshot.sources.count, 2)
        XCTAssertEqual(snapshot.sources[0].name, "GitHub")
        XCTAssertEqual(snapshot.sources[0].indicator, "none")
        XCTAssertEqual(snapshot.sources[1].indicator, "minor")
        XCTAssertEqual(snapshot.sources[1].group, "Cloud")
        XCTAssertTrue(snapshot.sources[1].snoozed)
        XCTAssertFalse(snapshot.updatedAt.isEmpty)
    }

    @MainActor
    func testSnapshotWithNoStatesIsUnknown() {
        let source = StatusSource(name: "S", baseURL: "https://s.com")
        let snapshot = StatusCache.snapshot(sources: [source], states: [:])
        XCTAssertEqual(snapshot.worst, "unknown")
        XCTAssertEqual(snapshot.issueCount, 0)
        XCTAssertEqual(snapshot.sources[0].indicator, "unknown")
    }

    func testWriteAndReadRoundTrip() {
        let url = tempCacheURL()
        let cache = StatusCache(fileURL: url)
        let snapshot = StatusCacheSnapshot(
            updatedAt: "2026-07-20T21:00:00Z",
            worst: "none",
            issueCount: 0,
            sources: [
                StatusCacheSource(
                    name: "GitHub", url: "https://www.githubstatus.com",
                    indicator: "none", description: "All Systems Operational",
                    group: nil, snoozed: false
                )
            ]
        )
        cache.write(snapshot)
        let read = cache.read()
        XCTAssertEqual(read, snapshot)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testReadMissingFileReturnsNil() {
        XCTAssertNil(StatusCache(fileURL: tempCacheURL()).read())
    }

    func testOverwriteReplacesPreviousSnapshot() {
        let url = tempCacheURL()
        let cache = StatusCache(fileURL: url)
        let first = StatusCacheSnapshot(updatedAt: "a", worst: "none", issueCount: 0, sources: [])
        let second = StatusCacheSnapshot(updatedAt: "b", worst: "major", issueCount: 2, sources: [])
        cache.write(first)
        cache.write(second)
        XCTAssertEqual(cache.read(), second)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
