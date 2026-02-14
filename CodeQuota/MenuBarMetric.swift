import Foundation

enum MenuBarMetric: String, CaseIterable, Codable {
    case claude5Hour = "claude_5hour"
    case claudeWeeklyAll = "claude_weekly_all"
    case claudeWeeklySonnet = "claude_weekly_sonnet"
    case copilotPremium = "copilot_premium"
    
    var displayName: String {
        switch self {
        case .claude5Hour: return "Claude — 5-Hour Session"
        case .claudeWeeklyAll: return "Claude — Weekly All Models"
        case .claudeWeeklySonnet: return "Claude — Weekly Sonnet"
        case .copilotPremium: return "Copilot — Premium Requests"
        }
    }
    
    var shortName: String {
        switch self {
        case .claude5Hour: return "5h"
        case .claudeWeeklyAll: return "Wk"
        case .claudeWeeklySonnet: return "Son"
        case .copilotPremium: return "CP"
        }
    }
    
    var providerName: String {
        switch self {
        case .claude5Hour, .claudeWeeklyAll, .claudeWeeklySonnet: return "Claude"
        case .copilotPremium: return "Copilot"
        }
    }
}

class MenuBarSettings: ObservableObject {
    static let shared = MenuBarSettings()
    
    private static let key = "menubar_selected_metric"
    
    @Published var selectedMetric: MenuBarMetric {
        didSet {
            UserDefaults.standard.set(selectedMetric.rawValue, forKey: Self.key)
        }
    }
    
    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key),
           let metric = MenuBarMetric(rawValue: raw) {
            selectedMetric = metric
        } else {
            selectedMetric = .claude5Hour
        }
    }
}
