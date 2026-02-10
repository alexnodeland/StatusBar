// SettingsWindow.swift
// Native macOS settings window with sidebar navigation.

import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings Window Controller

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func open(service: StatusService, updateChecker: UpdateChecker) {
        if let window {
            show(window)
            return
        }

        let content = SettingsWindowContent(service: service, updateChecker: updateChecker)
        let hostingView = NSHostingView(rootView: content)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "StatusBar Settings"
        w.contentView = hostingView
        w.isReleasedWhenClosed = false
        w.center()

        self.window = w
        show(w)
    }

    private func show(_ window: NSWindow) {
        // LSUIElement apps need accessory policy to show windows
        NSApp.setActivationPolicy(.accessory)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case notifications = "Notifications"
    case webhooks = "Webhooks"
    case data = "Data"
    case updates = "Updates"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gear"
        case .notifications: "bell.badge"
        case .webhooks: "antenna.radiowaves.left.and.right"
        case .data: "square.and.arrow.up.on.square"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Settings Window Content

struct SettingsWindowContent: View {
    @ObservedObject var service: StatusService
    @ObservedObject var updateChecker: UpdateChecker
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 200)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsTab(service: service)
                case .notifications:
                    NotificationsSettingsTab(service: service)
                case .webhooks:
                    WebhooksSettingsTab()
                case .data:
                    DataSettingsTab(service: service)
                case .updates:
                    UpdatesSettingsTab(updateChecker: updateChecker)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .frame(minWidth: 520, minHeight: 360)
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @ObservedObject var service: StatusService
    @State private var launchAtLogin = false

    private var hotkeyDisplayString: String { "\u{2303}\u{2325}S" }

    var body: some View {
        Form {
            Section("Preferences") {
                Picker("Refresh interval", selection: $service.refreshInterval) {
                    ForEach(kRefreshIntervalOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .onChange(of: service.refreshInterval) {
                    service.startTimer()
                }

                Toggle("Launch at login", isOn: $launchAtLogin)
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
            }

            Section("Keyboard") {
                LabeledContent("Global Hotkey") {
                    Text(hotkeyDisplayString)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Global hotkey: \(hotkeyDisplayString)")
            }

            Section {
                Button("Reset to Defaults", role: .destructive) {
                    service.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Notifications Settings Tab

struct NotificationsSettingsTab: View {
    @ObservedObject var service: StatusService
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("defaultAlertLevel") private var defaultAlertLevel: String = AlertLevel.all.rawValue

    var body: some View {
        Form {
            Section {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
            }

            Section("Default Level") {
                Picker("New sources notify at", selection: $defaultAlertLevel) {
                    ForEach(AlertLevel.allCases, id: \.rawValue) { level in
                        Text(level.rawValue).tag(level.rawValue)
                    }
                }
                .disabled(!notificationsEnabled)
            }

            Section("Per-Source Levels") {
                if service.sources.isEmpty {
                    Text("No sources configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.sources) { source in
                        Picker(
                            source.name,
                            selection: Binding(
                                get: { source.alertLevel },
                                set: { newLevel in
                                    service.updateAlertLevel(sourceID: source.id, level: newLevel)
                                }
                            )
                        ) {
                            ForEach(AlertLevel.allCases, id: \.self) { level in
                                Text(level.rawValue).tag(level)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Webhooks Settings Tab

struct WebhooksSettingsTab: View {
    @ObservedObject private var webhookManager = WebhookManager.shared
    @State private var showingAddWebhook = false
    @State private var newWebhookURL = ""
    @State private var newWebhookPlatform: WebhookPlatform = .generic
    @FocusState private var isWebhookURLFocused: Bool

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
}

// MARK: - Data Settings Tab

struct DataSettingsTab: View {
    @ObservedObject var service: StatusService

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import or export your monitored status pages as a TSV file for backup or sharing between machines.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } header: {
                Text("Import / Export Sources")
            }

            Section {
                Button {
                    importSources()
                } label: {
                    Label("Import from File\u{2026}", systemImage: "square.and.arrow.down")
                }
                .help("Import sources from TSV file")
                .accessibilityLabel("Import sources from file")

                Button {
                    exportSources()
                } label: {
                    Label("Export to File\u{2026}", systemImage: "square.and.arrow.up")
                }
                .help("Export sources as TSV file")
                .accessibilityLabel("Export sources to file")
            }
        }
        .formStyle(.grouped)
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
}

// MARK: - Updates Settings Tab

struct UpdatesSettingsTab: View {
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Version") {
                    Text(updateChecker.currentVersion)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Status") {
                    if updateChecker.isUpdateAvailable {
                        Label("Update available", systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    } else if updateChecker.lastCheckDate != nil {
                        Label("Up to date", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Not checked yet")
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastCheck = updateChecker.lastCheckDate {
                    LabeledContent("Last checked") {
                        Text("\(lastCheck, style: .relative) ago")
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    if let url = URL(string: "https://github.com/\(kGitHubRepo)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("View on GitHub", systemImage: "arrow.up.right")
                }
                .buttonStyle(.borderless)
            }

            Section {
                Button {
                    Task { await updateChecker.checkForUpdates() }
                } label: {
                    if updateChecker.isChecking {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                            Text("Checking\u{2026}")
                        }
                    } else {
                        Label("Check for Updates Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(updateChecker.isChecking)
            }

            Section("Automatic Updates") {
                Toggle("Check for updates automatically", isOn: $updateChecker.autoCheckEnabled)
                    .onChange(of: updateChecker.autoCheckEnabled) {
                        if updateChecker.autoCheckEnabled {
                            updateChecker.startNightlyTimer()
                        } else {
                            updateChecker.stopNightlyTimer()
                            updateChecker.autoUpdateEnabled = false
                        }
                    }

                Toggle("Download and install automatically", isOn: $updateChecker.autoUpdateEnabled)
                    .onChange(of: updateChecker.autoUpdateEnabled) {
                        if updateChecker.autoUpdateEnabled {
                            updateChecker.autoCheckEnabled = true
                            updateChecker.startNightlyTimer()
                        }
                    }
            }

            if updateChecker.isUpdateAvailable, let latest = updateChecker.latestVersion {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Version \(latest) is available")
                                .font(.body.weight(.medium))
                            if updateChecker.isAutoUpdating {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 12, height: 12)
                                    Text("Downloading update\u{2026}")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if !updateChecker.isAutoUpdating {
                            Button("Download") {
                                updateChecker.openDownload()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            if let error = updateChecker.lastCheckError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}
