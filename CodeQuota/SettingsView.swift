import SwiftUI
import AppKit

// Brand violet from the logo
private let violet = Color(red: 0.49, green: 0.42, blue: 0.96)

struct SettingsView: View {
    @ObservedObject var anthropicAuth = AnthropicAuthManager.shared
    @ObservedObject var githubAuth = GitHubAuthManager.shared
    @ObservedObject var menuBarSettings = MenuBarSettings.shared
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
                Text("Anthropic")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.7))
                
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
                
                Button(action: {
                    anthropicURL = anthropicAuth.generateAuthorizationURL()
                    showingAnthropicFlow = true
                }) {
                    Text("Connect")
                        .font(.system(size: 11))
                        .foregroundColor(violet)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 6)
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
            
            if let error = githubAuth.authError {
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
        }
    }
    
    // MARK: - Helpers
    
    private var availableMetrics: [MenuBarMetric] {
        var metrics: [MenuBarMetric] = []
        if anthropicAuth.isConnected {
            metrics.append(contentsOf: [.claude5Hour, .claudeWeeklyAll, .claudeWeeklySonnet])
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
