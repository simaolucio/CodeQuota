import Foundation
import Combine

// MARK: - Usage Data Models

struct UsageBucket: Equatable {
    var percent: Double // 0.0 to 100.0
    var resetAt: Date?
    
    var timeRemainingString: String {
        guard let resetAt = resetAt else { return "--" }
        let seconds = Int(resetAt.timeIntervalSinceNow)
        if seconds <= 0 { return "now" }
        
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct ClaudeUsage: Equatable {
    /// Model whose weekly limit is shown as the third metric.
    static let preferredModelName = "Fable"

    var fiveHour: UsageBucket
    var weeklyAll: UsageBucket
    /// Weekly limit scoped to one model (Fable on current plans).
    var weeklyModel: UsageBucket
    /// Display name of the model behind `weeklyModel`, as reported by the API.
    var weeklyModelName: String?

    var weeklyModelLabel: String { weeklyModelName ?? Self.preferredModelName }

    static let empty = ClaudeUsage(
        fiveHour: UsageBucket(percent: 0, resetAt: nil),
        weeklyAll: UsageBucket(percent: 0, resetAt: nil),
        weeklyModel: UsageBucket(percent: 0, resetAt: nil),
        weeklyModelName: nil
    )
}

enum UsageState: Equatable {
    case notConnected
    case loading
    case loaded(ClaudeUsage)
    case error(String)
}

// MARK: - Usage Manager

class ClaudeUsageManager: ObservableObject {
    static let shared = ClaudeUsageManager()
    
    @Published var state: UsageState = .notConnected
    @Published var lastUpdateText: String = "never"
    @Published var debugLog: String = ""
    
    private var lastUpdateTime: Date?
    private var refreshTimer: Timer?
    private var textTimer: Timer?
    private let authManager = AnthropicAuthManager.shared
    
    // Parsing is delegated to ClaudeUsageParser
    
    private init() {}
    
    private func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)"
        print(line)
        DispatchQueue.main.async {
            self.debugLog += line + "\n"
            // Keep only the last 2000 chars
            if self.debugLog.count > 2000 {
                self.debugLog = String(self.debugLog.suffix(2000))
            }
        }
    }
    
    // MARK: - Polling policy
    //
    // The usage endpoint enforces a budget on third-party clients of roughly
    // 28-30 requests per identity per rolling hour (measured by the claude-swap
    // project). Polling every 30 s exceeded that and produced constant HTTP 429s.
    // Target: at most ~20 requests/hour, leaving headroom for manual refreshes.
    static let pollInterval: TimeInterval = 180
    /// Data younger than this is considered fresh; opening the popover does not
    /// trigger a new fetch while it holds.
    static let serveTTL: TimeInterval = 180
    /// Wait after a 429 that carried no usable Retry-After.
    static let defaultBackoff: TimeInterval = 300
    /// Extra wait on top of Retry-After: a retry landing exactly on the server's
    /// deadline is frequently re-blocked for another full window.
    static let retryAfterMargin: TimeInterval = 120
    /// Upper bound on any single backoff so a pathological header cannot park
    /// the app for hours.
    static let maxBackoff: TimeInterval = 3900

    /// Earliest time the next network request is allowed after a 429.
    private(set) var backoffUntil: Date?

    func startAutoRefresh() {
        // Invalidate existing timers to avoid duplicates
        refreshTimer?.invalidate()
        textTimer?.invalidate()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.refresh(force: false)
        }

