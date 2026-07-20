// WebhooksSettingsTab.swift
// Webhook configuration UI with add, toggle, test, and delete actions.

import SwiftUI

struct WebhooksSettingsTab: View {
    @ObservedObject private var webhookManager = WebhookManager.shared
    @State private var showingAddWebhook = false
    @State private var newWebhookURL = ""
    @State private var newWebhookLabel = ""
    @State private var newWebhookPlatform: WebhookPlatform = .generic
    @FocusState private var isWebhookURLFocused: Bool
    @State private var sendingTestIDs: Set<UUID> = []
    @State private var testResults: [UUID: String?] = [:]

    var body: some View {
        Form {
            Section {
                if showingAddWebhook {
                    TextField("Webhook URL", text: $newWebhookURL)
                        .textFieldStyle(.roundedBorder)
                        .focused($isWebhookURLFocused)

                    TextField("Label (optional, e.g. \u{201C}Ops channel\u{201D})", text: $newWebhookLabel)
                        .textFieldStyle(.roundedBorder)

                    Picker("Platform", selection: $newWebhookPlatform) {
                        ForEach(WebhookPlatform.allCases, id: \.rawValue) { platform in
                            Text(platform.rawValue.capitalized).tag(platform)
                        }
                    }

                    HStack {
                        Button("Cancel", role: .cancel) {
                            showingAddWebhook = false
                            newWebhookURL = ""
                            newWebhookLabel = ""
                            newWebhookPlatform = .generic
                        }

                        Spacer()

                        Button("Add Webhook") {
                            let url = newWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !url.isEmpty, URL(string: url) != nil else { return }
                            let label = newWebhookLabel.trimmingCharacters(in: .whitespaces)
                            let config = WebhookConfig(
                                url: url, platform: newWebhookPlatform,
                                label: label.isEmpty ? nil : label
                            )
                            webhookManager.addConfig(config)
                            showingAddWebhook = false
                            newWebhookURL = ""
                            newWebhookLabel = ""
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
                HStack(spacing: 6) {
                    Text(config.displayName)
                        .font(.body.weight(.medium))
                    if config.label != nil {
                        Text(config.platform.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(config.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let result = testResults[config.id], let error = result {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            if sendingTestIDs.contains(config.id) {
                ProgressView()
                    .controlSize(.small)
            } else if let result = testResults[config.id] {
                Image(systemName: result == nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result == nil ? .green : .red)
                    .help(result ?? "Delivered")
                    .accessibilityLabel(result.map { "Test failed: \($0)" } ?? "Test delivered")
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
            let error = await webhookManager.sendTest(config: config)
            sendingTestIDs.remove(config.id)
            testResults[config.id] = error
            // Successful results clear quickly; failures stay visible until retried
            if error == nil {
                try? await Task.sleep(for: .seconds(3))
                if testResults[config.id] == nil || testResults[config.id]! == nil {
                    testResults.removeValue(forKey: config.id)
                }
            }
        }
    }
}
