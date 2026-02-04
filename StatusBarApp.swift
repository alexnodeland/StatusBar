// StatusBarApp.swift
// A single-file macOS menu bar app that monitors multiple Atlassian Statuspage-powered status pages.
//
// Requirements: macOS 13+ (Ventura), Swift 5.9+
//
// Build & Run:
//   swiftc StatusBarApp.swift -parse-as-library -o StatusBar -framework SwiftUI -framework AppKit
//   ./StatusBar
//
// Or use the included build.sh to produce a proper .app bundle.

import SwiftUI

// MARK: - Configuration

private let kRefreshInterval: TimeInterval = 300 // 5 minutes

private let kDefaultSources = """
Anthropic | https://status.anthropic.com
GitHub | https://www.githubstatus.com
Cloudflare | https://www.cloudflarestatus.com
"""

// MARK: - Source Model

struct StatusSource: Identifiable, Equatable {
    let id: UUID
    var name: String
    var baseURL: String

    init(id: UUID = UUID(), name: String, baseURL: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Parse from "Name | URL" line format. Lines starting with # are ignored.
    static func parse(lines: String) -> [StatusSource] {
        lines
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> StatusSource? in
                let raw = String(line).trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty, !raw.hasPrefix("#") else { return nil }
                let parts = raw.split(separator: "|", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                let url = parts[1].trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, url.hasPrefix("http") else { return nil }
                return StatusSource(name: name, baseURL: url)
            }
    }

    /// Serialize back to line format
    static func serialize(_ sources: [StatusSource]) -> String {
        sources.map { "\($0.name) | \($0.baseURL)" }.joined(separator: "\n")
    }
}

// MARK: - API Models

struct SPPage: Codable {
    let id: String
    let name: String
    let url: String
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case id, name, url
        case updatedAt = "updated_at"
    }
}

struct SPStatus: Codable {
    let indicator: String   // "none" | "minor" | "major" | "critical"
    let description: String
}

struct SPComponent: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let description: String?
    let position: Int
    let groupId: String?
    enum CodingKeys: String, CodingKey {
        case id, name, status, description, position
        case groupId = "group_id"
    }
}

struct SPIncidentUpdate: Codable, Identifiable {
    let id: String
    let status: String
    let body: String
    let createdAt: String
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case id, status, body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SPIncident: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let impact: String
    let createdAt: String
    let updatedAt: String
    let shortlink: String?
    let incidentUpdates: [SPIncidentUpdate]
    enum CodingKeys: String, CodingKey {
        case id, name, status, impact, shortlink
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case incidentUpdates = "incident_updates"
    }
}

struct SPSummary: Codable {
    let page: SPPage
    let status: SPStatus
    let components: [SPComponent]
    let incidents: [SPIncident]
}

struct SPIncidentsResponse: Codable {
    let page: SPPage
    let incidents: [SPIncident]
}

// MARK: - Per-Source State

struct SourceState {
    var summary: SPSummary?
    var recentIncidents: [SPIncident] = []
    var isLoading: Bool = false
    var lastError: String?
    var lastRefresh: Date?

    var indicator: String { summary?.status.indicator ?? "unknown" }
    var statusDescription: String { summary?.status.description ?? "Loading…" }

    var indicatorSeverity: Int {
        switch indicator {
        case "none": return 0
        case "minor": return 1
        case "major": return 2
        case "critical": return 3
        default: return -1
        }
    }

    var topLevelComponents: [SPComponent] {
        (summary?.components ?? [])
            .filter { $0.groupId == nil }
            .sorted { $0.position < $1.position }
    }

    var activeIncidents: [SPIncident] {
        summary?.incidents ?? []
    }
}

// MARK: - Multi-Source Service

@MainActor
final class StatusService: ObservableObject {
    @Published var sources: [StatusSource] = []
    @Published var states: [UUID: SourceState] = [:]

    @AppStorage("statusSourceLines") private var storedLines: String = kDefaultSources

    private var refreshTimer: Timer?

    init() {
        sources = StatusSource.parse(lines: storedLines)
        if sources.isEmpty {
            sources = StatusSource.parse(lines: kDefaultSources)
            storedLines = kDefaultSources
        }
        Task { await refreshAll() }
        startTimer()
    }

