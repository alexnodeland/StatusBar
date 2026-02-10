// SourceListView.swift
// Root navigation view, source list with sort/filter, and source row.

import AppKit
import SwiftUI

// MARK: - Root View

struct RootView: View {
    @ObservedObject var service: StatusService
    @ObservedObject var updateChecker: UpdateChecker
    @State private var selectedSourceID: UUID?
    @State private var showSettings = false
    @State private var showCatalog = false

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .popover, blendingMode: .behindWindow)

            VStack(spacing: 0) {
                if let sourceID = selectedSourceID,
                    let source = service.sources.first(where: { $0.id == sourceID })
                {
                    SourceDetailView(
                        source: source,
                        state: service.state(for: source),
                        historyStore: service.historyStore,
                        onRefresh: { Task { await service.refresh(source: source) } },
                        onBack: { withAnimation(Design.Timing.transition) { selectedSourceID = nil } }
                    )
                } else if showCatalog {
                    ServiceCatalogView(
                        service: service,
                        onBack: { withAnimation(Design.Timing.transition) { showCatalog = false } }
                    )
                } else if showSettings {
                    SettingsView(
                        service: service,
                        updateChecker: updateChecker,
                        onBack: { withAnimation(Design.Timing.transition) { showSettings = false } }
                    )
                } else {
                    SourceListView(
                        service: service,
                        updateChecker: updateChecker,
                        onSelect: { id in withAnimation(Design.Timing.transition) { selectedSourceID = id } },
                        onSettings: { withAnimation(Design.Timing.transition) { showSettings = true } },
                        onCatalog: { withAnimation(Design.Timing.transition) { showCatalog = true } }
                    )
                }
            }

            // Hidden buttons for global keyboard shortcuts
            Button("") { Task { await service.refreshAll() } }
                .keyboardShortcut("r", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)

            Button("") {
                withAnimation(Design.Timing.transition) {
                    selectedSourceID = nil
                    showSettings = true
                }
            }
            .keyboardShortcut(",", modifiers: .command)
            .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .frame(width: 380, height: 520)
    }
}

// MARK: - Source List View

struct SourceListView: View {
    @ObservedObject var service: StatusService
    @ObservedObject var updateChecker: UpdateChecker
    let onSelect: (UUID) -> Void
    let onSettings: () -> Void
    var onCatalog: (() -> Void)?

    @State private var sortOrder: SourceSortOrder = .alphabetical
    @State private var statusFilter: SourceStatusFilter = .all
    @State private var sortAscending: Bool = true
    @State private var filterExcludes: Bool = false
    @AppStorage("compactViewMode") private var isCompact = false
    @State private var collapsedGroups: Set<String> = []
    @State private var showingAddSource = false
    @State private var newSourceName = ""
    @State private var newSourceURL = ""

