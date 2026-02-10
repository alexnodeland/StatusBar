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

    private let barWidth: CGFloat = 2
    private let barGap: CGFloat = 1
    @ScaledMetric(relativeTo: .caption2) private var maxHeight: CGFloat = 12

    private func barHeight(for indicator: String) -> CGFloat {
        switch indicator {
        case "none": return 4
        case "minor": return 7
        case "major": return 10
        case "critical": return 12
        default: return 4
        }
    }

    private var issueCount: Int {
        checkpoints.filter { $0.indicator != "none" }.count
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: barGap) {
            ForEach(Array(checkpoints.suffix(30).enumerated()), id: \.offset) { _, checkpoint in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(colorForIndicator(checkpoint.indicator))
                    .frame(width: barWidth, height: barHeight(for: checkpoint.indicator))
            }
        }
        .frame(height: maxHeight, alignment: .center)
        .help("Last \(checkpoints.suffix(30).count) checks: \(issueCount) with issues")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status history: \(issueCount) of \(checkpoints.suffix(30).count) checks had issues")
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
            .font(Design.Typography.micro.weight(.medium))
            .padding(.horizontal, Design.Spacing.badgeH)
            .padding(.vertical, Design.Spacing.badgeV)
            .foregroundStyle(style == .muted ? Color.secondary : color)
            .background(style == .muted ? Color.primary.opacity(0.05) : color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Dividers

struct ChromeDivider: View {
    var body: some View { Divider().opacity(0.5) }
}

struct ContentDivider: View {
    var body: some View { Divider().opacity(0.3) }
}
