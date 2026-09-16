import Foundation

// MARK: - Auth Credentials

struct OAuthCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }
}

// MARK: - Auth Source

/// Where the Anthropic access token comes from.
enum AnthropicAuthSource: Equatable {
    /// Reuse the login of the Claude Code CLI (Keychain item "Claude Code-credentials"
    /// or ~/.claude/.credentials.json). Read-only; Claude Code owns token refresh.
    case claudeCode
    /// Tokens obtained by CodeQuota's own PKCE OAuth flow (legacy / fallback).
    case manualOAuth
}

// MARK: - Auth Manager

class AnthropicAuthManager: ObservableObject {
    static let shared = AnthropicAuthManager()

    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private static let scopes = "org:create_api_key user:profile user:inference"
    // Token endpoint moved from console.anthropic.com to platform.claude.com
    // (same host Claude Code and claude-swap use).
    private static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let credentialsKey = "anthropic_oauth_credentials"
    /// Set when the user explicitly disconnected the Claude Code source, so we
    /// don't silently re-adopt it on the next launch.
    private static let claudeCodeDisabledKey = "anthropic_claude_code_disabled"

    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "CodeQuota/\(version)"
    }()

    @Published var isConnected: Bool = false
    @Published var isExchangingCode: Bool = false
    @Published var authError: String?
    @Published private(set) var source: AnthropicAuthSource?
    /// e.g. "max", "pro" — from Claude Code's stored credentials, when present.
    @Published private(set) var claudeCodeSubscription: String?
    /// Human-readable description of where Claude Code's credentials were read from.
    @Published private(set) var claudeCodeSourceDescription: String?

    private var currentVerifier: String?
    private(set) var credentials: OAuthCredentials?
    private(set) var claudeCodeCredentials: ClaudeCodeCredentials?

    private init() {
        loadCredentials()
        if !UserDefaults.standard.bool(forKey: Self.claudeCodeDisabledKey) {
            adoptClaudeCodeCredentials()
        }
    }

    // MARK: - Claude Code login (preferred)

    /// Whether Claude Code credentials can currently be read on this machine.
    var isClaudeCodeAvailable: Bool {
        ClaudeCodeCredentialReader.isAvailable()
    }

    /// Re-read Claude Code's stored credentials and, if present, use them as the
    /// active source. Returns true on success.
    @discardableResult
    func adoptClaudeCodeCredentials() -> Bool {
        guard let result = ClaudeCodeCredentialReader.read() else {
            print("[Auth] no Claude Code credentials found (Keychain or .credentials.json)")
            if source == .claudeCode {
                // Previously connected via Claude Code but the login is gone.
                claudeCodeCredentials = nil
                claudeCodeSubscription = nil
                claudeCodeSourceDescription = nil
                source = nil
                isConnected = false
            }
            return false
        }
        if result.credentials != claudeCodeCredentials {
            print("[Auth] using Claude Code credentials from \(result.source.displayName) (plan: \(result.credentials.subscriptionType ?? "unknown"), expires: \(result.credentials.expiresAt.map { "\($0)" } ?? "n/a"))")
        }
        claudeCodeCredentials = result.credentials
        claudeCodeSubscription = result.credentials.subscriptionType
        claudeCodeSourceDescription = result.source.displayName
        source = .claudeCode
        isConnected = true
        authError = nil
        return true
    }

    /// Called from the UI "Use Claude Code login" button.
    func connectWithClaudeCode() {
        UserDefaults.standard.removeObject(forKey: Self.claudeCodeDisabledKey)
        if adoptClaudeCodeCredentials() {
            ClaudeUsageManager.shared.refresh()
        } else {
            authError = "No Claude Code login found. Run `claude` in a terminal and sign in, then try again."
        }
    }

    // MARK: - Authorization URL (manual OAuth fallback)

    /// Generates the OAuth authorization URL and stores the PKCE verifier.
    /// Returns the URL the user should open in their browser.
    func generateAuthorizationURL() -> URL {
        let pkce = PKCEHelper.generatePKCE()
        currentVerifier = pkce.verifier

        var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.verifier),
        ]

        return components.url!
    }

    private func makeTokenRequest(body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Code Exchange

    /// Exchange the authorization code for access + refresh tokens.
    func exchangeCode(_ rawCode: String) {
        guard let verifier = currentVerifier else {
            authError = "No pending authorization. Please click the link first."
            return
        }

        isExchangingCode = true
        authError = nil

        // The code may contain "#state" appended
        let splits = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "#")
        let code = splits[0]
        let state = splits.count > 1 ? splits[1] : nil

        var body: [String: Any] = [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
        ]
        if let state = state {
            body["state"] = state
        }

        let request = makeTokenRequest(body: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isExchangingCode = false

                if let error = error {
                    print("[Auth] exchangeCode network error: \(error)")
                    self?.authError = "Network error: \(error.localizedDescription)"
                    return
                }

                let httpResponse = response as? HTTPURLResponse
                let statusCode = httpResponse?.statusCode ?? 0
                print("[Auth] exchangeCode HTTP \(statusCode)")

                guard let data = data else {
                    self?.authError = "No data received from server."
                    return
                }

                let bodyStr = String(data: data, encoding: .utf8) ?? "(binary)"
                print("[Auth] exchangeCode body: \(bodyStr.prefix(500))")

                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        self?.authError = "Invalid response format."
                        return
                    }

                    if let errorMsg = json["error"] as? String {
                        let desc = json["error_description"] as? String ?? errorMsg
                        self?.authError = "Auth error: \(desc)"
                        return
                    }

                    guard let accessToken = json["access_token"] as? String,
                          let refreshToken = json["refresh_token"] as? String else {
                        self?.authError = "Missing token fields in response. Keys: \(json.keys.sorted())"
                        return
                    }

                    // expires_in might be Int or Double
                    let expiresIn: TimeInterval
                    if let intVal = json["expires_in"] as? Int {
                        expiresIn = TimeInterval(intVal)
                    } else if let dblVal = json["expires_in"] as? Double {
                        expiresIn = dblVal
                    } else {
                        // Default to 1 hour if not provided
                        expiresIn = 3600
                    }

                    print("[Auth] exchangeCode success! expires_in=\(expiresIn) token=\(accessToken.prefix(8))...")

                    let creds = OAuthCredentials(
                        accessToken: accessToken,
                        refreshToken: refreshToken,
                        expiresAt: Date().addingTimeInterval(expiresIn)
                    )

                    self?.credentials = creds
                    self?.source = .manualOAuth
                    self?.isConnected = true
                    self?.currentVerifier = nil
                    self?.saveCredentials(creds)

                    // Trigger a usage refresh now that we're connected
                    ClaudeUsageManager.shared.refresh()

                } catch {
                    self?.authError = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    // MARK: - Token Refresh

    /// Obtain a fresh access token.
    ///
    /// - Claude Code source: re-read Claude Code's store. Claude Code rotates the
    ///   token itself; we must never POST its (single-use) refresh token.
    /// - Manual source: use our own refresh token against the token endpoint.
    func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        if source == .claudeCode {
            // Success only when Claude Code has rotated to a new, unexpired token;
            // re-trying the same token would just 401 again.
            let before = claudeCodeCredentials
            let ok = adoptClaudeCodeCredentials()
            let rotated = ok
                && claudeCodeCredentials != before
                && !(claudeCodeCredentials?.isExpired ?? true)
            completion(rotated)
            return
        }

        guard let creds = credentials else {
            completion(false)
            return
        }

        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": creds.refreshToken,
            "client_id": Self.clientID,
        ]

        let request = makeTokenRequest(body: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[Auth] refreshToken network error: \(error)")
                    self?.dropManualCredentials()
                    completion(false)
                    return
                }

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("[Auth] refreshToken HTTP \(statusCode)")

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("[Auth] refreshToken: no data or not JSON")
                    let bodyStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? "(nil)"
                    print("[Auth] refreshToken body: \(bodyStr.prefix(300))")
                    self?.dropManualCredentials()
                    completion(false)
                    return
                }

                guard let accessToken = json["access_token"] as? String else {
                    print("[Auth] refreshToken: missing access_token. keys=\(json.keys.sorted())")
                    self?.dropManualCredentials()
                    completion(false)
                    return
                }
                // The server may omit refresh_token when it does not rotate it.
                let refreshToken = (json["refresh_token"] as? String) ?? creds.refreshToken

                let expiresIn: TimeInterval
                if let intVal = json["expires_in"] as? Int {
                    expiresIn = TimeInterval(intVal)
                } else if let dblVal = json["expires_in"] as? Double {
                    expiresIn = dblVal
                } else {
                    expiresIn = 3600
                }

                print("[Auth] refreshToken success! expires_in=\(expiresIn)")

                let newCreds = OAuthCredentials(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresAt: Date().addingTimeInterval(expiresIn)
                )

                self?.credentials = newCreds
                self?.saveCredentials(newCreds)
                completion(true)
            }
        }.resume()
    }

    private func dropManualCredentials() {
        credentials = nil
        clearCredentials()
        if source == .manualOAuth {
            source = nil
            isConnected = false
        }
    }

    /// Get a valid access token, refreshing if needed.
    /// Completion receives `nil` when no usable token exists; `authError` then
    /// explains why for the Claude Code source.
    func getValidAccessToken(completion: @escaping (String?) -> Void) {
        if source == .claudeCode {
            // Always re-read: Claude Code may have rotated the token since last time.
            guard adoptClaudeCodeCredentials(), let creds = claudeCodeCredentials else {
                completion(nil)
                return
            }
            if creds.isExpired {
                authError = "Claude Code session token expired. Run `claude` in a terminal to refresh it."
                completion(nil)
                return
            }
            completion(creds.accessToken)
            return
        }

        guard let creds = credentials else {
            completion(nil)
            return
        }

        if creds.isExpired {
            refreshAccessToken { [weak self] success in
                if success {
                    completion(self?.credentials?.accessToken)
                } else {
                    completion(nil)
                }
            }
        } else {
            completion(creds.accessToken)
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        if source == .claudeCode {
            // Remember the choice so we don't re-adopt on next launch.
            UserDefaults.standard.set(true, forKey: Self.claudeCodeDisabledKey)
            claudeCodeCredentials = nil
            claudeCodeSubscription = nil
            claudeCodeSourceDescription = nil
        }
        credentials = nil
        source = nil
        isConnected = false
        currentVerifier = nil
        authError = nil
        clearCredentials()
    }

    // MARK: - Persistence (manual OAuth only)

    private func saveCredentials(_ creds: OAuthCredentials) {
        if let data = try? JSONEncoder().encode(creds) {
            UserDefaults.standard.set(data, forKey: Self.credentialsKey)
        }
    }

    private func loadCredentials() {
        guard let data = UserDefaults.standard.data(forKey: Self.credentialsKey),
              let creds = try? JSONDecoder().decode(OAuthCredentials.self, from: data) else {
            return
        }
        credentials = creds
        source = .manualOAuth
        isConnected = true
    }

    private func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: Self.credentialsKey)
    }
}
