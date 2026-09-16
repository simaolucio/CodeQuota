import XCTest
@testable import CodeQuota

final class UsageBucketTests: XCTestCase {
    
    // MARK: - timeRemainingString
    
    func testTimeRemainingString_nilResetAt_returnsDash() {
        let bucket = UsageBucket(percent: 50, resetAt: nil)
        XCTAssertEqual(bucket.timeRemainingString, "--")
    }
    
    func testTimeRemainingString_pastDate_returnsNow() {
        let pastDate = Date().addingTimeInterval(-60)
        let bucket = UsageBucket(percent: 75, resetAt: pastDate)
        XCTAssertEqual(bucket.timeRemainingString, "now")
    }
    
    func testTimeRemainingString_exactlyNow_returnsNow() {
        // 0 seconds remaining
        let bucket = UsageBucket(percent: 100, resetAt: Date())
        XCTAssertEqual(bucket.timeRemainingString, "now")
    }
    
    func testTimeRemainingString_minutesOnly() {
        // 90 seconds from now = 1 minute (Int division: 90 / 60 = 1)
        let futureDate = Date().addingTimeInterval(90)
        let bucket = UsageBucket(percent: 30, resetAt: futureDate)
        XCTAssertEqual(bucket.timeRemainingString, "1m")
    }
    
    func testTimeRemainingString_hoursAndMinutes() {
        // Use a fixed reference point to avoid timing drift
        // 2 hours 15 minutes 30 seconds — the 30s buffer ensures we stay in the "2h 15m" bucket
        let futureDate = Date().addingTimeInterval(2 * 3600 + 15 * 60 + 30)
        let bucket = UsageBucket(percent: 60, resetAt: futureDate)
        XCTAssertEqual(bucket.timeRemainingString, "2h 15m")
    }
    
    func testTimeRemainingString_daysAndHours() {
        // 1 day 3 hours 30 seconds — buffer to stay in "1d 3h" bucket
        let futureDate = Date().addingTimeInterval(86400 + 3 * 3600 + 30)
        let bucket = UsageBucket(percent: 10, resetAt: futureDate)
        XCTAssertEqual(bucket.timeRemainingString, "1d 3h")
    }
    
    func testTimeRemainingString_exactlyOneHour() {
        // 1 hour + 30 seconds buffer to stay in "1h 0m" bucket
        let futureDate = Date().addingTimeInterval(3600 + 30)
        let bucket = UsageBucket(percent: 40, resetAt: futureDate)
        XCTAssertEqual(bucket.timeRemainingString, "1h 0m")
    }
    
    func testTimeRemainingString_zeroMinutesRemaining() {
        // 30 seconds from now
        let futureDate = Date().addingTimeInterval(30)
        let bucket = UsageBucket(percent: 90, resetAt: futureDate)
        XCTAssertEqual(bucket.timeRemainingString, "0m")
    }
    
    // MARK: - ClaudeUsage.empty
    
    func testClaudeUsageEmpty() {
        let empty = ClaudeUsage.empty
        XCTAssertEqual(empty.fiveHour.percent, 0)
        XCTAssertEqual(empty.weeklyAll.percent, 0)
        XCTAssertEqual(empty.weeklyModel.percent, 0)
        XCTAssertNil(empty.fiveHour.resetAt)
        XCTAssertNil(empty.weeklyAll.resetAt)
        XCTAssertNil(empty.weeklyModel.resetAt)
    }
    
    // MARK: - Equatable
    
    func testUsageBucketEquality() {
        let date = Date()
        let a = UsageBucket(percent: 50, resetAt: date)
        let b = UsageBucket(percent: 50, resetAt: date)
        let c = UsageBucket(percent: 75, resetAt: date)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
