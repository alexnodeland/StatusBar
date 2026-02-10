import Foundation
import XCTest

// MARK: - HistoryStoreTests

final class HistoryStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: HistoryStore!

    @MainActor
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("history.json")
        store = HistoryStore(fileURL: fileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Record & Query

    @MainActor
    func testRecordAndRetrieve() {
        let id = UUID()
        store.record(sourceID: id, indicator: "none")
        store.record(sourceID: id, indicator: "minor")

        let all = store.data[id]
        XCTAssertEqual(all?.count, 2)
        XCTAssertEqual(all?[0].indicator, "none")
        XCTAssertEqual(all?[1].indicator, "minor")
    }

    @MainActor
    func testCheckpointsSinceDate() {
        let id = UUID()
        let old = StatusCheckpoint(date: Date().addingTimeInterval(-3600), indicator: "none")
        let recent = StatusCheckpoint(date: Date(), indicator: "minor")
        store.data[id] = [old, recent]

        let since30min = store.checkpoints(for: id, since: Date().addingTimeInterval(-1800))
        XCTAssertEqual(since30min.count, 1)
        XCTAssertEqual(since30min[0].indicator, "minor")

        let sinceAllTime = store.checkpoints(for: id, since: Date().addingTimeInterval(-7200))
        XCTAssertEqual(sinceAllTime.count, 2)
    }

    @MainActor
    func testCheckpointsForMissingSource() {
        let result = store.checkpoints(for: UUID(), since: Date().addingTimeInterval(-3600))
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Uptime Fraction

    @MainActor
    func testUptimeFractionAllOperational() {
        let id = UUID()
        store.data[id] = [
            StatusCheckpoint(date: Date(), indicator: "none"),
            StatusCheckpoint(date: Date(), indicator: "none"),
            StatusCheckpoint(date: Date(), indicator: "none"),
        ]
        let fraction = store.uptimeFraction(for: id, since: Date().addingTimeInterval(-3600))
        XCTAssertEqual(fraction, 1.0)
    }

    @MainActor
    func testUptimeFractionMixed() {
        let id = UUID()
        store.data[id] = [
            StatusCheckpoint(date: Date(), indicator: "none"),
            StatusCheckpoint(date: Date(), indicator: "minor"),
            StatusCheckpoint(date: Date(), indicator: "none"),
            StatusCheckpoint(date: Date(), indicator: "major"),
        ]
        let fraction = store.uptimeFraction(for: id, since: Date().addingTimeInterval(-3600))
        XCTAssertEqual(fraction, 0.5, accuracy: 0.001)
    }

    @MainActor
    func testUptimeFractionNoData() {
        let fraction = store.uptimeFraction(for: UUID(), since: Date().addingTimeInterval(-3600))
        XCTAssertEqual(fraction, 1.0)
    }

    // MARK: - Prune

    @MainActor
    func testPruneOlderThan() {
        let id = UUID()
        let old = StatusCheckpoint(date: Date().addingTimeInterval(-86400 * 31), indicator: "none")
        let recent = StatusCheckpoint(date: Date(), indicator: "minor")
        store.data[id] = [old, recent]

        store.pruneOlderThan(Date().addingTimeInterval(-86400 * 30))

        XCTAssertEqual(store.data[id]?.count, 1)
        XCTAssertEqual(store.data[id]?[0].indicator, "minor")
    }

    @MainActor
    func testPruneRemovesEmptySources() {
        let id = UUID()
        let old = StatusCheckpoint(date: Date().addingTimeInterval(-86400 * 31), indicator: "none")
        store.data[id] = [old]

        store.pruneOlderThan(Date().addingTimeInterval(-86400 * 30))

        XCTAssertNil(store.data[id])
    }

    // MARK: - Remove Source

    @MainActor
    func testRemoveSource() {
        let id = UUID()
        store.record(sourceID: id, indicator: "none")
        XCTAssertNotNil(store.data[id])

        store.removeSource(id)
        XCTAssertNil(store.data[id])
    }

    // MARK: - Persistence Round-Trip

    @MainActor
    func testSaveAndLoad() {
        let id = UUID()
        store.record(sourceID: id, indicator: "none")
        store.record(sourceID: id, indicator: "major")
        store.flushToDisk()

        let fileURL = tempDir.appendingPathComponent("history.json")
        let newStore = HistoryStore(fileURL: fileURL)
        newStore.load()

        XCTAssertEqual(newStore.data[id]?.count, 2)
        XCTAssertEqual(newStore.data[id]?[0].indicator, "none")
        XCTAssertEqual(newStore.data[id]?[1].indicator, "major")
    }

    @MainActor
    func testLoadMissingFile() {
        let missing = tempDir.appendingPathComponent("nonexistent.json")
        let newStore = HistoryStore(fileURL: missing)
        newStore.load()
        XCTAssertTrue(newStore.data.isEmpty)
    }

    @MainActor
    func testLoadCorruptFile() throws {
        let fileURL = tempDir.appendingPathComponent("history.json")
        try "not valid json".data(using: .utf8)!.write(to: fileURL)
        let newStore = HistoryStore(fileURL: fileURL)
        newStore.load()
        XCTAssertTrue(newStore.data.isEmpty)
    }

    // MARK: - Migration

    @MainActor
    func testMigrateFromAppStorage() {
        let id = UUID()
        let checkpoint = StatusCheckpoint(date: Date(timeIntervalSince1970: 1700000000), indicator: "minor")
        var legacy: [String: [StatusCheckpoint]] = [:]
        legacy[id.uuidString] = [checkpoint]
        let json = String(data: try! JSONEncoder().encode(legacy), encoding: .utf8)!

        store.migrateFromAppStorage(json)

        XCTAssertEqual(store.data[id]?.count, 1)
        XCTAssertEqual(store.data[id]?[0].indicator, "minor")

        // Verify it was flushed to disk
        let fileURL = tempDir.appendingPathComponent("history.json")
        let newStore = HistoryStore(fileURL: fileURL)
        newStore.load()
        XCTAssertEqual(newStore.data[id]?.count, 1)
    }

    @MainActor
    func testMigrateFromInvalidAppStorage() {
        store.migrateFromAppStorage("not json")
        XCTAssertTrue(store.data.isEmpty)
    }
}
