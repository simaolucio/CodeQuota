import Foundation

enum MenuBarMetric: String, CaseIterable, Codable {
    case claude5Hour = "claude_5hour"
    case claudeWeeklyAll = "claude_weekly_all"
    case claudeWeeklyModel = "claude_weekly_model"
    case copilotPremium = "copilot_premium"
    
    var displayName: String {
        switch self {
        case .claude5Hour: return "Claude — 5-Hour Session"
        case .claudeWeeklyAll: return "Claude — Weekly All Models"
        case .claudeWeeklyModel: return "Claude — Weekly \(ClaudeUsage.preferredModelName)"
        case .copilotPremium: return "Copilot — Premium Requests"
        }
    }
    
    var shortName: String {
        switch self {
        case .claude5Hour: return "5h"
        case .claudeWeeklyAll: return "Wk"
        case .claudeWeeklyModel: return "Fab"
        case .copilotPremium: return "CP"
        }
    }
    
    var providerName: String {
        switch self {
        case .claude5Hour, .claudeWeeklyAll, .claudeWeeklyModel: return "Claude"
        case .copilotPremium: return "Copilot"
        }
    }
}

class MenuBarSettings: ObservableObject {
    static let shared = MenuBarSettings()
    
    static let key = "menubar_selected_metric"
    static let hiddenKey = "hidden_metrics"
    static let showResetTimeKey = "show_reset_time"
    
    let defaults: UserDefaults
    
    @Published var showResetTime: Bool {
        didSet {
            defaults.set(showResetTime, forKey: Self.showResetTimeKey)
        }
    }
    
    @Published var selectedMetric: MenuBarMetric {
        didSet {
            defaults.set(selectedMetric.rawValue, forKey: Self.key)
        }
    }
    
    @Published var hiddenMetrics: Set<MenuBarMetric> {
        didSet {
            let rawValues = hiddenMetrics.map { $0.rawValue }
            defaults.set(rawValues, forKey: Self.hiddenKey)
        }
    }
    
    private convenience init() {
        self.init(defaults: .standard)
    }
    
    init(defaults: UserDefaults) {
        self.defaults = defaults
        
        if let raw = defaults.string(forKey: Self.key),
           let metric = MenuBarMetric(rawValue: Self.migrateRawValue(raw)) {
            selectedMetric = metric
        } else {
            selectedMetric = .claude5Hour
        }
        
        if let rawValues = defaults.stringArray(forKey: Self.hiddenKey) {
            hiddenMetrics = Set(rawValues.compactMap { MenuBarMetric(rawValue: Self.migrateRawValue($0)) })
        } else {
            hiddenMetrics = []
        }
        
        // Default to true if never set
        if defaults.object(forKey: Self.showResetTimeKey) != nil {
            showResetTime = defaults.bool(forKey: Self.showResetTimeKey)
        } else {
            showResetTime = true
        }
    }
    
    /// Map raw values persisted by older versions onto current cases.
    /// The weekly Sonnet metric became the weekly model (Fable) metric.
    static func migrateRawValue(_ raw: String) -> String {
        raw == "claude_weekly_sonnet" ? MenuBarMetric.claudeWeeklyModel.rawValue : raw
    }
    
    func isVisible(_ metric: MenuBarMetric) -> Bool {
        !hiddenMetrics.contains(metric)
    }
    
    func toggleVisibility(_ metric: MenuBarMetric) {
        if hiddenMetrics.contains(metric) {
            hiddenMetrics.remove(metric)
        } else {
            // Don't allow hiding the selected menu bar metric
            if metric == selectedMetric { return }
            hiddenMetrics.insert(metric)
        }
    }
}
