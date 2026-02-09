<p align="center">
  <img src="icon.png" width="128" alt="StatusBar icon">
</p>

<h1 align="center">StatusBar</h1>

<p align="center">
  A single-file SwiftUI menu bar app that monitors multiple status pages simultaneously. Supports <a href="https://www.atlassian.com/software/statuspage">Atlassian Statuspage</a>, <a href="https://incident.io">incident.io</a>, and <a href="https://instatus.com">Instatus</a>-powered pages with automatic provider detection.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange" alt="Swift 5.9+">
  <a href="https://github.com/alexnodeland/StatusBar/releases/latest"><img src="https://img.shields.io/github/v/release/alexnodeland/StatusBar" alt="GitHub Release"></a>
  <a href="https://alexnodeland.github.io/StatusBar/"><img src="https://img.shields.io/badge/docs-website-blue" alt="Docs"></a>
</p>

## ✨ Features

🟢 **Monitoring** — Menu bar icon reflects the worst status across all sources (green → yellow → orange → red) with a badge showing how many have issues. Drill into any source to see components, active incidents, and update timelines.

📋 **Sources** — Add and remove sources visually with **+** / **−** buttons, or bulk import/export as TSV files. Sources refresh concurrently on a configurable interval (1–15 min).

⚙️ **Settings** — Status change notifications, automatic update checks, and launch at login. Runs as a pure menu bar agent with no Dock icon.

## 📦 Install

Grab the latest universal binary from the [Releases page](https://github.com/alexnodeland/StatusBar/releases/latest):

1. Download `StatusBar-vX.Y.Z-universal.zip`
2. Extract and drag `StatusBar.app` to `/Applications`
3. On first launch, right-click → **Open** to bypass Gatekeeper (ad-hoc signed, not notarized)

Runs natively on both Apple Silicon and Intel Macs.

## 🔗 Sources

The app ships with three default sources:

| Name | URL |
|------|-----|
| Anthropic | `https://status.anthropic.com` |
| GitHub | `https://www.githubstatus.com` |
| Cloudflare | `https://www.cloudflarestatus.com` |

Open **Settings** and click **+** to add more. The app auto-detects the provider — no configuration needed.

<details>
<summary>Example sources</summary>

| Service | Provider | URL |
|---------|----------|-----|
| Atlassian | Atlassian Statuspage | `https://status.atlassian.com` |
| Datadog | Atlassian Statuspage | `https://status.datadoghq.com` |
| Linear | incident.io | `https://linearstatus.com` |
| Notion | Atlassian Statuspage | `https://status.notion.so` |
| Zed | Instatus | `https://status.zed.dev` |
| Deno | Instatus | `https://denostatus.com` |

</details>

> **Note:** Incident history detail varies by provider. Atlassian Statuspage sources include full incident timelines. incident.io and Instatus sources may have limited or unavailable incident details due to provider API restrictions.

Sources are persisted via `@AppStorage` and survive restarts.

## 🛠 Development

```bash
brew install swiftlint swift-format   # One-time setup
make build                            # Dev build
make test                             # Run tests
make check                            # Full CI check (lint + format + test)
```

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for the full development guide.

## 🤝 Contributing

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for build instructions, architecture overview, and roadmap.
