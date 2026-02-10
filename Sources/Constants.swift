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

let kDefaultSources = """
    Anthropic\thttps://status.anthropic.com
    GitHub\thttps://www.githubstatus.com
    Cloudflare\thttps://www.cloudflarestatus.com
    """

let kGitHubRepo = "alexnodeland/StatusBar"

let kServiceCatalog = """
    GitHub\thttps://www.githubstatus.com\tDeveloper Tools
    Cloudflare\thttps://www.cloudflarestatus.com\tInfrastructure
    Anthropic\thttps://status.anthropic.com\tAI & ML
    OpenAI\thttps://status.openai.com\tAI & ML
    AWS\thttps://health.aws.amazon.com\tCloud
    Datadog\thttps://status.datadoghq.com\tObservability
    PagerDuty\thttps://status.pagerduty.com\tIncident Management
    Vercel\thttps://www.vercel-status.com\tDeveloper Tools
    Netlify\thttps://www.netlifystatus.com\tDeveloper Tools
    Twilio\thttps://status.twilio.com\tCommunication
    Stripe\thttps://status.stripe.com\tPayments
    Braintree\thttps://status.braintreepayments.com\tPayments
    HashiCorp\thttps://status.hashicorp.com\tDeveloper Tools
    Atlassian\thttps://status.atlassian.com\tProductivity
    Bitbucket\thttps://bitbucket.status.atlassian.com\tDeveloper Tools
    Figma\thttps://status.figma.com\tDesign
    Reddit\thttps://www.redditstatus.com\tSocial
    Discord\thttps://discordstatus.com\tCommunication
    Linear\thttps://linearstatus.com\tProductivity
    Notion\thttps://status.notion.so\tProductivity
    """

// MARK: - App Notifications

enum StatusBarNotification {
    static let openSettings = Notification.Name("StatusBar.openSettings")
    /// Flag for first-open edge case: RootView checks this in .onAppear
    /// before the .onReceive subscription is active.
    static var settingsPending = false
}

// MARK: - Retry Configuration

let kMaxRetries = 3
let kRetryBaseDelay: TimeInterval = 1.0
let kRetryMaxDelay: TimeInterval = 8.0

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
