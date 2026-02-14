import Foundation
import CryptoKit
import Security

// MARK: - PKCE Helpers

private func generateRandomBytes(_ count: Int) -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
    return Data(bytes)
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func generatePKCE() -> (verifier: String, challenge: String) {
    let verifier = base64URLEncode(generateRandomBytes(32))
    let challengeData = SHA256.hash(data: Data(verifier.utf8))
    let challenge = base64URLEncode(Data(challengeData))
    return (verifier, challenge)
}

// MARK: - Auth Credentials

struct OAuthCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    
    var isExpired: Bool {
        Date() >= expiresAt
    }
}

// MARK: - Auth Manager

class AnthropicAuthManager: ObservableObject {
    static let shared = AnthropicAuthManager()
    
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private static let scopes = "org:create_api_key user:profile user:inference"
    private static let credentialsKey = "anthropic_oauth_credentials"
    
    @Published var isConnected: Bool = false
    @Published var isExchangingCode: Bool = false
    @Published var authError: String?
    
    private var currentVerifier: String?
    private(set) var credentials: OAuthCredentials?
    
    private init() {
        loadCredentials()
    }
    
    // MARK: - Authorization URL
    
    /// Generates the OAuth authorization URL and stores the PKCE verifier.
    /// Returns the URL the user should open in their browser.
    func generateAuthorizationURL() -> URL {
        let pkce = generatePKCE()
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
        
        var request = URLRequest(url: URL(string: "https://console.anthropic.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
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
    
    /// Refresh the access token using the refresh token.
    func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let creds = credentials else {
            completion(false)
            return
        }
        
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": creds.refreshToken,
            "client_id": Self.clientID,
        ]
        
        var request = URLRequest(url: URL(string: "https://console.anthropic.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[Auth] refreshToken network error: \(error)")
                    self?.isConnected = false
                    self?.credentials = nil
                    self?.clearCredentials()
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
                    self?.isConnected = false
                    self?.credentials = nil
                    self?.clearCredentials()
                    completion(false)
                    return
                }
                
                guard let accessToken = json["access_token"] as? String,
                      let refreshToken = json["refresh_token"] as? String else {
                    print("[Auth] refreshToken: missing tokens. keys=\(json.keys.sorted())")
                    self?.isConnected = false
                    self?.credentials = nil
                    self?.clearCredentials()
                    completion(false)
                    return
                }
                
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
    
    /// Get a valid access token, refreshing if needed.
    func getValidAccessToken(completion: @escaping (String?) -> Void) {
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
        credentials = nil
        isConnected = false
        currentVerifier = nil
        authError = nil
        clearCredentials()
    }
    
    // MARK: - Persistence
    
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
        isConnected = true
    }
    
    private func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: Self.credentialsKey)
    }
}
