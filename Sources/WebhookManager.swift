// WebhookManager.swift
// Outbound webhook delivery for status change notifications.

import SwiftUI

@MainActor
final class WebhookManager: ObservableObject {
    static let shared = WebhookManager()

    @AppStorage("webhookConfigs") private var storedConfigs: String = "[]"
    @Published private(set) var configs: [WebhookConfig] = []

    private init() {
        loadConfigs()
    }

    // MARK: - Config CRUD

    func loadConfigs() {
        guard let data = storedConfigs.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([WebhookConfig].self, from: data)
        else {
            configs = []
            return
        }
        configs = decoded
    }

    func saveConfigs() {
        guard let data = try? JSONEncoder().encode(configs),
            let json = String(data: data, encoding: .utf8)
        else { return }
        storedConfigs = json
    }

    func addConfig(_ config: WebhookConfig) {
        configs.append(config)
        saveConfigs()
    }

    func removeConfig(id: UUID) {
        configs.removeAll { $0.id == id }
        saveConfigs()
    }

    func updateConfig(_ config: WebhookConfig) {
        guard let idx = configs.firstIndex(where: { $0.id == config.id }) else { return }
        configs[idx] = config
        saveConfigs()
    }

    // MARK: - Sending

    func sendAll(event: WebhookEvent) async {
        let enabledConfigs = configs.filter(\.enabled)
        guard !enabledConfigs.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for config in enabledConfigs {
                group.addTask {
                    await self.send(config: config, event: event)
                }
            }
        }
    }

    func sendTest(config: WebhookConfig) async {
        let event = WebhookEvent(
            source: "StatusBar Test",
            title: "StatusBar Test — Status Degraded",
            body: "This is a test notification from StatusBar. If you see this, your webhook is working!",
            severity: "minor",
            event: "degraded",
            url: "https://github.com/alexnodeland/StatusBar",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            components: ["API", "Dashboard"]
        )
        await send(config: config, event: event)
    }

    private func send(config: WebhookConfig, event: WebhookEvent) async {
        guard let url = URL(string: config.url) else { return }
        let payload = Self.buildPayload(platform: config.platform, event: event)
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 10

        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Payload Construction

    nonisolated static func buildPayload(platform: WebhookPlatform, event: WebhookEvent) -> [String: Any] {
        switch platform {
        case .slack:
            return buildSlackPayload(event: event)
        case .discord:
            return buildDiscordPayload(event: event)
        case .teams:
            return buildTeamsPayload(event: event)
        case .generic:
            return buildGenericPayload(event: event)
        }
    }

    // MARK: - Slack (Block Kit)

    nonisolated private static func buildSlackPayload(event: WebhookEvent) -> [String: Any] {
        let emoji = severityEmoji(event.severity, event: event.event)
        let color = severityHexColor(event.severity, event: event.event)
        let label = eventLabel(event.event)

        var blocks: [[String: Any]] = [
            [
                "type": "header",
                "text": ["type": "plain_text", "text": event.source, "emoji": true] as [String: Any],
            ],
            [
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": "\(emoji) *\(label)*\n\(event.body)",
                ] as [String: Any],
            ],
        ]

        if !event.components.isEmpty {
            blocks.append([
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": "*Affected:* \(event.components.joined(separator: ", "))",
                ] as [String: Any],
            ])
        }

        blocks.append([
            "type": "context",
            "elements": [
                [
                    "type": "mrkdwn",
                    "text": "\(event.timestamp) | <\(event.url)|View Status Page>",
                ] as [String: Any]
            ] as [[String: Any]],
        ])

        return [
            "attachments": [
                [
                    "color": color,
                    "blocks": blocks,
                ] as [String: Any]
            ] as [[String: Any]]
        ]
    }

    // MARK: - Discord (Embeds)

    nonisolated private static func buildDiscordPayload(event: WebhookEvent) -> [String: Any] {
        let emoji = severityEmoji(event.severity, event: event.event)
        let color = severityDecimalColor(event.severity, event: event.event)
        let label = eventLabel(event.event)

        var fields: [[String: Any]] = [
            ["name": "Status", "value": "\(emoji) \(label)", "inline": true],
            ["name": "Severity", "value": event.severity, "inline": true],
        ]

        if !event.components.isEmpty {
            fields.append([
                "name": "Affected Components",
                "value": event.components.joined(separator: ", "),
                "inline": false,
            ])
        }

        let embed: [String: Any] = [
            "title": "\(event.source) \u{2014} \(label)",
            "description": event.body,
            "color": color,
            "fields": fields,
            "url": event.url,
            "timestamp": event.timestamp,
            "footer": ["text": "StatusBar"] as [String: Any],
        ]

        return ["embeds": [embed] as [[String: Any]]]
    }

    // MARK: - Teams (Adaptive Cards)

    nonisolated private static func buildTeamsPayload(event: WebhookEvent) -> [String: Any] {
        let color = teamsColor(event.severity, event: event.event)
        let label = eventLabel(event.event)

        var facts: [[String: String]] = [
            ["title": "Source", "value": event.source],
            ["title": "Status", "value": label],
            ["title": "Severity", "value": event.severity],
            ["title": "Time", "value": event.timestamp],
        ]

        if !event.components.isEmpty {
            facts.append(["title": "Affected", "value": event.components.joined(separator: ", ")])
        }

        let card: [String: Any] = [
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            "type": "AdaptiveCard",
            "version": "1.4",
            "body": [
                [
                    "type": "TextBlock",
                    "text": "\(event.source) \u{2014} \(label)",
                    "size": "Large",
                    "weight": "Bolder",
                    "color": color,
                ] as [String: Any],
                [
                    "type": "TextBlock",
                    "text": event.body,
                    "wrap": true,
                    "spacing": "Small",
                ] as [String: Any],
                [
                    "type": "FactSet",
                    "facts": facts,
                ] as [String: Any],
            ] as [[String: Any]],
            "actions": [
                [
                    "type": "Action.OpenUrl",
                    "title": "View Status Page",
                    "url": event.url,
                ] as [String: Any]
            ] as [[String: Any]],
        ]

        return [
            "type": "message",
            "attachments": [
                [
                    "contentType": "application/vnd.microsoft.card.adaptive",
                    "content": card,
                ] as [String: Any]
            ] as [[String: Any]],
        ]
    }

    // MARK: - Generic (Structured JSON)

    nonisolated private static func buildGenericPayload(event: WebhookEvent) -> [String: Any] {
        [
            "source": event.source,
            "title": event.title,
            "body": event.body,
            "severity": event.severity,
            "event": event.event,
            "url": event.url,
            "timestamp": event.timestamp,
            "components": event.components,
        ]
    }

    // MARK: - Helpers

    nonisolated private static func severityEmoji(_ severity: String, event: String) -> String {
        if event == "recovered" { return ":large_green_circle:" }
        switch severity {
        case "critical", "major": return ":red_circle:"
        case "minor": return ":large_yellow_circle:"
        default: return ":white_circle:"
        }
    }

    nonisolated private static func severityHexColor(_ severity: String, event: String) -> String {
        if event == "recovered" { return "#2ECC71" }
        switch severity {
        case "critical", "major": return "#E74C3C"
        case "minor": return "#F39C12"
        default: return "#95A5A6"
        }
    }

    nonisolated private static func severityDecimalColor(_ severity: String, event: String) -> Int {
        if event == "recovered" { return 0x2ECC71 }
        switch severity {
        case "critical", "major": return 0xE74C3C
        case "minor": return 0xF39C12
        default: return 0x95A5A6
        }
    }

    nonisolated private static func eventLabel(_ event: String) -> String {
        switch event {
        case "degraded": return "Status Degraded"
        case "recovered": return "Recovered"
        case "incident": return "Active Incident"
        default: return "Status Update"
        }
    }

    nonisolated private static func teamsColor(_ severity: String, event: String) -> String {
        if event == "recovered" { return "Good" }
        switch severity {
        case "critical", "major": return "Attention"
        case "minor": return "Warning"
        default: return "Default"
        }
    }
}
