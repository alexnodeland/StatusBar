// OnboardingView.swift
// First-run welcome screen shown before any sources exist.

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var service: StatusService
    let onBrowseCatalog: () -> Void
    let onDone: () -> Void

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        VStack(spacing: Design.Spacing.sectionGap) {
            Spacer()

            Image(nsImage: Self.appIcon)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(spacing: Design.Spacing.cellInner) {
                Text("Welcome to StatusBar")
                    .font(.title3.weight(.semibold))
                Text("Every status page you care about,\nin one menu bar icon.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Design.Spacing.cardInner) {
                onboardingButton(
                    title: "Start with Popular Picks",
                    subtitle: "Anthropic, GitHub, and Cloudflare",
                    systemImage: "sparkles",
                    prominent: true
                ) {
                    service.applySources(kDefaultSources)
                    complete()
                    onDone()
                }

                onboardingButton(
                    title: "Browse the Catalog",
                    subtitle: "Pick from \(kServiceCatalog.count) popular services",
                    systemImage: "square.grid.2x2"
                ) {
                    complete()
                    onBrowseCatalog()
                }

                onboardingButton(
                    title: "Start Empty",
                    subtitle: "Add your own status pages, including self-hosted Gatus",
                    systemImage: "plus.circle"
                ) {
                    complete()
                    onDone()
                }
            }
            .padding(.horizontal, Design.Spacing.sectionH)

            Spacer()

            HStack(spacing: Design.Spacing.innerInset) {
                Image(systemName: "keyboard")
                    .font(Design.Typography.dataMicro)
                Text("tip: toggle this popover anytime with \u{2303}\u{2325}S")
                    .font(Design.Typography.dataMicro)
            }
            .foregroundStyle(.tertiary)
            .padding(.bottom, Design.Spacing.sectionH)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Read the icns from the bundle directly — NSApp.applicationIconImage
    // can serve a stale cached icon after the artwork changes.
    static let appIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "StatusBar", withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }()

    private func complete() {
        hasCompletedOnboarding = true
    }

    private func onboardingButton(
        title: String,
        subtitle: String,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.standard) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(prominent ? Color.green : Color.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Design.Typography.bodyMedium)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(Design.Typography.micro)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Design.Typography.micro)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, Design.Spacing.rowH)
            .padding(.vertical, Design.Spacing.sectionV)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                    .fill(prominent ? Color.green.opacity(0.12) : Design.Depth.contentFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                    .strokeBorder(
                        prominent ? Color.green.opacity(0.35) : Design.Depth.contentStroke,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
