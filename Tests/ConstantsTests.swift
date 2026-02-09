import XCTest
import Foundation

// MARK: - ConstantsTests

final class ConstantsTests: XCTestCase {

    func testDefaultRefreshInterval() {
        XCTAssertEqual(kDefaultRefreshInterval, 300)
    }

    func testRefreshIntervalOptionsCount() {
        XCTAssertEqual(kRefreshIntervalOptions.count, 5)
    }

    func testRefreshIntervalOptionsContainsDefault() {
        let containsDefault = kRefreshIntervalOptions.contains { $0.seconds == kDefaultRefreshInterval }
        XCTAssertTrue(containsDefault, "kRefreshIntervalOptions should contain the default interval")
    }

    func testRefreshIntervalOptionsSortedAscending() {
        let seconds = kRefreshIntervalOptions.map(\.seconds)
        let sorted = seconds.sorted()
        XCTAssertEqual(seconds, sorted, "Interval options should be sorted ascending")
    }

    func testDefaultSourcesParseable() {
        let sources = StatusSource.parse(lines: kDefaultSources)
        XCTAssertGreaterThanOrEqual(sources.count, 3)
    }

    func testDefaultSourcesContainExpectedEntries() {
        let sources = StatusSource.parse(lines: kDefaultSources)
        let names = sources.map(\.name)
        XCTAssertTrue(names.contains("Anthropic"), "Should contain Anthropic")
        XCTAssertTrue(names.contains("GitHub"), "Should contain GitHub")
        XCTAssertTrue(names.contains("Cloudflare"), "Should contain Cloudflare")
    }

    func testGitHubRepoFormat() {
        let parts = kGitHubRepo.split(separator: "/")
        XCTAssertEqual(parts.count, 2, "kGitHubRepo should be in 'owner/repo' format")
        XCTAssertFalse(parts[0].isEmpty)
        XCTAssertFalse(parts[1].isEmpty)
    }

}
