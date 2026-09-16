import XCTest
@testable import CodeQuota

final class CswapClientTests: XCTestCase {

    // Trimmed real output of `cswap list --json` (v0.26.0), emails replaced.
    private let listJSON = """
    {
      "schemaVersion": 1,
      "activeAccountNumber": 2,
      "accounts": [
        {
          "number": 1, "email": "one@example.com", "organizationName": "one's Organization",
          "organizationUuid": "cc818be0", "isOrganization": true, "active": false, "usageStatus": "ok",
          "alias": "work",
          "usage": {
            "fiveHour": {"pct": 0.0},
            "sevenDay": {"pct": 33.0, "resetsAt": "2026-09-17T08:00:00.328115+00:00", "countdown": "13h 1m"},
            "scoped": [{"pct": 63.0, "resetsAt": "2026-09-17T08:00:00.328350+00:00", "name": "Fable"}]
          },
          "usageFetchedAt": "2026-09-16T18:56:05Z", "usageAgeSeconds": 140.7
        },
        {
          "number": 2, "email": "two@example.com", "organizationName": "two's Organization",
          "organizationUuid": "e3e45d76", "isOrganization": true, "active": true, "usageStatus": "ok",
          "usage": {
            "fiveHour": {"pct": 7.0, "resetsAt": "2026-09-16T23:30:00.949950+00:00"},
            "sevenDay": {"pct": 12.0, "resetsAt": "2026-09-21T20:59:59.949982+00:00"},
            "scoped": [
              {"pct": 40.0, "name": "Opus"},
              {"pct": 12.0, "resetsAt": "2026-09-21T21:00:00.950342+00:00", "name": "Fable"}
            ]
          },
          "usageFetchedAt": "2026-09-16T18:56:05Z", "usageAgeSeconds": 140.7
        },
        {
          "number": 3, "email": "three@example.com", "organizationName": "", "organizationUuid": "",
          "isOrganization": false, "active": false, "usageStatus": "unavailable", "usage": null,
          "lastGoodUsage": {"fiveHour": {"pct": 99.0}, "sevenDay": {"pct": 50.0}, "scoped": []},
          "lastGoodFetchedAt": "2026-09-16T17:00:00Z", "lastGoodAgeSeconds": 7000.0,
          "usageError": "http-429", "usageRetryAt": "2026-09-16T19:30:00Z"
        },
        {
          "number": 4, "email": "four@example.com", "organizationName": "", "organizationUuid": "",
          "isOrganization": false, "active": false, "usageStatus": "relogin_required", "usage": null,
          "disabled": true
        }
      ]
    }
    """

    func testParseList_accountsAndActive() throws {
        let (accounts, active) = try CswapClient.parseList(Data(listJSON.utf8))
        XCTAssertEqual(active, 2)
        XCTAssertEqual(accounts.map { $0.number }, [1, 2, 3, 4])
        XCTAssertEqual(accounts.filter { $0.isActive }.map { $0.number }, [2])
    }

    func testParseList_aliasAndDisplayName() throws {
        let (accounts, _) = try CswapClient.parseList(Data(listJSON.utf8))
        XCTAssertEqual(accounts[0].alias, "work")
        XCTAssertEqual(accounts[0].displayName, "work")
        XCTAssertEqual(accounts[1].displayName, "two@example.com")
    }

    func testParseList_usageBuckets() throws {
        let (accounts, _) = try CswapClient.parseList(Data(listJSON.utf8))
        let one = try XCTUnwrap(accounts[0].usage)
        XCTAssertEqual(one.fiveHour.percent, 0)
        XCTAssertNil(one.fiveHour.resetAt)
        XCTAssertEqual(one.weeklyAll.percent, 33)
        XCTAssertNotNil(one.weeklyAll.resetAt)
        XCTAssertEqual(one.weeklyModel.percent, 63)
        XCTAssertEqual(one.weeklyModelName, "Fable")
        XCTAssertEqual(accounts[0].usageAge, 140.7)
        XCTAssertFalse(accounts[0].isStale)
    }

    func testParseList_prefersFableAmongScoped() throws {
        let (accounts, _) = try CswapClient.parseList(Data(listJSON.utf8))
        let two = try XCTUnwrap(accounts[1].usage)
        XCTAssertEqual(two.weeklyModel.percent, 12)
        XCTAssertEqual(two.weeklyModelName, "Fable")
    }

