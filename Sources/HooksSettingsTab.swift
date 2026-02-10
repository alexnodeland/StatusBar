// HooksSettingsTab.swift
// Settings UI for script hooks and URL scheme reference.

import SwiftUI

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
                        Text(
                            "Hooks are shell scripts that run automatically when status events happen"
                                + " \u{2014} like a source going down or recovering."
                                + " Use them to send custom alerts, log to a file,"
                                + " trigger automations, or anything you can script."
                        )
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
                    howItWorksStep(
                        number: "1",
                        text: "Click \"Add Example Hook\" or place any executable script in the hooks folder"
                    )
                    howItWorksStep(
                        number: "2",
                        text: "Scripts run on every status event \u{2014} check $STATUSBAR_EVENT to filter"
                    )
                    howItWorksStep(
                        number: "3",
                        text: "Event details arrive as environment variables and JSON on stdin"
                    )
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
        .alert(
            "Delete Hook",
            isPresented: Binding(
                get: { hookToDelete != nil },
                set: { if !$0 { hookToDelete = nil } }
            )
        ) {
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
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
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
