// AppleScriptBridge.swift
// AppleScript / Cocoa Scripting support — ScriptableSource wrapper,
// AppDelegate KVC extension, and NSScriptCommand subclasses.

import AppKit

// MARK: - Scripting Bridge Reference

/// Shared reference for AppleScript commands.
/// SwiftUI's @NSApplicationDelegateAdaptor wraps the delegate in a proxy,
/// so `NSApp.delegate as? AppDelegate` fails. This provides a direct path.
enum ScriptBridge {
    nonisolated(unsafe) static weak var service: StatusService?
}

// MARK: - ScriptableSource (NSObject wrapper for AppleScript)

@objc(ScriptableSource)
class ScriptableSource: NSObject {
    @objc let uniqueID: String
    @objc let name: String
    @objc let url: String
    @objc let status: String
    @objc let statusDescription: String
    @objc let alertLevel: String
    @objc let group: String

    init(source: StatusSource, state: SourceState) {
        self.uniqueID = source.id.uuidString
        self.name = source.name
        self.url = source.baseURL
        self.status = state.indicator
        self.statusDescription = state.statusDescription
        self.alertLevel = source.alertLevel.rawValue
        self.group = source.group ?? ""
        super.init()
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let appDescription = NSApp.classDescription as? NSScriptClassDescription else {
            return nil
        }
        return NSNameSpecifier(
            containerClassDescription: appDescription,
            containerSpecifier: nil,
            key: "scriptableSources",
            name: self.name
        )
    }
}

// MARK: - AppDelegate KVC Extension

@MainActor
extension AppDelegate {
    @objc var scriptableSources: [ScriptableSource] {
        guard let service else { return [] }
        return service.sources.map { source in
            ScriptableSource(source: source, state: service.state(for: source))
        }
    }

    @objc var worstStatus: String {
        service?.worstIndicator ?? "unknown"
    }

    @objc var scriptableIssueCount: Int {
        service?.issueCount ?? 0
    }

    @objc func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        switch key {
        case "scriptableSources", "worstStatus", "scriptableIssueCount":
            return true
        default:
            return false
        }
    }
}

// MARK: - Refresh Command

@objc(RefreshCommand)
class RefreshCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let service = ScriptBridge.service else {
            scriptErrorNumber = 1
            scriptErrorString = "StatusBar service not available"
            return nil
        }
        Task { @MainActor in
            await service.refreshAll()
        }
        return nil
    }
}

// MARK: - Add Source Command

@objc(AddSourceCommand)
class AddSourceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let urlString = directParameter as? String, !urlString.isEmpty else {
            scriptErrorNumber = 1
            scriptErrorString = "URL is required"
            return nil
        }

        let validation = validateSourceURL(urlString)
        guard validation.isAcceptable else {
            scriptErrorNumber = 2
            scriptErrorString = "Invalid URL: \(urlString)"
            return nil
        }

        guard let service = ScriptBridge.service else {
            scriptErrorNumber = 1
            scriptErrorString = "StatusBar service not available"
            return nil
        }

        let name: String
        if let providedName = evaluatedArguments?["name"] as? String, !providedName.isEmpty {
            name = providedName
        } else {
            name = URLRoute.deriveSourceName(from: urlString)
        }

        Task { @MainActor in
            service.addSource(name: name, baseURL: urlString)
        }
        return nil
    }
}

// MARK: - Remove Source Command

@objc(RemoveSourceCommand)
class RemoveSourceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let sourceName = directParameter as? String, !sourceName.isEmpty else {
            scriptErrorNumber = 1
            scriptErrorString = "Source name is required"
            return nil
        }

        guard let service = ScriptBridge.service else {
            scriptErrorNumber = 1
            scriptErrorString = "StatusBar service not available"
            return nil
        }

        Task { @MainActor in
            guard let source = service.findSource(named: sourceName) else { return }
            service.removeSource(id: source.id)
        }
        return nil
    }
}
