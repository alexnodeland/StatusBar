// SourceDetailView.swift
// Detail view for a single status source, including components, incidents, and incident cards.

import SwiftUI

// MARK: - Source Detail View

struct SourceDetailView: View {
    let source: StatusSource
    let state: SourceState
    let onRefresh: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider().opacity(0.5)

            if state.isLoading && state.summary == nil {
                loadingView
            } else if let error = state.lastError, state.summary == nil {
                errorView(error)
            } else if state.summary != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if state.isStale, let error = state.lastError {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(Design.Typography.caption)
                                Text("Showing cached data — \(error)")
                                    .font(Design.Typography.micro)
                            }
                            .foregroundStyle(.white)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                        }

                        if !state.activeIncidents.isEmpty {
                            activeIncidentsSection
                        }
                        componentsSection
                        recentIncidentsSection
                    }
                    .padding(12)
                }
            }

            Divider().opacity(0.5)
            detailFooter
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(Design.Typography.body)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Back (Esc)")

            Image(systemName: iconForIndicator(state.indicator))
                .font(.title3)
                .foregroundStyle(colorForIndicator(state.indicator))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
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
            }

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(Design.Typography.body)
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Sections

    private var activeIncidentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Components")
                .font(Design.Typography.captionSemibold)
                .foregroundStyle(.secondary)

            if state.topLevelComponents.isEmpty {
                Text("No components reported")
                    .font(Design.Typography.micro)
                    .foregroundStyle(.tertiary)
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(state.topLevelComponents.enumerated()), id: \.element.id) { index, component in
                            ComponentRow(component: component)
                            if index < state.topLevelComponents.count - 1 {
                                Divider().opacity(0.3).padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(6)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Incidents")
                .font(Design.Typography.captionSemibold)
                .foregroundStyle(.secondary)

            let incidents = Array(state.recentIncidents.prefix(10))
            if let notice = providerLimitationNotice {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(Design.Typography.micro)
                    Text(notice)
                        .font(Design.Typography.micro)
                }
                .foregroundStyle(.tertiary)
                .padding(.vertical, 4)
            }

            if incidents.isEmpty {
                if providerLimitationNotice == nil {
                    Text("No recent incidents")
                        .font(Design.Typography.micro)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                }
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
            Text("Loading status\u{2026}")
                .font(Design.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text("Failed to load status")
                .font(Design.Typography.bodyMedium)
            Text(message)
                .font(Design.Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRefresh)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Component Row

struct ComponentRow: View {
    let component: SPComponent

    var body: some View {
        HStack {
            Circle()
                .fill(colorForComponentStatus(component.status))
                .frame(width: 7, height: 7)
            Text(component.name)
                .font(Design.Typography.caption)
                .foregroundStyle(.primary)
            Spacer()
            Text(labelForComponentStatus(component.status))
                .font(Design.Typography.micro)
                .foregroundStyle(colorForComponentStatus(component.status))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .hoverHighlight()
    }
}

// MARK: - Incident Card

struct IncidentCard: View {
    let incident: SPIncident
    let isActive: Bool
    @State private var isExpanded = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(impactColor)
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(incident.name)
                            .font(Design.Typography.captionMedium)
                            .lineLimit(isExpanded ? nil : 2)

                        HStack(spacing: 6) {
                            Text(statusBadge)
                                .font(Design.Typography.micro.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(statusBadgeColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(statusBadgeColor)

                            Text(relativeDate(incident.updatedAt))
                                .font(Design.Typography.micro)
                                .foregroundStyle(.quaternary)
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation(Design.Timing.expand) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(Design.Typography.micro)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }

                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
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
                            .padding(6)
                            .background(
                                Color.primary.opacity(0.03),
                                in: RoundedRectangle(cornerRadius: 4)
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
                    .transition(.opacity)
                }
            }
            .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? impactColor.opacity(0.3) : Color.clear, lineWidth: 0.5)
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
