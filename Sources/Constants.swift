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

// MARK: - Retry Configuration

let kMaxRetries = 3
let kRetryBaseDelay: TimeInterval = 1.0
let kRetryMaxDelay: TimeInterval = 8.0

// MARK: - Design System

enum Design {
    enum Typography {
        static let body = Font.system(size: 13)
        static let bodyMedium = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11)
        static let captionMedium = Font.system(size: 11, weight: .medium)
        static let captionSemibold = Font.system(size: 11, weight: .semibold)
        static let micro = Font.system(size: 10)
        static let mono = Font.system(size: 11, design: .monospaced)
    }

    enum Timing {
        static let hover = SwiftUI.Animation.easeOut(duration: 0.12)
        static let transition = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let expand = SwiftUI.Animation.easeInOut(duration: 0.2)
    }
}
