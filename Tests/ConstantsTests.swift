import Foundation
import XCTest

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

    func testDefaultSourcesNotEmpty() {
        XCTAssertGreaterThanOrEqual(kDefaultSources.count, 3)
    }

    func testDefaultSourcesContainExpectedEntries() {
        let names = kDefaultSources.map(\.name)
        XCTAssertTrue(names.contains("Anthropic"), "Should contain Anthropic")
        XCTAssertTrue(names.contains("GitHub"), "Should contain GitHub")
        XCTAssertTrue(names.contains("Cloudflare"), "Should contain Cloudflare")
    }

    func testDefaultSourcesHaveValidURLs() {
        for source in kDefaultSources {
            XCTAssertTrue(source.baseURL.hasPrefix("https://"), "\(source.name) URL should use https")
        }
    }

    // MARK: - Retry Constants

    func testMaxRetries() {
        XCTAssertEqual(kMaxRetries, 3)
    }

    func testRetryBaseDelay() {
        XCTAssertEqual(kRetryBaseDelay, 1.0)
    }

    func testRetryMaxDelay() {
        XCTAssertEqual(kRetryMaxDelay, 8.0)
    }

    func testRetryMaxDelayGreaterThanBase() {
        XCTAssertGreaterThan(kRetryMaxDelay, kRetryBaseDelay, "Max delay should be greater than base delay")
    }

    func testGitHubRepoFormat() {
        let parts = kGitHubRepo.split(separator: "/")
        XCTAssertEqual(parts.count, 2, "kGitHubRepo should be in 'owner/repo' format")
        XCTAssertFalse(parts[0].isEmpty)
        XCTAssertFalse(parts[1].isEmpty)
    }

}
