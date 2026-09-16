import SwiftUI
import AppKit

// Brand violet from the logo
private let violet = Color(red: 0.49, green: 0.42, blue: 0.96)

struct SettingsView: View {
    @ObservedObject var anthropicAuth = AnthropicAuthManager.shared
    @ObservedObject var githubAuth = GitHubAuthManager.shared
    @ObservedObject var menuBarSettings = MenuBarSettings.shared
    @ObservedObject var accounts = ClaudeAccountsManager.shared
    @State private var showAddAccount = false
    @State private var newAccountAlias = ""
    @ObservedObject var updater = UpdaterViewModel.shared!
    @State private var anthropicCode: String = ""
    @State private var anthropicURL: URL?
    @State private var showingAnthropicFlow = false
    
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11))
                        Text("Back")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(violet)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Text("SETTINGS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.5)
                    .foregroundColor(.secondary.opacity(0.5))
                
                Spacer()
                
                // Balance spacer
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11))
                    Text("Back").font(.system(size: 11))
                }
                .opacity(0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)
            
            // --- Accounts ---
            accountsSection
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            
            // Thin divider
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            
            // --- Menu Bar ---
            metricSection
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            
            // Thin divider
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            
            // --- Updates ---
            updatesSection
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            
            // Thin divider
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            
            // Buy me a coffee
            HStack {
                Spacer()
                Button(action: {
                    if let url = URL(string: "https://ko-fi.com/P5P31U8CJQ") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 10))
                        Text("Buy me a coffee")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(violet)
                }
                .buttonStyle(PlainButtonStyle())
                Spacer()
            }
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Accounts
    
    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Claude row
            claudeRow
            
            // Auth flow expands inline below Claude row
            if showingAnthropicFlow && !anthropicAuth.isConnected {
                anthropicAuthFlow
                    .padding(.leading, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
            } else if let error = anthropicAuth.authError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
                    .padding(.bottom, 4)
            }
            
            // Claude accounts managed by claude-swap (cswap)
            if accounts.isAvailable {
                claudeAccountsBlock
                    .padding(.leading, 20)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            }
            
            // GitHub row
            githubRow
            
            // Auth flow expands inline below GitHub row
            if githubAuth.isAuthenticating && !githubAuth.isConnected {
                githubDeviceFlow
                    .padding(.leading, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
            }
        }
    }
    
    // MARK: - Claude Row
    
    private var claudeRow: some View {
        HStack(spacing: 8) {
            // Status pip
            Circle()
                .fill(anthropicAuth.isConnected ? violet : Color.primary.opacity(0.15))
                .frame(width: 7, height: 7)
            
            if anthropicAuth.isConnected {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Anthropic")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary.opacity(0.7))
                    if anthropicAuth.source == .claudeCode {
                        Text(claudeCodeSubtitle)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
                
                Spacer()
                
                Button(action: {
                    anthropicAuth.disconnect()
                    showingAnthropicFlow = false
                    anthropicCode = ""
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.3))
                        .frame(width: 18, height: 18)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Text("Anthropic")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.4))
                
                Spacer()
                
                // Preferred: reuse the Claude Code CLI login (no browser flow).
                Button(action: {
                    anthropicAuth.connectWithClaudeCode()
                    showingAnthropicFlow = false
                }) {
                    Text("Use Claude Code login")
                        .font(.system(size: 11))
                        .foregroundColor(violet)
                }
                .buttonStyle(PlainButtonStyle())
                
                Text("·")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.3))
                
                // Fallback: CodeQuota's own OAuth flow.
                Button(action: {
                    anthropicAuth.authError = nil
                    anthropicURL = anthropicAuth.generateAuthorizationURL()
                    showingAnthropicFlow = true
                }) {
                    Text("Sign in")
                        .font(.system(size: 11))
                        .foregroundColor(violet)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 6)
    }
    
    private var claudeCodeSubtitle: String {
        var parts = ["via Claude Code login"]
        if let sub = anthropicAuth.claudeCodeSubscription, !sub.isEmpty {
            parts.append(sub.capitalized)
        }
        return parts.joined(separator: " · ")
    }
    
    // MARK: - Claude Accounts (cswap)
    
    private var claudeAccountsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(accounts.accounts.count) account\(accounts.accounts.count == 1 ? "" : "s") via cswap")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.45))
                Spacer()
                Button(action: {
                    showAddAccount.toggle()
                    accounts.lastAddMessage = nil
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: showAddAccount ? "minus" : "plus")
                            .font(.system(size: 8, weight: .semibold))
                        Text(showAddAccount ? "Cancel" : "Add account")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(violet)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            ForEach(accounts.accounts) { account in
                HStack(spacing: 6) {
                    Circle()
                        .fill(account.isActive ? violet : Color.primary.opacity(0.15))
                        .frame(width: 5, height: 5)
                    Text(account.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.primary.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let status = account.statusText {
                        Text(status)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    Spacer()
                    if account.isActive {
                        Text("active")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.35))
                    }
                }
            }
            
            if showAddAccount {
                addAccountPanel
                    .padding(.top, 4)
            }
        }
    }
    
    /// Guided flow mirroring `cswap add`: sign in to Claude Code with the other
    /// account, then register that login. Do not log out first; Claude Code
    /// may revoke the refresh token of the account being left.
    private var addAccountPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                stepBadge("1")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sign in to Claude Code with the other account.")
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.6))
                    Button(action: { accounts.openTerminalForLogin() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "terminal")
                                .font(.system(size: 10))
                            Text("Open Terminal: claude auth login")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(violet)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Text("Don't log out first — Claude Code may revoke the token of the account you're leaving.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            HStack(alignment: .top, spacing: 6) {
                stepBadge("2")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Register that login with cswap.")
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.6))
                    HStack(spacing: 8) {
                        TextField("Alias (optional)", text: $newAccountAlias)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .frame(maxWidth: 160)
                            .disabled(accounts.isAdding)
                        Button(action: {
                            accounts.addCurrentLogin(alias: newAccountAlias)
                        }) {
                            if accounts.isAdding {
                                ProgressView().controlSize(.small).frame(width: 110)
                            } else {
                                Text("Add current login")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(violet)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(accounts.isAdding)
                    }
                }
            }
            
            if let msg = accounts.lastAddMessage {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundColor(accounts.lastAddSucceeded ? .green.opacity(0.8) : .red.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .onAppear {
                        if accounts.lastAddSucceeded { newAccountAlias = "" }
                    }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
    
    private func stepBadge(_ n: String) -> some View {
        Text(n)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.4))
            .frame(width: 12)
    }
    
    // MARK: - GitHub Row
    
    private var githubRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(githubAuth.isConnected ? violet : Color.primary.opacity(0.15))
                .frame(width: 7, height: 7)
            
            if githubAuth.isConnected {
                Text("GitHub Copilot")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.7))
                
                Spacer()
                
                Button(action: {
                    githubAuth.disconnect()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.3))
                        .frame(width: 18, height: 18)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            } else if githubAuth.isAuthenticating {
                Text("GitHub Copilot")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.4))
                
                Spacer()
                
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Text("GitHub Copilot")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.4))
                
                Spacer()
                
                Button(action: {
                    githubAuth.startDeviceFlow()
                }) {
                    Text("Connect")
                        .font(.system(size: 11))
                        .foregroundColor(violet)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if githubAuth.authError != nil {
                errorDot
            }
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Anthropic Auth Flow (inline)
    
    private var anthropicAuthFlow: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Step 1
            HStack(spacing: 6) {
                Text("1")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.4))
                Text("Open authorization page")
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.6))
            }
            
            if let url = anthropicURL {
                Button(action: { NSWorkspace.shared.open(url) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text("Open in Browser")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(violet)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Step 2
            HStack(spacing: 6) {
                Text("2")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.4))
                Text("Paste authorization code")
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.6))
            }
            
            HStack(spacing: 8) {
                TextField("Paste code...", text: $anthropicCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .disabled(anthropicAuth.isExchangingCode)
                
                Button(action: {
                    guard !anthropicCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    anthropicAuth.exchangeCode(anthropicCode)
                }) {
                    if anthropicAuth.isExchangingCode {
                        ProgressView().controlSize(.small).frame(width: 50)
                    } else {
                        Text("Submit")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(violet)
                            .frame(width: 50)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(anthropicCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || anthropicAuth.isExchangingCode)
            }
            
            if let error = anthropicAuth.authError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Button("Cancel") {
                showingAnthropicFlow = false
                anthropicCode = ""
                anthropicAuth.authError = nil
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary.opacity(0.3))
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - GitHub Device Flow (inline)
    
    private var githubDeviceFlow: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let code = githubAuth.userCode, let url = githubAuth.verificationURL {
                HStack(spacing: 8) {
                    Text(code)
                        .font(.system(size: 16, weight: .light, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.9))
                        .textSelection(.enabled)
                    
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Button(action: {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text("Open GitHub")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(violet)
                }
                .buttonStyle(PlainButtonStyle())
                
                Text("Waiting for authorization...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.3))
            }
            
            if let error = githubAuth.authError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Button("Cancel") { githubAuth.cancelAuth() }
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.3))
                .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Metric Section
    
    private var metricSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MENU BAR")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(.secondary.opacity(0.3))
                .padding(.bottom, 2)
            
            ForEach(availableMetrics, id: \.self) { metric in
                let isSelected = menuBarSettings.selectedMetric == metric
                let isVisible = menuBarSettings.isVisible(metric)
                
                HStack(spacing: 0) {
                    // Select metric
                    Button(action: { menuBarSettings.selectedMetric = metric }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isSelected ? violet : Color.clear)
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color.clear : Color.primary.opacity(0.15), lineWidth: 1)
                                )
                                .frame(width: 7, height: 7)
                            
                            Text(metric.displayName)
                                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                                .foregroundColor(
                                    !isVisible ? .secondary.opacity(0.2) :
                                    isSelected ? .primary.opacity(0.8) : .secondary.opacity(0.5)
                                )
                            
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Visibility toggle
                    Button(action: { menuBarSettings.toggleVisibility(metric) }) {
                        Image(systemName: isVisible ? "eye" : "eye.slash")
                            .font(.system(size: 9))
                            .foregroundColor(isVisible ? .secondary.opacity(0.25) : .secondary.opacity(0.12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.vertical, 2)
            }
            
            // Show reset time toggle
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
                .padding(.vertical, 8)
            
            Toggle(isOn: $menuBarSettings.showResetTime) {
                Text("Show reset time")
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.7))
            }
            .toggleStyle(SwitchToggleStyle(tint: violet))
            .controlSize(.mini)
        }
    }
    
    // MARK: - Updates Section
    
    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UPDATES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(.secondary.opacity(0.3))
                .padding(.bottom, 2)
            
            Toggle(isOn: $updater.automaticallyChecksForUpdates) {
                Text("Check automatically")
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.7))
            }
            .toggleStyle(SwitchToggleStyle(tint: violet))
            .controlSize(.mini)
            
            HStack {
                Text("Version \(updater.appVersion)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.3))
                
                Spacer()
                
                Button(action: { updater.checkForUpdates() }) {
                    Text("Check for Updates")
                        .font(.system(size: 11))
                        .foregroundColor(violet)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!updater.canCheckForUpdates)
                .opacity(updater.canCheckForUpdates ? 1.0 : 0.4)
            }
            .padding(.top, 2)
        }
    }
    
    // MARK: - Helpers
    
    private var availableMetrics: [MenuBarMetric] {
        var metrics: [MenuBarMetric] = []
        if anthropicAuth.isConnected {
            metrics.append(contentsOf: [.claude5Hour, .claudeWeeklyAll, .claudeWeeklyModel])
        }
        if githubAuth.isConnected {
            metrics.append(.copilotPremium)
        }
        if metrics.isEmpty {
            return MenuBarMetric.allCases
        }
        return metrics
    }
    
    private var errorDot: some View {
        Circle()
            .fill(Color.red.opacity(0.7))
            .frame(width: 5, height: 5)
    }
}
