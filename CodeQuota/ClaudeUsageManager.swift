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
    var fiveHour: UsageBucket
    var dailyAllModels: UsageBucket
    var dailySonnet: UsageBucket
    
    static let empty = ClaudeUsage(
        fiveHour: UsageBucket(percent: 0, resetAt: nil),
        dailyAllModels: UsageBucket(percent: 0, resetAt: nil),
        dailySonnet: UsageBucket(percent: 0, resetAt: nil)
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
    
    func startAutoRefresh() {
        // Invalidate existing timers to avoid duplicates
        refreshTimer?.invalidate()
        textTimer?.invalidate()
        
        // Refresh usage every 30 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        
        // Update "updated X ago" text every second
        textTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateLastUpdateText()
        }
        
        // Initial refresh
        refresh()
    }
    
    func refresh() {
        guard authManager.isConnected else {
            state = .notConnected
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
                    self.state = .error("Session expired. Please reconnect in Settings.")
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
                                self.state = .error("Session expired. Please reconnect in Settings.")
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
                    
                    // Log relevant headers for diagnostics
                    if let httpResp = httpResponse {
                        let headers = httpResp.allHeaderFields
                        if let retryAfter = headers["Retry-After"] ?? headers["retry-after"] {
                            self.log("fetchUsage: 429 Retry-After=\(retryAfter)")
                        }
                        for (key, value) in headers {
                            if let keyStr = key as? String, keyStr.lowercased().contains("ratelimit") {
                                self.log("fetchUsage: 429 \(keyStr)=\(value)")
                            }
                        }
                    }
                    
                    // Keep existing data if we have it, otherwise show error
                    if case .loaded = self.state {
                        self.log("fetchUsage: 429 - keeping previous usage data")
                        // Don't change state - keep showing last known good data
                    } else {
                        self.state = .error("Rate limited. Please wait and try again.")
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
    
    private func parseUsageResponse(_ data: Data) {
        let result = ClaudeUsageParser.parseResponse(data)
        switch result {
        case .success(let usage):
            log("parseUsage: success! 5h=\(usage.fiveHour.percent)% daily=\(usage.dailyAllModels.percent)% sonnet=\(usage.dailySonnet.percent)%")
            state = .loaded(usage)
            lastUpdateTime = Date()
            lastUpdateText = "just now"
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
