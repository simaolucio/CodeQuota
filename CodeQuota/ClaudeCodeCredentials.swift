import Foundation
import Security

// MARK: - Claude Code Credentials
//
// Claude Code (the CLI) stores its OAuth session on macOS in the login Keychain,
// as a generic-password item with service "Claude Code-credentials" and account
// equal to the current username. The stored value is JSON:
//
//   {"claudeAiOauth": {"accessToken": "...", "refreshToken": "...",
//                      "expiresAt": <unix ms>, "scopes": [...],
//                      "subscriptionType": "max"}, ...}
//
// On non-Keychain setups the same JSON lives at ~/.claude/.credentials.json.
//
// This mirrors how claude-swap (github.com/realiti4/claude-swap) reads
// credentials. We only ever READ these credentials. We never use Claude Code's
// refresh token: refresh tokens are single-use, so consuming one here without
// writing the result back would log the user out of Claude Code.

struct ClaudeCodeCredentials: Equatable {
    var accessToken: String
    /// Access-token expiry. `nil` when the stored JSON has no usable `expiresAt`.
    var expiresAt: Date?
    var subscriptionType: String?

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }

    /// Parse the JSON blob Claude Code stores (Keychain item or `.credentials.json`).
    /// Returns `nil` when the blob is not JSON, has no `claudeAiOauth` object,
    /// or that object has no non-empty `accessToken`.
    static func parse(_ data: Data) -> ClaudeCodeCredentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }

        // expiresAt is Unix time in milliseconds. Accept Int or Double.
        var expiresAt: Date?
        if let ms = oauth["expiresAt"] as? Double, ms > 0 {
            expiresAt = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let ms = oauth["expiresAt"] as? Int, ms > 0 {
            expiresAt = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }

        return ClaudeCodeCredentials(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }

    static func parse(_ string: String) -> ClaudeCodeCredentials? {
        parse(Data(string.utf8))
    }
}

// MARK: - Reader

enum ClaudeCodeCredentialSource: Equatable {
    case keychain
    case file(URL)

    var displayName: String {
        switch self {
        case .keychain: return "Keychain"
        case .file(let url): return url.path
        }
    }
}

struct ClaudeCodeCredentialReader {
    static let keychainService = "Claude Code-credentials"
    private static let securityBinary = "/usr/bin/security"
    private static let securityTimeout: TimeInterval = 5

    /// Account name of the Keychain item. Claude Code uses `$USER`, then the OS
    /// username, then a fixed fallback. Matching that exactly matters on
    /// headless / launchd hosts where `$USER` may be unset.
    static func accountName() -> String {
        if let user = ProcessInfo.processInfo.environment["USER"], !user.isEmpty {
            return user
        }
        let osUser = NSUserName()
        return osUser.isEmpty ? "claude-code-user" : osUser
    }

    /// Candidate `.credentials.json` locations, most specific first.
    static func credentialsFileURLs() -> [URL] {
        var urls: [URL] = []
        let env = ProcessInfo.processInfo.environment
        if let dir = env["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            urls.append(URL(fileURLWithPath: dir).appendingPathComponent(".credentials.json"))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        urls.append(home.appendingPathComponent(".claude/.credentials.json"))
        return urls
    }

    /// Read Claude Code's current credentials. Tries, in order:
    /// 1. the `security` CLI (same reader Claude Code itself uses, so no Keychain prompt),
    /// 2. the Security framework directly (may show a one-time "allow" prompt),
    /// 3. the plaintext `.credentials.json` file.
    /// Returns `nil` when no source yields parseable credentials.
    static func read() -> (credentials: ClaudeCodeCredentials, source: ClaudeCodeCredentialSource)? {
        if let raw = readViaSecurityCLI(), let creds = ClaudeCodeCredentials.parse(raw) {
            return (creds, .keychain)
        }
        if let raw = readViaSecItem(), let creds = ClaudeCodeCredentials.parse(raw) {
            return (creds, .keychain)
        }
        for url in credentialsFileURLs() {
            if let data = try? Data(contentsOf: url), let creds = ClaudeCodeCredentials.parse(data) {
                return (creds, .file(url))
            }
        }
        return nil
    }

    /// True when some source holds credentials, without exposing them.
    static func isAvailable() -> Bool {
        read() != nil
    }

    // MARK: Keychain via `security` CLI

    private static func readViaSecurityCLI() -> Data? {
        guard FileManager.default.isExecutableFile(atPath: securityBinary) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: securityBinary)
        process.arguments = [
            "find-generic-password",
            "-a", accountName(),
            "-s", keychainService,
            "-w",
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            print("[ClaudeCodeCreds] could not launch security: \(error)")
            return nil
        }

        // Bound the wait so a locked Keychain prompting for an unlock that never
        // comes (headless host) cannot hang the app.
        let deadline = Date().addingTimeInterval(securityTimeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            print("[ClaudeCodeCreds] security timed out")
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            // 44 = errSecItemNotFound; anything else is locked/denied/unavailable.
            print("[ClaudeCodeCreds] security rc=\(process.terminationStatus)")
            return nil
        }

        // `-w` prints the value followed by exactly one newline.
        if data.last == UInt8(ascii: "\n") {
            return data.dropLast()
        }
        return data
    }

    // MARK: Keychain via Security framework

    private static func readViaSecItem() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: accountName(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                print("[ClaudeCodeCreds] SecItemCopyMatching status=\(status)")
            }
            return nil
        }
        return item as? Data
    }
}
