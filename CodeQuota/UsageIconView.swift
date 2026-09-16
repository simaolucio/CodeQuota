import SwiftUI

struct UsageIconView: View {
    @StateObject private var claudeUsage = ClaudeUsageManager.shared
    @StateObject private var copilotUsage = CopilotUsageManager.shared
    @StateObject private var anthropicAuth = AnthropicAuthManager.shared
    @StateObject private var githubAuth = GitHubAuthManager.shared
    @StateObject private var settings = MenuBarSettings.shared
    
    var body: some View {
        HStack(spacing: 4) {
            let (pct, time) = resolveMetric()
            
            if let pct = pct {
                // Connected: colored dot + percentage + optional reset time
                Circle()
                    .fill(color(for: pct))
                    .frame(width: 8, height: 8)
                
                Text(String(format: "%.0f%%", pct))
                    .font(.system(size: 12, weight: .medium))
                
                if settings.showResetTime, let time = time {
                    Text(time)
                        .font(.system(size: 11))
                }
            } else {
                // Disconnected: logo + "!"
                Image("MenuBarIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 16)
                
                Text("!")
                    .font(.system(size: 14, weight: .bold))
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }
    
    /// Returns (percent, timeRemaining) for the currently selected metric
    private func resolveMetric() -> (Double?, String?) {
        switch settings.selectedMetric {
        case .claude5Hour:
            guard anthropicAuth.isConnected, case .loaded(let u) = claudeUsage.state else { return (nil, nil) }
            return (u.fiveHour.percent, u.fiveHour.timeRemainingString)
            
        case .claudeWeeklyAll:
            guard anthropicAuth.isConnected, case .loaded(let u) = claudeUsage.state else { return (nil, nil) }
            return (u.weeklyAll.percent, u.weeklyAll.timeRemainingString)
            
        case .claudeWeeklyModel:
            guard anthropicAuth.isConnected, case .loaded(let u) = claudeUsage.state else { return (nil, nil) }
            return (u.weeklyModel.percent, u.weeklyModel.timeRemainingString)
            
        case .copilotPremium:
            guard githubAuth.isConnected, case .loaded(let u) = copilotUsage.state else { return (nil, nil) }
            return (u.percent, nil)
        }
    }
    
    private func color(for percentage: Double) -> Color {
        if percentage < 50 { return .green }
        else if percentage < 80 { return .yellow }
        else { return .red }
    }
}
