// RootView.swift
// Root navigation view and navigation destination enum.

import SwiftUI

// MARK: - Navigation Destination

enum NavigationDestination: Equatable, Hashable {
    case sourceList
    case sourceDetail(UUID)
    case catalog
}

// MARK: - Root View

struct RootView: View {
    @ObservedObject var service: StatusService
    @ObservedObject var updateChecker: UpdateChecker
    @State private var destination: NavigationDestination = .sourceList
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            switch destination {
            case .sourceList:
                SourceListView(
                    service: service,
                    updateChecker: updateChecker,
                    onSelect: { id in
                        withAnimation(
                            reduceMotionAnimation(
                                Design.Timing.transition,
                                reduceMotion: reduceMotion
                            )
                        ) {
                            destination = .sourceDetail(id)
                        }
                    },
                    onSettings: {
                        SettingsWindowController.shared.open(
                            service: service,
                            updateChecker: updateChecker
                        )
                    },
                    onCatalog: {
                        withAnimation(
                            reduceMotionAnimation(
                                Design.Timing.transition,
                                reduceMotion: reduceMotion
                            )
                        ) {
                            destination = .catalog
                        }
                    }
                )

            case .sourceDetail(let sourceID):
                if let source = service.sources.first(
                    where: { $0.id == sourceID }
                ) {
                    SourceDetailView(
                        source: source,
                        state: service.state(for: source),
                        historyStore: service.historyStore,
                        onRefresh: {
                            Task { await service.refresh(source: source) }
                        },
                        onBack: {
                            withAnimation(
                                reduceMotionAnimation(
                                    Design.Timing.transition,
                                    reduceMotion: reduceMotion
                                )
                            ) {
                                destination = .sourceList
                            }
                        }
                    )
                } else {
                    Color.clear.onAppear {
                        withAnimation(
                            reduceMotionAnimation(
                                Design.Timing.transition,
                                reduceMotion: reduceMotion
                            )
                        ) {
                            destination = .sourceList
                        }
                    }
                }

            case .catalog:
                ServiceCatalogView(
                    service: service,
                    onBack: {
                        withAnimation(
                            reduceMotionAnimation(
                                Design.Timing.transition,
                                reduceMotion: reduceMotion
                            )
                        ) {
                            destination = .sourceList
                        }
                    }
                )
            }
        }
        .background {
            Button("") {
                withAnimation(
                    reduceMotionAnimation(
                        Design.Timing.transition,
                        reduceMotion: reduceMotion
                    )
                ) {
                    destination = .sourceList
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: 0, height: 0).opacity(0)
            .accessibilityHidden(true)

            Button("") { Task { await service.refreshAll() } }
                .keyboardShortcut("r", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)
                .accessibilityHidden(true)

            Button("") {
                SettingsWindowController.shared.open(
                    service: service,
                    updateChecker: updateChecker
                )
            }
            .keyboardShortcut(",", modifiers: .command)
            .frame(width: 0, height: 0).opacity(0)
            .accessibilityHidden(true)

            Button("") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .frame(width: 0, height: 0).opacity(0)
            .accessibilityHidden(true)
        }
        .frame(
            minWidth: 340, idealWidth: 380, maxWidth: 480,
            minHeight: 400, idealHeight: 520, maxHeight: 700
        )
        .onChange(of: destination) { _, newValue in
            let label: String
            switch newValue {
            case .sourceList:
                label = "Source list"
            case .sourceDetail(let id):
                if let source = service.sources.first(
                    where: { $0.id == id }
                ) {
                    label = "\(source.name) detail view"
                } else {
                    label = "Detail view"
                }
            case .catalog:
                label = "Service catalog"
            }
            AccessibilityNotification.Announcement(label).post()
        }
    }
}
