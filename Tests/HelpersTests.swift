import Foundation
import XCTest

// MARK: - HelpersTests

final class HelpersTests: XCTestCase {

    // MARK: - parseDate

    func testParseDateWithFractionalSeconds() {
        let date = parseDate("2024-01-15T10:30:00.000Z")
        XCTAssertNotNil(date)
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date!)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 15)
    }

    func testParseDateWithoutFractionalSeconds() {
        let date = parseDate("2024-01-15T10:30:00Z")
        XCTAssertNotNil(date)
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date!)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.hour, 10)
        XCTAssertEqual(comps.minute, 30)
    }

    func testParseDateInvalidString() {
        XCTAssertNil(parseDate("not-a-date"))
    }

    func testParseDateEmptyString() {
        XCTAssertNil(parseDate(""))
    }

    // MARK: - formatDate

    func testFormatDateValidISO() {
        let result = formatDate("2024-01-15T10:30:00.000Z")
        // Should not return the original string (meaning it parsed successfully)
        XCTAssertNotEqual(result, "2024-01-15T10:30:00.000Z")
        XCTAssertFalse(result.isEmpty)
    }

    func testFormatDateInvalidReturnsOriginal() {
        let input = "garbage-string"
        let result = formatDate(input)
        XCTAssertEqual(result, input)
    }

    // MARK: - relativeDate

    func testRelativeDateReturnsNonEmpty() {
        let result = relativeDate("2024-01-15T10:30:00.000Z")
        XCTAssertFalse(result.isEmpty)
        // Should have been transformed (not the original ISO string)
        XCTAssertNotEqual(result, "2024-01-15T10:30:00.000Z")
    }

    func testRelativeDateInvalidReturnsOriginal() {
        let input = "not-valid"
        let result = relativeDate(input)
        XCTAssertEqual(result, input)
    }

    // MARK: - iconForIndicator

    func testIconForIndicatorNone() {
        XCTAssertEqual(iconForIndicator("none"), "checkmark.circle.fill")
    }

    func testIconForIndicatorMinor() {
        XCTAssertEqual(iconForIndicator("minor"), "exclamationmark.triangle.fill")
    }

    func testIconForIndicatorMajor() {
        XCTAssertEqual(iconForIndicator("major"), "exclamationmark.octagon.fill")
    }

    func testIconForIndicatorCritical() {
        XCTAssertEqual(iconForIndicator("critical"), "xmark.octagon.fill")
    }

    func testIconForIndicatorUnknown() {
        XCTAssertEqual(iconForIndicator("something"), "questionmark.circle")
        XCTAssertEqual(iconForIndicator(""), "questionmark.circle")
    }

    // MARK: - colorForIndicator (smoke test — just verify no crash, returns a Color)

    func testColorForIndicatorAllCases() {
        // Just verify each branch executes without crashing
        _ = colorForIndicator("none")
        _ = colorForIndicator("minor")
        _ = colorForIndicator("major")
        _ = colorForIndicator("critical")
        _ = colorForIndicator("unknown")
    }

    // MARK: - colorForComponentStatus (smoke test)

    func testColorForComponentStatusAllCases() {
        _ = colorForComponentStatus("operational")
        _ = colorForComponentStatus("degraded_performance")
        _ = colorForComponentStatus("partial_outage")
        _ = colorForComponentStatus("major_outage")
        _ = colorForComponentStatus("something_else")
    }

    // MARK: - labelForComponentStatus

    func testLabelForComponentStatusAllCases() {
        XCTAssertEqual(labelForComponentStatus("operational"), "Operational")
        XCTAssertEqual(labelForComponentStatus("degraded_performance"), "Degraded")
        XCTAssertEqual(labelForComponentStatus("partial_outage"), "Partial Outage")
        XCTAssertEqual(labelForComponentStatus("major_outage"), "Major Outage")
    }

    func testLabelForComponentStatusUnknownPassthrough() {
        XCTAssertEqual(labelForComponentStatus("custom_status"), "custom_status")
        XCTAssertEqual(labelForComponentStatus(""), "")
    }

    // MARK: - validateSourceURL

    func testValidateSourceURLValid() {
        let result = validateSourceURL("https://status.example.com")
        XCTAssertEqual(result, .valid)
        XCTAssertTrue(result.isAcceptable)
        XCTAssertNil(result.message)
    }

    func testValidateSourceURLEmpty() {
        let result = validateSourceURL("")
        XCTAssertEqual(result, .invalid("URL cannot be empty"))
        XCTAssertFalse(result.isAcceptable)
    }

    func testValidateSourceURLWhitespaceOnly() {
        let result = validateSourceURL("   ")
        XCTAssertEqual(result, .invalid("URL cannot be empty"))
        XCTAssertFalse(result.isAcceptable)
    }

    func testValidateSourceURLMissingScheme() {
        let result = validateSourceURL("status.example.com")
        XCTAssertFalse(result.isAcceptable)
    }

    func testValidateSourceURLFTPScheme() {
        let result = validateSourceURL("ftp://example.com")
        XCTAssertEqual(result, .invalid("URL must use http or https scheme"))
        XCTAssertFalse(result.isAcceptable)
    }

    func testValidateSourceURLHTTPWarning() {
        let result = validateSourceURL("http://status.example.com")
        XCTAssertEqual(result, .validWithWarning("Consider using https for secure connections"))
        XCTAssertTrue(result.isAcceptable)
        XCTAssertNotNil(result.message)
    }

    func testValidateSourceURLNoHost() {
        let result = validateSourceURL("https://")
        XCTAssertFalse(result.isAcceptable)
    }

    func testValidateSourceURLNoDotInHost() {
        let result = validateSourceURL("https://localhost")
        XCTAssertEqual(result, .invalid("Host must contain a domain (e.g. example.com)"))
        XCTAssertFalse(result.isAcceptable)
    }

    func testValidateSourceURLAPIPathWarning() {
        let result = validateSourceURL("https://example.com/api/v2/summary.json")
        XCTAssertEqual(result, .validWithWarning("URL appears to contain an API path — use the base status page URL instead"))
        XCTAssertTrue(result.isAcceptable)
    }

    func testValidateSourceURLTrimsWhitespace() {
        let result = validateSourceURL("  https://status.example.com  ")
        XCTAssertEqual(result, .valid)
    }

    // MARK: - withRetry

    func testWithRetrySucceedsFirstAttempt() async throws {
        var attempts = 0
        let result = try await withRetry(maxAttempts: 3, baseDelay: 0.01, maxDelay: 0.01) {
            attempts += 1
            return "success"
        }
        XCTAssertEqual(result, "success")
        XCTAssertEqual(attempts, 1)
    }

    func testWithRetrySucceedsAfterTransientFailures() async throws {
        var attempts = 0
        let result: String = try await withRetry(maxAttempts: 3, baseDelay: 0.01, maxDelay: 0.01) {
            attempts += 1
            if attempts < 3 {
                throw URLError(.timedOut)
            }
            return "recovered"
        }
        XCTAssertEqual(result, "recovered")
        XCTAssertEqual(attempts, 3)
    }

    func testWithRetryThrowsAfterAllFail() async {
        var attempts = 0
        do {
            let _: String = try await withRetry(maxAttempts: 3, baseDelay: 0.01, maxDelay: 0.01) {
                attempts += 1
                throw URLError(.notConnectedToInternet)
            }
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(attempts, 3)
            XCTAssertTrue(error is URLError)
        }
    }

    // MARK: - compareVersions

    func testCompareVersionsEqual() {
        XCTAssertEqual(compareVersions("1.0.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(compareVersions("2.3.4", "2.3.4"), .orderedSame)
        XCTAssertEqual(compareVersions("1.0", "1.0.0"), .orderedSame)
    }

    func testCompareVersionsLessThan() {
        XCTAssertEqual(compareVersions("1.0.0", "1.0.1"), .orderedAscending)
        XCTAssertEqual(compareVersions("1.0.0", "2.0.0"), .orderedAscending)
        XCTAssertEqual(compareVersions("1.9.9", "2.0.0"), .orderedAscending)
        XCTAssertEqual(compareVersions("1.0", "1.0.1"), .orderedAscending)
    }

    func testCompareVersionsGreaterThan() {
        XCTAssertEqual(compareVersions("1.0.1", "1.0.0"), .orderedDescending)
        XCTAssertEqual(compareVersions("2.0.0", "1.9.9"), .orderedDescending)
        XCTAssertEqual(compareVersions("10.0.0", "9.9.9"), .orderedDescending)
    }

}
