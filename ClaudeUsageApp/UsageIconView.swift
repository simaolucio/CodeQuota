import SwiftUI

struct UsageIconView: View {
    @StateObject private var usageManager = ClaudeUsageManager.shared
    @StateObject private var authManager = AnthropicAuthManager.shared
    
    var body: some View {
        Group {
            if authManager.isConnected, case .loaded(let usage) = usageManager.state {
                connectedView(usage)
            } else if authManager.isConnected {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                    Text("...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .strokeBorder(Color.secondary, lineWidth: 1)
                        .frame(width: 8, height: 8)
                    Text("--")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
    }
    
    private func connectedView(_ usage: ClaudeUsage) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color(for: usage.fiveHour.percent))
                .frame(width: 8, height: 8)
            
            Text(String(format: "%.0f%%", usage.fiveHour.percent))
                .font(.system(size: 12, weight: .medium))
            
            Text(usage.fiveHour.timeRemainingString)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    private func color(for percentage: Double) -> Color {
        if percentage < 50 {
            return .green
        } else if percentage < 80 {
            return .yellow
        } else {
            return .red
        }
    }
}
