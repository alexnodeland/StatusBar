// StatusBarApp.swift
// A macOS menu bar app that monitors multiple Atlassian Statuspage-powered status pages.
// Features native glass UI, status change notifications, and optimized polling.
//
// Requirements: macOS 14+ (Sonoma), Swift 5.9+
//
// Build & Run:
//   ./build.sh
//   open ./build/StatusBar.app

import SwiftUI

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @ObservedObject var service: StatusService

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: service.menuBarIcon)
            if service.issueCount > 0 {
                Text("\(service.issueCount)")
                    .font(.caption2.monospacedDigit())
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestPermission()
    }
}

// MARK: - App Entry Point

@main
struct StatusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var service = StatusService()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        MenuBarExtra {
            RootView(service: service, updateChecker: updateChecker)
        } label: {
            MenuBarLabel(service: service)
        }
        .menuBarExtraStyle(.window)
    }
}
