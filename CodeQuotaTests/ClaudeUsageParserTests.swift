import XCTest
@testable import CodeQuota

final class ClaudeUsageParserTests: XCTestCase {
    
    // MARK: - Helpers
    
    private func jsonData(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - clamp0100
    
    func testClamp0100_normalValue() {
        XCTAssertEqual(ClaudeUsageParser.clamp0100(50), 50)
    }
    
    func testClamp0100_negativeValue() {
        XCTAssertEqual(ClaudeUsageParser.clamp0100(-10), 0)
    }
    
    func testClamp0100_overflowValue() {
        XCTAssertEqual(ClaudeUsageParser.clamp0100(150), 100)
    }
    
    func testClamp0100_zeroValue() {
        XCTAssertEqual(ClaudeUsageParser.clamp0100(0), 0)
    }
    
    func testClamp0100_hundredValue() {
        XCTAssertEqual(ClaudeUsageParser.clamp0100(100), 100)
    }
    
    // MARK: - parseDate
    
    func testParseDate_iso8601WithFractionalSeconds() {
        let dict: [String: Any] = ["reset_at": "2025-06-15T12:30:00.000Z"]
        let date = ClaudeUsageParser.parseDate(from: dict, key: "reset_at")
        XCTAssertNotNil(date)
    }
    
    func testParseDate_iso8601WithoutFractionalSeconds() {
        let dict: [String: Any] = ["reset_at": "2025-06-15T12:30:00Z"]
        let date = ClaudeUsageParser.parseDate(from: dict, key: "reset_at")
        XCTAssertNotNil(date)
    }
    
    func testParseDate_unixTimestamp() {
        let timestamp: TimeInterval = 1750000000 // Well above 1 billion
        let dict: [String: Any] = ["reset_at": timestamp]
        let date = ClaudeUsageParser.parseDate(from: dict, key: "reset_at")
        XCTAssertNotNil(date)
        XCTAssertEqual(date, Date(timeIntervalSince1970: timestamp))
    }
    
    func testParseDate_smallTimestamp_ignored() {
        // Timestamps below 1 billion are ignored (not a valid epoch)
        let dict: [String: Any] = ["reset_at": 100.0]
        let date = ClaudeUsageParser.parseDate(from: dict, key: "reset_at")
        XCTAssertNil(date)
    }
    
    func testParseDate_missingKey() {
        let dict: [String: Any] = ["other_key": "2025-06-15T12:30:00Z"]
        let date = ClaudeUsageParser.parseDate(from: dict, key: "reset_at")
        XCTAssertNil(date)
    }
    
    func testParseDate_invalidString() {
        let dict: [String: Any] = ["reset_at": "not-a-date"]
        let date = ClaudeUsageParser.parseDate(from: dict, key: "reset_at")
        XCTAssertNil(date)
    }
    
    // MARK: - parseBucketFromDict
    
    func testParseBucketFromDict_utilizationKey() {
        let dict: [String: Any] = ["utilization": 0.75, "reset_at": "2025-06-15T12:30:00Z"]
        let bucket = ClaudeUsageParser.parseBucketFromDict(dict)
        XCTAssertNotNil(bucket)
        XCTAssertEqual(bucket?.percent, 0.75)
        XCTAssertNotNil(bucket?.resetAt)
    }
    
    func testParseBucketFromDict_usageKey() {
        let dict: [String: Any] = ["usage": 45.5]
        let bucket = ClaudeUsageParser.parseBucketFromDict(dict)
        XCTAssertNotNil(bucket)
        XCTAssertEqual(bucket?.percent, 45.5)
    }
    
    func testParseBucketFromDict_percentKey_dividedBy100() {
        // "percent" values are divided by 100 (mapping from 0-10000 to 0-100 range)
        let dict: [String: Any] = ["percent": 7500.0]
        let bucket = ClaudeUsageParser.parseBucketFromDict(dict)
        XCTAssertNotNil(bucket)
        XCTAssertEqual(bucket?.percent, 75.0)
    }
    
    func testParseBucketFromDict_valueKey() {
        let dict: [String: Any] = ["value": 33.0]
        let bucket = ClaudeUsageParser.parseBucketFromDict(dict)
        XCTAssertNotNil(bucket)
        XCTAssertEqual(bucket?.percent, 33.0)
    }
    
    func testParseBucketFromDict_noUtilization_returnsNil() {
        let dict: [String: Any] = ["name": "test"]
        let bucket = ClaudeUsageParser.parseBucketFromDict(dict)
        XCTAssertNil(bucket)
    }
    
    func testParseBucketFromDict_triesMultipleResetKeys() {
        // Should find reset date under "resetAt" key
        let dict: [String: Any] = ["utilization": 0.5, "resetAt": "2025-06-15T12:30:00Z"]
        let bucket = ClaudeUsageParser.parseBucketFromDict(dict)
        XCTAssertNotNil(bucket?.resetAt)
        
        // Should find reset date under "resets_at" key
        let dict2: [String: Any] = ["utilization": 0.5, "resets_at": "2025-06-15T12:30:00Z"]
        let bucket2 = ClaudeUsageParser.parseBucketFromDict(dict2)
        XCTAssertNotNil(bucket2?.resetAt)
        
        // Should find reset date under "expires_at" key
        let dict3: [String: Any] = ["utilization": 0.5, "expires_at": "2025-06-15T12:30:00Z"]
        let bucket3 = ClaudeUsageParser.parseBucketFromDict(dict3)
        XCTAssertNotNil(bucket3?.resetAt)
    }
    
    // MARK: - parseBucket (nested vs flat)
    
    func testParseBucket_nestedObject() {
        let json: [String: Any] = [
            "five_hour": ["utilization": 0.65, "reset_at": "2025-06-15T12:30:00Z"]
        ]
        let bucket = ClaudeUsageParser.parseBucket(json, key: "five_hour")
        XCTAssertNotNil(bucket)
        XCTAssertEqual(bucket?.percent, 0.65)
    }
    
    func testParseBucket_flatKeys() {
        let json: [String: Any] = [
            "five_hour_utilization": 0.42,
            "five_hour_reset_at": "2025-06-15T12:30:00Z"
        ]
        let bucket = ClaudeUsageParser.parseBucket(json, key: "five_hour")
        XCTAssertNotNil(bucket)
        XCTAssertEqual(bucket?.percent, 0.42)
    }
    
    func testParseBucket_missingKey_returnsNil() {
        let json: [String: Any] = ["unrelated": 123]
        let bucket = ClaudeUsageParser.parseBucket(json, key: "five_hour")
        XCTAssertNil(bucket)
    }
    
    // MARK: - parseResponse (full JSON)
    
    func testParseResponse_wellFormedNestedResponse() {
        let data = jsonData([
            "five_hour": ["utilization": 0.25, "reset_at": "2025-06-15T12:30:00Z"],
            "seven_day": ["utilization": 0.50],
            "seven_day_sonnet": ["utilization": 0.10]
        ])
        
        let result = ClaudeUsageParser.parseResponse(data)
        
        switch result {
        case .success(let usage):
            XCTAssertEqual(usage.fiveHour.percent, 0.25)
            XCTAssertEqual(usage.weeklyAll.percent, 0.50)
            XCTAssertEqual(usage.weeklyModel.percent, 0.10)
            XCTAssertNotNil(usage.fiveHour.resetAt)
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }
    
    func testParseResponse_alternativeKeyNames() {
        let data = jsonData([
            "short_term": ["utilization": 0.30],
            "long_term": ["utilization": 0.60],
            "sonnet": ["utilization": 0.15]
        ])
        
        let result = ClaudeUsageParser.parseResponse(data)
        
        switch result {
        case .success(let usage):
            XCTAssertEqual(usage.fiveHour.percent, 0.30)
            XCTAssertEqual(usage.weeklyAll.percent, 0.60)
            XCTAssertEqual(usage.weeklyModel.percent, 0.15)
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }
    
    func testParseResponse_camelCaseKeys() {
        let data = jsonData([
            "fiveHour": ["utilization": 0.20],
            "sevenDayAll": ["utilization": 0.40],
            "sevenDaySonnet": ["utilization": 0.05]
        ])
        
        let result = ClaudeUsageParser.parseResponse(data)
        
        switch result {
        case .success(let usage):
            XCTAssertEqual(usage.fiveHour.percent, 0.20)
            XCTAssertEqual(usage.weeklyAll.percent, 0.40)
            XCTAssertEqual(usage.weeklyModel.percent, 0.05)
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }
    
    func testParseResponse_partialKeys_missingBucketsDefaultToZero() {
        // Only five_hour present — others should default to 0
        let data = jsonData([
            "five_hour": ["utilization": 0.80]
        ])
        
        let result = ClaudeUsageParser.parseResponse(data)
        
        switch result {
        case .success(let usage):
            XCTAssertEqual(usage.fiveHour.percent, 0.80)
            XCTAssertEqual(usage.weeklyAll.percent, 0)
            XCTAssertEqual(usage.weeklyModel.percent, 0)
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }
    
    func testParseResponse_invalidJSON_returnsFailure() {
        let data = "not json".data(using: .utf8)!
        let result = ClaudeUsageParser.parseResponse(data)
        
        switch result {
        case .success:
            XCTFail("Expected failure for invalid JSON")
        case .failure(let error):
            XCTAssertEqual(error, .invalidJSON)
        }
    }
    
    func testParseResponse_unrecognizedKeys_returnsFailure() {
        let data = jsonData(["foo": "bar", "baz": 123])
        let result = ClaudeUsageParser.parseResponse(data)
        
        switch result {
        case .success:
            XCTFail("Expected failure for unrecognized keys")
        case .failure(let error):
            if case .unrecognizedFormat(let keys) = error {
                XCTAssertTrue(keys.contains("foo"))
                XCTAssertTrue(keys.contains("baz"))
            } else {
                XCTFail("Expected unrecognizedFormat error")
            }
        }
    }
    
    func testParseResponse_dynamicFallback_unknownBucketKeys() {
        // No known key names, but values are valid bucket dicts
        let data = jsonData([
            "alpha_bucket": ["utilization": 0.10],
            "beta_bucket": ["utilization": 0.20],
            "gamma_bucket": ["utilization": 0.30]
        ])
        
        let result = ClaudeUsageParser.parseResponse(data)
        
        switch result {
        case .success(let usage):
            // Sorted alphabetically: alpha=0.10, beta=0.20, gamma=0.30
            XCTAssertEqual(usage.fiveHour.percent, 0.10)
            XCTAssertEqual(usage.weeklyAll.percent, 0.20)
            XCTAssertEqual(usage.weeklyModel.percent, 0.30)
        case .failure(let error):
            XCTFail("Expected success via dynamic fallback, got failure: \(error)")
        }
    }
    
    func testParseResponse_clampsValues() {
        let data = jsonData([
            "five_hour": ["utilization": 150.0] // Should be clamped to 100
        ])
        
        let result = ClaudeUsageParser.parseResponse(data)
        
        switch result {
        case .success(let usage):
            XCTAssertEqual(usage.fiveHour.percent, 100)
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    // MARK: - limits[] (current API shape)
    
    func testParseResponse_limitsArray_isAuthoritative() {
        let data = jsonData([
            "five_hour": ["utilization": 7.0, "resets_at": "2026-09-16T23:30:00.925212+00:00"],
            "seven_day": ["utilization": 12.0, "resets_at": "2026-09-21T20:59:59.925236+00:00"],
            "seven_day_sonnet": NSNull(),
            "seven_day_opus": NSNull(),
            "limits": [
                ["kind": "session", "group": "session", "percent": 7, "resets_at": "2026-09-16T23:30:00.925212+00:00", "scope": NSNull()],
                ["kind": "weekly_all", "group": "weekly", "percent": 12, "resets_at": "2026-09-21T20:59:59.925236+00:00", "scope": NSNull()],
                ["kind": "weekly_scoped", "group": "weekly", "percent": 63, "resets_at": "2026-09-21T21:00:00.925435+00:00",
                 "scope": ["model": ["id": NSNull(), "display_name": "Fable"], "surface": NSNull()]]
            ]
        ])
        
        switch ClaudeUsageParser.parseResponse(data) {
        case .success(let usage):
            XCTAssertEqual(usage.fiveHour.percent, 7)
            XCTAssertEqual(usage.weeklyAll.percent, 12)
            XCTAssertEqual(usage.weeklyModel.percent, 63)
            XCTAssertEqual(usage.weeklyModelName, "Fable")
            XCTAssertEqual(usage.weeklyModelLabel, "Fable")
            XCTAssertNotNil(usage.weeklyModel.resetAt)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }
    
    func testParseLimits_prefersFableAmongScoped() {
        let json: [String: Any] = ["limits": [
            ["kind": "weekly_scoped", "percent": 40, "scope": ["model": ["display_name": "Opus"]]],
            ["kind": "weekly_scoped", "percent": 55, "scope": ["model": ["display_name": "Fable"]]],
        ]]
        let limits = ClaudeUsageParser.parseLimits(json)
        XCTAssertEqual(limits.weeklyModel?.percent, 55)
        XCTAssertEqual(limits.weeklyModelName, "Fable")
    }
    
    func testParseLimits_fallsBackToFirstScopedModel() {
        let json: [String: Any] = ["limits": [
            ["kind": "weekly_scoped", "percent": 40, "scope": ["model": ["display_name": "Opus"]]],
        ]]
        let limits = ClaudeUsageParser.parseLimits(json)
        XCTAssertEqual(limits.weeklyModel?.percent, 40)
        XCTAssertEqual(limits.weeklyModelName, "Opus")
    }
    
    func testParseLimits_ignoresSurfaceScopedEntries() {
        let json: [String: Any] = ["limits": [
            ["kind": "weekly_scoped", "percent": 90, "scope": ["model": NSNull(), "surface": "cowork"]],
        ]]
        let limits = ClaudeUsageParser.parseLimits(json)
        XCTAssertNil(limits.weeklyModel)
    }
    
    func testParseResponse_legacyModelKeyNamesModel() {
        let data = jsonData(["five_hour": ["utilization": 0.1], "seven_day_sonnet": ["utilization": 0.2]])
        if case .success(let usage) = ClaudeUsageParser.parseResponse(data) {
            XCTAssertEqual(usage.weeklyModel.percent, 0.2)
            XCTAssertEqual(usage.weeklyModelName, "Sonnet")
        } else {
            XCTFail("Expected success")
        }
    }
}
