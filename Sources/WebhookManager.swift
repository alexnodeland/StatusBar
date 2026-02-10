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

    func sendAll(source: String, title: String, body: String) async {
        let enabledConfigs = configs.filter(\.enabled)
        guard !enabledConfigs.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for config in enabledConfigs {
                group.addTask {
                    await self.send(config: config, source: source, title: title, body: body)
                }
            }
        }
    }

    private func send(config: WebhookConfig, source: String, title: String, body: String) async {
        guard let url = URL(string: config.url) else { return }
        let payload = Self.buildPayload(platform: config.platform, source: source, title: title, body: body)
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 10

        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Payload Construction

    nonisolated static func buildPayload(platform: WebhookPlatform, source: String, title: String, body: String) -> [String: Any] {
        switch platform {
        case .slack:
            return ["text": "\(title)\n\(body)"]
        case .discord:
            return ["content": "\(title)\n\(body)"]
        case .teams:
            return [
                "@type": "MessageCard",
                "@context": "https://schema.org/extensions",
                "summary": title,
                "sections": [
                    [
                        "activityTitle": title,
                        "activitySubtitle": body,
                    ] as [String: Any]
                ],
            ]
        case .generic:
            return [
                "source": source,
                "title": title,
                "body": body,
            ]
        }
    }
}
