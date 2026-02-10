// Constants.swift
// Configuration values and design system for StatusBar.

import SwiftUI

// MARK: - Configuration

let kDefaultRefreshInterval: TimeInterval = 300

let kRefreshIntervalOptions: [(label: String, seconds: TimeInterval)] = [
    ("1 min", 60),
    ("2 min", 120),
    ("5 min", 300),
    ("10 min", 600),
    ("15 min", 900),
]

let kDefaultSources: [StatusSource] = [
    StatusSource(name: "Anthropic", baseURL: "https://status.anthropic.com"),
    StatusSource(name: "GitHub", baseURL: "https://www.githubstatus.com"),
    StatusSource(name: "Cloudflare", baseURL: "https://www.cloudflarestatus.com"),
]

let kGitHubRepo = "alexnodeland/StatusBar"

let kServiceCatalog: [CatalogEntry] = [
    CatalogEntry(name: "GitHub", url: "https://www.githubstatus.com", category: "Developer Tools"),
    CatalogEntry(name: "Cloudflare", url: "https://www.cloudflarestatus.com", category: "Infrastructure"),
    CatalogEntry(name: "Anthropic", url: "https://status.anthropic.com", category: "AI & ML"),
    CatalogEntry(name: "OpenAI", url: "https://status.openai.com", category: "AI & ML"),
    CatalogEntry(name: "AWS", url: "https://health.aws.amazon.com", category: "Cloud"),
    CatalogEntry(name: "Datadog", url: "https://status.datadoghq.com", category: "Observability"),
    CatalogEntry(name: "PagerDuty", url: "https://status.pagerduty.com", category: "Incident Management"),
    CatalogEntry(name: "Vercel", url: "https://www.vercel-status.com", category: "Developer Tools"),
    CatalogEntry(name: "Netlify", url: "https://www.netlifystatus.com", category: "Developer Tools"),
    CatalogEntry(name: "Twilio", url: "https://status.twilio.com", category: "Communication"),
    CatalogEntry(name: "Stripe", url: "https://status.stripe.com", category: "Payments"),
    CatalogEntry(name: "Braintree", url: "https://status.braintreepayments.com", category: "Payments"),
    CatalogEntry(name: "HashiCorp", url: "https://status.hashicorp.com", category: "Developer Tools"),
    CatalogEntry(name: "Atlassian", url: "https://status.atlassian.com", category: "Productivity"),
    CatalogEntry(name: "Bitbucket", url: "https://bitbucket.status.atlassian.com", category: "Developer Tools"),
    CatalogEntry(name: "Figma", url: "https://status.figma.com", category: "Design"),
    CatalogEntry(name: "Reddit", url: "https://www.redditstatus.com", category: "Social"),
    CatalogEntry(name: "Discord", url: "https://discordstatus.com", category: "Communication"),
    CatalogEntry(name: "Linear", url: "https://linearstatus.com", category: "Productivity"),
    CatalogEntry(name: "Notion", url: "https://status.notion.so", category: "Productivity"),
]

// MARK: - Retry Configuration

let kMaxRetries = 3
let kRetryBaseDelay: TimeInterval = 1.0
let kRetryMaxDelay: TimeInterval = 8.0

// MARK: - Notification Names

extension Notification.Name {
    static let statusBarNavigateToSource = Notification.Name("statusBarNavigateToSource")
    static let statusBarNavigateToSettingsTab = Notification.Name("statusBarNavigateToSettingsTab")
}

// MARK: - Design System

enum Design {
    enum Typography {
        static let body: Font = .body
        static let bodyMedium: Font = .body.weight(.medium)
        static let caption: Font = .caption
        static let captionMedium: Font = .caption.weight(.medium)
        static let captionSemibold: Font = .caption.weight(.semibold)
        static let micro: Font = .caption2
        static let mono: Font = .system(.caption, design: .monospaced)
    }

    enum Spacing {
        static let sectionH: CGFloat = 12
        static let rowH: CGFloat = 10
        static let cardInner: CGFloat = 8
        static let cellInner: CGFloat = 6
        static let badgeH: CGFloat = 6
        static let innerInset: CGFloat = 4
        static let sectionV: CGFloat = 8
        static let contentV: CGFloat = 6
        static let compactV: CGFloat = 4
        static let badgeV: CGFloat = 2
        static let listGap: CGFloat = 2
        static let sectionGap: CGFloat = 12
        static let standard: CGFloat = 10
    }

    enum Radius {
        static let card: CGFloat = 8
        static let row: CGFloat = 6
        static let small: CGFloat = 4
    }

    enum Depth {
        static let contentFill = Color.primary.opacity(0.04)
        static let contentStroke = Color.primary.opacity(0.08)
        static let secondaryFill = Color.primary.opacity(0.03)
        static let inlineFill = Color.primary.opacity(0.03)
    }

    enum Timing {
        static let hover = SwiftUI.Animation.easeOut(duration: 0.12)
        static let transition = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let expand = SwiftUI.Animation.easeInOut(duration: 0.2)
    }
}

// MARK: - Accessibility Helpers

func reduceMotionAnimation(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : animation
}

struct ConditionalTransition: ViewModifier {
    let transition: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        if reduceMotion { content } else { content.transition(transition) }
    }
}

extension View {
    func accessibleTransition(_ transition: AnyTransition) -> some View {
        modifier(ConditionalTransition(transition: transition))
    }
}
