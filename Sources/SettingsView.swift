// SettingsView.swift
// App settings: source management, preferences, and update checking.

import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var service: StatusService
    @ObservedObject var updateChecker: UpdateChecker
    let onBack: () -> Void
    @State private var launchAtLogin = false
    @State private var showingAddSource = false
    @State private var newSourceName = ""
    @State private var newSourceURL = ""
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader
            Divider().opacity(0.5)
            sourceListSection
            Spacer()
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
            updateSection
            Divider().opacity(0.5)
            settingsFooter
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var sourceListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Status Pages")
                    .font(Design.Typography.captionSemibold)
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    importSources()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(Design.Typography.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Import from TSV")

                Button {
                    exportSources()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(Design.Typography.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Export as TSV")

                Button {
                    withAnimation(Design.Timing.expand) {
                        showingAddSource.toggle()
                        newSourceName = ""
                        newSourceURL = ""
                    }
                } label: {
                    Image(systemName: showingAddSource ? "xmark.circle.fill" : "plus.circle.fill")
                        .font(Design.Typography.body)
                        .foregroundStyle(showingAddSource ? .secondary : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .help(showingAddSource ? "Cancel" : "Add source")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if showingAddSource {
                addSourceForm
            }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(service.sources) { source in
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(Design.Timing.expand) {
                                    service.removeSource(id: source.id)
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(Design.Typography.body)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove source")

                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.name)
                                    .font(Design.Typography.captionMedium)
                                    .lineLimit(1)
                                Text(source.baseURL)
                                    .font(Design.Typography.micro)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .hoverHighlight()
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var addSourceForm: some View {
        VStack(spacing: 6) {
            TextField("Name", text: $newSourceName)
                .font(Design.Typography.caption)
                .textFieldStyle(.roundedBorder)

            TextField("URL (e.g. https://status.example.com)", text: $newSourceURL)
                .font(Design.Typography.caption)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Add") {
                    let name = newSourceName.trimmingCharacters(in: .whitespaces)
                    let url = newSourceURL.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty, url.hasPrefix("http") else { return }
                    withAnimation(Design.Timing.expand) {
                        service.addSource(name: name, baseURL: url)
                        showingAddSource = false
                        newSourceName = ""
                        newSourceURL = ""
                    }
                }
                .font(Design.Typography.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(
                    newSourceName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    !newSourceURL.trimmingCharacters(in: .whitespaces).hasPrefix("http")
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
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
                        Image(nsImage: { img.isTemplate = true; return img }())
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
                        }
                    }
                .help("Check for Updates")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if updateChecker.isUpdateAvailable, let latest = updateChecker.latestVersion {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Version \(latest) available")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Button("Download") {
                        updateChecker.openDownload()
                    }
                    .font(Design.Typography.caption)
                    .buttonStyle(GlassButtonStyle())
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
            .help("Back")

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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
