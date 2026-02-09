// SharedComponents.swift
// Reusable UI components: VisualEffectBackground, HoverEffect, GlassButtonStyle, GlassCard.

import SwiftUI

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

// MARK: - Hover Effect

struct HoverEffect: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering in
                withAnimation(Design.Timing.hover) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverEffect())
    }
}

// MARK: - Button Style

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Design.Typography.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.1) : Color.primary.opacity(0.05))
            )
    }
}

// MARK: - Sparkline View

struct SparklineView: View {
    let checkpoints: [StatusCheckpoint]

    private let barWidth: CGFloat = 2
    private let barGap: CGFloat = 1
    private let maxHeight: CGFloat = 12

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
    }
}

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }
}
