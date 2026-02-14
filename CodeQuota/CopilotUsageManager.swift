import Foundation
import Combine

// MARK: - Copilot Usage Models

struct CopilotUsage: Equatable {
    var premiumRequestsUsed: Int
    var premiumRequestsLimit: Int // 0 = unknown
    var percent: Double // 0-100
    var byModel: [(model: String, count: Int)]
    
    static func == (lhs: CopilotUsage, rhs: CopilotUsage) -> Bool {
        lhs.premiumRequestsUsed == rhs.premiumRequestsUsed
        && lhs.premiumRequestsLimit == rhs.premiumRequestsLimit
        && lhs.percent == rhs.percent
    }
    
    static let empty = CopilotUsage(premiumRequestsUsed: 0, premiumRequestsLimit: 0, percent: 0, byModel: [])
}

enum CopilotUsageState: Equatable {
    case notConnected
    case loading
    case loaded(CopilotUsage)
    case error(String)
}

// MARK: - Copilot Usage Manager

class CopilotUsageManager: ObservableObject {
    static let shared = CopilotUsageManager()
    
    @Published var state: CopilotUsageState = .notConnected
    @Published var lastUpdateText: String = "never"
    
    private var lastUpdateTime: Date?
    private var refreshTimer: Timer?
    private var textTimer: Timer?
    private let authManager = GitHubAuthManager.shared
    
    // Known plan limits (premium requests/month)
    private static let planLimits: [String: Int] = [
        "free": 50,
        "pro": 300,
        "pro+": 1500,
        "business": 300,
        "enterprise": 1000,
    ]
    
    private init() {}
    
    func startAutoRefresh() {
        refreshTimer?.invalidate()
        textTimer?.invalidate()
        
        // Copilot billing data is monthly, no need to poll aggressively
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        
        textTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateLastUpdateText()
        }
        
        refresh()
    }
    
    func refresh() {
        guard authManager.isConnected, let token = authManager.accessToken else {
            state = .notConnected
            return
        }
        
        let username = authManager.username
        guard !username.isEmpty else {
            if case .loaded = state { } else { state = .loading }
            // Username not loaded yet, retry shortly
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.refresh()
            }
            return
        }
        
        if case .loaded = state { } else { state = .loading }
        
        fetchPremiumRequestUsage(token: token, username: username)
    }
    
    private func fetchPremiumRequestUsage(token: String, username: String) {
        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        
        let urlString = "https://api.github.com/users/\(username)/settings/billing/premium_request/usage?year=\(year)&month=\(month)"
        
        guard let url = URL(string: urlString) else {
            state = .error("Invalid URL for billing API.")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        print("[Copilot] fetching: \(urlString)")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    print("[Copilot] network error: \(error)")
                    self.state = .error("Network error: \(error.localizedDescription)")
                    return
                }
                
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("[Copilot] HTTP \(statusCode)")
                
                guard let data = data else {
                    self.state = .error("No data received.")
                    return
                }
                
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                print("[Copilot] body: \(bodyStr.prefix(500))")
                
                if statusCode == 401 || statusCode == 403 {
                    self.state = .error("Access denied (HTTP \(statusCode)). The token may lack the required scope.")
                    return
                }
                
                if statusCode == 404 {
                    self.state = .error("Billing API not found. You may need a Copilot Pro subscription.")
                    return
                }
                
                if statusCode < 200 || statusCode >= 300 {
                    self.state = .error("GitHub API error (HTTP \(statusCode))")
                    return
                }
                
                self.parseUsageResponse(data)
            }
        }.resume()
    }
    
    private func parseUsageResponse(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                state = .error("Invalid response format.")
                return
            }
            
            print("[Copilot] parse keys: \(json.keys.sorted())")
            
            var totalUsed = 0
            var totalDiscount = 0
            var byModel: [(String, Int)] = []
            
            let items = (json["usageItems"] as? [[String: Any]])
                ?? (json["usage_items"] as? [[String: Any]])
                ?? []
            
            for item in items {
                let model = item["model"] as? String
                    ?? item["model"] as? String
                    ?? "Unknown"
                
                // grossQuantity comes as Double from the API (e.g. 1494.0)
                let gross = intFromAny(item["grossQuantity"] ?? item["gross_quantity"])
                let discount = intFromAny(item["discountQuantity"] ?? item["discount_quantity"])
                
                totalUsed += gross
                totalDiscount += discount
                if gross > 0 {
                    byModel.append((model, gross))
                }
            }
            
            // Infer plan limit from discount quantity (discount = included allowance)
            // Fall back to common plan limits
            let limit: Int
            if totalDiscount > 0 {
                // The discount represents the plan's included allowance
                // Round up to the nearest known plan tier
                limit = inferPlanLimit(fromDiscount: totalDiscount)
            } else {
                limit = 300 // Default Copilot Pro
            }
            
            let percent = limit > 0 ? min(Double(totalUsed) / Double(limit) * 100, 100) : 0
            
            byModel.sort { $0.1 > $1.1 }
            
            let usage = CopilotUsage(
                premiumRequestsUsed: totalUsed,
                premiumRequestsLimit: limit,
                percent: percent,
                byModel: byModel
            )
            
            print("[Copilot] parsed: used=\(totalUsed)/\(limit) (\(String(format: "%.0f", percent))%) models=\(byModel.count)")
            
            state = .loaded(usage)
            lastUpdateTime = Date()
            lastUpdateText = "just now"
            
        } catch {
            state = .error("Parse error: \(error.localizedDescription)")
        }
    }
    
    /// Extract an Int from a JSON value that may be Int or Double
    private func intFromAny(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String, let i = Int(s) { return i }
        return 0
    }
    
    /// Infer the plan limit from the total discount (included allowance)
    private func inferPlanLimit(fromDiscount discount: Int) -> Int {
        // Known plan tiers
        let tiers = [50, 300, 1500]
        // Find the smallest tier >= discount, or use the discount itself
        for tier in tiers {
            if discount <= tier { return tier }
        }
        // If discount exceeds all known tiers, use it directly
        return discount
    }
    
    private func updateLastUpdateText() {
        guard let t = lastUpdateTime else { lastUpdateText = "never"; return }
        let s = Int(Date().timeIntervalSince(t))
        if s < 5 { lastUpdateText = "just now" }
        else if s < 60 { lastUpdateText = "\(s)s ago" }
        else if s < 3600 { lastUpdateText = "\(s / 60)m ago" }
        else { lastUpdateText = "\(s / 3600)h ago" }
    }
    
    deinit {
        refreshTimer?.invalidate()
        textTimer?.invalidate()
    }
}
