import AppKit
import SwiftUI

@main
struct EnchronMacOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var application = EnchronApplication()

    var body: some Scene {
        WindowGroup("Enchron macOS") {
            switch ProcessInfo.processInfo.environment["ENCHRON_L2_SCENARIO"] {
            case "core":
                CorePlaybackScenarioView(backend: .core)
            case "app-adapter":
                CorePlaybackScenarioView(backend: .appAdapter)
            default:
                EnchronMacOSProductRoot()
                    .enchronEnvironment(application)
            }
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
