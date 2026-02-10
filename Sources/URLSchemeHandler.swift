// URLSchemeHandler.swift
// URL scheme parsing for statusbar:// deep links.

import Foundation

// MARK: - URL Route

enum URLRoute: Equatable {
    case open
    case openSource(String)
    case refresh
    case addSource(url: String, name: String?)
    case removeSource(name: String)
    case settings
    case settingsTab(String)

    // MARK: - Parsing

    static func parse(_ url: URL) -> URLRoute? {
        guard url.scheme == "statusbar" else { return nil }

        let host = url.host ?? ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch host {
        case "open": return parseOpen(queryItems)
        case "refresh": return .refresh
        case "add": return parseAdd(queryItems)
        case "remove": return parseRemove(queryItems)
        case "settings": return parseSettings(queryItems)
        default: return nil
        }
    }

    // MARK: - Route Parsers

    private static func queryValue(_ name: String, from items: [URLQueryItem]) -> String? {
        items.first(where: { $0.name == name })?.value
    }

    private static func parseOpen(_ queryItems: [URLQueryItem]) -> URLRoute {
        if let sourceName = queryValue("source", from: queryItems), !sourceName.isEmpty {
            return .openSource(sourceName)
        }
        return .open
    }

    private static func parseAdd(_ queryItems: [URLQueryItem]) -> URLRoute? {
        guard let urlString = queryValue("url", from: queryItems), !urlString.isEmpty else { return nil }
        let validation = validateSourceURL(urlString)
        guard validation.isAcceptable else { return nil }
        let name = queryValue("name", from: queryItems)
        return .addSource(url: urlString, name: name?.isEmpty == true ? nil : name)
    }

    private static func parseRemove(_ queryItems: [URLQueryItem]) -> URLRoute? {
        guard let name = queryValue("name", from: queryItems), !name.isEmpty else { return nil }
        return .removeSource(name: name)
    }

    private static func parseSettings(_ queryItems: [URLQueryItem]) -> URLRoute {
        if let tab = queryValue("tab", from: queryItems), !tab.isEmpty {
            return .settingsTab(tab)
        }
        return .settings
    }

    // MARK: - Execution

    @MainActor
    func execute(
        service: StatusService?,
        showPopover: () -> Void,
        openSettings: () -> Void
    ) {
        switch self {
        case .open:
            showPopover()
        case .openSource(let name):
            executeOpenSource(name, service: service, showPopover: showPopover)
        case .refresh:
            if let service { Task { await service.refreshAll() } }
        case .addSource(let urlString, let name):
            service?.addSource(name: name ?? URLRoute.deriveSourceName(from: urlString), baseURL: urlString)
        case .removeSource(let name):
            if let source = service?.findSource(named: name) { service?.removeSource(id: source.id) }
        case .settings:
            openSettings()
        case .settingsTab(let tab):
            executeSettingsTab(tab, openSettings: openSettings)
        }
    }

    @MainActor
    private func executeOpenSource(
        _ name: String,
        service: StatusService?,
        showPopover: () -> Void
    ) {
        showPopover()
        guard let source = service?.findSource(named: name) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: .statusBarNavigateToSource,
                object: nil,
                userInfo: ["sourceID": source.id]
            )
        }
    }

    @MainActor
    private func executeSettingsTab(_ tab: String, openSettings: () -> Void) {
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: .statusBarNavigateToSettingsTab,
                object: nil,
                userInfo: ["tab": tab]
            )
        }
    }

    // MARK: - Name Derivation

    static func deriveSourceName(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString
        }

        var name = host
        for prefix in ["www.", "status."] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }

        // Remove common status-page suffixes from domain
        let suffixesToStrip = ["status.com", "status.io", "status.net"]
        if let suffix = suffixesToStrip.first(where: { name.hasSuffix($0) }) {
            name = String(name.dropLast(suffix.count))
            while name.hasSuffix(".") || name.hasSuffix("-") {
                name = String(name.dropLast())
            }
        }

        // Remove TLD if still present (e.g. "example.com" -> "example")
        if let dotRange = name.range(of: ".", options: .backwards) {
            let afterDot = name[dotRange.upperBound...]
            if afterDot.count >= 2 && afterDot.count <= 6 && !afterDot.contains(".") {
                name = String(name[..<dotRange.lowerBound])
            }
        }

        guard !name.isEmpty else { return host }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
