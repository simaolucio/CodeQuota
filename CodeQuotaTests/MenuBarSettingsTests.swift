import XCTest
@testable import CodeQuota

final class MenuBarSettingsTests: XCTestCase {
    
    private var testDefaults: UserDefaults!
    
    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "com.codequota.tests.\(name)")!
        // Clear all test keys
        testDefaults.removePersistentDomain(forName: "com.codequota.tests.\(name)")
    }
    
    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "com.codequota.tests.\(name)")
        testDefaults = nil
        super.tearDown()
    }
    
    // MARK: - Defaults
    
    func testDefaultSelectedMetric() {
        let settings = MenuBarSettings(defaults: testDefaults)
        XCTAssertEqual(settings.selectedMetric, .claude5Hour)
    }
    
    func testDefaultHiddenMetrics_isEmpty() {
        let settings = MenuBarSettings(defaults: testDefaults)
        XCTAssertTrue(settings.hiddenMetrics.isEmpty)
    }
    
    func testDefaultShowResetTime_isTrue() {
        let settings = MenuBarSettings(defaults: testDefaults)
        XCTAssertTrue(settings.showResetTime)
    }
    
    // MARK: - Persistence
    
    func testSelectedMetric_persistsToDefaults() {
        let settings = MenuBarSettings(defaults: testDefaults)
        settings.selectedMetric = .copilotPremium
        
        let raw = testDefaults.string(forKey: MenuBarSettings.key)
        XCTAssertEqual(raw, "copilot_premium")
    }
    
    func testSelectedMetric_restoresFromDefaults() {
        testDefaults.set("claude_weekly_model", forKey: MenuBarSettings.key)
        let settings = MenuBarSettings(defaults: testDefaults)
        XCTAssertEqual(settings.selectedMetric, .claudeWeeklyModel)
    }
    
    func testSelectedMetric_migratesLegacySonnetRawValue() {
        testDefaults.set("claude_weekly_sonnet", forKey: MenuBarSettings.key)
        testDefaults.set(["claude_weekly_sonnet"], forKey: MenuBarSettings.hiddenKey)
        let settings = MenuBarSettings(defaults: testDefaults)
        XCTAssertEqual(settings.selectedMetric, .claudeWeeklyModel)
        XCTAssertEqual(settings.hiddenMetrics, [.claudeWeeklyModel])
    }
    
    func testShowResetTime_persistsToDefaults() {
        let settings = MenuBarSettings(defaults: testDefaults)
        settings.showResetTime = false
        
        XCTAssertFalse(testDefaults.bool(forKey: MenuBarSettings.showResetTimeKey))
    }
    
    func testHiddenMetrics_persistsToDefaults() {
        let settings = MenuBarSettings(defaults: testDefaults)
        settings.hiddenMetrics = [.claudeWeeklyAll, .claudeWeeklyModel]
        
        let raw = testDefaults.stringArray(forKey: MenuBarSettings.hiddenKey)
        XCTAssertNotNil(raw)
        XCTAssertEqual(Set(raw!), Set(["claude_weekly_all", "claude_weekly_model"]))
    }
    
    // MARK: - isVisible
    
    func testIsVisible_defaultAllVisible() {
        let settings = MenuBarSettings(defaults: testDefaults)
        for metric in MenuBarMetric.allCases {
            XCTAssertTrue(settings.isVisible(metric), "\(metric) should be visible by default")
        }
    }
    
    func testIsVisible_hiddenMetricNotVisible() {
        let settings = MenuBarSettings(defaults: testDefaults)
        settings.hiddenMetrics = [.copilotPremium]
        XCTAssertFalse(settings.isVisible(.copilotPremium))
        XCTAssertTrue(settings.isVisible(.claude5Hour))
    }
    
    // MARK: - toggleVisibility
    
    func testToggleVisibility_hideNonSelectedMetric() {
        let settings = MenuBarSettings(defaults: testDefaults)
        settings.selectedMetric = .claude5Hour
        
        settings.toggleVisibility(.copilotPremium)
        XCTAssertTrue(settings.hiddenMetrics.contains(.copilotPremium))
    }
    
    func testToggleVisibility_unhideHiddenMetric() {
        let settings = MenuBarSettings(defaults: testDefaults)
        settings.hiddenMetrics = [.copilotPremium]
        
        settings.toggleVisibility(.copilotPremium)
        XCTAssertFalse(settings.hiddenMetrics.contains(.copilotPremium))
    }
    
    func testToggleVisibility_cannotHideSelectedMetric() {
        let settings = MenuBarSettings(defaults: testDefaults)
        settings.selectedMetric = .claude5Hour
        
        settings.toggleVisibility(.claude5Hour) // Should be a no-op
        XCTAssertFalse(settings.hiddenMetrics.contains(.claude5Hour))
        XCTAssertTrue(settings.isVisible(.claude5Hour))
    }
    
    func testToggleVisibility_canHideOtherMetricsAfterChangingSelection() {
        let settings = MenuBarSettings(defaults: testDefaults)
        settings.selectedMetric = .copilotPremium
        
        // Now claude5Hour is no longer selected, so it can be hidden
        settings.toggleVisibility(.claude5Hour)
        XCTAssertTrue(settings.hiddenMetrics.contains(.claude5Hour))
    }
    
    // MARK: - MenuBarMetric properties
    
    func testMenuBarMetric_displayNames() {
        XCTAssertEqual(MenuBarMetric.claude5Hour.displayName, "Claude \u{2014} 5-Hour Session")
        XCTAssertEqual(MenuBarMetric.copilotPremium.displayName, "Copilot \u{2014} Premium Requests")
    }
    
    func testMenuBarMetric_shortNames() {
        XCTAssertEqual(MenuBarMetric.claude5Hour.shortName, "5h")
        XCTAssertEqual(MenuBarMetric.claudeWeeklyAll.shortName, "Wk")
        XCTAssertEqual(MenuBarMetric.claudeWeeklyModel.shortName, "Fab")
        XCTAssertEqual(MenuBarMetric.copilotPremium.shortName, "CP")
    }
    
    func testMenuBarMetric_providerNames() {
        XCTAssertEqual(MenuBarMetric.claude5Hour.providerName, "Claude")
        XCTAssertEqual(MenuBarMetric.claudeWeeklyAll.providerName, "Claude")
        XCTAssertEqual(MenuBarMetric.claudeWeeklyModel.providerName, "Claude")
        XCTAssertEqual(MenuBarMetric.copilotPremium.providerName, "Copilot")
    }
    
    func testMenuBarMetric_rawValues() {
        XCTAssertEqual(MenuBarMetric.claude5Hour.rawValue, "claude_5hour")
        XCTAssertEqual(MenuBarMetric.claudeWeeklyAll.rawValue, "claude_weekly_all")
        XCTAssertEqual(MenuBarMetric.claudeWeeklyModel.rawValue, "claude_weekly_model")
        XCTAssertEqual(MenuBarMetric.copilotPremium.rawValue, "copilot_premium")
    }
    
    func testMenuBarMetric_codable() throws {
        let original = MenuBarMetric.claudeWeeklyModel
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MenuBarMetric.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
