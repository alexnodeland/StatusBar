// SourceRowViews.swift
// Source row views and SourceListView extensions (context menu, footer).

import AppKit
import SwiftUI

// MARK: - Source Row

struct SourceRow: View {
    let source: StatusSource
    let state: SourceState
    var checkpoints: [StatusCheckpoint] = []

    var body: some View {
        HStack(spacing: Design.Spacing.standard) {
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

            // Status text owns the full line under the name — the sparkline
            // is a separate right-aligned column, so nothing ever truncates.
            VStack(alignment: .leading, spacing: Design.Spacing.listGap) {
                Text(source.name)
                    .font(Design.Typography.bodyMedium)
                    .lineLimit(1)

                if state.isStale, state.lastError != nil {
                    Text("\(state.statusDescription) (stale)")
                        .font(Design.Typography.dataMicro)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else if let error = state.lastError {
                    Text(error)
                        .font(Design.Typography.dataMicro)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    Text(state.statusDescription)
                        .font(Design.Typography.dataMicro)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: Design.Spacing.cardInner)

            if !checkpoints.isEmpty {
                SparklineView(checkpoints: checkpoints)
                    .layoutPriority(1)
            }

            if source.isSnoozed {
                Image(systemName: "bell.slash.fill")
                    .font(Design.Typography.micro)
                    .foregroundStyle(.tertiary)
                    .help("Notifications snoozed")
                    .accessibilityLabel("Notifications snoozed")
            }

            let activeCount = state.activeIncidents.count
            if activeCount > 0 {
                BadgeView(
                    text: "\(activeCount)",
                    color: colorForIndicator(state.indicator)
                )
            }

            if state.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12)
                    .accessibilityLabel("Loading")
            }

            Image(systemName: "chevron.right")
                .font(Design.Typography.micro)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, Design.Spacing.rowH)
        .padding(.vertical, Design.Spacing.sectionV)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous)
                .fill(
                    state.indicatorSeverity > 0
                        ? colorForIndicator(state.indicator).opacity(0.06)
                        : Color.clear)
        )
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(source.name), status: \(state.statusDescription)"
        )
        .accessibilityValue(activeIncidentsLabel(state))
        .accessibilityHint("Double tap to view details")
    }
}

// MARK: - Compact Source Row

struct CompactSourceRow: View {
    let source: StatusSource
    let state: SourceState

    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor

    var body: some View {
        HStack(spacing: Design.Spacing.cardInner) {
            if differentiateWithoutColor {
                Image(systemName: iconForIndicator(state.indicator))
                    .font(.system(size: 9))
                    .foregroundStyle(colorForIndicator(state.indicator))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 10)
            } else {
                Circle()
                    .fill(colorForIndicator(state.indicator))
                    .frame(width: 7, height: 7)
            }
            Text(source.name)
                .font(Design.Typography.caption)
                .lineLimit(1)
            Spacer()
            if source.isSnoozed {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Notifications snoozed")
            }
            if state.isStale {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 8))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, Design.Spacing.rowH)
        .padding(.vertical, Design.Spacing.compactV)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(source.name), status: \(state.statusDescription)"
        )
        .accessibilityValue(activeIncidentsLabel(state))
        .accessibilityHint("Double tap to view details")
    }
}

// MARK: - Helpers

private func activeIncidentsLabel(_ state: SourceState) -> String {
    let count = state.activeIncidents.count
    if count == 0 { return "No active incidents" }
    return "\(count) active incident\(count == 1 ? "" : "s")"
}

// MARK: - SourceListView Context Menu

extension SourceListView {
    @ViewBuilder
    func sourceContextMenu(
        for source: StatusSource
    ) -> some View {
        Button {
            Task { await service.refresh(source: source) }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }

        Button {
            editingSource = source
        } label: {
            Label("Edit\u{2026}", systemImage: "pencil")
        }

        Divider()

        snoozeMenu(for: source)

        Menu {
            ForEach(AlertLevel.allCases, id: \.self) { level in
                Button {
                    service.updateAlertLevel(
                        sourceID: source.id, level: level
                    )
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

        moveToGroupMenu(for: source)

        Divider()

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                source.baseURL, forType: .string
            )
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

    @ViewBuilder
    private func snoozeMenu(for source: StatusSource) -> some View {
        Menu {
            if source.isSnoozed {
                Button {
                    service.snooze(sourceID: source.id, until: nil)
                } label: {
                    Label("Unsnooze", systemImage: "bell")
                }
                Divider()
            }
            Button("For 1 Hour") {
                service.snooze(sourceID: source.id, until: Date().addingTimeInterval(3600))
            }
            Button("For 8 Hours") {
                service.snooze(sourceID: source.id, until: Date().addingTimeInterval(8 * 3600))
            }
            Button("For 24 Hours") {
                service.snooze(sourceID: source.id, until: Date().addingTimeInterval(24 * 3600))
            }
        } label: {
            Label(
                source.isSnoozed ? "Snoozed" : "Snooze",
                systemImage: source.isSnoozed ? "bell.slash.fill" : "bell.slash"
            )
        }
    }

    @ViewBuilder
    private func moveToGroupMenu(for source: StatusSource) -> some View {
        Menu {
            let groups = Set(
                service.sources.compactMap(\.group)
            ).sorted()
            ForEach(groups, id: \.self) { group in
                Button {
                    service.setGroup(
                        sourceID: source.id, group: group
                    )
                } label: {
                    if source.group == group {
                        Label(group, systemImage: "checkmark")
                    } else {
                        Text(group)
                    }
                }
            }
            if !groups.isEmpty {
                Divider()
            }
            Button {
                promptForNewGroup(sourceID: source.id)
            } label: {
                Label("New Group\u{2026}", systemImage: "plus")
            }
            if source.group != nil {
                Button("Remove from Group") {
                    service.setGroup(
                        sourceID: source.id, group: nil
                    )
                }
            }
        } label: {
            Label("Move to Group", systemImage: "folder")
        }
    }

    @ViewBuilder
    func groupContextMenu(for name: String) -> some View {
        Button {
            promptForRenameGroup(named: name)
        } label: {
            Label("Rename Group\u{2026}", systemImage: "pencil")
        }
        Button {
            service.ungroupAll(named: name)
        } label: {
            Label("Ungroup All", systemImage: "folder.badge.minus")
        }
    }

    func promptForRenameGroup(named oldName: String) {
        let alert = NSAlert()
        alert.messageText = "Rename Group"
        alert.informativeText = "Enter a new name for \u{201C}\(oldName)\u{201D}:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 200, height: 24)
        )
        field.stringValue = oldName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && name != oldName {
                service.renameGroup(from: oldName, to: name)
            }
        }
    }

    func promptForNewGroup(sourceID: UUID) {
        let alert = NSAlert()
        alert.messageText = "New Group"
        alert.informativeText = "Enter a name for the new group:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 200, height: 24)
        )
        field.placeholderString = "Group name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(
                in: .whitespaces
            )
            if !name.isEmpty {
                service.setGroup(sourceID: sourceID, group: name)
            }
        }
    }
}
