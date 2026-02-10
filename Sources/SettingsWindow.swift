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
    case hooks = "Hooks"
    case data = "Data"
    case updates = "Updates"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gear"
        case .notifications: "bell.badge"
        case .webhooks: "antenna.radiowaves.left.and.right"
        case .hooks: "terminal"
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
                case .hooks:
                    HooksSettingsTab()
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
        .onReceive(NotificationCenter.default.publisher(for: .statusBarNavigateToSettingsTab)) { notification in
            if let tabRawValue = notification.userInfo?["tab"] as? String,
               let tab = SettingsTab(rawValue: tabRawValue.capitalized) {
                selectedTab = tab
            }
        }
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
    @State private var importError: String?

    var body: some View {
        Form {
            Section("Full Configuration") {
                Text("Export all settings, sources, and webhooks as a single JSON file for backup or sharing.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                if service.hasWebhooks {
                    Label(
                        "Exported files contain webhook URLs. Share only with trusted recipients.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.callout).foregroundStyle(.orange)
                }
                Button {
                    importConfig()
                } label: {
                    Label("Import Configuration\u{2026}", systemImage: "square.and.arrow.down")
                }
                .help("Import settings, sources, and webhooks from JSON file")
                Button {
                    exportConfig()
                } label: {
                    Label("Export Configuration\u{2026}", systemImage: "square.and.arrow.up")
                }
                .help("Export settings, sources, and webhooks as JSON file")
            }

            Section("Sources Only") {
                Text("Export or import only your monitored status pages as JSON.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Button {
                    importSources()
                } label: {
                    Label("Import Sources\u{2026}", systemImage: "square.and.arrow.down")
                }
                .help("Import sources from JSON file")
                Button {
                    exportSources()
                } label: {
                    Label("Export Sources\u{2026}", systemImage: "square.and.arrow.up")
                }
                .help("Export sources as JSON file")
            }

            if let importError {
                Section {
                    Label(importError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.title = "Export Configuration"
        panel.nameFieldStringValue = "statusbar-config.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            if let data = service.exportConfigJSON() {
                try? data.write(to: url)
            }
        }
    }

    private func importConfig() {
        importError = nil
        let panel = NSOpenPanel()
        panel.title = "Import Configuration"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url) {
                if !service.importConfigJSON(data) {
                    importError = "Could not read configuration file. Check that it is a valid StatusBar JSON export."
                }
            } else {
                importError = "Could not read the selected file."
            }
        }
    }

    private func exportSources() {
        let panel = NSSavePanel()
        panel.title = "Export Sources"
        panel.nameFieldStringValue = "statusbar-sources.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            if let data = service.exportSourcesJSON() {
                try? data.write(to: url)
            }
        }
    }

    private func importSources() {
        importError = nil
        let panel = NSOpenPanel()
        panel.title = "Import Sources"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url) {
                if !service.importSourcesJSON(data) {
                    importError = "Could not read sources file. Check that it is a valid JSON export."
                }
            } else {
                importError = "Could not read the selected file."
            }
        }
    }
}

// MARK: - Hooks Settings Tab

