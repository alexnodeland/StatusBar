// SourceListView.swift
// Root navigation view, source list with sort/filter, and source row.

import SwiftUI

// MARK: - Root View

struct RootView: View {
    @ObservedObject var service: StatusService
    @ObservedObject var updateChecker: UpdateChecker
    @State private var selectedSourceID: UUID?
    @State private var showSettings = false

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
                        onRefresh: { Task { await service.refresh(source: source) } },
                        onBack: { withAnimation(Design.Timing.transition) { selectedSourceID = nil } }
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
                        onSettings: { withAnimation(Design.Timing.transition) { showSettings = true } }
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

    @State private var sortOrder: SourceSortOrder = .alphabetical
    @State private var statusFilter: SourceStatusFilter = .all
    @State private var sortAscending: Bool = true
    @State private var filterExcludes: Bool = false

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
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().opacity(0.5)
            sourceList
            Divider().opacity(0.5)
            footerSection
        }
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: service.menuBarIcon)
                .font(.title2)
                .foregroundStyle(service.menuBarColor)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))

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
    }

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
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(sources) { source in
                        SourceRow(
                            source: source,
                            state: service.state(for: source),
                            checkpoints: service.history[source.id] ?? []
                        )
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(source.id) }
                    }
                }
                .padding(8)
            }
        }
    }

    private var footerSection: some View {
        HStack {
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
    }
}
