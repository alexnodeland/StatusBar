// SourceDetailView.swift
// Detail view for a single status source, including components, incidents, and incident cards.

import SwiftUI

// MARK: - Source Detail View

struct SourceDetailView: View {
    let source: StatusSource
    let state: SourceState
    var historyStore: HistoryStore?
    let onRefresh: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            ChromeDivider()

            if state.isLoading && state.summary == nil {
                loadingView
            } else if let error = state.lastError, state.summary == nil {
                errorView(error)
            } else if state.summary != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.sectionGap) {
                        if state.isStale, let error = state.lastError {
                            HStack(spacing: Design.Spacing.cellInner) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(Design.Typography.caption)
                                Text("Showing cached data — \(error)")
                                    .font(Design.Typography.micro)
                            }
                            .foregroundStyle(.orange)
                            .padding(Design.Spacing.cardInner)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: Design.Radius.row))
                        }

                        if !state.activeIncidents.isEmpty {
                            activeIncidentsSection
                        }
                        componentsSection
                        recentIncidentsSection
                    }
                    .padding(Design.Spacing.sectionH)
                }
            }

            if historyStore != nil {
                ContentDivider()
                uptimeTrendRow
            }
            ChromeDivider()
            detailFooter
        }
    }

    // MARK: - Uptime Trend

    private var uptimeTrendRow: some View {
        HStack(spacing: Design.Spacing.cardInner) {
            Text("Uptime")
                .font(Design.Typography.captionSemibold)
                .foregroundStyle(.secondary)
            Spacer()
            uptimeBadge(label: "24h", since: Date().addingTimeInterval(-24 * 60 * 60))
            uptimeBadge(label: "7d", since: Date().addingTimeInterval(-7 * 24 * 60 * 60))
            uptimeBadge(label: "30d", since: Date().addingTimeInterval(-30 * 24 * 60 * 60))
        }
        .padding(.horizontal, Design.Spacing.sectionH)
        .padding(.vertical, Design.Spacing.contentV)
        .background(Design.Depth.secondaryFill)
    }

    private func uptimeBadge(label: String, since: Date) -> some View {
        let fraction = historyStore?.uptimeFraction(for: source.id, since: since) ?? 1.0
        let pct = fraction * 100
        let color = uptimeColor(fraction)
        return HStack(spacing: 3) {
            if differentiateWithoutColor {
                Image(systemName: uptimeIcon(fraction))
                    .font(Design.Typography.micro)
                    .foregroundStyle(color)
            }
            Text(label)
                .font(Design.Typography.micro)
                .foregroundStyle(.tertiary)
            Text(String(format: "%.1f%%", pct))
                .font(Design.Typography.micro.weight(.medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, Design.Spacing.badgeH)
        .padding(.vertical, Design.Spacing.badgeV)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityLabel("\(label) uptime: \(String(format: "%.1f", pct)) percent")
        .accessibilityValue(String(format: "%.1f percent", pct))
    }

    private func uptimeColor(_ fraction: Double) -> Color {
        if fraction > 0.995 { return .green }
        if fraction > 0.95 { return .yellow }
        if fraction > 0.90 { return .orange }
        return .red
    }

    private func uptimeIcon(_ fraction: Double) -> String {
        if fraction > 0.995 { return "checkmark.circle.fill" }
        if fraction > 0.95 { return "exclamationmark.triangle.fill" }
        if fraction > 0.90 { return "exclamationmark.octagon.fill" }
        return "xmark.octagon.fill"
    }

    private var detailHeader: some View {
        HStack(spacing: Design.Spacing.standard) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(Design.Typography.body)
            }
            .buttonStyle(.borderless)
            .help("Back")
            .accessibilityLabel("Back to source list")

            Image(systemName: iconForIndicator(state.indicator))
                .font(.title3)
                .foregroundStyle(colorForIndicator(state.indicator))
                .symbolRenderingMode(.hierarchical)
                .accessibilityLabel("Status: \(state.indicator)")

            VStack(alignment: .leading, spacing: Design.Spacing.listGap) {
                Text(source.name)
                    .font(Design.Typography.bodyMedium)
                Text(state.statusDescription)
                    .font(Design.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if state.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
                    .accessibilityLabel("Loading")
            }

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(Design.Typography.body)
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .accessibilityLabel("Refresh \(source.name)")
        }
        .padding(Design.Spacing.sectionH)
        .chromeBackground()
    }

    // MARK: - Sections

    private var activeIncidentsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.cardInner) {
            Label("Active Incidents", systemImage: "exclamationmark.triangle.fill")
                .font(Design.Typography.captionSemibold)
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)

            ForEach(state.activeIncidents) { incident in
                IncidentCard(incident: incident, isActive: true)
            }
        }
    }

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.cellInner) {
            Text("Components")
                .font(Design.Typography.captionSemibold)
                .foregroundStyle(.secondary)

            if state.topLevelComponents.isEmpty {
                Text("No components reported")
                    .font(Design.Typography.micro)
                    .foregroundStyle(.tertiary)
            } else {
                ContentCard {
                    VStack(spacing: 0) {
                        ForEach(Array(state.topLevelComponents.enumerated()), id: \.element.id) { index, component in
                            ComponentRow(component: component)
                            if index < state.topLevelComponents.count - 1 {
                                ContentDivider().padding(.horizontal, Design.Spacing.innerInset)
                            }
                        }
                    }
                    .padding(Design.Spacing.cellInner)
                }
            }
        }
    }

    private var providerLimitationNotice: String? {
        switch state.provider {
        case .instatus:
            return "Incident history is not available for this status page provider"
        case .incidentIO, .incidentIOCompat:
            return "Incident details are not available for this status page provider"
        default:
            return nil
        }
    }

    private var recentIncidentsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.cardInner) {
            Text("Recent Incidents")
                .font(Design.Typography.captionSemibold)
                .foregroundStyle(.secondary)

            let incidents = Array(state.recentIncidents.prefix(10))
            if let notice = providerLimitationNotice {
                HStack(spacing: Design.Spacing.innerInset) {
                    Image(systemName: "info.circle")
                        .font(Design.Typography.micro)
                    Text(notice)
                        .font(Design.Typography.micro)
                }
                .foregroundStyle(.tertiary)
                .padding(.vertical, Design.Spacing.innerInset)
            }

            if incidents.isEmpty {
                if providerLimitationNotice == nil {
                    Text("No recent incidents")
                        .font(Design.Typography.micro)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, Design.Spacing.innerInset)
                }
            } else {
                ForEach(incidents) { incident in
                    IncidentCard(incident: incident, isActive: false)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: Design.Spacing.sectionGap) {
            ProgressView()
                .accessibilityLabel("Loading")
            Text("Loading \(source.name)\u{2026}")
                .font(Design.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading status for \(source.name)")
    }

    private func errorView(_ message: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.sectionGap) {
                ContentCard {
                    VStack(alignment: .leading, spacing: Design.Spacing.cardInner) {
                        HStack(spacing: Design.Spacing.cellInner) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .symbolRenderingMode(.hierarchical)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Failed to load status")
                                    .font(Design.Typography.bodyMedium)
                                Text(source.baseURL)
                                    .font(Design.Typography.micro)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Text(message)
                            .font(Design.Typography.caption)
                            .foregroundStyle(.secondary)

                        if let last = state.lastSuccessfulRefresh {
                            Text("Last successful check: \(relativeFormatter.localizedString(for: last, relativeTo: Date()))")
                                .font(Design.Typography.micro)
                                .foregroundStyle(.tertiary)
                        }

                        Button("Retry", action: onRefresh)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(Design.Spacing.sectionH)
                }
            }
            .padding(Design.Spacing.sectionH)
        }
    }

    private var detailFooter: some View {
        HStack {
            if let last = state.lastRefresh {
                Text("Updated \(relativeFormatter.localizedString(for: last, relativeTo: Date()))\(state.isStale ? " (stale)" : "")")
                    .font(Design.Typography.micro)
                    .foregroundStyle(state.isStale ? Color.orange : Color.secondary.opacity(0.3))
            }
            Spacer()
            Button {
                if let url = URL(string: source.baseURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open Status Page", systemImage: "arrow.up.forward")
                    .font(Design.Typography.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open \(source.name) status page in browser")
        }
        .padding(.horizontal, Design.Spacing.sectionH)
        .padding(.vertical, Design.Spacing.sectionV)
        .chromeBackground()
    }
}

// MARK: - Component Row

struct ComponentRow: View {
    let component: SPComponent

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        HStack {
            if differentiateWithoutColor {
                Image(systemName: miniIconForComponentStatus(component.status))
                    .font(Design.Typography.micro)
                    .foregroundStyle(colorForComponentStatus(component.status))
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .fill(colorForComponentStatus(component.status))
                    .frame(width: 7, height: 7)
            }
            Text(component.name)
                .font(Design.Typography.caption)
                .foregroundStyle(.primary)
            Spacer()
            Text(labelForComponentStatus(component.status))
                .font(Design.Typography.micro)
                .foregroundStyle(colorForComponentStatus(component.status))
        }
        .padding(.vertical, Design.Spacing.compactV)
        .padding(.horizontal, Design.Spacing.innerInset)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(component.name), \(labelForComponentStatus(component.status))")
        .accessibilityValue(labelForComponentStatus(component.status))
    }
}

// MARK: - Incident Card

struct IncidentCard: View {
    let incident: SPIncident
    let isActive: Bool
    @State private var isExpanded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: Design.Spacing.cellInner) {
                    if differentiateWithoutColor {
                        Image(systemName: miniIconForImpact(incident.impact))
                            .font(Design.Typography.micro)
                            .foregroundStyle(impactColor)
                            .frame(width: 10, height: 10)
                            .padding(.top, 4)
                    } else {
                        Circle()
                            .fill(impactColor)
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(incident.name)
                            .font(Design.Typography.captionMedium)
                            .lineLimit(isExpanded ? nil : 2)

                        HStack(spacing: Design.Spacing.cellInner) {
                            BadgeView(text: statusBadge, color: statusBadgeColor)

                            Text(relativeDate(incident.updatedAt))
                                .font(Design.Typography.micro)
                                .foregroundStyle(.quaternary)
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(Design.Typography.micro)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(reduceMotionAnimation(Design.Timing.expand, reduceMotion: reduceMotion)) {
                        isExpanded.toggle()
                    }
                }

                if isExpanded {
                    VStack(alignment: .leading, spacing: Design.Spacing.cellInner) {
                        ForEach(incident.incidentUpdates.prefix(5)) { update in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(update.status.capitalized)
                                        .font(Design.Typography.micro.weight(.semibold))
                                    Spacer()
                                    Text(formatDate(update.createdAt))
                                        .font(Design.Typography.micro)
                                        .foregroundStyle(.quaternary)
                                }
                                Text(update.body)
                                    .font(Design.Typography.micro)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                            .padding(Design.Spacing.cellInner)
                            .background(
                                Design.Depth.inlineFill,
                                in: RoundedRectangle(cornerRadius: Design.Radius.small)
                            )
                        }

                        if let link = incident.shortlink, let url = URL(string: link) {
                            Button("View on Status Page") {
                                NSWorkspace.shared.open(url)
                            }
                            .font(Design.Typography.micro)
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.leading, 14)
                    .accessibleTransition(.opacity)
                }
            }
            .padding(Design.Spacing.cardInner)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(isActive ? impactColor.opacity(0.3) : Color.clear, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(incident.name), \(incident.status)")
        .accessibilityValue("\(incident.impact) impact, \(incident.status)")
        .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")
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
