// Helpers.swift
// Date formatters/functions, indicator color/icon mappers, and version comparison.

import SwiftUI

// MARK: - Date Helpers

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

let isoFormatterNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

let displayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

func parseDate(_ str: String) -> Date? {
    isoFormatter.date(from: str) ?? isoFormatterNoFrac.date(from: str)
}

func formatDate(_ str: String) -> String {
    guard let d = parseDate(str) else { return str }
    return displayFormatter.string(from: d)
}

func relativeDate(_ str: String) -> String {
    guard let d = parseDate(str) else { return str }
    return relativeFormatter.localizedString(for: d, relativeTo: Date())
}

// MARK: - Indicator Helpers

func iconForIndicator(_ indicator: String) -> String {
    switch indicator {
    case "none": return "checkmark.circle.fill"
    case "minor": return "exclamationmark.triangle.fill"
    case "major": return "exclamationmark.octagon.fill"
    case "critical": return "xmark.octagon.fill"
    default: return "questionmark.circle"
    }
}

func colorForIndicator(_ indicator: String) -> Color {
    switch indicator {
    case "none": return .green
    case "minor": return .yellow
    case "major": return .orange
    case "critical": return .red
    default: return .secondary
    }
}

func colorForComponentStatus(_ status: String) -> Color {
    switch status {
    case "operational": return .green
    case "degraded_performance": return .yellow
    case "partial_outage": return .orange
    case "major_outage": return .red
    default: return .secondary
    }
}

func labelForComponentStatus(_ status: String) -> String {
    switch status {
    case "operational": return "Operational"
    case "degraded_performance": return "Degraded"
    case "partial_outage": return "Partial Outage"
    case "major_outage": return "Major Outage"
    default: return status
    }
}

// MARK: - Version Comparison

func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
    let aParts = a.split(separator: ".").compactMap { Int($0) }
    let bParts = b.split(separator: ".").compactMap { Int($0) }
    let count = max(aParts.count, bParts.count)
    for i in 0..<count {
        let aVal = i < aParts.count ? aParts[i] : 0
        let bVal = i < bParts.count ? bParts[i] : 0
        if aVal < bVal { return .orderedAscending }
        if aVal > bVal { return .orderedDescending }
    }
    return .orderedSame
}
