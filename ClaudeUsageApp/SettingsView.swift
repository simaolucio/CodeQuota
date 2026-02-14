import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var authManager = AnthropicAuthManager.shared
    @State private var authCode: String = ""
    @State private var authURL: URL?
    @State private var showingAuthFlow = false
    
    var onDismiss: () -> Void
    
    var body: some View {
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
                
                // Invisible spacer to balance the back button
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
            
            Divider()
                .opacity(0.3)
                .padding(.bottom, 16)
            
            // Connection section
            VStack(alignment: .leading, spacing: 16) {
                Text("Anthropic Account")
                    .font(.system(size: 14, weight: .semibold))
                
                if authManager.isConnected {
                    // Connected state
                    connectedView
                } else if showingAuthFlow {
                    // Auth flow in progress
                    authFlowView
                } else {
                    // Not connected — show connect button
                    connectButton
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // App info
            HStack {
                Text("Claude Usage Monitor v1.0")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Connect Button
    
    private var connectButton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your Claude Pro or Max subscription to monitor your usage limits in real time.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Button(action: {
                authURL = authManager.generateAuthorizationURL()
                showingAuthFlow = true
            }) {
                HStack {
                    Image(systemName: "link")
                        .font(.system(size: 14))
                    Text("Connect to Anthropic")
                        .font(.system(size: 14, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Auth Flow View
    
    private var authFlowView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Step 1: Open link
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("1")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                    
                    Text("Open authorization page")
                        .font(.system(size: 14, weight: .medium))
                }
                
                Text("Click the link below to open Anthropic's authorization page in your browser.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let url = authURL {
                    Button(action: {
                        NSWorkspace.shared.open(url)
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13))
                            Text("Open in Browser")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Divider().opacity(0.3)
            
            // Step 2: Paste code
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("2")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                    
                    Text("Paste authorization code")
                        .font(.system(size: 14, weight: .medium))
                }
                
                Text("After authorizing, copy the code shown on the page and paste it here.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 8) {
                    TextField("Paste authorization code...", text: $authCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(authManager.isExchangingCode)
                    
                    Button(action: {
                        guard !authCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        authManager.exchangeCode(authCode)
                    }) {
                        if authManager.isExchangingCode {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 60)
                        } else {
                            Text("Connect")
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 60)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authManager.isExchangingCode)
                }
            }
            
            // Error message
            if let error = authManager.authError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            
            // Cancel
            Button(action: {
                showingAuthFlow = false
                authCode = ""
                authManager.authError = nil
            }) {
                Text("Cancel")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Connected View
    
    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 20))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected")
                        .font(.system(size: 14, weight: .medium))
                    Text("Claude Pro/Max")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(12)
            .background(Color.green.opacity(0.08))
            .cornerRadius(8)
            
            Button(action: {
                authManager.disconnect()
                showingAuthFlow = false
                authCode = ""
            }) {
                Text("Disconnect")
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}
