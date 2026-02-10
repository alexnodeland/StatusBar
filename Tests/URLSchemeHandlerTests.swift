import Foundation
import XCTest

// MARK: - URLSchemeHandlerTests

final class URLSchemeHandlerTests: XCTestCase {

    // MARK: - Valid Routes

    func testParseOpen() {
        let url = URL(string: "statusbar://open")!
        XCTAssertEqual(URLRoute.parse(url), .open)
    }

    func testParseOpenWithSource() {
        let url = URL(string: "statusbar://open?source=GitHub")!
        XCTAssertEqual(URLRoute.parse(url), .openSource("GitHub"))
    }

    func testParseOpenWithEncodedSource() {
        let url = URL(string: "statusbar://open?source=My%20Service")!
        XCTAssertEqual(URLRoute.parse(url), .openSource("My Service"))
    }

    func testParseRefresh() {
        let url = URL(string: "statusbar://refresh")!
        XCTAssertEqual(URLRoute.parse(url), .refresh)
    }

    func testParseAddSource() {
        let url = URL(string: "statusbar://add?url=https://status.openai.com")!
        let route = URLRoute.parse(url)
        XCTAssertEqual(route, .addSource(url: "https://status.openai.com", name: nil))
    }

    func testParseAddSourceWithName() {
        let url = URL(string: "statusbar://add?url=https://status.openai.com&name=OpenAI")!
        let route = URLRoute.parse(url)
        XCTAssertEqual(route, .addSource(url: "https://status.openai.com", name: "OpenAI"))
    }

    func testParseRemoveSource() {
        let url = URL(string: "statusbar://remove?name=GitHub")!
        XCTAssertEqual(URLRoute.parse(url), .removeSource(name: "GitHub"))
    }

    func testParseSettings() {
        let url = URL(string: "statusbar://settings")!
        XCTAssertEqual(URLRoute.parse(url), .settings)
    }

    func testParseSettingsWithTab() {
        let url = URL(string: "statusbar://settings?tab=webhooks")!
        XCTAssertEqual(URLRoute.parse(url), .settingsTab("webhooks"))
    }

    // MARK: - Invalid Routes

    func testParseWrongScheme() {
        let url = URL(string: "https://open")!
        XCTAssertNil(URLRoute.parse(url))
    }

    func testParseUnknownRoute() {
        let url = URL(string: "statusbar://unknown")!
        XCTAssertNil(URLRoute.parse(url))
    }

    func testParseAddMissingURL() {
        let url = URL(string: "statusbar://add")!
        XCTAssertNil(URLRoute.parse(url))
    }

    func testParseAddEmptyURL() {
        let url = URL(string: "statusbar://add?url=")!
        XCTAssertNil(URLRoute.parse(url))
    }

    func testParseAddInvalidURL() {
        let url = URL(string: "statusbar://add?url=not-a-url")!
        XCTAssertNil(URLRoute.parse(url))
    }

    func testParseRemoveMissingName() {
        let url = URL(string: "statusbar://remove")!
        XCTAssertNil(URLRoute.parse(url))
    }

    func testParseRemoveEmptyName() {
        let url = URL(string: "statusbar://remove?name=")!
        XCTAssertNil(URLRoute.parse(url))
    }

    func testParseOpenEmptySourceFallsToOpen() {
        let url = URL(string: "statusbar://open?source=")!
        XCTAssertEqual(URLRoute.parse(url), .open)
    }

    func testParseSettingsEmptyTabFallsToSettings() {
        let url = URL(string: "statusbar://settings?tab=")!
        XCTAssertEqual(URLRoute.parse(url), .settings)
    }

    // MARK: - Name Derivation

    func testDeriveNameFromGitHubStatus() {
        let name = URLRoute.deriveSourceName(from: "https://www.githubstatus.com")
        XCTAssertEqual(name, "Github")
    }

    func testDeriveNameFromStatusSubdomain() {
        let name = URLRoute.deriveSourceName(from: "https://status.openai.com")
        XCTAssertEqual(name, "Openai")
    }

    func testDeriveNameFromStatusDotIO() {
        let name = URLRoute.deriveSourceName(from: "https://status.figma.com")
        XCTAssertEqual(name, "Figma")
    }

    func testDeriveNameFromPlainDomain() {
        let name = URLRoute.deriveSourceName(from: "https://example.com")
        XCTAssertEqual(name, "Example")
    }

    func testDeriveNameFromInvalidURL() {
        let name = URLRoute.deriveSourceName(from: "not-a-url")
        XCTAssertEqual(name, "not-a-url")
    }

    func testDeriveNameCapitalizes() {
        let name = URLRoute.deriveSourceName(from: "https://status.stripe.com")
        XCTAssertTrue(name.first?.isUppercase == true)
    }
}
