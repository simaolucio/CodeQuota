import Foundation

// MARK: - claude-swap (cswap) integration
//
// claude-swap (https://github.com/realiti4/claude-swap) manages several Claude
// Code logins on one machine. It owns the per-account credential store, the
// usage cache and the polling budget, and it performs the actual switch by
// rewriting Claude Code's active credential. CodeQuota does not duplicate any
// of that: it shells out to the `cswap` CLI and reads its JSON.
//
//   cswap list --json          -> every account with cached usage
//   cswap switch <num> --json  -> switch the active Claude Code login

// MARK: - Models

struct ClaudeAccount: Identifiable, Equatable {
    let number: Int
    let email: String
    let alias: String?
    let organizationName: String?
    let isActive: Bool
    let isDisabled: Bool
    /// cswap's usageStatus: "ok", "token_expired", "relogin_required",
    /// "api_key", "keychain_unavailable", "no_credentials", "unavailable", ...
    let usageStatus: String
    /// Usage to display. When cswap could not fetch fresh data it may still
    /// hand us the last good measurement; `isStale` is then true.
    let usage: ClaudeUsage?
    let isStale: Bool
    let usageAge: TimeInterval?
    /// Failure kind for status "unavailable" (e.g. "http-429", "timeout").
    let usageError: String?

    var id: Int { number }

    var displayName: String {
        if let alias = alias, !alias.isEmpty { return alias }
        return email
    }

    /// Short human-readable explanation when there is no usable usage.
    var statusText: String? {
        switch usageStatus {
        case "ok": return isStale ? "stale" : nil
        case "token_expired": return "token expired"
        case "relogin_required": return "re-login required"
        case "api_key": return "API key account"
        case "keychain_unavailable": return "keychain unavailable"
        case "no_credentials": return "no credentials"
        case "foreign_credential": return "foreign credential"
        case "unavailable":
            if let err = usageError { return "unavailable (\(err))" }
            return "unavailable"
        default: return usageStatus
        }
    }
}

struct CswapSwitchResult: Equatable {
    let switched: Bool
    let toNumber: Int?
    let toEmail: String?
    let reason: String?
    let message: String?
    let warnings: [String]
}

enum CswapError: Error, Equatable {
    case notInstalled
    case launchFailed(String)
    case timedOut
    case nonZeroExit(Int32, String)
    case badJSON(String)
    case cswapError(String)

    var localizedDescription: String {
        switch self {
        case .notInstalled: return "cswap is not installed."
        case .launchFailed(let s): return "Could not launch cswap: \(s)"
        case .timedOut: return "cswap timed out."
        case .nonZeroExit(let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "cswap exited with code \(code)." : detail
        case .badJSON(let s): return "Unexpected cswap output: \(s)"
        case .cswapError(let s): return s
        }
    }
}

// MARK: - Client

struct CswapClient {
    /// UserDefaults key for a user-specified cswap path (optional override).
    static let pathOverrideKey = "cswap_path"

