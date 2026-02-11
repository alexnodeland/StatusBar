import Foundation
import XCTest

// MARK: - WebhookManagerTests

final class WebhookManagerTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeEvent(
        source: String = "GitHub",
        title: String = "GitHub \u{2014} Status Degraded",
        body: String = "Partial System Outage",
        severity: String = "major",
        event: String = "degraded",
        url: String = "https://www.githubstatus.com",
        timestamp: String = "2025-06-15T12:34:56Z",
        components: [String] = ["API Requests", "Git Operations"]
    ) -> WebhookEvent {
        WebhookEvent(
            source: source, title: title, body: body,
            severity: severity, event: event, url: url,
            timestamp: timestamp, components: components
        )
    }

    // MARK: - Payload: Slack (Block Kit)

    func testSlackPayloadStructure() {
        let event = makeEvent()
        let payload = WebhookManager.buildPayload(platform: .slack, event: event)

        let attachments = payload["attachments"] as? [[String: Any]]
        XCTAssertEqual(attachments?.count, 1)

        let attachment = attachments?[0]
        XCTAssertEqual(attachment?["color"] as? String, "#E74C3C")

        let blocks = attachment?["blocks"] as? [[String: Any]]
        XCTAssertNotNil(blocks)
        XCTAssertEqual(blocks?.count, 4)  // header, section, components, context
    }

    func testSlackHeaderBlock() {
        let event = makeEvent()
        let payload = WebhookManager.buildPayload(platform: .slack, event: event)
        let blocks = ((payload["attachments"] as? [[String: Any]])?[0]["blocks"] as? [[String: Any]])!

        let header = blocks[0]
        XCTAssertEqual(header["type"] as? String, "header")
        let headerText = header["text"] as? [String: Any]
        XCTAssertEqual(headerText?["text"] as? String, "GitHub")
    }

    func testSlackSectionEmoji() {
        let event = makeEvent()
        let payload = WebhookManager.buildPayload(platform: .slack, event: event)
        let blocks = ((payload["attachments"] as? [[String: Any]])?[0]["blocks"] as? [[String: Any]])!

        let section = blocks[1]
        let sectionText = (section["text"] as? [String: Any])?["text"] as? String
        XCTAssertTrue(sectionText?.contains(":red_circle:") ?? false)
        XCTAssertTrue(sectionText?.contains("Status Degraded") ?? false)
        XCTAssertTrue(sectionText?.contains("Partial System Outage") ?? false)
    }

    func testSlackComponentsBlock() {
        let event = makeEvent()
        let payload = WebhookManager.buildPayload(platform: .slack, event: event)
        let blocks = ((payload["attachments"] as? [[String: Any]])?[0]["blocks"] as? [[String: Any]])!

        let componentsBlock = blocks[2]
        let text = (componentsBlock["text"] as? [String: Any])?["text"] as? String
        XCTAssertTrue(text?.contains("API Requests") ?? false)
        XCTAssertTrue(text?.contains("Git Operations") ?? false)
    }

    func testSlackNoComponentsBlock() {
        let event = makeEvent(components: [])
        let payload = WebhookManager.buildPayload(platform: .slack, event: event)
        let blocks = ((payload["attachments"] as? [[String: Any]])?[0]["blocks"] as? [[String: Any]])!

        // header, section, context (no components block)
        XCTAssertEqual(blocks.count, 3)
    }

    func testSlackContextBlock() {
        let event = makeEvent()
        let payload = WebhookManager.buildPayload(platform: .slack, event: event)
        let blocks = ((payload["attachments"] as? [[String: Any]])?[0]["blocks"] as? [[String: Any]])!

        let context = blocks.last!
        XCTAssertEqual(context["type"] as? String, "context")
        let elements = context["elements"] as? [[String: Any]]
        let text = elements?[0]["text"] as? String
        XCTAssertTrue(text?.contains("2025-06-15T12:34:56Z") ?? false)
        XCTAssertTrue(text?.contains("githubstatus.com") ?? false)
    }

    func testSlackRecoveredColor() {
        let event = makeEvent(severity: "none", event: "recovered")
        let payload = WebhookManager.buildPayload(platform: .slack, event: event)
        let attachment = (payload["attachments"] as? [[String: Any]])?[0]
        XCTAssertEqual(attachment?["color"] as? String, "#2ECC71")
    }

    func testSlackMinorColor() {
        let event = makeEvent(severity: "minor", event: "degraded")
        let payload = WebhookManager.buildPayload(platform: .slack, event: event)
        let attachment = (payload["attachments"] as? [[String: Any]])?[0]
        XCTAssertEqual(attachment?["color"] as? String, "#F39C12")
    }

    // MARK: - Payload: Discord (Embeds)

    func testDiscordEmbedStructure() {
        let event = makeEvent()
        let payload = WebhookManager.buildPayload(platform: .discord, event: event)

        let embeds = payload["embeds"] as? [[String: Any]]
        XCTAssertEqual(embeds?.count, 1)

        let embed = embeds![0]
        XCTAssertEqual(embed["title"] as? String, "GitHub \u{2014} Status Degraded")
        XCTAssertEqual(embed["description"] as? String, "Partial System Outage")
        XCTAssertEqual(embed["color"] as? Int, 0xE74C3C)
        XCTAssertEqual(embed["url"] as? String, "https://www.githubstatus.com")
        XCTAssertEqual(embed["timestamp"] as? String, "2025-06-15T12:34:56Z")
    }

    func testDiscordEmbedFields() {
        let event = makeEvent()
        let payload = WebhookManager.buildPayload(platform: .discord, event: event)
        let embed = (payload["embeds"] as? [[String: Any]])?[0]
        let fields = embed?["fields"] as? [[String: Any]]

        XCTAssertEqual(fields?.count, 3)  // Status, Severity, Affected Components
        XCTAssertEqual(fields?[0]["name"] as? String, "Status")
        XCTAssertTrue((fields?[0]["value"] as? String)?.contains(":red_circle:") ?? false)
        XCTAssertEqual(fields?[1]["name"] as? String, "Severity")
        XCTAssertEqual(fields?[1]["value"] as? String, "major")
        XCTAssertEqual(fields?[2]["name"] as? String, "Affected Components")
        XCTAssertTrue((fields?[2]["value"] as? String)?.contains("API Requests") ?? false)
    }

    func testDiscordNoComponentsField() {
        let event = makeEvent(components: [])
        let payload = WebhookManager.buildPayload(platform: .discord, event: event)
        let embed = (payload["embeds"] as? [[String: Any]])?[0]
        let fields = embed?["fields"] as? [[String: Any]]
        XCTAssertEqual(fields?.count, 2)  // Status, Severity only
    }

    func testDiscordFooter() {
        let event = makeEvent()
        let payload = WebhookManager.buildPayload(platform: .discord, event: event)
        let embed = (payload["embeds"] as? [[String: Any]])?[0]
        let footer = embed?["footer"] as? [String: Any]
        XCTAssertEqual(footer?["text"] as? String, "StatusBar")
    }

    func testDiscordRecoveredColor() {
        let event = makeEvent(severity: "none", event: "recovered")
        let payload = WebhookManager.buildPayload(platform: .discord, event: event)
        let embed = (payload["embeds"] as? [[String: Any]])?[0]
        XCTAssertEqual(embed?["color"] as? Int, 0x2ECC71)
    }

    // MARK: - Payload: Teams (Adaptive Cards)

    func testTeamsAdaptiveCardStructure() {
        let event = makeEvent()
        let payload = WebhookManager.buildPayload(platform: .teams, event: event)

        XCTAssertEqual(payload["type"] as? String, "message")
        let attachments = payload["attachments"] as? [[String: Any]]
        XCTAssertEqual(attachments?.count, 1)
        XCTAssertEqual(attachments?[0]["contentType"] as? String, "application/vnd.microsoft.card.adaptive")

        let card = attachments?[0]["content"] as? [String: Any]
        XCTAssertEqual(card?["type"] as? String, "AdaptiveCard")
        XCTAssertEqual(card?["version"] as? String, "1.4")
    }

    func testTeamsCardBody() {
        let event = makeEvent()
        let payload = WebhookManager.buildPayload(platform: .teams, event: event)
        let card = ((payload["attachments"] as? [[String: Any]])?[0]["content"] as? [String: Any])!
        let body = card["body"] as? [[String: Any]]

        XCTAssertEqual(body?.count, 3)  // title TextBlock, body TextBlock, FactSet

        // Title block
        XCTAssertEqual(body?[0]["type"] as? String, "TextBlock")
        XCTAssertEqual(body?[0]["text"] as? String, "GitHub \u{2014} Status Degraded")
        XCTAssertEqual(body?[0]["color"] as? String, "Attention")

        // Body block
        XCTAssertEqual(body?[1]["text"] as? String, "Partial System Outage")

        // FactSet
        let factSet = body?[2]
        XCTAssertEqual(factSet?["type"] as? String, "FactSet")
        let facts = factSet?["facts"] as? [[String: String]]
        XCTAssertEqual(facts?.count, 5)  // Source, Status, Severity, Time, Affected
        XCTAssertEqual(facts?[0]["title"], "Source")
        XCTAssertEqual(facts?[0]["value"], "GitHub")
    }

    func testTeamsCardActions() {
        let event = makeEvent()
        let payload = WebhookManager.buildPayload(platform: .teams, event: event)
        let card = ((payload["attachments"] as? [[String: Any]])?[0]["content"] as? [String: Any])!
        let actions = card["actions"] as? [[String: Any]]

        XCTAssertEqual(actions?.count, 1)
        XCTAssertEqual(actions?[0]["type"] as? String, "Action.OpenUrl")
        XCTAssertEqual(actions?[0]["title"] as? String, "View Status Page")
        XCTAssertEqual(actions?[0]["url"] as? String, "https://www.githubstatus.com")
    }

    func testTeamsRecoveredColor() {
        let event = makeEvent(severity: "none", event: "recovered")
        let payload = WebhookManager.buildPayload(platform: .teams, event: event)
        let card = ((payload["attachments"] as? [[String: Any]])?[0]["content"] as? [String: Any])!
        let body = card["body"] as? [[String: Any]]
        XCTAssertEqual(body?[0]["color"] as? String, "Good")
    }

    // MARK: - Payload: Generic (Structured JSON)

    func testGenericPayload() {
        let event = makeEvent()
        let payload = WebhookManager.buildPayload(platform: .generic, event: event)

        XCTAssertEqual(payload["source"] as? String, "GitHub")
        XCTAssertEqual(payload["title"] as? String, "GitHub \u{2014} Status Degraded")
        XCTAssertEqual(payload["body"] as? String, "Partial System Outage")
        XCTAssertEqual(payload["severity"] as? String, "major")
        XCTAssertEqual(payload["event"] as? String, "degraded")
        XCTAssertEqual(payload["url"] as? String, "https://www.githubstatus.com")
        XCTAssertEqual(payload["timestamp"] as? String, "2025-06-15T12:34:56Z")
        XCTAssertEqual(payload["components"] as? [String], ["API Requests", "Git Operations"])
        XCTAssertEqual(payload.count, 8)
    }

    func testGenericEmptyComponents() {
        let event = makeEvent(components: [])
        let payload = WebhookManager.buildPayload(platform: .generic, event: event)
        XCTAssertEqual(payload["components"] as? [String], [])
    }

    // MARK: - Severity Color Mapping

    func testCriticalSeverityColors() {
        let event = makeEvent(severity: "critical", event: "degraded")

        let slack = WebhookManager.buildPayload(platform: .slack, event: event)
        let slackColor = ((slack["attachments"] as? [[String: Any]])?[0])?["color"] as? String
        XCTAssertEqual(slackColor, "#E74C3C")

        let discord = WebhookManager.buildPayload(platform: .discord, event: event)
        let discordColor = ((discord["embeds"] as? [[String: Any]])?[0])?["color"] as? Int
        XCTAssertEqual(discordColor, 0xE74C3C)
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
        let event = makeEvent()
        let platforms: [WebhookPlatform] = [.slack, .discord, .teams, .generic]
        for platform in platforms {
            let payload = WebhookManager.buildPayload(platform: platform, event: event)
            let data = try? JSONSerialization.data(withJSONObject: payload)
            XCTAssertNotNil(data, "Payload for \(platform) should serialize to JSON")
        }
    }
}
