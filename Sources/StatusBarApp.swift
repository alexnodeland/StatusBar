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

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var service: StatusService?
    var updateChecker: UpdateChecker?
    private var statusItem: NSStatusItem?
    private weak var popoverPanel: NSPanel?
    private var eventMonitor: Any?

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About StatusBar", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit StatusBar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }()

    /// Lazily resolve the NSStatusItem created by MenuBarExtra via KVC.
    @discardableResult
    func resolveStatusItem() -> NSStatusItem? {
        if let statusItem { return statusItem }
        statusItem =
            NSApp.windows
            .compactMap({ $0.value(forKey: "statusItem") as? NSStatusItem })
            .first
        return statusItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestPermission()
        HookManager.shared.ensureHooksDirectory()

        HotkeyManager.shared.onToggle = { [weak self] in
            self?.resolveStatusItem()?.button?.performClick(nil)
        }
        HotkeyManager.shared.register()

        // Try to resolve now; resolveStatusItem() retries lazily on each use
        resolveStatusItem()

        // Right-click on status bar icon shows context menu
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self,
                let button = self.resolveStatusItem()?.button,
                event.window == button.window
            else {
                return event
            }
            self.showContextMenu()
            return nil
        }

        // Track the MenuBarExtra popover panel so we can dismiss it precisely
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard popoverPanel == nil,
            let panel = notification.object as? NSPanel,
            panel != statusItem?.button?.window
        else { return }
        popoverPanel = panel
    }

    private func showContextMenu() {
        popoverPanel?.orderOut(nil)

        statusItem?.menu = contextMenu
        statusItem?.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    @MainActor @objc func openSettings() {
        guard let service, let updateChecker else { return }
        SettingsWindowController.shared.open(service: service, updateChecker: updateChecker)
    }

    @objc private func openAbout() {
        if let url = URL(string: "https://github.com/\(kGitHubRepo)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - URL Scheme Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    @MainActor private func handleURL(_ url: URL) {
        guard let route = URLRoute.parse(url) else { return }

        switch route {
        case .open:
            showPopover()

        case .openSource(let name):
            showPopover()
            guard let service else { return }
            if let source = service.sources.first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(
                        name: .statusBarNavigateToSource,
                        object: nil,
                        userInfo: ["sourceID": source.id]
                    )
                }
            }

        case .refresh:
            guard let service else { return }
            Task { await service.refreshAll() }

        case .addSource(let urlString, let name):
            guard let service else { return }
            let sourceName = name ?? URLRoute.deriveSourceName(from: urlString)
            service.addSource(name: sourceName, baseURL: urlString)

        case .removeSource(let name):
            guard let service else { return }
            if let source = service.sources.first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                service.removeSource(id: source.id)
            }

        case .settings:
            openSettings()

        case .settingsTab(let tab):
            openSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: .statusBarNavigateToSettingsTab,
                    object: nil,
                    userInfo: ["tab": tab]
                )
            }
        }
    }

    func showPopover() {
        resolveStatusItem()?.button?.performClick(nil)
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
                .onAppear {
                    appDelegate.service = service
                    appDelegate.updateChecker = updateChecker
                    #if canImport(Sparkle)
                        updateChecker.setupSparkle()
                    #endif
                }
        } label: {
            MenuBarLabel(service: service)
        }
        .menuBarExtraStyle(.window)
    }
}
