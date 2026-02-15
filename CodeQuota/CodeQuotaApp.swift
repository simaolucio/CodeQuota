import SwiftUI
import Sparkle

@main
struct CodeQuotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Sparkle updater controller — starts checking automatically on launch
    private let updaterController: SPUStandardUpdaterController
    
    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        // Create the shared view model so the rest of the app can access it
        UpdaterViewModel.shared = UpdaterViewModel(updater: updaterController.updater)
    }
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
