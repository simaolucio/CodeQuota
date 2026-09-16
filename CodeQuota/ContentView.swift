import SwiftUI

struct ContentView: View {
    @StateObject private var claudeUsage = ClaudeUsageManager.shared
    @StateObject private var copilotUsage = CopilotUsageManager.shared
    @StateObject private var anthropicAuth = AnthropicAuthManager.shared
    @StateObject private var githubAuth = GitHubAuthManager.shared
    @StateObject private var settings = MenuBarSettings.shared
    @StateObject private var accounts = ClaudeAccountsManager.shared
    @State private var isRefreshing = false
    @State private var showSettings = false
    
    var body: some View {
        Group {
            if showSettings {
                SettingsView(onDismiss: { showSettings = false })
                    .frame(width: 400)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                mainView
                    .frame(width: 400)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(Color(nsColor: NSColor(white: 0.12, alpha: 1.0)))
        .environment(\.colorScheme, .dark)
        .onAppear {
            claudeUsage.startAutoRefresh()
            copilotUsage.startAutoRefresh()
        }
    }
    
    // MARK: - Main View
    
    private var mainView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — uppercase tracked
            Text("CODEQUOTA")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2.5)
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)
            
            // Claude section
            if anthropicAuth.isConnected && hasVisibleClaudeMetrics {
                claudeSection
            }
            
            // Copilot section
            if githubAuth.isConnected && settings.isVisible(.copilotPremium) {
                copilotSection
            }
            
            // Not connected prompt
            if !anthropicAuth.isConnected && !githubAuth.isConnected {
                notConnectedView
            }
            
