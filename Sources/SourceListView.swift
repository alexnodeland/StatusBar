// SourceListView.swift
// Source list with sort/filter.

import AppKit
import SwiftUI

// MARK: - Source List View

// swiftlint:disable:next type_body_length
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: AddSourceField?
    @State private var urlAnnouncementTask: Task<Void, Never>?

    private enum AddSourceField: Hashable {
        case name
        case url
    }

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

    private var isFilterActive: Bool { statusFilter != .all || filterExcludes }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            ChromeDivider()
            if showingAddSource {
                addSourceForm
                ChromeDivider()
            }
            sourceList
            ChromeDivider()
            footerSection
        }
        .onChange(of: newSourceURL) { _, newValue in
            urlAnnouncementTask?.cancel()
            urlAnnouncementTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let result = validateSourceURL(trimmed)
                if let message = result.message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }

    // MARK: - Add Source Form

    private var addSourceForm: some View {
        VStack(spacing: Design.Spacing.cellInner) {
            TextField("Name", text: $newSourceName)
                .font(Design.Typography.caption)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .name)

            TextField("URL (e.g. https://status.example.com)", text: $newSourceURL)
                .font(Design.Typography.caption)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .url)

            if !newSourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let message = urlValidation.message
            {
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
                    withAnimation(reduceMotionAnimation(Design.Timing.expand, reduceMotion: reduceMotion)) {
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
        .padding(.horizontal, Design.Spacing.sectionH)
        .padding(.vertical, Design.Spacing.sectionV)
        .accessibleTransition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: Design.Spacing.standard) {
            Image(systemName: service.menuBarIcon)
                .font(.title2)
                .foregroundStyle(service.menuBarColor)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel(
                    {
                        let status =
                            service.worstIndicator == "none"
                            ? "all operational" : "\(service.issueCount) issues"
                        return "Status indicator: \(status)"
                    }())

            VStack(alignment: .leading, spacing: Design.Spacing.listGap) {
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
                    .accessibilityLabel("Loading")
            }

            GlassEffectContainer {
                HStack(spacing: Design.Spacing.compactV) {
                    Button {
                        withAnimation(reduceMotionAnimation(Design.Timing.transition, reduceMotion: reduceMotion)) {
                            isCompact.toggle()
                        }
                    } label: {
                        Image(systemName: isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                            .font(Design.Typography.caption)
                    }
                    .buttonStyle(.glass)
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
                    .buttonStyle(.glass)
                    .help("Refresh all (Cmd+R)")
                    .accessibilityLabel("Refresh all sources")
                    .accessibilityHint("Fetches latest status for all monitored pages")
                }
            }
        }
        .padding(Design.Spacing.sectionH)
        .chromeBackground()
    }

    // MARK: - Sort & Filter Menus

    private var isSortActive: Bool { sortOrder != .alphabetical || !sortAscending }

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
            if service.sources.isEmpty {
                // No sources added at all
                VStack(spacing: Design.Spacing.cellInner) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .symbolRenderingMode(.hierarchical)
                    Text("No sources added yet")
                        .font(Design.Typography.caption)
                        .foregroundStyle(.secondary)
                    Text("Add a status page or browse the catalog to get started.")
                        .font(Design.Typography.micro)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else if sources.isEmpty {
                // Sources exist but none match filter
                VStack(spacing: Design.Spacing.cellInner) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .symbolRenderingMode(.hierarchical)
                    Text("No sources match filter")
                        .font(Design.Typography.caption)
                        .foregroundStyle(.secondary)
                    Text("Try changing the filter to \"\(filterExcludes ? "Include" : "All")\" or selecting a different status level.")
                        .font(Design.Typography.micro)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
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
        LazyVStack(spacing: Design.Spacing.listGap) {
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
        .padding(Design.Spacing.cardInner)
    }

    private func groupSection(name: String, sources: [StatusSource]) -> some View {
        VStack(spacing: Design.Spacing.listGap) {
            Button {
                withAnimation(reduceMotionAnimation(Design.Timing.expand, reduceMotion: reduceMotion)) {
                    if collapsedGroups.contains(name) {
                        collapsedGroups.remove(name)
                    } else {
                        collapsedGroups.insert(name)
                    }
                }
            } label: {
                HStack(spacing: Design.Spacing.cellInner) {
                    Image(systemName: collapsedGroups.contains(name) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                    Text(name)
                        .font(Design.Typography.captionSemibold)
                        .foregroundStyle(.secondary)
                    BadgeView(text: "\(sources.count)", color: .secondary, style: .muted)
                    Spacer()
                }
                .padding(.horizontal, Design.Spacing.rowH)
                .padding(.vertical, Design.Spacing.compactV)
            }
            .buttonStyle(.borderless)

            if !collapsedGroups.contains(name) {
                ForEach(sources) { source in
                    sourceRow(for: source)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(source.id) }
                        .contextMenu { sourceContextMenu(for: source) }
                        .padding(.leading, Design.Spacing.sectionH)
                }
            }
        }
    }

    private func manualSortList(sources: [StatusSource]) -> some View {
        LazyVStack(spacing: Design.Spacing.listGap) {
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
                        withAnimation(reduceMotionAnimation(Design.Timing.transition, reduceMotion: reduceMotion)) {
                            service.moveSources(from: fromSet, to: dest)
                        }
                        return true
                    }
                    .simultaneousGesture(TapGesture().onEnded { onSelect(source.id) })
                    .contextMenu { sourceContextMenu(for: source) }
            }
        }
        .padding(Design.Spacing.cardInner)
    }

    private func flatSourceList(sources: [StatusSource]) -> some View {
        LazyVStack(spacing: Design.Spacing.listGap) {
            ForEach(sources) { source in
                sourceRow(for: source)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(source.id) }
                    .contextMenu { sourceContextMenu(for: source) }
            }
        }
        .padding(Design.Spacing.cardInner)
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

    // MARK: - Footer

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
                withAnimation(
                    reduceMotionAnimation(
                        Design.Timing.expand,
                        reduceMotion: reduceMotion
                    )
                ) {
                    showingAddSource.toggle()
                    newSourceName = ""
                    newSourceURL = ""
                    focusedField = showingAddSource ? .name : nil
                }
            } label: {
                Image(
                    systemName: showingAddSource
                        ? "xmark.circle.fill" : "plus.circle.fill"
                )
                .font(Design.Typography.caption)
                .foregroundStyle(
                    showingAddSource
                        ? .secondary : Color.accentColor
                )
            }
            .buttonStyle(.borderless)
            .help(showingAddSource ? "Cancel" : "Add source")
            .accessibilityLabel(
                showingAddSource
                    ? "Cancel adding source" : "Add new source"
            )

            Group {
                let c = service.sources.count
                if statusFilter == .all {
                    Text("\(c) source\(c == 1 ? "" : "s")")
                } else {
                    let f = filteredAndSortedSources.count
                    Text("\(f) of \(c) source\(c == 1 ? "" : "s")")
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
            .help(
                updateChecker.isUpdateAvailable
                    ? "Settings \u{2014} Update available (Cmd+,)"
                    : "Settings (Cmd+,)"
            )
            .accessibilityLabel(
                updateChecker.isUpdateAvailable
                    ? "Settings, update available" : "Settings"
            )
        }
        .padding(.horizontal, Design.Spacing.sectionH)
        .padding(.vertical, Design.Spacing.sectionV)
        .chromeBackground()
    }
}
