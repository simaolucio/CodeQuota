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
        VStack(alignment: .leading, spacing: 0) {
                // Header — matching CODEQUOTA style
                HStack {
                    Button(action: onDismiss) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11))
                            Text("Back")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(Color(red: 0.49, green: 0.42, blue: 0.96))
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
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11))
                        Text("Back")
                            .font(.system(size: 11))
                    }
                    .opacity(0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)
                
                // Menu Bar Metric Picker
                metricPickerSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                
                // Divider
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                
                // Anthropic Account
                anthropicSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                
                // Divider
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                
                // GitHub Account
                githubSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
        }
    }
    
    // MARK: - Metric Picker
    
    private var metricPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metrics")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text("Tap to set the menu bar metric. Use the eye to show or hide in the main view.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.35))
            
            VStack(spacing: 4) {
                ForEach(availableMetrics, id: \.self) { metric in
                    let isSelected = menuBarSettings.selectedMetric == metric
                    let isVisible = menuBarSettings.isVisible(metric)
                    
                    HStack(spacing: 0) {
                        // Main tappable area — selects menu bar metric
                        Button(action: { menuBarSettings.selectedMetric = metric }) {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(isSelected ? Color.accentColor : Color.clear)
                                    .frame(width: 2, height: 14)
                                
                                Text(metric.displayName)
                                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                                    .foregroundColor(
                                        !isVisible ? .secondary.opacity(0.3) :
                                        isSelected ? .primary : .secondary.opacity(0.6)
                                    )
                                
                                Spacer()
                                
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Visibility toggle
                        Button(action: { menuBarSettings.toggleVisibility(metric) }) {
                            Image(systemName: isVisible ? "eye" : "eye.slash")
                                .font(.system(size: 10))
                                .foregroundColor(isVisible ? .secondary.opacity(0.3) : .secondary.opacity(0.15))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.vertical, 4)
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                isSelected
                                    ? LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.accentColor.opacity(0.08),
                                            Color.accentColor.opacity(0.02)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.primary.opacity(0.03),
                                            Color.primary.opacity(0.01)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04),
                                lineWidth: 0.5
                            )
                    )
                }
            }
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
            return MenuBarMetric.allCases
        }
        return metrics
    }
    
    // MARK: - Anthropic Section
    
    private var anthropicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anthropic")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
            
            if anthropicAuth.isConnected {
                connectedTile(title: "Claude Pro/Max", color: .green) {
                    anthropicAuth.disconnect()
                    showingAnthropicFlow = false
                    anthropicCode = ""
                }
            } else if showingAnthropicFlow {
                anthropicAuthFlow
            } else {
                Text("Connect your Claude Pro or Max subscription.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
                
                connectTileButton("Connect to Anthropic") {
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
                        Image(systemName: "arrow.up.right.square").font(.system(size: 12))
                        Text("Open in Browser").font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.accentColor.opacity(0.15),
                                Color.accentColor.opacity(0.06)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.accentColor)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.15), lineWidth: 0.5)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Step 2
            stepView(number: "2", title: "Paste authorization code")
            
            HStack(spacing: 8) {
                TextField("Paste code...", text: $anthropicCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .disabled(anthropicAuth.isExchangingCode)
                
                Button(action: {
                    guard !anthropicCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    anthropicAuth.exchangeCode(anthropicCode)
                }) {
                    if anthropicAuth.isExchangingCode {
                        ProgressView().controlSize(.small).frame(width: 56)
                    } else {
                        Text("Connect").font(.system(size: 12, weight: .medium)).frame(width: 56)
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
            .font(.system(size: 11)).foregroundColor(.secondary.opacity(0.4))
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - GitHub Section
    
    private var githubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
            
            if githubAuth.isConnected {
                connectedTile(title: "GitHub (\(githubAuth.username))", color: .purple) {
                    githubAuth.disconnect()
                }
            } else if githubAuth.isAuthenticating {
                githubDeviceFlow
            } else {
                Text("Connect your GitHub account to view Copilot premium request usage.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
                
                connectTileButton("Connect to GitHub") {
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
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
                
                HStack {
                    Text(code)
                        .font(.system(size: 18, weight: .light, design: .monospaced))
                        .textSelection(.enabled)
                    
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Button(action: {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }) {
                    HStack {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 12))
                        Text("Open GitHub").font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.purple.opacity(0.15),
                                Color.purple.opacity(0.06)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.purple)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple.opacity(0.15), lineWidth: 0.5)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for authorization...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }
            
            Button("Cancel") { githubAuth.cancelAuth() }
                .font(.system(size: 11)).foregroundColor(.secondary.opacity(0.4))
                .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Shared Components
    
    private func stepView(number: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.06))
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary.opacity(0.7))
        }
    }
    
    private func connectTileButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "link").font(.system(size: 12))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.accentColor.opacity(0.10),
                        Color.accentColor.opacity(0.03)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundColor(.accentColor)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func connectedTile(title: String, color: Color, disconnect: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(color)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(12)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        color.opacity(0.08),
                        color.opacity(0.02)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(0.12), lineWidth: 0.5)
            )
            
            Button("Disconnect", action: disconnect)
                .font(.system(size: 11)).foregroundColor(.red.opacity(0.7))
                .buttonStyle(PlainButtonStyle())
        }
    }
    
    private func errorLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red.opacity(0.7)).font(.system(size: 11))
            Text(text).font(.system(size: 11)).foregroundColor(.red.opacity(0.7))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