            // Bottom actions — always visible
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 12)
            
            HStack(spacing: 0) {
                Button(action: { showSettings = true }) {
                    Text("Settings")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.49, green: 0.42, blue: 0.96))
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Text("Quit")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.49, green: 0.42, blue: 0.96))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Claude Section
    
    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header — lighter weight from alt-3
            HStack {
                Text("Claude")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
                
                if let active = accounts.activeAccount {
                    Text(active.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
                
                Text(claudeUsage.lastUpdateText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.3))
                
                Button(action: { claudeUsage.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.secondary.opacity(0.3))
                        .font(.system(size: 10))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            
            switch claudeUsage.state {
            case .notConnected:
                EmptyView()
            case .loading:
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
            case .loaded(let usage):
                VStack(spacing: 8) {
                    if settings.isVisible(.claude5Hour) {
                        GradientTile(
                            icon: "clock.fill",
                            title: "5-Hour Session",
                            percentage: usage.fiveHour.percent,
                            detail: "Resets in: \(usage.fiveHour.timeRemainingString)"
                        )
                    }
                    
                    let showWeeklyAll = settings.isVisible(.claudeWeeklyAll)
                    let showModel = settings.isVisible(.claudeWeeklyModel)
                    
                    if showWeeklyAll && showModel {
                        // Both visible — side by side
                        HStack(spacing: 8) {
                            GradientTile(
                                icon: "calendar",
                                title: "Weekly All",
                                percentage: usage.weeklyAll.percent,
                                detail: usage.weeklyAll.timeRemainingString,
                                compact: true
                            )
                            GradientTile(
                                icon: "sparkles",
                                title: usage.weeklyModelLabel,
                                percentage: usage.weeklyModel.percent,
                                detail: usage.weeklyModel.timeRemainingString,
                                compact: true
                            )
                        }
                    } else if showWeeklyAll {
                        GradientTile(
                            icon: "calendar",
                            title: "Weekly — All Models",
                            percentage: usage.weeklyAll.percent,
                            detail: usage.weeklyAll.timeRemainingString
                        )
                    } else if showModel {
                        GradientTile(
                            icon: "sparkles",
                            title: "Weekly — \(usage.weeklyModelLabel)",
                            percentage: usage.weeklyModel.percent,
                            detail: usage.weeklyModel.timeRemainingString
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                
            case .error(let msg):
                inlineError(msg) { claudeUsage.refresh() }
                    .padding(.horizontal, 24).padding(.bottom, 16)
            }
            
            if accounts.isAvailable {
                accountsList
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
            
            // Thin divider from alt-3
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }
    
    // MARK: - Accounts (claude-swap)
    
    private var accountsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ACCOUNTS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.secondary.opacity(0.35))
                Spacer()
                if accounts.isRefreshing {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.bottom, 2)
            
            ForEach(accounts.accounts) { account in
                accountRow(account)
            }
            
            if let error = accounts.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.7))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(accounts.lastSwitchWarnings, id: \.self) { warning in
                Text(warning)
                    .font(.system(size: 10))
                    .foregroundColor(.orange.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func accountRow(_ account: ClaudeAccount) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accountColor(account))
                .frame(width: 7, height: 7)
                .overlay(
                    Circle().stroke(Color(red: 0.49, green: 0.42, blue: 0.96), lineWidth: account.isActive ? 1.5 : 0)
                        .frame(width: 11, height: 11)
                )
            
            VStack(alignment: .leading, spacing: 1) {
                Text(account.displayName)
                    .font(.system(size: 11, weight: account.isActive ? .medium : .regular))
                    .foregroundColor(.primary.opacity(account.isActive ? 0.8 : 0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if let usage = account.usage {
                    HStack(spacing: 6) {
                        usageChip("5h", usage.fiveHour.percent)
                        usageChip("Wk", usage.weeklyAll.percent)
                        usageChip(usage.weeklyModelLabel, usage.weeklyModel.percent)
                        if let status = account.statusText {
                            Text(status)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                    }
                } else {
                    Text(account.statusText ?? "no data")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }
            
            Spacer()
            
            if account.isActive {
                Text("active")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.35))
            } else if accounts.switchingTo == account.number {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            } else {
                Button(action: { accounts.switchTo(account.number) }) {
                    Text("Switch")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.49, green: 0.42, blue: 0.96))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(accounts.switchingTo != nil)
            }
        }
        .padding(.vertical, 4)
    }
    
    /// Colour-coded metric capsule: tint follows the same scale as the tiles
    /// (green < 50 %, yellow < 80 %, red otherwise) so status reads at a glance.
    private func usageChip(_ label: String, _ percent: Double) -> some View {
        let color = Self.usageColor(percent)
        return HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(color.opacity(0.9))
            Text("\(Int(percent.rounded()))%")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.5))
    }
    
    /// Shared threshold scale (matches GradientTile.tileColor).
    static func usageColor(_ percent: Double) -> Color {
        if percent < 50 { return .green }
        if percent < 80 { return .yellow }
        return .red
    }
    
    /// Worst of an account's buckets, used to tint its status pip.
    private func accountColor(_ account: ClaudeAccount) -> Color {
        guard let u = account.usage else { return Color.primary.opacity(0.15) }
        let worst = max(u.fiveHour.percent, u.weeklyAll.percent, u.weeklyModel.percent)
        return Self.usageColor(worst)
    }
    
    // MARK: - Copilot Section
    
    private var copilotSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Copilot")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
                
                Spacer()
                
                Text(copilotUsage.lastUpdateText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.3))
                
                Button(action: { copilotUsage.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.secondary.opacity(0.3))
                        .font(.system(size: 10))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            
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
                inlineError(msg) { copilotUsage.refresh() }
                    .padding(.horizontal, 24).padding(.bottom, 16)
            }
        }
    }
    
    // MARK: - Copilot Usage View
    
    private func copilotUsageView(_ usage: CopilotUsage) -> some View {
        VStack(spacing: 8) {
            GradientTile(
                icon: "cpu",
                title: "Premium Requests",
                percentage: usage.percent,
                detail: "\(usage.premiumRequestsUsed) / \(usage.premiumRequestsLimit) this month"
            )
            
            // Model breakdown — clean from alt-3
            if !usage.byModel.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(usage.byModel.prefix(5), id: \.model) { item in
                        HStack {
                            Text(item.model)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.5))
                            Spacer()
                            Text("\(item.count)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Not Connected View
    
    private var notConnectedView: some View {
        VStack(spacing: 12) {
            Text("No accounts connected")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.5))
            
            Button(action: { showSettings = true }) {
                Text("Connect")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
    
    // MARK: - Helpers
    
    private var hasVisibleClaudeMetrics: Bool {
        settings.isVisible(.claude5Hour) || settings.isVisible(.claudeWeeklyAll) || settings.isVisible(.claudeWeeklyModel)
    }
    
    // MARK: - Inline Error
    
    private func inlineError(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.5))
                .lineLimit(2)
            Spacer()
            Button("Retry", action: retry)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
                .buttonStyle(.borderless)
        }
    }
}

// MARK: - Gradient Tile

struct GradientTile: View {
    let icon: String
    let title: String
    let percentage: Double
    let detail: String
    var compact: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(tileColor)
                    .font(.system(size: compact ? 12 : 14))
                
                if !compact {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    
                    Spacer()
                }
                
                if compact {
                    Spacer()
                }
                
                // Large lightweight percentage from alt-3
                Text(String(format: "%.0f%%", percentage))
                    .font(.system(size: compact ? 18 : 22, weight: .light, design: .rounded))
                    .foregroundColor(tileColor)
            }
            
            if compact {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.7))
            }
            
            // Thin progress bar (3px from alt-3)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(tileColor)
                        .frame(width: max(0, geo.size.width * CGFloat(min(percentage, 100) / 100)), height: 3)
                }
            }
            .frame(height: 3)
            
            Text(detail)
                .font(.system(size: compact ? 9 : 10))
                .foregroundColor(.secondary.opacity(0.35))
                .lineLimit(1)
        }
        .padding(compact ? 12 : 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            tileColor.opacity(0.08),
                            tileColor.opacity(0.02)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tileColor.opacity(0.12), lineWidth: 0.5)
        )
    }
    
    private var tileColor: Color {
        if percentage < 50 { return .green }
        else if percentage < 80 { return .yellow }
        else { return .red }
    }
}

// MARK: - Progress Bar (kept for compatibility)

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
