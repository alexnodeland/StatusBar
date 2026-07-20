# Privacy Policy

**StatusBar sends zero telemetry.** No analytics, no crash reporting, no tracking of any kind.

## What the app does on the network

- **Status page requests.** StatusBar polls the status pages you configure (e.g. `https://www.githubstatus.com`) directly from your Mac. Those requests go straight to the status page provider — no intermediary servers. Providers see the same request they'd see from your browser.
- **Update checks.** If "Check for updates automatically" is enabled, StatusBar queries the GitHub Releases API for the latest version. This can be disabled in Settings → Updates.
- **Webhooks and hooks.** If you configure outbound webhooks or shell hooks, StatusBar sends notifications to endpoints *you* specify. Nothing is sent anywhere by default.

## What is stored, and where

All configuration (sources, settings, webhook URLs) and status history is stored locally on your Mac — in `UserDefaults` and `~/Library/Application Support/StatusBar/`. Nothing is synced or uploaded.

Webhook URLs may contain secrets; they are included in configuration exports you create, and the app warns you about this in Settings → Data.

## Contact

Questions? Email [alex@ournature.studio](mailto:alex@ournature.studio) or open an issue on [GitHub](https://github.com/alexnodeland/StatusBar/issues).
