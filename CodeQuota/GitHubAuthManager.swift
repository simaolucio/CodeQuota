import Foundation

class GitHubAuthManager: ObservableObject {
    static let shared = GitHubAuthManager()
    
    // GitHub CLI OAuth App — public, same as `gh` CLI
    private static let clientID = "178c6fc778ccc68e1d6a"
    private static let scopes = "user"
    private static let credentialsKey = "github_oauth_credentials"
    private static let usernameKey = "github_username"
    
    @Published var isConnected: Bool = false
    @Published var isAuthenticating: Bool = false
    @Published var authError: String?
    @Published var userCode: String?
    @Published var verificationURL: String?
    @Published var username: String = ""
    
    private(set) var accessToken: String?
    private var deviceCode: String?
    private var pollInterval: TimeInterval = 5
    private var pollTimer: Timer?
    
    private init() {
        loadCredentials()
    }
    
    // MARK: - Device Flow: Step 1 — Request codes
    
    func startDeviceFlow() {
        isAuthenticating = true
        authError = nil
        userCode = nil
        verificationURL = nil
        
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "client_id": Self.clientID,
            "scope": Self.scopes,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.authError = "Network error: \(error.localizedDescription)"
                    self.isAuthenticating = false
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.authError = "Invalid response from GitHub."
                    self.isAuthenticating = false
                    return
                }
                
                guard let deviceCode = json["device_code"] as? String,
                      let userCode = json["user_code"] as? String,
                      let verificationURI = json["verification_uri"] as? String else {
                    let errMsg = json["error_description"] as? String ?? "Missing device code fields."
                    self.authError = errMsg
                    self.isAuthenticating = false
                    return
                }
                
                self.deviceCode = deviceCode
                self.userCode = userCode
                self.verificationURL = verificationURI
                self.pollInterval = (json["interval"] as? TimeInterval) ?? 5
                
                // Start polling for the user to authorize
                self.startPolling()
            }
        }.resume()
    }
    
    // MARK: - Device Flow: Step 2 — Poll for token
    
    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollForToken()
        }
    }
    
    private func pollForToken() {
        guard let deviceCode = deviceCode else { return }
        
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "client_id": Self.clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if error != nil { return } // Silently retry on network errors
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                
                // Check for pending/slow_down/errors
                if let errorCode = json["error"] as? String {
                    switch errorCode {
                    case "authorization_pending":
                        return // Keep polling
                    case "slow_down":
                        self.pollInterval += 5
                        self.pollTimer?.invalidate()
                        self.startPolling()
                        return
                    case "expired_token":
                        self.authError = "Authorization timed out. Please try again."
                        self.stopPolling()
                        return
                    case "access_denied":
                        self.authError = "Authorization was denied."
                        self.stopPolling()
                        return
                    default:
                        let desc = json["error_description"] as? String ?? errorCode
                        self.authError = desc
                        self.stopPolling()
                        return
                    }
                }
                
                // Success — we have the token
                guard let token = json["access_token"] as? String else {
                    self.authError = "Missing access token in response."
                    self.stopPolling()
                    return
                }
                
                self.accessToken = token
                self.isConnected = true
                self.isAuthenticating = false
                self.stopPolling()
                self.saveCredentials(token)
                
                // Fetch username
                self.fetchUsername()
                
                // Trigger usage refresh
                CopilotUsageManager.shared.refresh()
            }
        }.resume()
    }
    
    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isAuthenticating = false
        deviceCode = nil
    }
    
    func cancelAuth() {
        stopPolling()
        userCode = nil
        verificationURL = nil
        authError = nil
    }
    
    // MARK: - Fetch Username
    
    private func fetchUsername() {
        guard let token = accessToken else { return }
        
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let login = json["login"] as? String else { return }
                self?.username = login
                UserDefaults.standard.set(login, forKey: Self.usernameKey)
            }
        }.resume()
    }
    
    // MARK: - Disconnect
    
    func disconnect() {
        accessToken = nil
        isConnected = false
        username = ""
        authError = nil
        userCode = nil
        verificationURL = nil
        stopPolling()
        clearCredentials()
    }
    
    // MARK: - Persistence
    
    private func saveCredentials(_ token: String) {
        UserDefaults.standard.set(token, forKey: Self.credentialsKey)
    }
    
    private func loadCredentials() {
        guard let token = UserDefaults.standard.string(forKey: Self.credentialsKey) else { return }
        accessToken = token
        isConnected = true
        username = UserDefaults.standard.string(forKey: Self.usernameKey) ?? ""
        // Refresh username in background
        fetchUsername()
    }
    
    private func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: Self.credentialsKey)
        UserDefaults.standard.removeObject(forKey: Self.usernameKey)
    }
}
