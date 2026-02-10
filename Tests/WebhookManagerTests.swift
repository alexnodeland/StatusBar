import Foundation
import XCTest

// MARK: - WebhookManagerTests

final class WebhookManagerTests: XCTestCase {

    // MARK: - Payload: Slack

    func testSlackPayload() {
        let payload = WebhookManager.buildPayload(
            platform: .slack,
            source: "GitHub",
            title: "GitHub \u{2014} Status Degraded",
            body: "Minor Service Outage"
        )
        let text = payload["text"] as? String
        XCTAssertEqual(text, "GitHub \u{2014} Status Degraded\nMinor Service Outage")
        // Slack payload should only have "text" key
        XCTAssertEqual(payload.count, 1)
    }

    // MARK: - Payload: Discord

    func testDiscordPayload() {
        let payload = WebhookManager.buildPayload(
            platform: .discord,
            source: "Cloudflare",
            title: "Cloudflare \u{2014} Recovered",
            body: "All systems operational"
        )
        let content = payload["content"] as? String
        XCTAssertEqual(content, "Cloudflare \u{2014} Recovered\nAll systems operational")
        XCTAssertEqual(payload.count, 1)
    }

    // MARK: - Payload: Teams

    func testTeamsPayload() {
        let payload = WebhookManager.buildPayload(
            platform: .teams,
            source: "AWS",
            title: "AWS \u{2014} Active Incident",
            body: "Elevated error rates"
        )
        XCTAssertEqual(payload["@type"] as? String, "MessageCard")
        XCTAssertEqual(payload["@context"] as? String, "https://schema.org/extensions")
        XCTAssertEqual(payload["summary"] as? String, "AWS \u{2014} Active Incident")

        let sections = payload["sections"] as? [[String: Any]]
        XCTAssertEqual(sections?.count, 1)
        XCTAssertEqual(sections?[0]["activityTitle"] as? String, "AWS \u{2014} Active Incident")
        XCTAssertEqual(sections?[0]["activitySubtitle"] as? String, "Elevated error rates")
    }

    // MARK: - Payload: Generic

    func testGenericPayload() {
        let payload = WebhookManager.buildPayload(
            platform: .generic,
            source: "Stripe",
            title: "Stripe \u{2014} Status Degraded",
            body: "Payment processing delayed"
        )
        XCTAssertEqual(payload["source"] as? String, "Stripe")
        XCTAssertEqual(payload["title"] as? String, "Stripe \u{2014} Status Degraded")
        XCTAssertEqual(payload["body"] as? String, "Payment processing delayed")
        XCTAssertEqual(payload.count, 3)
    }

    // MARK: - Config CRUD

    @MainActor
    func testAddAndRemoveConfig() {
        let manager = WebhookManager.shared
        let original = manager.configs
        let config = WebhookConfig(url: "https://hooks.example.com/test", platform: .slack)

        manager.addConfig(config)
        XCTAssertTrue(manager.configs.contains(where: { $0.id == config.id }))

        manager.removeConfig(id: config.id)
        XCTAssertFalse(manager.configs.contains(where: { $0.id == config.id }))

        // Restore original state
        for c in manager.configs where !original.contains(where: { $0.id == c.id }) {
            manager.removeConfig(id: c.id)
        }
    }

    @MainActor
    func testUpdateConfig() {
        let manager = WebhookManager.shared
        let config = WebhookConfig(url: "https://hooks.example.com/original", platform: .discord)
        manager.addConfig(config)

        var updated = config
        updated.url = "https://hooks.example.com/updated"
        updated.enabled = false
        manager.updateConfig(updated)

        let found = manager.configs.first(where: { $0.id == config.id })
        XCTAssertEqual(found?.url, "https://hooks.example.com/updated")
        XCTAssertEqual(found?.enabled, false)

        // Cleanup
        manager.removeConfig(id: config.id)
    }

    // MARK: - Codable Round-Trip

    func testWebhookConfigCodableRoundTrip() throws {
        let configs = [
            WebhookConfig(url: "https://hooks.slack.com/a", platform: .slack),
            WebhookConfig(url: "https://discord.com/api/webhooks/b", enabled: false, platform: .discord),
            WebhookConfig(url: "https://outlook.office.com/webhook/c", platform: .teams),
            WebhookConfig(url: "https://example.com/webhook", platform: .generic),
        ]
        let data = try JSONEncoder().encode(configs)
        let decoded = try JSONDecoder().decode([WebhookConfig].self, from: data)

        XCTAssertEqual(decoded.count, 4)
        for i in 0..<configs.count {
            XCTAssertEqual(decoded[i].id, configs[i].id)
            XCTAssertEqual(decoded[i].url, configs[i].url)
            XCTAssertEqual(decoded[i].enabled, configs[i].enabled)
            XCTAssertEqual(decoded[i].platform, configs[i].platform)
        }
    }

    // MARK: - Payload Serialization

    func testPayloadsSerializeToValidJSON() {
        let platforms: [WebhookPlatform] = [.slack, .discord, .teams, .generic]
        for platform in platforms {
            let payload = WebhookManager.buildPayload(
                platform: platform,
                source: "Test",
                title: "Title",
                body: "Body"
            )
            let data = try? JSONSerialization.data(withJSONObject: payload)
            XCTAssertNotNil(data, "Payload for \(platform) should serialize to JSON")
        }
    }
}
