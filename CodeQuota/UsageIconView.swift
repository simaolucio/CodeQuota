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
            
            Circle()
                .fill(pct != nil ? color(for: pct!) : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            
            if let pct = pct {
                Text(String(format: "%.0f%%", pct))
                    .font(.system(size: 12, weight: .medium))
                
                if let time = time {
                    Text(time)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("--")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
    
    /// Returns (percent, timeRemaining) for the currently selected metric
    private func resolveMetric() -> (Double?, String?) {
        switch settings.selectedMetric {
        case .claude5Hour:
            guard anthropicAuth.isConnected, case .loaded(let u) = claudeUsage.state else { return (nil, nil) }
            return (u.fiveHour.percent, u.fiveHour.timeRemainingString)
            
        case .claudeWeeklyAll:
            guard anthropicAuth.isConnected, case .loaded(let u) = claudeUsage.state else { return (nil, nil) }
            return (u.dailyAllModels.percent, u.dailyAllModels.timeRemainingString)
            
        case .claudeWeeklySonnet:
            guard anthropicAuth.isConnected, case .loaded(let u) = claudeUsage.state else { return (nil, nil) }
            return (u.dailySonnet.percent, u.dailySonnet.timeRemainingString)
            
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
