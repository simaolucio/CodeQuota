import XCTest
@testable import CodeQuota

final class ClaudeCodeCredentialsTests: XCTestCase {

    // Shape Claude Code writes to the Keychain / .credentials.json
    private let sample = """
    {"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"sk-ant-ort01-xyz",
    "expiresAt":1789605114083,"refreshTokenExpiresAt":1800000000000,
    "scopes":["user:inference","user:profile"],"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"},
    "mcpOAuth":{}}
    """

    func testParse_fullShape() throws {
        let creds = try XCTUnwrap(ClaudeCodeCredentials.parse(sample))
        XCTAssertEqual(creds.accessToken, "sk-ant-oat01-abc")
        XCTAssertEqual(creds.subscriptionType, "max")
        XCTAssertEqual(creds.expiresAt, Date(timeIntervalSince1970: 1789605114.083))
    }

    func testParse_expiresAtAsDouble() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"t","expiresAt":1700000000000.0}}"#
        let creds = try XCTUnwrap(ClaudeCodeCredentials.parse(json))
        XCTAssertEqual(creds.expiresAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testParse_missingExpiry_isNotExpired() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"t"}}"#
        let creds = try XCTUnwrap(ClaudeCodeCredentials.parse(json))
        XCTAssertNil(creds.expiresAt)
        XCTAssertFalse(creds.isExpired)
    }

    func testIsExpired_pastMillis() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"t","expiresAt":1000000000000}}"#
        let creds = try XCTUnwrap(ClaudeCodeCredentials.parse(json))
        XCTAssertTrue(creds.isExpired)
    }

    func testParse_rejectsMissingOAuthObject() {
        XCTAssertNil(ClaudeCodeCredentials.parse(#"{"mcpOAuth":{}}"#))
    }

    func testParse_rejectsEmptyToken() {
        XCTAssertNil(ClaudeCodeCredentials.parse(#"{"claudeAiOauth":{"accessToken":""}}"#))
    }

    func testParse_rejectsManagedApiKey() {
        // A raw `sk-ant-api...` key is not JSON and must not parse as OAuth creds.
        XCTAssertNil(ClaudeCodeCredentials.parse("sk-ant-api03-not-json"))
    }

    func testParse_rejectsInvalidJSON() {
        XCTAssertNil(ClaudeCodeCredentials.parse("{not json"))
    }

    // MARK: - Trailing newline from `security -w`

    func testParse_toleratesTrailingNewline() throws {
        let creds = try XCTUnwrap(ClaudeCodeCredentials.parse(sample + "\n"))
        XCTAssertEqual(creds.accessToken, "sk-ant-oat01-abc")
    }

    // MARK: - Backoff policy

    func testBackoff_noRetryAfter_usesDefault() {
        XCTAssertEqual(ClaudeUsageManager.backoffDuration(retryAfter: nil), ClaudeUsageManager.defaultBackoff)
    }

    func testBackoff_zeroRetryAfter_usesDefault() {
        XCTAssertEqual(ClaudeUsageManager.backoffDuration(retryAfter: 0), ClaudeUsageManager.defaultBackoff)
    }

    func testBackoff_positiveRetryAfter_addsMargin() {
        XCTAssertEqual(ClaudeUsageManager.backoffDuration(retryAfter: 60), 60 + ClaudeUsageManager.retryAfterMargin)
    }

    func testBackoff_isCapped() {
        XCTAssertEqual(ClaudeUsageManager.backoffDuration(retryAfter: 100_000), ClaudeUsageManager.maxBackoff)
    }

    func testParseRetryAfter() {
        XCTAssertEqual(ClaudeUsageManager.parseRetryAfter("120"), 120)
        XCTAssertEqual(ClaudeUsageManager.parseRetryAfter(" 7 "), 7)
        XCTAssertNil(ClaudeUsageManager.parseRetryAfter("Wed, 21 Oct 2026 07:28:00 GMT"))
        XCTAssertNil(ClaudeUsageManager.parseRetryAfter("-5"))
    }
}
