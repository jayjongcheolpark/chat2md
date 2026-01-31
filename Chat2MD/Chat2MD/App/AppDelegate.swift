import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    let settings = Settings()
    let syncService: SyncService

    override init() {
        self.syncService = SyncService(settings: Settings())
        super.init()
        self.syncService.settings = settings
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        if settings.syncEnabled {
            syncService.startPeriodicSync()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Chat2MD")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(syncService)
                .environmentObject(settings)
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func updateStatusIcon(state: SyncService.SyncStatus) {
        DispatchQueue.main.async {
            let imageName: String
            switch state {
            case .idle:
                imageName = "arrow.triangle.2.circlepath"
            case .syncing:
                imageName = "arrow.triangle.2.circlepath.circle.fill"
            case .error:
                imageName = "exclamationmark.triangle"
            }
            self.statusItem.button?.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Chat2MD")
        }
    }
}
