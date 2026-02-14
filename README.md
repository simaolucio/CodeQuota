# Claude Session Watcher

A native macOS menu bar app that monitors your Claude Pro/Max subscription usage limits in real time.

## Features

- Live usage tracking directly in the menu bar (colored status circle + percentage)
- 5-hour session usage monitoring
- Weekly all-models and Sonnet-specific limit tracking
- Auto-refresh every 30 seconds
- Transparent popover with system vibrancy
- Color-coded progress bars: green (<50%), yellow (50-80%), red (>80%)

## Installation

### Prerequisites
- macOS 13.0 or later
- Xcode 15.0 or later

### Building from Source

1. Clone this repository
2. Open `ClaudeUsageApp.xcodeproj` in Xcode
3. Build and run (Cmd+R)

## Setup

1. Launch the app — it appears in your menu bar
2. Click the menu bar icon and go to **Settings**
3. Click **Connect to Anthropic** — this opens the Anthropic authorization page in your browser
4. Authorize the app, then copy the code shown on the page
5. Paste the code back into the app and click **Connect**

That's it. The app will start fetching your usage data automatically.

## How It Works

The app uses Anthropic's OAuth PKCE flow (the same one used by Claude Code) to authenticate with your Claude Pro/Max subscription. Once connected, it polls the usage API every 30 seconds to display:

- **5-Hour Session** — your current rolling session utilization and reset countdown
- **Weekly — All Models** — your 7-day usage across all Claude models
- **Weekly — Sonnet** — your 7-day Sonnet-specific usage

Credentials are stored locally in UserDefaults and tokens are refreshed automatically.

## Project Structure

```
ClaudeUsageApp/
├── ClaudeUsageApp.swift          # App entry point
├── AppDelegate.swift              # Menu bar + popover setup
├── ContentView.swift              # Main popover UI
├── UsageIconView.swift            # Menu bar icon
├── ClaudeUsageManager.swift       # Usage data fetching and parsing
├── AnthropicAuthManager.swift     # OAuth PKCE authentication
├── SettingsView.swift             # Connection settings UI
├── Info.plist                     # App configuration
└── ClaudeUsageApp.entitlements    # Sandbox permissions
```

## License

MIT
