import SwiftUI

struct ContentView: View {
    @StateObject private var claudeUsage = ClaudeUsageManager.shared
    @StateObject private var copilotUsage = CopilotUsageManager.shared
    @StateObject private var anthropicAuth = AnthropicAuthManager.shared
    @StateObject private var githubAuth = GitHubAuthManager.shared
    @State private var isRefreshing = false
    @State private var showSettings = false
    
    var body: some View {
        Group {
            if showSettings {
                SettingsView(onDismiss: { showSettings = false })
            } else {
                mainView
            }
        }
        .frame(width: 400, height: 540)
        .onAppear {
            claudeUsage.startAutoRefresh()
            copilotUsage.startAutoRefresh()
        }
    }
    
    // MARK: - Main View
    
    private var mainView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text("Usage Monitor")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                
                // Claude section
                if anthropicAuth.isConnected {
                    claudeSection
                }
                
                // Copilot section
                if githubAuth.isConnected {
                    copilotSection
                }
                
                // Not connected prompt
                if !anthropicAuth.isConnected && !githubAuth.isConnected {
                    notConnectedView
                }
                
                Spacer(minLength: 16)
                
                // Divider
                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                
                // Bottom actions
                HStack(spacing: 20) {
                    Spacer()
                    
                    Button(action: { showSettings = true }) {
                        Text("Settings")
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Text("Quit")
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }
    
    // MARK: - Claude Section
    
    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Claude", updated: claudeUsage.lastUpdateText) {
                refreshClaude()
            }
            
            switch claudeUsage.state {
            case .notConnected:
                EmptyView()
            case .loading:
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
            case .loaded(let usage):
                usageBucketView(icon: "clock.fill", title: "5-Hour Session", bucket: usage.fiveHour)
                    .padding(.horizontal, 24).padding(.bottom, 16)
                usageBucketView(icon: "calendar", title: "Weekly — All Models", bucket: usage.dailyAllModels)
                    .padding(.horizontal, 24).padding(.bottom, 16)
                usageBucketView(icon: "sparkles", title: "Weekly — Sonnet", bucket: usage.dailySonnet)
                    .padding(.horizontal, 24).padding(.bottom, 16)
            case .error(let msg):
                inlineError(msg) { refreshClaude() }
                    .padding(.horizontal, 24).padding(.bottom, 16)
            }
            
            Divider().opacity(0.15).padding(.horizontal, 24).padding(.bottom, 16)
        }
    }
    
    // MARK: - Copilot Section
    
    private var copilotSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Copilot", updated: copilotUsage.lastUpdateText) {
                refreshCopilot()
            }
            
            switch copilotUsage.state {
            case .notConnected:
                EmptyView()
            case .loading:
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
            case .loaded(let usage):
                copilotUsageView(usage)
                    .padding(.horizontal, 24).padding(.bottom, 16)
            case .error(let msg):
                inlineError(msg) { refreshCopilot() }
                    .padding(.horizontal, 24).padding(.bottom, 16)
            }
        }
    }
    
    // MARK: - Section Header
    
    private func sectionHeader(_ title: String, updated: String, refresh: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            
            Spacer()
            
            Text(updated)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.5))
            
            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.system(size: 12))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }
    
    // MARK: - Copilot Usage View
    
    private func copilotUsageView(_ usage: CopilotUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .foregroundColor(color(for: usage.percent))
                    .font(.system(size: 16))
                
                Text("Premium Requests")
                    .font(.system(size: 15, weight: .semibold))
                
                Spacer()
                
                Text("\(usage.premiumRequestsUsed)/\(usage.premiumRequestsLimit)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(color(for: usage.percent))
            }
            
            ProgressBar(percentage: usage.percent)
            
            Text("This month")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.6))
            
            // Model breakdown
            if !usage.byModel.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(usage.byModel.prefix(5), id: \.model) { item in
                        HStack {
                            Text(item.model)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(item.count)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Usage Bucket Row (Claude)
    
    private func usageBucketView(icon: String, title: String, bucket: UsageBucket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(color(for: bucket.percent))
                    .font(.system(size: 16))
                
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                
                Spacer()
                
                Text(String(format: "%.0f%%", bucket.percent))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(color(for: bucket.percent))
            }
            
            ProgressBar(percentage: bucket.percent)
            
            if bucket.resetAt != nil {
                Text("Resets in: \(bucket.timeRemainingString)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
    }
    
    // MARK: - Not Connected View
    
    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            
            Image(systemName: "link.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Connect an account to view usage")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showSettings = true }) {
                Text("Open Settings")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Inline Error
    
    private func inlineError(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
                .font(.system(size: 14))
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: retry)
                .font(.system(size: 12))
                .buttonStyle(.borderless)
        }
    }
    
    // MARK: - Helpers
    
    private func refreshClaude() {
        claudeUsage.refresh()
    }
    
    private func refreshCopilot() {
        copilotUsage.refresh()
    }
    
    private func color(for percentage: Double) -> Color {
        if percentage < 50 { return .green }
        else if percentage < 80 { return .yellow }
        else { return .red }
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let percentage: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.primary.opacity(0.1))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 4)
                    .fill(color(for: percentage))
                    .frame(width: max(0, geometry.size.width * CGFloat(percentage / 100)), height: 6)
            }
        }
        .frame(height: 6)
    }
    
    private func color(for percentage: Double) -> Color {
        if percentage < 50 { return .green }
        else if percentage < 80 { return .yellow }
        else { return .red }
    }
}