    // MARK: - Aggregate Status

    var worstIndicator: String {
        let worst = states.values.max(by: { $0.indicatorSeverity < $1.indicatorSeverity })
        return worst?.indicator ?? "none"
    }

    /// Number of sources with non-operational status
    var issueCount: Int {
        states.values.filter { $0.indicator != "none" && $0.indicator != "unknown" }.count
    }

    var anyLoading: Bool {
        states.values.contains { $0.isLoading }
    }

    var menuBarIcon: String {
        iconForIndicator(worstIndicator)
    }

    var menuBarColor: Color {
        colorForIndicator(worstIndicator)
    }

    // MARK: - Timer

    func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: kRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAll()
            }
        }
    }

    // MARK: - Fetching

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask { await self.refresh(source: source) }
            }
        }
    }

    func refresh(source: StatusSource) async {
        states[source.id, default: SourceState()].isLoading = true
        states[source.id]?.lastError = nil

        do {
            async let s = fetchSummary(baseURL: source.baseURL)
            async let i = fetchIncidents(baseURL: source.baseURL)
            let (summary, incidents) = try await (s, i)
            states[source.id]?.summary = summary
            states[source.id]?.recentIncidents = incidents
            states[source.id]?.lastRefresh = Date()
        } catch {
            states[source.id]?.lastError = error.localizedDescription
        }

        states[source.id]?.isLoading = false
    }

    private func fetchSummary(baseURL: String) async throws -> SPSummary {
        let url = URL(string: "\(baseURL)/api/v2/summary.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SPSummary.self, from: data)
    }

    private func fetchIncidents(baseURL: String) async throws -> [SPIncident] {
        let url = URL(string: "\(baseURL)/api/v2/incidents.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SPIncidentsResponse.self, from: data).incidents
    }

    // MARK: - Source Management

    func applySources(from lines: String) {
        let parsed = StatusSource.parse(lines: lines)
        guard !parsed.isEmpty else { return }

        // Remove states for sources that no longer exist
        let newIDs = Set(parsed.map(\.id))
        for oldID in states.keys where !newIDs.contains(oldID) {
            states.removeValue(forKey: oldID)
        }

        sources = parsed
        storedLines = lines
        Task { await refreshAll() }
    }

    func resetToDefaults() {
        applySources(from: kDefaultSources)
    }

    var serializedSources: String {
        StatusSource.serialize(sources)
    }

    func state(for source: StatusSource) -> SourceState {
        states[source.id] ?? SourceState()
    }
}

// MARK: - Date Helpers

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let isoFormatterNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private let displayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

private func parseDate(_ str: String) -> Date? {
    isoFormatter.date(from: str) ?? isoFormatterNoFrac.date(from: str)
}

private func formatDate(_ str: String) -> String {
    guard let d = parseDate(str) else { return str }
    return displayFormatter.string(from: d)
}

private func relativeDate(_ str: String) -> String {
    guard let d = parseDate(str) else { return str }
    return relativeFormatter.localizedString(for: d, relativeTo: Date())
}

// MARK: - Indicator Helpers

private func iconForIndicator(_ indicator: String) -> String {
    switch indicator {
    case "none": return "checkmark.circle.fill"
    case "minor": return "exclamationmark.triangle.fill"
    case "major": return "exclamationmark.octagon.fill"
    case "critical": return "xmark.octagon.fill"
    default: return "questionmark.circle"
    }
}

private func colorForIndicator(_ indicator: String) -> Color {
    switch indicator {
    case "none": return .green
    case "minor": return .yellow
    case "major": return .orange
    case "critical": return .red
    default: return .secondary
    }
}

private func colorForComponentStatus(_ status: String) -> Color {
    switch status {
    case "operational": return .green
    case "degraded_performance": return .yellow
    case "partial_outage": return .orange
    case "major_outage": return .red
    default: return .secondary
    }
}

private func labelForComponentStatus(_ status: String) -> String {
    switch status {
    case "operational": return "Operational"
    case "degraded_performance": return "Degraded"
    case "partial_outage": return "Partial Outage"
    case "major_outage": return "Major Outage"
    default: return status
    }
}

// MARK: - Root View (List ↔ Detail navigation)

struct RootView: View {
    @ObservedObject var service: StatusService
    @State private var selectedSourceID: UUID?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if let sourceID = selectedSourceID,
               let source = service.sources.first(where: { $0.id == sourceID }) {
                SourceDetailView(
                    source: source,
                    state: service.state(for: source),
                    onRefresh: { Task { await service.refresh(source: source) } },
                    onBack: { withAnimation(.easeInOut(duration: 0.15)) { selectedSourceID = nil } }
                )
            } else if showSettings {
                SettingsView(
                    service: service,
                    onBack: { withAnimation(.easeInOut(duration: 0.15)) { showSettings = false } }
                )
            } else {
                SourceListView(
                    service: service,
                    onSelect: { id in withAnimation(.easeInOut(duration: 0.15)) { selectedSourceID = id } },
                    onSettings: { withAnimation(.easeInOut(duration: 0.15)) { showSettings = true } }
                )
            }
        }
        .frame(width: 400, height: 540)
    }
}

