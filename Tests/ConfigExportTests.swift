import Foundation
import XCTest

// MARK: - ConfigExportTests

final class ConfigExportTests: XCTestCase {

    // MARK: - StatusBarConfig

    func testStatusBarConfigEncodeDecodeRoundTrip() {
        let settings = ConfigSettings(
            refreshInterval: 120, notificationsEnabled: false,
            defaultAlertLevel: "Critical Only", autoCheckForUpdates: true
        )
        let sources = [
            StatusSource(name: "A", baseURL: "https://a.com", alertLevel: .all, group: nil, sortOrder: 0),
            StatusSource(name: "B", baseURL: "https://b.com", alertLevel: .critical, group: "Infra", sortOrder: 1),
        ]
        let webhooks = [
            WebhookConfig(url: "https://hooks.slack.com/test", enabled: true, platform: .slack),
            WebhookConfig(url: "https://discord.com/webhook", enabled: false, platform: .discord),
        ]
        let config = StatusBarConfig(settings: settings, sources: sources, webhooks: webhooks)

        let data = StatusBarConfig.encode(config)
        XCTAssertNotNil(data)
        let decoded = StatusBarConfig.decode(from: data!)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.version, StatusBarConfig.currentVersion)
        XCTAssertFalse(decoded!.exportedAt.isEmpty)
        XCTAssertEqual(decoded!.settings, settings)
        XCTAssertEqual(decoded!.sources.count, 2)
        XCTAssertEqual(decoded!.sources[0].name, "A")
        XCTAssertEqual(decoded!.sources[1].name, "B")
        XCTAssertEqual(decoded!.sources[1].alertLevel, .critical)
        XCTAssertEqual(decoded!.sources[1].group, "Infra")
        XCTAssertEqual(decoded!.webhooks.count, 2)
        XCTAssertEqual(decoded!.webhooks[0].platform, .slack)
        XCTAssertTrue(decoded!.webhooks[0].enabled)
        XCTAssertFalse(decoded!.webhooks[1].enabled)
    }

    func testStatusBarConfigVersion() {
        let config = StatusBarConfig(settings: ConfigSettings(), sources: [], webhooks: [])
        XCTAssertEqual(config.version, 1)
        let data = StatusBarConfig.encode(config)!
        let decoded = StatusBarConfig.decode(from: data)!
        XCTAssertEqual(decoded.version, 1)
    }

    func testStatusBarConfigExportedAtIsISO8601() {
        let config = StatusBarConfig(settings: ConfigSettings(), sources: [], webhooks: [])
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: config.exportedAt)
        XCTAssertNotNil(date, "exportedAt should be valid ISO8601: \(config.exportedAt)")
    }

    func testStatusBarConfigPrettyPrinted() {
        let config = StatusBarConfig(settings: ConfigSettings(), sources: [], webhooks: [])
        let data = StatusBarConfig.encode(config)
        XCTAssertNotNil(data)
        let json = String(data: data!, encoding: .utf8)!
        XCTAssertTrue(json.contains("\n"))
        XCTAssertTrue(json.contains("  "))
    }

    func testStatusBarConfigDecodeInvalidData() {
        let invalid = "not json at all".data(using: .utf8)!
        XCTAssertNil(StatusBarConfig.decode(from: invalid))

        let emptyJSON = "{}".data(using: .utf8)!
        XCTAssertNil(StatusBarConfig.decode(from: emptyJSON))
    }

    func testStatusBarConfigDecodeEmptyArrays() {
        let config = StatusBarConfig(settings: ConfigSettings(), sources: [], webhooks: [])
        let data = StatusBarConfig.encode(config)!
        let decoded = StatusBarConfig.decode(from: data)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.sources.count, 0)
        XCTAssertEqual(decoded!.webhooks.count, 0)
    }

    func testStatusBarConfigWithSources() {
        let json = """
            {
                "version": 1,
                "exportedAt": "2026-01-01T00:00:00Z",
                "settings": {
                    "refreshInterval": 60,
                    "notificationsEnabled": true,
                    "defaultAlertLevel": "All Changes",
                    "autoCheckForUpdates": false
                },
                "sources": [
                    {
                        "id": "12345678-1234-1234-1234-123456789012",
                        "name": "GitHub",
                        "baseURL": "https://www.githubstatus.com",
                        "alertLevel": "All Changes",
                        "sortOrder": 0
                    }
                ],
                "webhooks": []
            }
            """.data(using: .utf8)!
        let decoded = StatusBarConfig.decode(from: json)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.settings.refreshInterval, 60)
        XCTAssertFalse(decoded!.settings.autoCheckForUpdates)
        XCTAssertEqual(decoded!.sources.count, 1)
        XCTAssertEqual(decoded!.sources[0].name, "GitHub")
    }

    // MARK: - ConfigSettings

    func testConfigSettingsDefaults() {
        let settings = ConfigSettings()
        XCTAssertEqual(settings.refreshInterval, 300)
        XCTAssertTrue(settings.notificationsEnabled)
        XCTAssertEqual(settings.defaultAlertLevel, "All Changes")
        XCTAssertTrue(settings.autoCheckForUpdates)
    }

    func testConfigSettingsEquatable() {
        let a = ConfigSettings(
            refreshInterval: 60, notificationsEnabled: false,
            defaultAlertLevel: "Critical Only", autoCheckForUpdates: false
        )
        let b = ConfigSettings(
            refreshInterval: 60, notificationsEnabled: false,
            defaultAlertLevel: "Critical Only", autoCheckForUpdates: false
        )
        let c = ConfigSettings(
            refreshInterval: 120, notificationsEnabled: false,
            defaultAlertLevel: "Critical Only", autoCheckForUpdates: false
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testConfigSettingsCodableRoundTrip() throws {
        let settings = ConfigSettings(
            refreshInterval: 60, notificationsEnabled: false,
            defaultAlertLevel: "Critical Only", autoCheckForUpdates: false
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ConfigSettings.self, from: data)
        XCTAssertEqual(settings, decoded)
    }
}