struct HooksSettingsTab: View {
    @State private var discoveredHooks: [URL] = []
    @State private var hookToDelete: URL?
    @State private var showEventRef = false
    @State private var showEnvVars = false
    @State private var showURLRef = false

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "terminal")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Script Hooks")
                            .font(.body.weight(.medium))
                        Text("Hooks are shell scripts that run automatically when status events happen \u{2014} like a source going down or recovering. Use them to send custom alerts, log to a file, trigger automations, or anything you can script.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if discoveredHooks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No hooks installed")
                            .foregroundStyle(.secondary)
                        Text("Add a starter hook to see how it works.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                } else {
                    ForEach(discoveredHooks, id: \.absoluteString) { hook in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(hook.lastPathComponent)
                                    .font(.body)
                                Text("Runs on all events")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                hookToDelete = hook
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Delete \(hook.lastPathComponent)")
                            .accessibilityLabel("Delete hook \(hook.lastPathComponent)")
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        createExampleHook()
                    } label: {
                        Label("Add Example Hook", systemImage: "plus")
                    }
                    .accessibilityLabel("Add example hook script")

                    Button {
                        NSWorkspace.shared.open(HookManager.shared.hooksDirectory)
                    } label: {
                        Label("Open Folder", systemImage: "folder")
                    }
                    .accessibilityLabel("Open hooks folder in Finder")
                }
            } header: {
                HStack {
                    Text("Installed Hooks")
                    Spacer()
                    Button {
                        discoveredHooks = HookManager.shared.discoverHooks()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Rescan hooks folder")
                    .accessibilityLabel("Rescan hooks folder")
                }
            }

            Section("How It Works") {
                VStack(alignment: .leading, spacing: 8) {
                    howItWorksStep(number: "1", text: "Click \"Add Example Hook\" or place any executable script in the hooks folder")
                    howItWorksStep(number: "2", text: "Scripts run on every status event \u{2014} check $STATUSBAR_EVENT to filter")
                    howItWorksStep(number: "3", text: "Event details arrive as environment variables and JSON on stdin")
                }
                .padding(.vertical, 2)

                refToggle("Event reference", isExpanded: $showEventRef)
                if showEventRef {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(HookEvent.allCases, id: \.rawValue) { event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.rawValue)
                                    .font(.system(.caption, design: .monospaced))
                                Text(hookEventDescription(event))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                refToggle("Environment variables", isExpanded: $showEnvVars)
                if showEnvVars {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(envVarDocs, id: \.0) { item in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.0)
                                    .font(.system(.caption, design: .monospaced))
                                Text(item.1)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("URL Scheme") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "link")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                    Text("Control StatusBar from Terminal, browsers, Raycast, or Shortcuts with statusbar:// URLs.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                refToggle("URL reference", isExpanded: $showURLRef)
                if showURLRef {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(urlSchemeExamples, id: \.0) { example in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(example.0)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Text(example.1)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            discoveredHooks = HookManager.shared.discoverHooks()
        }
        .alert("Delete Hook", isPresented: Binding(
            get: { hookToDelete != nil },
            set: { if !$0 { hookToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { hookToDelete = nil }
            Button("Delete", role: .destructive) {
                if let url = hookToDelete {
                    try? FileManager.default.removeItem(at: url)
                    discoveredHooks = HookManager.shared.discoverHooks()
                    hookToDelete = nil
                }
            }
        } message: {
            if let url = hookToDelete {
                Text("Are you sure you want to delete \"\(url.lastPathComponent)\"? This cannot be undone.")
            }
        }
    }

    private func refToggle(_ title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(Design.Timing.expand) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(isExpanded.wrappedValue ? .degrees(90) : .zero)
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func howItWorksStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func createExampleHook() {
        HookManager.shared.ensureHooksDirectory()
        let scriptURL = HookManager.shared.hooksDirectory.appendingPathComponent("example-logger")
        // Don't overwrite if it already exists
        guard !FileManager.default.fileExists(atPath: scriptURL.path) else {
            NSWorkspace.shared.open(HookManager.shared.hooksDirectory)
            return
        }
        let script = """
            #!/bin/bash
            # StatusBar Example Hook
            # This script logs status events to a file.
            # Edit or replace it with your own logic.
            #
            # Environment variables available:
            #   STATUSBAR_EVENT        - Event name (on-status-change, on-refresh, etc.)
            #   STATUSBAR_SOURCE_NAME  - Source name (for status-change, add, remove)
            #   STATUSBAR_SOURCE_URL   - Source URL (for status-change, add, remove)
            #   STATUSBAR_TITLE        - Notification title (for status-change)
            #   STATUSBAR_BODY         - Notification body (for status-change)
            #   STATUSBAR_SOURCE_COUNT - Number of sources (for refresh)
            #   STATUSBAR_WORST_LEVEL  - Worst status level (for refresh)
            #
            # JSON payload is also piped to stdin.

            LOG_FILE="$HOME/Library/Logs/StatusBar/hooks.log"
            mkdir -p "$(dirname "$LOG_FILE")"

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Event: $STATUSBAR_EVENT" >> "$LOG_FILE"

            case "$STATUSBAR_EVENT" in
                on-status-change)
                    echo "  Source: $STATUSBAR_SOURCE_NAME ($STATUSBAR_SOURCE_URL)" >> "$LOG_FILE"
                    echo "  Title:  $STATUSBAR_TITLE" >> "$LOG_FILE"
                    echo "  Body:   $STATUSBAR_BODY" >> "$LOG_FILE"
                    ;;
                on-refresh)
                    echo "  Sources: $STATUSBAR_SOURCE_COUNT, Worst: $STATUSBAR_WORST_LEVEL" >> "$LOG_FILE"
                    ;;
                on-source-add|on-source-remove)
                    echo "  Source: $STATUSBAR_SOURCE_NAME ($STATUSBAR_SOURCE_URL)" >> "$LOG_FILE"
                    ;;
            esac

            """
        FileManager.default.createFile(atPath: scriptURL.path, contents: script.data(using: .utf8))
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        discoveredHooks = HookManager.shared.discoverHooks()
    }

    private func hookEventDescription(_ event: HookEvent) -> String {
        switch event {
        case .onStatusChange: return "A source's status changes severity (e.g. none \u{2192} major)"
        case .onRefresh: return "All sources finish refreshing"
        case .onSourceAdd: return "A new source is added"
        case .onSourceRemove: return "A source is removed"
        }
    }

    private var envVarDocs: [(String, String)] {
        [
            ("STATUSBAR_EVENT", "Event name: on-status-change, on-refresh, on-source-add, on-source-remove"),
            ("STATUSBAR_SOURCE_NAME", "Source display name (status-change, add, remove)"),
            ("STATUSBAR_SOURCE_URL", "Source base URL (status-change, add, remove)"),
            ("STATUSBAR_TITLE", "Notification title (status-change only)"),
            ("STATUSBAR_BODY", "Notification body (status-change only)"),
            ("STATUSBAR_SOURCE_COUNT", "Total number of sources (refresh only)"),
            ("STATUSBAR_WORST_LEVEL", "Worst indicator: none, minor, major, critical (refresh only)"),
        ]
    }

    private var urlSchemeExamples: [(String, String)] {
        [
            ("statusbar://open", "Show the status popover"),
            ("statusbar://open?source=GitHub", "Open popover and navigate to source"),
            ("statusbar://refresh", "Refresh all sources"),
            ("statusbar://add?url=https://status.openai.com&name=OpenAI", "Add a new source"),
            ("statusbar://remove?name=GitHub", "Remove a source by name"),
            ("statusbar://settings", "Open settings window"),
            ("statusbar://settings?tab=webhooks", "Open settings to a specific tab"),
        ]
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
