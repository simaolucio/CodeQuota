import SwiftUI

struct ContentView: View {
    @StateObject private var usageManager = ClaudeUsageManager.shared
    @StateObject private var authManager = AnthropicAuthManager.shared
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
        .frame(width: 400, height: 500)
        .onAppear {
            usageManager.startAutoRefresh()
        }
    }
    
    // MARK: - Main Usage View
    
    private var mainView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Claude Usage")
                    .font(.system(size: 20, weight: .semibold))
                
                Spacer()
                
                // intentionally empty — header right side reserved
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            // Content based on state
            switch usageManager.state {
            case .notConnected:
                notConnectedView
            case .loading:
                loadingView
            case .loaded(let usage):
                usageView(usage)
            case .error(let message):
                errorView(message)
            }
            
            Spacer()
            
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
    
    // MARK: - Not Connected View
    
    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "link.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Connect your Anthropic account to view usage")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showSettings = true }) {
                HStack {
                    Image(systemName: "link")
                        .font(.system(size: 13))
                    Text("Connect to Anthropic")
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading usage data...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Usage View
    
    private func usageView(_ usage: ClaudeUsage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 5-Hour Session
            usageBucketView(
                icon: "clock.fill",
                title: "5-Hour Session",
                bucket: usage.fiveHour
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            
            // Weekly — All Models
            usageBucketView(
                icon: "calendar",
                title: "Weekly — All Models",
                bucket: usage.dailyAllModels
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            
            // Weekly — Sonnet
            usageBucketView(
                icon: "sparkles",
                title: "Weekly — Sonnet",
                bucket: usage.dailySonnet
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            
            // Update info and refresh
            HStack {
                Text("Updated \(usageManager.lastUpdateText)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
                
                Spacer()
                
                Button(action: { refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.secondary.opacity(0.7))
                        .font(.system(size: 14))
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
        }
    }
    
    // MARK: - Usage Bucket Row
    
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
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { refresh() }) {
                Text("Retry")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Helpers
    
    private func refresh() {
        withAnimation(.linear(duration: 0.8)) {
            isRefreshing = true
        }
        usageManager.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isRefreshing = false
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

// MARK: - Progress Bar

struct ProgressBar: View {
    let percentage: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(.primary.opacity(0.1))
                    .frame(height: 6)
                
                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(color(for: percentage))
                    .frame(width: max(0, geometry.size.width * CGFloat(percentage / 100)), height: 6)
            }
        }
        .frame(height: 6)
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
