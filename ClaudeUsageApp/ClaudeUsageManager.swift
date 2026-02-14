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
    
    // ISO 8601 date formatter
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
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
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log("parseUsage: response is not a JSON object")
                state = .error("Invalid response format.")
                return
            }
            
            log("parseUsage: keys=\(json.keys.sorted())")
            
            // Parse each usage bucket — try many possible key names
            let fiveHour = parseBucket(json, key: "five_hour")
                ?? parseBucket(json, key: "fiveHour")
                ?? parseBucket(json, key: "5_hour")
                ?? parseBucket(json, key: "short_term")
                ?? parseBucket(json, key: "shortTerm")
            
            let dailyAll = parseBucket(json, key: "seven_day")
                ?? parseBucket(json, key: "seven_day_all")
                ?? parseBucket(json, key: "daily")
                ?? parseBucket(json, key: "sevenDayAll")
                ?? parseBucket(json, key: "7_day_all")
                ?? parseBucket(json, key: "long_term")
                ?? parseBucket(json, key: "longTerm")
                ?? parseBucket(json, key: "weekly")
            
            let dailySonnet = parseBucket(json, key: "seven_day_sonnet")
                ?? parseBucket(json, key: "daily_sonnet")
                ?? parseBucket(json, key: "sevenDaySonnet")
                ?? parseBucket(json, key: "7_day_sonnet")
                ?? parseBucket(json, key: "sonnet")
            
            // If none of the known keys matched, try to parse the top-level keys dynamically
            if fiveHour == nil && dailyAll == nil && dailySonnet == nil {
                log("parseUsage: no known keys matched, attempting dynamic parse")
                // Try all top-level keys as buckets
                var buckets: [(String, UsageBucket)] = []
                for (key, value) in json {
                    if let dict = value as? [String: Any] {
                        if let bucket = parseBucketFromDict(dict) {
                            buckets.append((key, bucket))
                            log("parseUsage: found bucket '\(key)': pct=\(bucket.percent)")
                        }
                    }
                }
                
                if !buckets.isEmpty {
                    let sorted = buckets.sorted { $0.0 < $1.0 }
                    let usage = ClaudeUsage(
                        fiveHour: sorted.count > 0 ? sorted[0].1 : UsageBucket(percent: 0, resetAt: nil),
                        dailyAllModels: sorted.count > 1 ? sorted[1].1 : UsageBucket(percent: 0, resetAt: nil),
                        dailySonnet: sorted.count > 2 ? sorted[2].1 : UsageBucket(percent: 0, resetAt: nil)
                    )
                    state = .loaded(usage)
                    lastUpdateTime = Date()
                    lastUpdateText = "just now"
                    return
                }
                
                state = .error("Unrecognized usage format. Keys: \(json.keys.sorted().joined(separator: ", "))")
                return
            }
            
            let usage = ClaudeUsage(
                fiveHour: fiveHour ?? UsageBucket(percent: 0, resetAt: nil),
                dailyAllModels: dailyAll ?? UsageBucket(percent: 0, resetAt: nil),
                dailySonnet: dailySonnet ?? UsageBucket(percent: 0, resetAt: nil)
            )
            
            log("parseUsage: success! 5h=\(usage.fiveHour.percent)% daily=\(usage.dailyAllModels.percent)% sonnet=\(usage.dailySonnet.percent)%")
            state = .loaded(usage)
            lastUpdateTime = Date()
            lastUpdateText = "just now"
            
        } catch {
            log("parseUsage: JSON parse error: \(error)")
            state = .error("Parse error: \(error.localizedDescription)")
        }
    }
    
    private func parseBucket(_ json: [String: Any], key: String) -> UsageBucket? {
        // Try as nested object
        if let bucket = json[key] as? [String: Any] {
            return parseBucketFromDict(bucket)
        }
        
        // Try as flat keys
        if let utilization = json["\(key)_utilization"] as? Double {
            let resetAt = parseDate(from: json, key: "\(key)_reset_at")
            return UsageBucket(percent: clamp0100(utilization), resetAt: resetAt)
        }
        
        return nil
    }
    
    private func parseBucketFromDict(_ dict: [String: Any]) -> UsageBucket? {
        let utilization = (dict["utilization"] as? Double)
            ?? (dict["usage"] as? Double)
            ?? (dict["percent"] as? Double).map { $0 / 100.0 }
            ?? (dict["value"] as? Double)
        
        guard let util = utilization else { return nil }
        
        let resetAt = parseDate(from: dict, key: "reset_at")
            ?? parseDate(from: dict, key: "resetAt")
            ?? parseDate(from: dict, key: "resets_at")
            ?? parseDate(from: dict, key: "reset")
            ?? parseDate(from: dict, key: "expires_at")
        
        return UsageBucket(percent: clamp0100(util), resetAt: resetAt)
    }
    
    private func parseDate(from dict: [String: Any], key: String) -> Date? {
        if let str = dict[key] as? String {
            return Self.isoFormatter.date(from: str)
                ?? Self.isoFormatterNoFrac.date(from: str)
        }
        if let ts = dict[key] as? TimeInterval {
            // Interpret as seconds since epoch if large enough, otherwise ignore
            if ts > 1_000_000_000 {
                return Date(timeIntervalSince1970: ts)
            }
        }
        return nil
    }
    
    private func clamp0100(_ v: Double) -> Double {
        min(max(v, 0), 100)
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
