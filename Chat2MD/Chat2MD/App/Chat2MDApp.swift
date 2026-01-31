import SwiftUI

@main
struct Chat2MDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            SettingsView()
                .environmentObject(appDelegate.syncService)
                .environmentObject(appDelegate.settings)
        }
    }
}
