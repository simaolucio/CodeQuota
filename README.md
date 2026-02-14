# CodeQuota

A native macOS menu bar app that monitors your AI service usage limits in real time. Supports **Claude Pro/Max** (Anthropic) and **GitHub Copilot** premium request tracking.

## Features

- Live usage tracking directly in the menu bar (colored status circle + percentage)
- **Claude**: 5-hour session, weekly all-models, and weekly Sonnet usage monitoring
- **Copilot**: Monthly premium request usage tracking per model
- Configurable menu bar metric — choose which usage stat to display
- Auto-refresh every 30 seconds
- Transparent popover with system vibrancy
- Color-coded progress bars: green (<50%), yellow (50-80%), red (>80%)

## Installation

### Prerequisites
- macOS 13.0 or later
- Xcode 15.0 or later

### Building from Source

1. Clone this repository
2. Open `CodeQuota.xcodeproj` in Xcode
3. Build and run (Cmd+R)

## Setup

### Anthropic (Claude)

1. Launch the app — it appears in your menu bar
2. Click the menu bar icon and go to **Settings**
3. Click **Connect to Anthropic** — this opens the Anthropic authorization page in your browser
4. Authorize the app, then copy the code shown on the page
5. Paste the code back into the app and click **Connect**

### GitHub (Copilot)

1. In **Settings**, click **Connect to GitHub**
2. A device code is displayed — copy it
3. Open the link to GitHub's device activation page and paste the code
4. Authorize the app on GitHub
5. The app detects authorization automatically and starts fetching your Copilot usage

### Menu Bar Metric

In **Settings**, use the **Menu Bar Metric** dropdown to choose which usage stat is shown in the menu bar icon (e.g., Claude 5-hour session, Copilot monthly usage, etc.).

## How It Works

### Claude (Anthropic)

The app uses Anthropic's OAuth PKCE flow (the same one used by Claude Code) to authenticate with your Claude Pro/Max subscription. Once connected, it polls the usage API every 30 seconds to display:

- **5-Hour Session** — your current rolling session utilization and reset countdown
- **Weekly — All Models** — your 7-day usage across all Claude models
- **Weekly — Sonnet** — your 7-day Sonnet-specific usage

### Copilot (GitHub)

The app uses GitHub's device flow OAuth to authenticate. Once connected, it fetches your monthly premium request billing data from the GitHub API, showing usage counts per model against your plan's included allowance.

Credentials are stored locally in UserDefaults and tokens are refreshed automatically.

## Project Structure

```
CodeQuota/
├── CodeQuotaApp.swift             # App entry point
├── AppDelegate.swift              # Menu bar + popover setup
├── ContentView.swift              # Main popover UI (Claude + Copilot sections)
├── UsageIconView.swift            # Menu bar icon (configurable metric)
├── ClaudeUsageManager.swift       # Claude usage data fetching and parsing
├── AnthropicAuthManager.swift     # Anthropic OAuth PKCE authentication
├── GitHubAuthManager.swift        # GitHub device flow OAuth
├── CopilotUsageManager.swift      # Copilot premium request billing
├── MenuBarMetric.swift            # Menu bar metric selection model
├── SettingsView.swift             # Connection settings UI
├── Info.plist                     # App configuration
└── CodeQuota.entitlements         # Sandbox permissions
```

## License

MIT
