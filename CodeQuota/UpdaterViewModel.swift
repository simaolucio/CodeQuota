import Foundation
import Sparkle
import Combine

/// Bridges Sparkle's SPUUpdater to SwiftUI via ObservableObject.
/// Provides reactive properties for update UI and controls.
final class UpdaterViewModel: ObservableObject {
    
    /// Shared instance, initialized from CodeQuotaApp.init().
    static var shared: UpdaterViewModel!
    
    /// Whether the updater is currently able to check for updates.
    @Published var canCheckForUpdates = false
    
    /// Whether the updater automatically checks for updates.
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    
    /// The current app version string (CFBundleShortVersionString).
    let appVersion: String
    
    private let updater: SPUUpdater
    private var cancellables = Set<AnyCancellable>()
    
    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        
        // KVO bridge: publish canCheckForUpdates changes
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }
    
    /// Trigger a manual update check.
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
