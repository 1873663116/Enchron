import AppKit
import SwiftUI

@main
struct PlaybackLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Playback Lab") {
            if CommandLine.arguments.contains("--hdr-visual-probe") {
                HDRVisualProbeView()
            } else if CommandLine.arguments.contains("--route-playback-probe") {
                RoutePlaybackProbeView()
            } else {
                ContentView()
            }
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
