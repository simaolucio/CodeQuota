# Claude Usage Menu Bar App

A native macOS menu bar application that displays your Claude API usage in real-time.

## Features

- 🎯 Live usage tracking in the menu bar
- ⏱️ 5-hour session usage monitoring
- 📊 Weekly limit tracking  
- 🔄 Auto-refresh every 20 seconds
- 🎨 Beautiful translucent UI matching macOS design language
- 📱 Quick access to claude.ai

## Installation

### Prerequisites
- macOS 13.0 or later
- Xcode 15.0 or later
- An Anthropic API key

### Building from Source

1. Clone this repository
2. Open `ClaudeUsageApp.xcodeproj` in Xcode
3. Build and run (⌘+R)

### Setting up your API Key

Set your Anthropic API key as an environment variable:

```bash
export ANTHROPIC_API_KEY=your_api_key_here
```

Or add it to your shell profile (~/.zshrc or ~/.bash_profile):

```bash
echo 'export ANTHROPIC_API_KEY=your_api_key_here' >> ~/.zshrc
source ~/.zshrc
```

Alternatively, the app will store your API key in UserDefaults once you enter it in the Settings.

## Usage

1. Launch the app - it will appear in your menu bar with usage statistics
2. Click the menu bar icon to see detailed usage information
3. The app automatically refreshes every 20 seconds
4. Click the refresh button to manually update usage data

## Features in Detail

### Menu Bar Display
Shows current 5-hour usage percentage and time remaining at a glance.

### Popover Window
- **5-Hour Session**: Current usage within the 5-hour rolling window
- **Weekly Limit**: Total weekly usage tracking
- **Progress Bars**: Visual representation with color coding (green < 50%, yellow < 80%, red ≥ 80%)
- **Time Remaining**: Countdown until each limit resets
- **Quick Actions**: 
  - Open claude.ai in your browser
  - Settings (coming soon)
  - Quit application

## API Integration

The app uses the Anthropic API to fetch usage data. Currently, it displays mock data as the exact API endpoint structure may vary. To integrate with the real API:

1. Update the `fetchUsageData` method in `ClaudeUsageManager.swift`
2. Parse the actual API response in `parseUsageData` method
3. Map the response fields to the `ClaudeUsage` struct

## Development

### Project Structure
```
ClaudeUsageApp/
├── ClaudeUsageApp.swift       # App entry point
├── AppDelegate.swift           # Menu bar setup
├── ContentView.swift           # Main popover UI
├── UsageIconView.swift         # Menu bar icon view
├── ClaudeUsageManager.swift    # Usage data management
├── Info.plist                  # App configuration
└── ClaudeUsageApp.entitlements # Sandbox permissions
```

### Key Components

- **ClaudeUsageManager**: Singleton that manages API calls and data updates
- **ContentView**: SwiftUI view for the main popover interface
- **UsageIconView**: Menu bar icon showing current usage
- **AppDelegate**: Sets up the NSStatusItem and popover

## Customization

You can customize:
- Refresh interval (default: 20 seconds) in `ClaudeUsageManager.startAutoRefresh()`
- Color thresholds in `ProgressBar.color(for:)` method
- Window size in `AppDelegate` and `ContentView`

## License

MIT License - feel free to use and modify as needed.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

If you encounter any issues or have questions, please open an issue on GitHub.
