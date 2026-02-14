import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var anthropicAuth = AnthropicAuthManager.shared
    @ObservedObject var githubAuth = GitHubAuthManager.shared
    @ObservedObject var menuBarSettings = MenuBarSettings.shared
    @State private var anthropicCode: String = ""
    @State private var anthropicURL: URL?
    @State private var showingAnthropicFlow = false
    
    var onDismiss: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Button(action: onDismiss) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .medium))
                            Text("Back")
                                .font(.system(size: 13))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    Text("Settings")
                        .font(.system(size: 17, weight: .semibold))
                    
                    Spacer()
                    
                    // Balance spacer
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .medium))
                        Text("Back")
                            .font(.system(size: 13))
                    }
                    .opacity(0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                Divider().opacity(0.3).padding(.bottom, 16)
                
                // Menu Bar Metric Picker
                metricPickerSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                
                Divider().opacity(0.15).padding(.horizontal, 20).padding(.bottom, 16)
                
                // Anthropic Account
                anthropicSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                
                Divider().opacity(0.15).padding(.horizontal, 20).padding(.bottom, 16)
                
                // GitHub Account
                githubSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Metric Picker
    
    private var metricPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu Bar Metric")
                .font(.system(size: 14, weight: .semibold))
            
            Text("Choose which metric to display in the menu bar.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Picker("", selection: $menuBarSettings.selectedMetric) {
                ForEach(availableMetrics, id: \.self) { metric in
                    Text(metric.displayName).tag(metric)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
    
    /// Only show metrics for connected providers
    private var availableMetrics: [MenuBarMetric] {
        var metrics: [MenuBarMetric] = []
        if anthropicAuth.isConnected {
            metrics.append(contentsOf: [.claude5Hour, .claudeWeeklyAll, .claudeWeeklySonnet])
        }
        if githubAuth.isConnected {
            metrics.append(.copilotPremium)
        }
        if metrics.isEmpty {
            // Show all as disabled hint
            return MenuBarMetric.allCases
        }
        return metrics
    }
    
    // MARK: - Anthropic Section
    
    private var anthropicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anthropic Account")
                .font(.system(size: 14, weight: .semibold))
            
            if anthropicAuth.isConnected {
                connectedBadge(title: "Claude Pro/Max", color: .green) {
                    anthropicAuth.disconnect()
                    showingAnthropicFlow = false
                    anthropicCode = ""
                }
            } else if showingAnthropicFlow {
                anthropicAuthFlow
            } else {
                Text("Connect your Claude Pro or Max subscription.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                connectButton("Connect to Anthropic") {
                    anthropicURL = anthropicAuth.generateAuthorizationURL()
                    showingAnthropicFlow = true
                }
            }
        }
    }
    
    private var anthropicAuthFlow: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Step 1
            stepView(number: "1", title: "Open authorization page")
            
            if let url = anthropicURL {
                Button(action: { NSWorkspace.shared.open(url) }) {
                    HStack {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 13))
                        Text("Open in Browser").font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Step 2
            stepView(number: "2", title: "Paste authorization code")
            
            HStack(spacing: 8) {
                TextField("Paste code...", text: $anthropicCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .disabled(anthropicAuth.isExchangingCode)
                
                Button(action: {
                    guard !anthropicCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    anthropicAuth.exchangeCode(anthropicCode)
                }) {
                    if anthropicAuth.isExchangingCode {
                        ProgressView().controlSize(.small).frame(width: 60)
                    } else {
                        Text("Connect").font(.system(size: 13, weight: .medium)).frame(width: 60)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(anthropicCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || anthropicAuth.isExchangingCode)
            }
            
            if let error = anthropicAuth.authError {
                errorLabel(error)
            }
            
            Button("Cancel") {
                showingAnthropicFlow = false
                anthropicCode = ""
                anthropicAuth.authError = nil
            }
            .font(.system(size: 12)).foregroundColor(.secondary)
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - GitHub Section
    
    private var githubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub Account")
                .font(.system(size: 14, weight: .semibold))
            
            if githubAuth.isConnected {
                connectedBadge(title: "GitHub (\(githubAuth.username))", color: .purple) {
                    githubAuth.disconnect()
                }
            } else if githubAuth.isAuthenticating {
                githubDeviceFlow
            } else {
                Text("Connect your GitHub account to view Copilot premium request usage.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                connectButton("Connect to GitHub") {
                    githubAuth.startDeviceFlow()
                }
            }
            
            if let error = githubAuth.authError {
                errorLabel(error)
            }
        }
    }
    
    private var githubDeviceFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let code = githubAuth.userCode, let url = githubAuth.verificationURL {
                Text("Enter this code on GitHub:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(code)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                    
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Button(action: {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }) {
                    HStack {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 13))
                        Text("Open GitHub").font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for authorization...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Button("Cancel") { githubAuth.cancelAuth() }
                .font(.system(size: 12)).foregroundColor(.secondary)
                .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Shared Components
    
    private func stepView(number: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(title).font(.system(size: 14, weight: .medium))
        }
    }
    
    private func connectButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "link").font(.system(size: 14))
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.15))
            .foregroundColor(.accentColor)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func connectedBadge(title: String, color: Color, disconnect: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(color)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .padding(10)
            .background(color.opacity(0.08))
            .cornerRadius(8)
            
            Button("Disconnect", action: disconnect)
                .font(.system(size: 12)).foregroundColor(.red)
                .buttonStyle(PlainButtonStyle())
        }
    }
    
    private func errorLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red).font(.system(size: 12))
            Text(text).font(.system(size: 12)).foregroundColor(.red)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
