// SharedComponents.swift
// Reusable UI components: HoverEffect, ContentCard, BadgeView, dividers.

import SwiftUI

// MARK: - Hover Effect

struct HoverEffect: ViewModifier {
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.row))
            .onHover { hovering in
                if reduceMotion {
                    isHovered = hovering
                } else {
                    withAnimation(Design.Timing.hover) { isHovered = hovering }
                }
            }
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverEffect())
    }
}

// MARK: - Sparkline View

struct SparklineView: View {
    let checkpoints: [StatusCheckpoint]

    private let barWidth: CGFloat = 3
    private let barGap: CGFloat = 2
    @ScaledMetric(relativeTo: .caption2) private var maxHeight: CGFloat = 13

    private func barHeight(for indicator: String) -> CGFloat {
        switch indicator {
        case "none": return 7
        case "minor": return 10
        case "major": return 12
        case "critical": return 13
        default: return 7
        }
    }

    private var issueCount: Int {
        checkpoints.filter { $0.indicator != "none" }.count
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: barGap) {
            ForEach(Array(checkpoints.suffix(24).enumerated()), id: \.offset) { _, checkpoint in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(colorForIndicator(checkpoint.indicator))
                    .opacity(checkpoint.indicator == "none" ? 0.85 : 1)
                    .frame(width: barWidth, height: barHeight(for: checkpoint.indicator))
            }
        }
        .frame(height: maxHeight, alignment: .center)
        .help("Last \(checkpoints.suffix(24).count) checks: \(issueCount) with issues")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status history: \(issueCount) of \(checkpoints.suffix(24).count) checks had issues")
        .accessibilityValue(issueCount == 0 ? "No issues" : "\(issueCount) issues detected")
    }
}

// MARK: - Content Card

struct ContentCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                Design.Depth.contentFill,
                in: RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                    .stroke(Design.Depth.contentStroke, lineWidth: 0.5)
            )
    }
}

// MARK: - Chrome Background (Liquid Glass)

extension View {
    func chromeBackground() -> some View {
        self.glassEffect(.regular, in: .rect)
    }
}

// MARK: - Badge View

struct BadgeView: View {
    let text: String
    let color: Color
    var style: BadgeStyle = .standard

    enum BadgeStyle { case standard, muted }

    var body: some View {
        Text(text)
            .font(Design.Typography.dataMicroMedium)
            .padding(.horizontal, Design.Spacing.badgeH)
            .padding(.vertical, Design.Spacing.badgeV)
            .foregroundStyle(style == .muted ? Color.secondary : color)
            .background(style == .muted ? Color.primary.opacity(0.05) : color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Aggregate Tick Strip

/// One tick per source, colored by current status — the popover header's
/// at-a-glance overview (mirrors the marketing site's signature strip).
struct AggregateTickStrip: View {
    let indicators: [String]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(indicators.enumerated()), id: \.offset) { _, indicator in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(colorForIndicator(indicator))
                    .opacity(indicator == "none" ? 0.85 : 1)
                    .frame(width: 4, height: indicator == "none" ? 10 : 13)
            }
        }
        .frame(height: 13, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let issues = indicators.filter { $0 != "none" && $0 != "unknown" }.count
        return issues == 0
            ? "All \(indicators.count) sources operational"
            : "\(issues) of \(indicators.count) sources with issues"
    }
}

// MARK: - Dividers

struct ChromeDivider: View {
    var body: some View { Divider().opacity(0.5) }
}

struct ContentDivider: View {
    var body: some View { Divider().opacity(0.3) }
}
