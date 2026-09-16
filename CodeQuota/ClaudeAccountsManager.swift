import Foundation
import Combine

// MARK: - Claude Accounts Manager
//
// Multi-account view over claude-swap (cswap). When cswap is installed this is
// the single source of Claude usage data for the app, including the active
// account: cswap already caches usage and paces its requests to stay inside
// the usage endpoint's budget, and polling the same account from two places
// would blow that budget.

class ClaudeAccountsManager: ObservableObject {
    static let shared = ClaudeAccountsManager()

    /// True when the cswap executable was found.
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var cswapPath: String?
    @Published private(set) var accounts: [ClaudeAccount] = []
    @Published private(set) var activeNumber: Int?
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var switchingTo: Int?
    @Published var lastError: String?
    /// Warnings returned by the last switch (e.g. running Claude Code sessions).
    @Published var lastSwitchWarnings: [String] = []
    @Published private(set) var isAdding: Bool = false
    /// Result line of the last `cswap add` (success or failure).
    @Published var lastAddMessage: String?
    @Published var lastAddSucceeded: Bool = false
    private(set) var lastRefresh: Date?

    /// `cswap list --json` is served from cswap's cache and is cheap, so a
    /// short freshness window keeps the popover current without extra cost.
    static let serveTTL: TimeInterval = 60

    private let queue = DispatchQueue(label: "codequota.cswap", qos: .userInitiated)
    private var client: CswapClient?

    private init() {
        detect()
    }

    var activeAccount: ClaudeAccount? {
        accounts.first { $0.isActive } ?? accounts.first { $0.number == activeNumber }
    }

    /// Look for cswap again (cheap; called on each refresh so installing cswap
    /// while the app runs is picked up).
    @discardableResult
    func detect() -> Bool {
        let found = CswapClient()
        client = found
        let available = found != nil
        if available != isAvailable || found?.executable != cswapPath {
            isAvailable = available
            cswapPath = found?.executable
            print("[Accounts] cswap \(available ? "found at \(found!.executable)" : "not found")")
        }
        return available
    }

    // MARK: - Refresh

    /// Reload accounts and usage from cswap.
    /// - Parameter force: bypass the freshness window (user-initiated).
    func refresh(force: Bool = true, completion: (() -> Void)? = nil) {
        guard detect(), let client = client else {
            completion?()
            return
        }
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < Self.serveTTL {
            completion?()
            return
        }
        if isRefreshing {
            completion?()
            return
        }
        isRefreshing = true

        queue.async { [weak self] in
            let result = Result { try client.listAccounts() }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRefreshing = false
                switch result {
                case .success(let (accounts, active)):
                    self.accounts = accounts
                    self.activeNumber = active
                    self.lastRefresh = Date()
                    self.lastError = nil
                    print("[Accounts] \(accounts.count) accounts, active=\(active.map(String.init) ?? "-")")
                    self.publishActiveUsage()
                case .failure(let error):
                    let msg = (error as? CswapError)?.localizedDescription ?? error.localizedDescription
                    print("[Accounts] list failed: \(msg)")
                    self.lastError = msg
                    ClaudeUsageManager.shared.applyExternalFailure(msg)
                }
                completion?()
            }
        }
    }

    /// Push the active account's usage into the single-account usage manager
    /// so the menu bar icon and the main tiles keep working unchanged.
    private func publishActiveUsage() {
        guard let active = activeAccount else {
            ClaudeUsageManager.shared.applyExternalFailure("cswap has no active account.")
            return
        }
        if let usage = active.usage {
            let fetchedAt = active.usageAge.map { Date().addingTimeInterval(-$0) } ?? Date()
            ClaudeUsageManager.shared.applyExternal(usage: usage, fetchedAt: fetchedAt)
        } else {
            ClaudeUsageManager.shared.applyExternalFailure(
                "Active account: \(active.statusText ?? "no usage data")."
            )
        }
    }

    // MARK: - Add

    /// Register Claude Code's current login with cswap (`cswap add`).
    /// The user signs in to Claude Code with the new account first.
    func addCurrentLogin(alias: String?) {
        guard detect(), let client = client else { return }
        guard !isAdding else { return }
        isAdding = true
        lastAddMessage = nil
        lastAddSucceeded = false

        queue.async { [weak self] in
            let result = Result { try client.addCurrentLogin(alias: alias) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isAdding = false
                switch result {
                case .success(let summary):
                    print("[Accounts] add: \(summary)")
                    self.lastAddMessage = summary
                    self.lastAddSucceeded = true
                    AnthropicAuthManager.shared.adoptClaudeCodeCredentials()
                    self.lastRefresh = nil
                    self.refresh(force: true)
                case .failure(let error):
                    let msg = (error as? CswapError)?.localizedDescription ?? error.localizedDescription
                    print("[Accounts] add failed: \(msg)")
                    self.lastAddMessage = msg
                    self.lastAddSucceeded = false
                }
            }
        }
    }

    /// Open Terminal running `claude auth login` so the user can sign in with
    /// another account before adding it.
    func openTerminalForLogin() {
        let script = """
        tell application "Terminal"
            activate
            do script "claude auth login"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: - Switch

    /// Switch the active Claude Code login via `cswap switch <number>`.
    func switchTo(_ number: Int) {
        guard detect(), let client = client else { return }
        guard switchingTo == nil else { return }
        switchingTo = number
        lastError = nil
        lastSwitchWarnings = []

        queue.async { [weak self] in
            let result = Result { try client.switchTo(number: number) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.switchingTo = nil
                switch result {
                case .success(let r):
                    print("[Accounts] switch -> \(number): switched=\(r.switched) reason=\(r.reason ?? "-")")
                    self.lastSwitchWarnings = r.warnings
                    // The active Claude Code credential changed: re-read it and
                    // refresh everything from cswap.
                    AnthropicAuthManager.shared.adoptClaudeCodeCredentials()
                    self.lastRefresh = nil
                    self.refresh(force: true)
                case .failure(let error):
                    let msg = (error as? CswapError)?.localizedDescription ?? error.localizedDescription
                    print("[Accounts] switch failed: \(msg)")
                    self.lastError = msg
                }
            }
        }
    }
}
