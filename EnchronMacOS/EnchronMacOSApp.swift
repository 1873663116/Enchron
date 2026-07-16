import AppKit
import SwiftUI

@main
struct EnchronMacOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Enchron macOS") {
            switch ProcessInfo.processInfo.environment["ENCHRON_L2_SCENARIO"] {
            case "core":
                CorePlaybackScenarioView(backend: .core)
            case "app-adapter":
                CorePlaybackScenarioView(backend: .appAdapter)
            default:
                PlaybackVerificationView()
            }
        }
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
