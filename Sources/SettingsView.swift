// SettingsView.swift
// App settings: preferences, webhooks, and update checking.

import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var service: StatusService
    @ObservedObject var updateChecker: UpdateChecker
    let onBack: () -> Void
    @State private var launchAtLogin = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @ObservedObject private var webhookManager = WebhookManager.shared
    @State private var showingAddWebhook = false
    @State private var newWebhookURL = ""
    @State private var newWebhookPlatform: WebhookPlatform = .generic

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader
            Divider().opacity(0.5)
            importExportRow
            Divider().opacity(0.5)

            HStack {
                Text("Refresh interval")
                    .font(Design.Typography.caption)
                Spacer()
                Picker("", selection: $service.refreshInterval) {
                    ForEach(kRefreshIntervalOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: service.refreshInterval) {
                    service.startTimer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.5)

            Toggle(isOn: $launchAtLogin) {
                Text("Launch at login")
                    .font(Design.Typography.caption)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onChange(of: launchAtLogin) {
                do {
                    if launchAtLogin {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin.toggle()
                }
            }

            Divider().opacity(0.5)

            Toggle(isOn: $notificationsEnabled) {
                Text("Notifications")
                    .font(Design.Typography.caption)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.5)
            webhooksSection
            Divider().opacity(0.5)
            hotkeySection
            Spacer()
            Divider().opacity(0.5)
            updateSection
            Divider().opacity(0.5)
            settingsFooter
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var importExportRow: some View {
        HStack(spacing: 12) {
            Button {
                importSources()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .font(Design.Typography.caption)
            }
            .buttonStyle(.borderless)
            .help("Import sources from TSV file")
            .accessibilityLabel("Import sources from file")

            Button {
                exportSources()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(Design.Typography.caption)
            }
            .buttonStyle(.borderless)
            .help("Export sources as TSV file")
            .accessibilityLabel("Export sources to file")

            Spacer()

            Text("Import / Export Sources")
                .font(Design.Typography.micro)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func exportSources() {
        let panel = NSSavePanel()
        panel.title = "Export Status Pages"
        panel.nameFieldStringValue = "status-pages.tsv"
        panel.allowedContentTypes = [.tabSeparatedText]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            let tsv = service.exportSourcesTSV()
            try? tsv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func importSources() {
        let panel = NSOpenPanel()
        panel.title = "Import Status Pages"
        panel.allowedContentTypes = [.tabSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            if let tsv = try? String(contentsOf: url, encoding: .utf8) {
                service.importSourcesTSV(tsv)
            }
        }
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    if let url = URL(string: "https://github.com/\(kGitHubRepo)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    if let img = NSImage(contentsOfFile: Bundle.main.path(forResource: "github", ofType: "png") ?? "") {
                        Image(
                            nsImage: {
                                img.isTemplate = true
                                return img
                            }()
                        )
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                    }
                }
                .buttonStyle(.borderless)
                .help("View on GitHub")

                Text("Version")
                    .font(Design.Typography.caption)
                Text(updateChecker.currentVersion)
                    .font(Design.Typography.mono)
                    .foregroundStyle(.secondary)

                if updateChecker.isUpdateAvailable {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption2)
                    Text("Update available")
                        .font(Design.Typography.micro)
                        .foregroundStyle(Color.accentColor)
                } else if updateChecker.lastCheckDate != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                    Text("Up to date")
                        .font(Design.Typography.micro)
                        .foregroundStyle(.green)
                }

                Button {
                    Task { await updateChecker.checkForUpdates() }
                } label: {
                    if updateChecker.isChecking {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(updateChecker.isChecking)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            HStack(spacing: 12) {
                Toggle(isOn: $updateChecker.autoCheckEnabled) {
                    Text("Check automatically")
                        .font(Design.Typography.micro)
                }
                .toggleStyle(.checkbox)
                .onChange(of: updateChecker.autoCheckEnabled) {
                    if updateChecker.autoCheckEnabled {
                        updateChecker.startNightlyTimer()
                    } else {
                        updateChecker.stopNightlyTimer()
                        updateChecker.autoUpdateEnabled = false
                    }
                }
                .help("Check for Updates")

                Toggle(isOn: $updateChecker.autoUpdateEnabled) {
                    Text("Update automatically")
                        .font(Design.Typography.micro)
                }
                .toggleStyle(.checkbox)
                .onChange(of: updateChecker.autoUpdateEnabled) {
                    if updateChecker.autoUpdateEnabled {
                        updateChecker.autoCheckEnabled = true
                        updateChecker.startNightlyTimer()
                    }
                }
                .help("Download and install updates automatically")

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if updateChecker.isUpdateAvailable, let latest = updateChecker.latestVersion {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Version \(latest) available")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    if updateChecker.isAutoUpdating {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                        Text("Updating…")
                            .font(Design.Typography.micro)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Download") {
                            updateChecker.openDownload()
                        }
                        .font(Design.Typography.caption)
                        .buttonStyle(GlassButtonStyle())
                    }
                }
                .padding(8)
                .padding(.horizontal, 4)
                .background(
                    Color.accentColor.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if let error = updateChecker.lastCheckError {
                Text(error)
                    .font(Design.Typography.micro)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(Design.Typography.body)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Back (Esc)")
            .accessibilityLabel("Back to source list")

            Image(systemName: "gear")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
            Text("Settings")
                .font(Design.Typography.bodyMedium)
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Webhooks

    private var webhooksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Webhooks")
                    .font(Design.Typography.captionSemibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(Design.Timing.expand) {
                        showingAddWebhook.toggle()
                        newWebhookURL = ""
                        newWebhookPlatform = .generic
                    }
                } label: {
                    Image(systemName: showingAddWebhook ? "xmark.circle.fill" : "plus.circle.fill")
                        .font(Design.Typography.body)
                        .foregroundStyle(showingAddWebhook ? .secondary : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .help(showingAddWebhook ? "Cancel" : "Add webhook")
                .accessibilityLabel(showingAddWebhook ? "Cancel adding webhook" : "Add new webhook")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if showingAddWebhook {
                addWebhookForm
            }

            let configs = webhookManager.configs
            if configs.isEmpty {
                Text("No webhooks configured")
                    .font(Design.Typography.micro)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            } else {
                VStack(spacing: 2) {
                    ForEach(configs) { config in
                        webhookRow(config)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
    }

    private var addWebhookForm: some View {
        VStack(spacing: 6) {
            TextField("Webhook URL", text: $newWebhookURL)
                .font(Design.Typography.caption)
                .textFieldStyle(.roundedBorder)

            HStack {
                Picker("Platform", selection: $newWebhookPlatform) {
                    ForEach(WebhookPlatform.allCases, id: \.rawValue) { platform in
                        Text(platform.rawValue.capitalized).tag(platform)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .font(Design.Typography.caption)

                Spacer()

                Button("Add") {
                    let url = newWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !url.isEmpty, URL(string: url) != nil else { return }
                    let config = WebhookConfig(url: url, platform: newWebhookPlatform)
                    webhookManager.addConfig(config)
                    withAnimation(Design.Timing.expand) {
                        showingAddWebhook = false
                        newWebhookURL = ""
                        newWebhookPlatform = .generic
                    }
                }
                .font(Design.Typography.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || URL(string: newWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func webhookRow(_ config: WebhookConfig) -> some View {
        HStack(spacing: 8) {
            Button {
                webhookManager.removeConfig(id: config.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .font(Design.Typography.body)
            }
            .buttonStyle(.borderless)
            .help("Remove webhook")
            .accessibilityLabel("Remove webhook")

            Toggle("", isOn: Binding(
                get: { config.enabled },
                set: { newValue in
                    var updated = config
                    updated.enabled = newValue
                    webhookManager.updateConfig(updated)
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                Text(config.platform.rawValue.capitalized)
                    .font(Design.Typography.captionMedium)
                Text(config.url)
                    .font(Design.Typography.micro)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .hoverHighlight()
    }

    // MARK: - Global Hotkey

    private var hotkeyDisplayString: String { "\u{2303}\u{2325}S" }

    private var hotkeySection: some View {
        HStack {
            Text("Global Hotkey")
                .font(Design.Typography.caption)
            Spacer()
            Text(hotkeyDisplayString)
                .font(Design.Typography.mono)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Global hotkey: \(hotkeyDisplayString)")
    }

    private var settingsFooter: some View {
        HStack {
            Button("Reset to Defaults") {
                service.resetToDefaults()
            }
            .font(Design.Typography.caption)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(Design.Typography.micro)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .help("Quit StatusBar")
            .accessibilityLabel("Quit StatusBar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
