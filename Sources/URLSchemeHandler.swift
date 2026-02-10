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
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        func queryValue(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        switch host {
        case "open":
            if let sourceName = queryValue("source"), !sourceName.isEmpty {
                return .openSource(sourceName)
            }
            return .open

        case "refresh":
            return .refresh

        case "add":
            guard let urlString = queryValue("url"), !urlString.isEmpty else { return nil }
            let validation = validateSourceURL(urlString)
            guard validation.isAcceptable else { return nil }
            let name = queryValue("name")
            return .addSource(url: urlString, name: name?.isEmpty == true ? nil : name)

        case "remove":
            guard let name = queryValue("name"), !name.isEmpty else { return nil }
            return .removeSource(name: name)

        case "settings":
            if let tab = queryValue("tab"), !tab.isEmpty {
                return .settingsTab(tab)
            }
            return .settings

        default:
            return nil
        }
    }

    // MARK: - Name Derivation

    static func deriveSourceName(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString
        }

        // Remove common prefixes
        var name = host
        if name.hasPrefix("www.") {
            name = String(name.dropFirst(4))
        }
        if name.hasPrefix("status.") {
            name = String(name.dropFirst(7))
        }

        // Remove common status-page suffixes from domain
        let suffixesToStrip = ["status.com", "status.io", "status.net"]
        for suffix in suffixesToStrip {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                // Remove trailing dot or hyphen
                while name.hasSuffix(".") || name.hasSuffix("-") {
                    name = String(name.dropLast())
                }
                break
            }
        }

        // Remove TLD if still present (e.g. "example.com" -> "example")
        if let dotRange = name.range(of: ".", options: .backwards) {
            let afterDot = name[dotRange.upperBound...]
            // Only strip if it looks like a TLD (2-6 chars, no dots)
            if afterDot.count >= 2 && afterDot.count <= 6 && !afterDot.contains(".") {
                name = String(name[..<dotRange.lowerBound])
            }
        }

        // Capitalize first letter
        guard !name.isEmpty else { return host }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
