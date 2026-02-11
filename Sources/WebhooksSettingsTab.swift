// WebhooksSettingsTab.swift
// Webhook configuration UI with add, toggle, test, and delete actions.

import SwiftUI

struct WebhooksSettingsTab: View {
    @ObservedObject private var webhookManager = WebhookManager.shared
    @State private var showingAddWebhook = false
    @State private var newWebhookURL = ""
    @State private var newWebhookPlatform: WebhookPlatform = .generic
    @FocusState private var isWebhookURLFocused: Bool
    @State private var sendingTestIDs: Set<UUID> = []
    @State private var testSentIDs: Set<UUID> = []

    var body: some View {
        Form {
            Section {
                if showingAddWebhook {
                    TextField("Webhook URL", text: $newWebhookURL)
                        .textFieldStyle(.roundedBorder)
                        .focused($isWebhookURLFocused)

                    Picker("Platform", selection: $newWebhookPlatform) {
                        ForEach(WebhookPlatform.allCases, id: \.rawValue) { platform in
                            Text(platform.rawValue.capitalized).tag(platform)
                        }
                    }

                    HStack {
                        Button("Cancel", role: .cancel) {
                            showingAddWebhook = false
                            newWebhookURL = ""
                            newWebhookPlatform = .generic
                        }

                        Spacer()

                        Button("Add Webhook") {
                            let url = newWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !url.isEmpty, URL(string: url) != nil else { return }
                            let config = WebhookConfig(url: url, platform: newWebhookPlatform)
                            webhookManager.addConfig(config)
                            showingAddWebhook = false
                            newWebhookURL = ""
                            newWebhookPlatform = .generic
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            newWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || URL(string: newWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                    }
                } else {
                    Button {
                        showingAddWebhook = true
                        newWebhookURL = ""
                        newWebhookPlatform = .generic
                    } label: {
                        Label("Add Webhook", systemImage: "plus")
                    }
                    .accessibilityLabel("Add new webhook")
                }
            } header: {
                Text("Configured Webhooks")
            }

            if !webhookManager.configs.isEmpty {
                Section {
                    ForEach(webhookManager.configs) { config in
                        webhookRow(config)
                    }
                }
            } else if !showingAddWebhook {
                Section {
                    Text("No webhooks configured. Add one to receive notifications on Slack, Discord, Teams, or a custom endpoint.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: showingAddWebhook) {
            if showingAddWebhook {
                isWebhookURLFocused = true
            }
        }
    }

    private func webhookRow(_ config: WebhookConfig) -> some View {
        HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { config.enabled },
                    set: { newValue in
                        var updated = config
                        updated.enabled = newValue
                        webhookManager.updateConfig(updated)
                    }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(config.platform.rawValue.capitalized)
                    .font(.body.weight(.medium))
                Text(config.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if sendingTestIDs.contains(config.id) {
                ProgressView()
                    .controlSize(.small)
            } else if testSentIDs.contains(config.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    sendTestWebhook(config)
                } label: {
                    Image(systemName: "paperplane")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Send test event")
                .accessibilityLabel("Send test event to \(config.platform.rawValue) webhook")
            }

            Button {
                webhookManager.removeConfig(id: config.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove webhook")
            .accessibilityLabel("Remove \(config.platform.rawValue) webhook")
        }
    }

    private func sendTestWebhook(_ config: WebhookConfig) {
        sendingTestIDs.insert(config.id)
        Task {
            await webhookManager.sendTest(config: config)
            sendingTestIDs.remove(config.id)
            testSentIDs.insert(config.id)
            try? await Task.sleep(for: .seconds(2))
            testSentIDs.remove(config.id)
        }
    }
}