// MARK: - Source List View

struct SourceListView: View {
    @ObservedObject var service: StatusService
    let onSelect: (UUID) -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            sourceList
            Divider()
            footerSection
        }
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: service.menuBarIcon)
                .font(.title2)
                .foregroundStyle(service.menuBarColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Status Monitor")
                    .font(.headline)
                Group {
                    if service.issueCount == 0 {
                        Text("All systems operational")
                    } else {
                        Text("\(service.issueCount) source\(service.issueCount == 1 ? "" : "s") with issues")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if service.anyLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Button {
                Task { await service.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh all")
        }
        .padding(12)
        .background(.bar)
    }

    private var sourceList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(service.sources) { source in
                    SourceRow(source: source, state: service.state(for: source))
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(source.id) }
                }
            }
            .padding(8)
        }
    }

    private var footerSection: some View {
        HStack {
            Text("\(service.sources.count) source\(service.sources.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Button(action: onSettings) {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Source Row

struct SourceRow: View {
    let source: StatusSource
    let state: SourceState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconForIndicator(state.indicator))
                .font(.body)
                .foregroundStyle(colorForIndicator(state.indicator))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                if let error = state.lastError {
                    Text("Error: \(error)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else {
                    Text(state.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Badge: active incident count
            let activeCount = state.activeIncidents.count
            if activeCount > 0 {
                Text("\(activeCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorForIndicator(state.indicator))
                    .clipShape(Capsule())
            }

            if state.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(state.indicatorSeverity > 0
                      ? colorForIndicator(state.indicator).opacity(0.06)
                      : Color.clear)
        )
    }
}

// MARK: - Source Detail View

struct SourceDetailView: View {
    let source: StatusSource
    let state: SourceState
    let onRefresh: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()

            if state.isLoading && state.summary == nil {
                loadingView
            } else if let error = state.lastError, state.summary == nil {
                errorView(error)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !state.activeIncidents.isEmpty {
                            activeIncidentsSection
                        }
                        componentsSection
                        recentIncidentsSection
                    }
                    .padding(12)
                }
            }

            Divider()
            detailFooter
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Image(systemName: iconForIndicator(state.indicator))
                .font(.title3)
                .foregroundStyle(colorForIndicator(state.indicator))

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.headline)
                Text(state.statusDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if state.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: - Sections

    private var activeIncidentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Active Incidents", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            ForEach(state.activeIncidents) { incident in
                IncidentCard(incident: incident, isActive: true)
            }
        }
    }

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Components")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if state.topLevelComponents.isEmpty {
                Text("No components reported")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(state.topLevelComponents) { component in
                    ComponentRow(component: component)
                }
            }
        }
    }

    private var recentIncidentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Incidents")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            let incidents = Array(state.recentIncidents.prefix(10))
            if incidents.isEmpty {
                Text("No recent incidents")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(incidents) { incident in
                    IncidentCard(incident: incident, isActive: false)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading status…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Failed to load status")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRefresh)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailFooter: some View {
        HStack {
            if let last = state.lastRefresh {
                Text("Updated \(relativeFormatter.localizedString(for: last, relativeTo: Date()))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Open Status Page") {
                if let url = URL(string: source.baseURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Component Row

struct ComponentRow: View {
    let component: SPComponent

    var body: some View {
        HStack {
            Circle()
                .fill(colorForComponentStatus(component.status))
                .frame(width: 8, height: 8)
            Text(component.name)
                .font(.caption)
            Spacer()
            Text(labelForComponentStatus(component.status))
                .font(.caption2)
                .foregroundStyle(colorForComponentStatus(component.status))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Incident Card

struct IncidentCard: View {
    let incident: SPIncident
    let isActive: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(impactColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(incident.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(isExpanded ? nil : 2)

                    HStack(spacing: 6) {
                        Text(statusBadge)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(statusBadgeColor.opacity(0.15))
                            .foregroundStyle(statusBadgeColor)
                            .clipShape(Capsule())

                        Text(relativeDate(incident.updatedAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(incident.incidentUpdates.prefix(5)) { update in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(update.status.capitalized)
                                    .font(.caption2.weight(.semibold))
                                Spacer()
                                Text(formatDate(update.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(update.body)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                        .padding(6)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(4)
                    }

                    if let link = incident.shortlink, let url = URL(string: link) {
                        Button("View on Status Page →") {
                            NSWorkspace.shared.open(url)
                        }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.leading, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(isActive ? impactColor.opacity(0.06) : Color.clear)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? impactColor.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    private var impactColor: Color {
        switch incident.impact {
        case "none": return .green
        case "minor": return .yellow
        case "major": return .orange
        case "critical": return .red
        default: return .secondary
        }
    }

    private var statusBadge: String {
        switch incident.status {
        case "investigating": return "Investigating"
        case "identified": return "Identified"
        case "monitoring": return "Monitoring"
        case "resolved": return "Resolved"
        case "postmortem": return "Postmortem"
        default: return incident.status.capitalized
        }
    }

    private var statusBadgeColor: Color {
        switch incident.status {
        case "investigating": return .red
        case "identified": return .orange
        case "monitoring": return .blue
        case "resolved": return .green
        case "postmortem": return .purple
        default: return .secondary
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var service: StatusService
    let onBack: () -> Void
    @State private var editText: String = ""
    @State private var parsePreview: [StatusSource] = []
    @State private var hasChanges = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("One per line:  **Name | URL**")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Lines starting with **#** are ignored.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                TextEditor(text: $editText)
                    .font(.system(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .frame(minHeight: 160)
                    .onChange(of: editText) { _ in
                        parsePreview = StatusSource.parse(lines: editText)
                        hasChanges = true
                    }

                HStack {
                    if parsePreview.isEmpty && hasChanges {
                        Label("No valid sources found", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else if hasChanges {
                        Text("\(parsePreview.count) source\(parsePreview.count == 1 ? "" : "s") detected")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(12)

            Spacer()
            Divider()
            settingsFooter
        }
        .onAppear {
            editText = service.serializedSources
            parsePreview = service.sources
            hasChanges = false
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Image(systemName: "gear")
                .font(.title3)
            Text("Sources")
                .font(.headline)
            Spacer()
        }
        .padding(12)
        .background(.bar)
    }

    private var settingsFooter: some View {
        HStack {
            Button("Reset to Defaults") {
                editText = kDefaultSources
                parsePreview = StatusSource.parse(lines: kDefaultSources)
                service.resetToDefaults()
                hasChanges = false
            }
            .font(.caption)

            Spacer()

            Button("Apply") {
                service.applySources(from: editText)
                hasChanges = false
                onBack()
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
            .disabled(parsePreview.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @ObservedObject var service: StatusService

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: service.menuBarIcon)
            if service.issueCount > 0 {
                Text("\(service.issueCount)")
                    .font(.caption2.monospacedDigit())
            }
        }
    }
}

// MARK: - App Entry Point

@main
struct StatusBarApp: App {
    @StateObject private var service = StatusService()

    var body: some Scene {
        MenuBarExtra {
            RootView(service: service)
        } label: {
            MenuBarLabel(service: service)
        }
        .menuBarExtraStyle(.window)
    }
}
