import AppKit
import SwiftUI

@main
struct VibeIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = CodexMonitor()
    private var panelController: IslandPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = IslandPanelController(monitor: monitor)
        panelController?.show()
        monitor.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: {
            $0.scheme == "vibeisland" && $0.host == "open-codex"
        }), let applicationURL = CodexInstallation.applicationURL() else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration,
            completionHandler: nil
        )
    }
}