    /// Locations to look for the `cswap` executable, in order.
    static func candidatePaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin/cswap",
            "/opt/homebrew/bin/cswap",
            "/usr/local/bin/cswap",
            "\(home)/.cargo/bin/cswap",
            "\(home)/Library/Python/3.12/bin/cswap",
            "\(home)/Library/Python/3.13/bin/cswap",
        ]
    }

    /// Resolve the cswap executable. Returns nil when not found.
    static func locate() -> String? {
        if let override = UserDefaults.standard.string(forKey: pathOverrideKey),
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        for path in candidatePaths() where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    let executable: String

    init?(executable: String? = CswapClient.locate()) {
        guard let exe = executable else { return nil }
        self.executable = exe
    }

    // MARK: Commands

    /// `cswap list --json`. Blocking; call off the main thread.
    func listAccounts() throws -> (accounts: [ClaudeAccount], activeNumber: Int?) {
        // The list may trigger network fetches for several accounts (each
        // bounded by cswap's own 5 s timeout), so allow a generous ceiling.
        let data = try run(["list", "--json"], timeout: 90)
        return try Self.parseList(data)
    }

    /// `cswap switch <number> --json`. Blocking; call off the main thread.
    func switchTo(number: Int) throws -> CswapSwitchResult {
        let data = try run(["switch", String(number), "--json"], timeout: 60)
        return try Self.parseSwitch(data)
    }

    /// `cswap add [--alias NAME]`: register the login Claude Code currently
    /// holds as a managed account (or refresh it in place if already managed).
    /// Never prompts when no slot is given. Returns a one-line summary.
    /// Blocking; call off the main thread.
    func addCurrentLogin(alias: String?) throws -> String {
        var args = ["add"]
        if let alias = alias?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty {
            args += ["--alias", alias]
        }
        let data = try run(args, timeout: 60)
        return Self.summarizeAddOutput(String(data: data, encoding: .utf8) ?? "")
    }

    // MARK: Parsing (pure; unit-tested)

    /// Reduce `cswap add` console output to its meaningful line.
    /// cswap prints e.g. "Added Account 3 (x@y.z [Max])" or
    /// "Updated credentials for Account 2 (x@y.z [Max])."
    static func summarizeAddOutput(_ output: String) -> String {
        let cleaned = stripANSI(output)
        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let hit = lines.first(where: { $0.localizedCaseInsensitiveContains("added") || $0.localizedCaseInsensitiveContains("updated credentials") }) {
            return hit
        }
        return lines.last ?? "Done."
    }

    /// Remove ANSI colour/style escape sequences.
    static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }

    static func parseList(_ data: Data) throws -> (accounts: [ClaudeAccount], activeNumber: Int?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CswapError.badJSON(String(data: data.prefix(200), encoding: .utf8) ?? "(binary)")
        }
        if let err = json["error"] as? [String: Any] {
            throw CswapError.cswapError((err["message"] as? String) ?? "cswap reported an error")
        }
        let active = json["activeAccountNumber"] as? Int
        let rows = json["accounts"] as? [[String: Any]] ?? []
        let accounts = rows.compactMap { parseAccount($0) }.sorted { $0.number < $1.number }
        return (accounts, active)
    }

    static func parseAccount(_ row: [String: Any]) -> ClaudeAccount? {
        guard let number = row["number"] as? Int else { return nil }
        let email = (row["email"] as? String) ?? "Account-\(number)"
        let status = (row["usageStatus"] as? String) ?? "unavailable"

        var usage: ClaudeUsage?
        var stale = false
        var age: TimeInterval?
        if let u = row["usage"] as? [String: Any] {
            usage = parseUsage(u)
            age = row["usageAgeSeconds"] as? TimeInterval
        } else if let u = row["lastGoodUsage"] as? [String: Any] {
            usage = parseUsage(u)
            stale = true
            age = row["lastGoodAgeSeconds"] as? TimeInterval
        }

        return ClaudeAccount(
            number: number,
            email: email,
            alias: row["alias"] as? String,
            organizationName: row["organizationName"] as? String,
            isActive: (row["active"] as? Bool) ?? false,
            isDisabled: (row["disabled"] as? Bool) ?? false,
            usageStatus: status,
            usage: usage,
            isStale: stale,
            usageAge: age,
            usageError: row["usageError"] as? String
        )
    }

    /// cswap's usage object: {fiveHour:{pct,resetsAt}, sevenDay:{...}, scoped:[{name,pct,resetsAt}]}
    static func parseUsage(_ u: [String: Any]) -> ClaudeUsage {
        func bucket(_ d: [String: Any]?) -> UsageBucket {
            guard let d = d else { return UsageBucket(percent: 0, resetAt: nil) }
            let pct = (d["pct"] as? Double) ?? Double(d["pct"] as? Int ?? 0)
            return UsageBucket(
                percent: ClaudeUsageParser.clamp0100(pct),
                resetAt: ClaudeUsageParser.parseDate(from: d, key: "resetsAt")
            )
        }
        let five = bucket(u["fiveHour"] as? [String: Any])
        let week = bucket(u["sevenDay"] as? [String: Any])

        let scoped = (u["scoped"] as? [[String: Any]]) ?? []
        // Prefer the Fable limit; otherwise the first model-scoped one.
        let chosen = scoped.first { ($0["name"] as? String)?.lowercased() == ClaudeUsage.preferredModelName.lowercased() }
            ?? scoped.first
        let model = bucket(chosen)
        let modelName = chosen?["name"] as? String

        return ClaudeUsage(fiveHour: five, weeklyAll: week, weeklyModel: model, weeklyModelName: modelName)
    }

    static func parseSwitch(_ data: Data) throws -> CswapSwitchResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CswapError.badJSON(String(data: data.prefix(200), encoding: .utf8) ?? "(binary)")
        }
        if let err = json["error"] as? [String: Any] {
            throw CswapError.cswapError((err["message"] as? String) ?? "cswap reported an error")
        }
        let to = json["to"] as? [String: Any]
        return CswapSwitchResult(
            switched: (json["switched"] as? Bool) ?? false,
            toNumber: to?["number"] as? Int,
            toEmail: to?["email"] as? String,
            reason: json["reason"] as? String,
            message: json["message"] as? String,
            warnings: (json["warnings"] as? [String]) ?? []
        )
    }

    // MARK: Process plumbing

    private func run(_ arguments: [String], timeout: TimeInterval) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        // The GUI app inherits a minimal environment; give the CLI what a
        // login shell would (uv/pipx shims, Homebrew) plus HOME/USER so it
        // resolves the same Keychain item and config files as the terminal.
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["HOME"] = env["HOME"] ?? home
        env["USER"] = env["USER"] ?? NSUserName()
        let extraPath = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = [env["PATH"], extraPath].compactMap { $0 }.joined(separator: ":")
        env["NO_COLOR"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CswapError.launchFailed(error.localizedDescription)
        }

        // Drain pipes on background threads so a large payload cannot block
        // the child on a full pipe buffer.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outData = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw CswapError.timedOut
        }
        group.wait()

        let stderrText = String(data: errData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            // cswap emits a JSON error envelope on stdout for handled errors.
            if let json = try? JSONSerialization.jsonObject(with: outData) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String {
                throw CswapError.cswapError(msg)
            }
            throw CswapError.nonZeroExit(process.terminationStatus, stderrText)
        }
        return outData
    }
}