        // Update "updated X ago" text every second
        textTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateLastUpdateText()
        }

        // Initial refresh, unless we already have fresh data (the popover calls
        // this every time it opens).
        refresh(force: false)
    }

    /// True when claude-swap is installed; usage then comes from cswap for all
    /// accounts (see ClaudeAccountsManager) instead of a direct API poll.
    var usesCswap: Bool { ClaudeAccountsManager.shared.isAvailable }

    /// - Parameter force: `true` for a user-initiated refresh (bypasses the
    ///   freshness check but still honors a server-imposed backoff).
    func refresh(force: Bool = true) {
        if ClaudeAccountsManager.shared.detect() {
            if case .loaded = state {} else if case .error = state {} else { state = .loading }
            log("refresh: delegating to cswap")
            ClaudeAccountsManager.shared.refresh(force: force)
            return
        }

        guard authManager.isConnected else {
            state = .notConnected
            return
        }

        if let until = backoffUntil {
            if Date() < until {
                let secs = Int(until.timeIntervalSinceNow)
                log("refresh: skipped, backing off for another \(secs)s after 429")
                return
            }
            backoffUntil = nil
        }

        if !force, let last = lastUpdateTime, Date().timeIntervalSince(last) < Self.serveTTL {
            log("refresh: skipped, data is \(Int(Date().timeIntervalSince(last)))s old (< \(Int(Self.serveTTL))s)")
            return
        }
        
        // Always show loading if we don't have data yet
        if case .loaded = state {
            // Keep showing existing data while refreshing
        } else {
            state = .loading
        }
        
        log("refresh: getting valid access token...")
        
        authManager.getValidAccessToken { [weak self] (token: String?) in
            guard let self = self else { return }
            guard let token = token else {
                self.log("refresh: no valid token returned")
                DispatchQueue.main.async {
                    if !self.authManager.isConnected {
                        self.state = .notConnected
                    } else if let reason = self.authManager.authError {
                        self.state = .error(reason)
                    } else {
                        self.state = .error("Session expired. Please reconnect in Settings.")
                    }
                }
                return
            }
            self.log("refresh: got token (\(token.prefix(8))...), fetching usage")
            self.fetchUsage(accessToken: token)
        }
    }
    
    private var retryCount = 0
    private let maxRetries = 1
    
    private func fetchUsage(accessToken: String) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AnthropicAuthManager.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.log("fetchUsage: network error: \(error.localizedDescription)")
                    self.state = .error("Network error: \(error.localizedDescription)")
                    return
                }
                
                let httpResponse = response as? HTTPURLResponse
                let statusCode = httpResponse?.statusCode ?? 0
                self.log("fetchUsage: HTTP \(statusCode)")
                
                guard let data = data else {
                    self.log("fetchUsage: no data")
                    self.state = .error("No data received.")
                    return
                }
                
                let bodyPreview = String(data: data, encoding: .utf8)?.prefix(500) ?? "(binary)"
                self.log("fetchUsage: body=\(bodyPreview)")
                
                if statusCode == 401 {
                    if self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        self.log("fetchUsage: 401, attempting token refresh (retry \(self.retryCount)/\(self.maxRetries))")
                        self.authManager.refreshAccessToken { (success: Bool) in
                            if success {
                                self.log("fetchUsage: token refreshed, retrying")
                                self.refresh()
                            } else {
                                self.log("fetchUsage: token refresh failed")
                                self.retryCount = 0
                                if self.authManager.source == .claudeCode {
                                    self.state = .error("Claude Code session rejected. Run `claude` in a terminal to sign in again.")
                                } else {
                                    self.state = .error("Session expired. Please reconnect in Settings.")
                                }
                            }
                        }
                    } else {
                        self.retryCount = 0
                        let bodyStr = String(data: data, encoding: .utf8) ?? ""
                        self.log("fetchUsage: 401 after max retries. body=\(bodyStr.prefix(200))")
                        self.state = .error("Authentication failed. Please reconnect in Settings.")
                    }
                    return
                }
                
                // Handle 429 (rate limited)
                // This is likely transient rate limiting on the usage endpoint.
                // Preserve last known usage data instead of showing an error.
                if statusCode == 429 {
                    let bodyStr = String(data: data, encoding: .utf8) ?? "(no body)"
                    self.log("fetchUsage: 429 RATE LIMITED")
                    self.log("fetchUsage: 429 body=\(bodyStr)")
                    
                    // Honor Retry-After (seconds form) plus a margin; otherwise a default wait.
                    var retryAfterSeconds: TimeInterval?
                    if let httpResp = httpResponse {
                        let headers = httpResp.allHeaderFields
                        if let retryAfter = headers["Retry-After"] ?? headers["retry-after"] {
                            self.log("fetchUsage: 429 Retry-After=\(retryAfter)")
                            retryAfterSeconds = Self.parseRetryAfter(retryAfter)
                        }
                        for (key, value) in headers {
                            if let keyStr = key as? String, keyStr.lowercased().contains("ratelimit") {
                                self.log("fetchUsage: 429 \(keyStr)=\(value)")
                            }
                        }
                    }
                    let wait = Self.backoffDuration(retryAfter: retryAfterSeconds)
                    self.backoffUntil = Date().addingTimeInterval(wait)
                    self.log("fetchUsage: 429 - next request no sooner than \(Int(wait))s from now")

                    // Keep existing data if we have it, otherwise show error
                    if case .loaded = self.state {
                        self.log("fetchUsage: 429 - keeping previous usage data")
                        // Don't change state - keep showing last known good data
                    } else {
                        self.state = .error("Rate limited by Anthropic. Retrying in \(Int(wait / 60)) min.")
                    }
                    return
                }
                
                if statusCode < 200 || statusCode >= 300 {
                    let bodyStr = String(data: data, encoding: .utf8) ?? ""
                    self.log("fetchUsage: HTTP \(statusCode) body=\(bodyStr.prefix(200))")
                    self.state = .error("Server error (HTTP \(statusCode))")
                    return
                }
                
                self.retryCount = 0
                self.parseUsageResponse(data)
            }
        }.resume()
    }
    
    // MARK: - External source (cswap)

    /// Accept usage produced by ClaudeAccountsManager for the active account.
    func applyExternal(usage: ClaudeUsage, fetchedAt: Date) {
        state = .loaded(usage)
        lastUpdateTime = fetchedAt
        updateLastUpdateText()
        backoffUntil = nil
    }

    /// Report a cswap-side failure. Keeps last good data when present.
    func applyExternalFailure(_ message: String) {
        if case .loaded = state {
            log("cswap: \(message) (keeping previous data)")
        } else {
            state = .error(message)
        }
    }

    /// Parse a Retry-After header value in its seconds form. HTTP-date form is
    /// rare on this endpoint and is treated as absent.
    static func parseRetryAfter(_ value: Any) -> TimeInterval? {
        let str = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let secs = TimeInterval(str), secs >= 0 else { return nil }
        return secs
    }

    /// How long to wait before the next request after a 429.
    /// - `nil` or `0`: the server gave no deadline (or the "saturated edge" case);
    ///   wait `defaultBackoff`.
    /// - `N > 0`: wait N + `retryAfterMargin`, capped at `maxBackoff`.
    static func backoffDuration(retryAfter: TimeInterval?) -> TimeInterval {
        guard let ra = retryAfter, ra > 0 else { return defaultBackoff }
        return min(ra + retryAfterMargin, maxBackoff)
    }

    private func parseUsageResponse(_ data: Data) {
        let result = ClaudeUsageParser.parseResponse(data)
        switch result {
        case .success(let usage):
            log("parseUsage: success! 5h=\(usage.fiveHour.percent)% weekly=\(usage.weeklyAll.percent)% \(usage.weeklyModelLabel)=\(usage.weeklyModel.percent)%")
            state = .loaded(usage)
            lastUpdateTime = Date()
            lastUpdateText = "just now"
            backoffUntil = nil
        case .failure(let error):
            switch error {
            case .invalidJSON:
                log("parseUsage: response is not a JSON object")
                state = .error("Invalid response format.")
            case .unrecognizedFormat(let keys):
                log("parseUsage: no known keys matched")
                state = .error("Unrecognized usage format. Keys: \(keys.joined(separator: ", "))")
            }
        }
    }
    
    private func updateLastUpdateText() {
        guard let lastUpdateTime = lastUpdateTime else {
            lastUpdateText = "never"
            return
        }
        
        let seconds = Int(Date().timeIntervalSince(lastUpdateTime))
        
        if seconds < 5 {
            lastUpdateText = "just now"
        } else if seconds < 60 {
            lastUpdateText = "\(seconds)s ago"
        } else if seconds < 3600 {
            lastUpdateText = "\(seconds / 60)m ago"
        } else {
            lastUpdateText = "\(seconds / 3600)h ago"
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
        textTimer?.invalidate()
    }
}