    func testParseList_lastGoodUsageIsStale() throws {
        let (accounts, _) = try CswapClient.parseList(Data(listJSON.utf8))
        let three = accounts[2]
        XCTAssertEqual(three.usageStatus, "unavailable")
        XCTAssertTrue(three.isStale)
        XCTAssertEqual(three.usage?.fiveHour.percent, 99)
        XCTAssertEqual(three.usageAge, 7000)
        XCTAssertEqual(three.usageError, "http-429")
        XCTAssertEqual(three.statusText, "unavailable (http-429)")
    }

    func testParseList_statusWithoutUsage() throws {
        let (accounts, _) = try CswapClient.parseList(Data(listJSON.utf8))
        let four = accounts[3]
        XCTAssertNil(four.usage)
        XCTAssertTrue(four.isDisabled)
        XCTAssertEqual(four.statusText, "re-login required")
    }

    func testParseList_errorEnvelope() {
        let json = #"{"schemaVersion":1,"error":{"type":"ClaudeSwitchError","message":"No accounts configured"}}"#
        XCTAssertThrowsError(try CswapClient.parseList(Data(json.utf8))) { error in
            XCTAssertEqual(error as? CswapError, .cswapError("No accounts configured"))
        }
    }

    func testParseList_notJSON() {
        XCTAssertThrowsError(try CswapClient.parseList(Data("nope".utf8))) { error in
            if case .badJSON = error as? CswapError {} else { XCTFail("expected badJSON, got \(error)") }
        }
    }

    // MARK: - switch

    func testParseSwitch_switched() throws {
        let json = """
        {"schemaVersion":1,"switched":true,"from":{"number":2,"email":"two@example.com"},
         "to":{"number":1,"email":"one@example.com"},"strategy":"explicit","reason":"switched",
         "message":"Switched to Account-1 (one@example.com)","warnings":["2 claude processes running"]}
        """
        let r = try CswapClient.parseSwitch(Data(json.utf8))
        XCTAssertTrue(r.switched)
        XCTAssertEqual(r.toNumber, 1)
        XCTAssertEqual(r.toEmail, "one@example.com")
        XCTAssertEqual(r.reason, "switched")
        XCTAssertEqual(r.warnings, ["2 claude processes running"])
    }

    func testParseSwitch_alreadyActive() throws {
        let json = #"{"schemaVersion":1,"switched":false,"from":{"number":2,"email":"x"},"to":{"number":2,"email":"x"},"strategy":"explicit","reason":"already-active","message":"Already on Account-2 (x)","warnings":[]}"#
        let r = try CswapClient.parseSwitch(Data(json.utf8))
        XCTAssertFalse(r.switched)
        XCTAssertEqual(r.reason, "already-active")
        XCTAssertTrue(r.warnings.isEmpty)
    }

    func testParseSwitch_errorEnvelope() {
        let json = #"{"schemaVersion":1,"error":{"type":"ClaudeSwitchError","message":"Account 9 not found"}}"#
        XCTAssertThrowsError(try CswapClient.parseSwitch(Data(json.utf8))) { error in
            XCTAssertEqual(error as? CswapError, .cswapError("Account 9 not found"))
        }
    }

    // MARK: - locate

    func testCandidatePaths_includeUserLocalBin() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(CswapClient.candidatePaths().first, "\(home)/.local/bin/cswap")
    }

    // MARK: - add

    func testSummarizeAddOutput_added() {
        let out = "\u{1B}[32mAdded\u{1B}[0m Account 3 (new@example.com \u{1B}[2m[Max]\u{1B}[0m).\nNext: cswap switch 3\n"
        XCTAssertEqual(CswapClient.summarizeAddOutput(out), "Added Account 3 (new@example.com [Max]).")
    }

    func testSummarizeAddOutput_updated() {
        let out = "Updated credentials for Account 2 (two@example.com [Max]).\n"
        XCTAssertEqual(CswapClient.summarizeAddOutput(out), "Updated credentials for Account 2 (two@example.com [Max]).")
    }

    func testSummarizeAddOutput_fallsBackToLastLine() {
        XCTAssertEqual(CswapClient.summarizeAddOutput("Something\nelse happened\n"), "else happened")
        XCTAssertEqual(CswapClient.summarizeAddOutput(""), "Done.")
    }

    func testStripANSI() {
        XCTAssertEqual(CswapClient.stripANSI("\u{1B}[1;31mred\u{1B}[0m plain"), "red plain")
    }
}