    private var filteredAndSortedSources: [StatusSource] {
        let filtered: [StatusSource]
        if let indicator = statusFilter.indicator {
            filtered = service.sources.filter { source in
                let matches = service.state(for: source).indicator == indicator
                return filterExcludes ? !matches : matches
            }
        } else {
            filtered = service.sources
        }

        switch sortOrder {
        case .alphabetical:
            return filtered.sorted {
                let ascending = $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                return sortAscending ? ascending : !ascending
            }
        case .latest:
            return filtered.sorted { a, b in
                let dateA = service.state(for: a).recentIncidents.compactMap({ parseDate($0.updatedAt) }).max() ?? .distantPast
                let dateB = service.state(for: b).recentIncidents.compactMap({ parseDate($0.updatedAt) }).max() ?? .distantPast
                let ascending = dateA > dateB
                return sortAscending ? ascending : !ascending
            }
        case .status:
            return filtered.sorted { a, b in
                let sevA = service.state(for: a).indicatorSeverity
                let sevB = service.state(for: b).indicatorSeverity
                if sevA != sevB {
                    let ascending = sevA > sevB
                    return sortAscending ? ascending : !ascending
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        case .manual:
            return filtered.sorted {
                let ascending = $0.sortOrder < $1.sortOrder
                return sortAscending ? ascending : !ascending
            }
        }
    }

    private var groupedSources: [(group: String?, sources: [StatusSource])] {
        let sources = filteredAndSortedSources
        var groups: [String?: [StatusSource]] = [:]
        for source in sources {
            groups[source.group, default: []].append(source)
        }
        var result: [(group: String?, sources: [StatusSource])] = []
        if let ungrouped = groups[nil], !ungrouped.isEmpty {
            result.append((group: nil, sources: ungrouped))
        }
        for key in groups.keys.compactMap({ $0 }).sorted() {
            if let sources = groups[key] {
                result.append((group: key, sources: sources))
            }
        }
        return result
    }

    private var hasGroups: Bool {
        service.sources.contains { $0.group != nil }
    }

    private var urlValidation: URLValidationResult {
        validateSourceURL(newSourceURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().opacity(0.5)
            if showingAddSource {
                addSourceForm
                Divider().opacity(0.5)
            }
            sourceList
            Divider().opacity(0.5)
            footerSection
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

            if !newSourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let message = urlValidation.message {
                HStack(spacing: 4) {
                    Image(systemName: urlValidation.isAcceptable ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                        .font(Design.Typography.micro)
                    Text(message)
                        .font(Design.Typography.micro)
                }
                .foregroundStyle(urlValidation.isAcceptable ? .orange : .red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Add") {
                    let name = newSourceName.trimmingCharacters(in: .whitespaces)
                    let url = newSourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, urlValidation.isAcceptable else { return }
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
                    newSourceName.trimmingCharacters(in: .whitespaces).isEmpty
                        || !urlValidation.isAcceptable
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: service.menuBarIcon)
                .font(.title2)
                .foregroundStyle(service.menuBarColor)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel("Status indicator: \(service.worstIndicator == "none" ? "all operational" : "\(service.issueCount) issues")")

            VStack(alignment: .leading, spacing: 2) {
                Text("Status Monitor")
                    .font(Design.Typography.bodyMedium)
                Group {
                    if service.issueCount == 0 {
                        Text("All systems operational")
                    } else {
                        Text("\(service.issueCount) source\(service.issueCount == 1 ? "" : "s") with issues")
                    }
                }
                .font(Design.Typography.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if service.anyLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }

            Button {
                withAnimation(Design.Timing.transition) { isCompact.toggle() }
            } label: {
                Image(systemName: isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                    .font(Design.Typography.caption)
            }
            .buttonStyle(.borderless)
            .help(isCompact ? "Expand view" : "Compact view")
            .accessibilityLabel(isCompact ? "Switch to expanded view" : "Switch to compact view")

            sortMenuButton
            filterMenuButton

            Button {
                Task { await service.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(Design.Typography.body)
            }
            .buttonStyle(.borderless)
            .help("Refresh all (Cmd+R)")
            .accessibilityLabel("Refresh all sources")
            .accessibilityHint("Fetches latest status for all monitored pages")
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private var isSortActive: Bool { sortOrder != .alphabetical || !sortAscending }
    private var isFilterActive: Bool { statusFilter != .all || filterExcludes }

    private var sortMenuButton: some View {
        Menu {
            Picker("Sort By", selection: $sortOrder) {
                ForEach(SourceSortOrder.allCases, id: \.self) { order in
                    Label(order.rawValue, systemImage: order.systemImage)
                        .tag(order)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("Direction", selection: $sortAscending) {
                Label("Ascending", systemImage: "arrow.up").tag(true)
                Label("Descending", systemImage: "arrow.down").tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(Design.Typography.caption)
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(isSortActive ? .white : .secondary)
        .background(
            Circle()
                .fill(isSortActive ? Color.accentColor : Color.clear)
                .frame(width: 22, height: 22)
        )
        .contentShape(Circle())
        .help("Sort options")
        .accessibilityLabel("Sort options, current: \(sortOrder.rawValue)")
    }

    private var filterMenuButton: some View {
        Menu {
            Picker("Filter", selection: $statusFilter) {
                ForEach(SourceStatusFilter.allCases, id: \.self) { filter in
                    Label(filter.rawValue, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("Mode", selection: $filterExcludes) {
                Label("Include", systemImage: "checkmark.circle").tag(false)
                Label("Exclude", systemImage: "minus.circle").tag(true)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(Design.Typography.caption)
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(isFilterActive ? .white : .secondary)
        .background(
            Circle()
                .fill(isFilterActive ? Color.accentColor : Color.clear)
                .frame(width: 22, height: 22)
        )
        .contentShape(Circle())
        .help("Filter options")
        .accessibilityLabel("Filter options, current: \(statusFilter.rawValue)")
    }

    // MARK: - Source List Body

    private var sourceList: some View {
        ScrollView {
            let sources = filteredAndSortedSources
            if sources.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .symbolRenderingMode(.hierarchical)
                    Text("No sources match filter")
                        .font(Design.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else if hasGroups && (sortOrder == .manual || sortOrder == .alphabetical) {
                groupedSourceList
            } else if sortOrder == .manual {
                manualSortList(sources: sources)
            } else {
                flatSourceList(sources: sources)
            }
        }
    }

    private var groupedSourceList: some View {
        LazyVStack(spacing: 2) {
            ForEach(groupedSources, id: \.group) { entry in
                if let group = entry.group {
                    groupSection(name: group, sources: entry.sources)
                } else {
                    // Ungrouped sources rendered flat
                    ForEach(entry.sources) { source in
                        sourceRow(for: source)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(source.id) }
                            .contextMenu { sourceContextMenu(for: source) }
                    }
                }
            }
        }
        .padding(8)
    }

    private func groupSection(name: String, sources: [StatusSource]) -> some View {
        VStack(spacing: 2) {
            Button {
                withAnimation(Design.Timing.expand) {
                    if collapsedGroups.contains(name) {
                        collapsedGroups.remove(name)
                    } else {
                        collapsedGroups.insert(name)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: collapsedGroups.contains(name) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                    Text(name)
                        .font(Design.Typography.captionSemibold)
                        .foregroundStyle(.secondary)
                    Text("\(sources.count)")
                        .font(Design.Typography.micro)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderless)

            if !collapsedGroups.contains(name) {
                ForEach(sources) { source in
                    sourceRow(for: source)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(source.id) }
                        .contextMenu { sourceContextMenu(for: source) }
                        .padding(.leading, 12)
                }
            }
        }
    }

    private func manualSortList(sources: [StatusSource]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(sources) { source in
                sourceRow(for: source)
                    .contentShape(Rectangle())
                    .draggable(source.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        guard let draggedIDString = items.first,
                              let draggedID = UUID(uuidString: draggedIDString),
                              let fromIndex = service.sources.firstIndex(where: { $0.id == draggedID }),
                              let toIndex = service.sources.firstIndex(where: { $0.id == source.id })
                        else { return false }
                        let fromSet = IndexSet(integer: fromIndex)
                        let dest = toIndex > fromIndex ? toIndex + 1 : toIndex
                        withAnimation(Design.Timing.transition) {
                            service.moveSources(from: fromSet, to: dest)
                        }
                        return true
                    }
                    .simultaneousGesture(TapGesture().onEnded { onSelect(source.id) })
                    .contextMenu { sourceContextMenu(for: source) }
            }
        }
        .padding(8)
    }

    private func flatSourceList(sources: [StatusSource]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(sources) { source in
                sourceRow(for: source)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(source.id) }
                    .contextMenu { sourceContextMenu(for: source) }
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private func sourceRow(for source: StatusSource) -> some View {
        let state = service.state(for: source)
        if isCompact {
            CompactSourceRow(source: source, state: state)
        } else {
            SourceRow(
                source: source,
                state: state,
                checkpoints: service.history[source.id] ?? []
            )
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func sourceContextMenu(for source: StatusSource) -> some View {
        Button {
            Task { await service.refresh(source: source) }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }

        Divider()

        // Alert Level submenu
        Menu {
            ForEach(AlertLevel.allCases, id: \.self) { level in
                Button {
                    service.updateAlertLevel(sourceID: source.id, level: level)
                } label: {
                    if source.alertLevel == level {
                        Label(level.rawValue, systemImage: "checkmark")
                    } else {
                        Text(level.rawValue)
                    }
                }
            }
        } label: {
            Label("Alert Level", systemImage: "bell")
        }

        // Move to Group submenu
        Menu {
            let existingGroups = Set(service.sources.compactMap(\.group)).sorted()
            ForEach(existingGroups, id: \.self) { group in
                Button {
                    service.setGroup(sourceID: source.id, group: group)
                } label: {
                    if source.group == group {
                        Label(group, systemImage: "checkmark")
                    } else {
                        Text(group)
                    }
                }
            }
            if !existingGroups.isEmpty {
                Divider()
            }
            Button {
                promptForNewGroup(sourceID: source.id)
            } label: {
                Label("New Group\u{2026}", systemImage: "plus")
            }
            if source.group != nil {
                Button("Remove from Group") {
                    service.setGroup(sourceID: source.id, group: nil)
                }
            }
        } label: {
            Label("Move to Group", systemImage: "folder")
        }

        Divider()

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(source.baseURL, forType: .string)
        } label: {
            Label("Copy URL", systemImage: "doc.on.doc")
        }

        Button {
            if let url = URL(string: source.baseURL) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Open in Browser", systemImage: "safari")
        }

        Divider()

        Button(role: .destructive) {
            service.removeSource(id: source.id)
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func promptForNewGroup(sourceID: UUID) {
        let alert = NSAlert()
        alert.messageText = "New Group"
        alert.informativeText = "Enter a name for the new group:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = "Group name"
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField
        if alert.runModal() == .alertFirstButtonReturn {
            let name = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                service.setGroup(sourceID: sourceID, group: name)
            }
        }
    }

    private var footerSection: some View {
        HStack {
            if let onCatalog {
                Button(action: onCatalog) {
                    Image(systemName: "list.star")
                        .font(Design.Typography.caption)
                }
                .buttonStyle(.borderless)
                .help("Browse service catalog")
                .accessibilityLabel("Browse service catalog")
            }

            Button {
                withAnimation(Design.Timing.expand) {
                    showingAddSource.toggle()
                    newSourceName = ""
                    newSourceURL = ""
                }
            } label: {
                Image(systemName: showingAddSource ? "xmark.circle.fill" : "plus.circle.fill")
                    .font(Design.Typography.caption)
                    .foregroundStyle(showingAddSource ? .secondary : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .help(showingAddSource ? "Cancel" : "Add source")
            .accessibilityLabel(showingAddSource ? "Cancel adding source" : "Add new source")

            Group {
                if statusFilter == .all {
                    Text("\(service.sources.count) source\(service.sources.count == 1 ? "" : "s")")
                } else {
                    Text("\(filteredAndSortedSources.count) of \(service.sources.count) source\(service.sources.count == 1 ? "" : "s")")
                }
            }
            .font(Design.Typography.micro)
            .foregroundStyle(.quaternary)

            Spacer()

            Button(action: onSettings) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gear")
                        .font(Design.Typography.caption)
                    if updateChecker.isUpdateAvailable {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(.borderless)
            .help(updateChecker.isUpdateAvailable ? "Settings — Update available (Cmd+,)" : "Settings (Cmd+,)")
            .accessibilityLabel(updateChecker.isUpdateAvailable ? "Settings, update available" : "Settings")

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

// MARK: - Source Row

struct SourceRow: View {
    let source: StatusSource
    let state: SourceState
    var checkpoints: [StatusCheckpoint] = []

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: iconForIndicator(state.indicator))
                    .font(Design.Typography.body)
                    .foregroundStyle(colorForIndicator(state.indicator))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 20)

                if state.isStale {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 7))
                        .foregroundStyle(.orange)
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(Design.Typography.bodyMedium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !checkpoints.isEmpty {
                        SparklineView(checkpoints: checkpoints)
                    }

                    if state.isStale, state.lastError != nil {
                        Text("\(state.statusDescription) (stale)")
                            .font(Design.Typography.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else if let error = state.lastError {
                        Text(error)
                            .font(Design.Typography.micro)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else {
                        Text(state.statusDescription)
                            .font(Design.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            let activeCount = state.activeIncidents.count
            if activeCount > 0 {
                Text("\(activeCount)")
                    .font(Design.Typography.micro.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(colorForIndicator(state.indicator))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorForIndicator(state.indicator).opacity(0.15), in: Capsule())
            }

            if state.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12)
            }

            Image(systemName: "chevron.right")
                .font(Design.Typography.micro)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    state.indicatorSeverity > 0
                        ? colorForIndicator(state.indicator).opacity(0.06)
                        : Color.clear)
        )
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.name), status: \(state.statusDescription)")
        .accessibilityHint("Double tap to view details")
    }
}

// MARK: - Compact Source Row

struct CompactSourceRow: View {
    let source: StatusSource
    let state: SourceState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(colorForIndicator(state.indicator))
                .frame(width: 7, height: 7)
            Text(source.name)
                .font(Design.Typography.caption)
                .lineLimit(1)
            Spacer()
            if state.isStale {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 8))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.name), status: \(state.statusDescription)")
        .accessibilityHint("Double tap to view details")
    }
}
