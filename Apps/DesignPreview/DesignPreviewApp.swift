import Foundation
import SwiftUI

@main
struct DesignPreviewApp: App {
    private let launchesWindowPlayback =
        ProcessInfo.processInfo.environment[
            "ENCHRON_DESIGN_PREVIEW_WINDOW_PLAYBACK"
        ] == "1"

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultLaunchBehavior(
            launchesWindowPlayback ? .suppressed : .presented
        )

        Window("Window Playback", id: "windowPlayback") {
            WindowPlaybackPreview()
        }
        .defaultSize(
            width: WindowPlaybackLayout.fallback.defaultSize.width,
            height: WindowPlaybackLayout.fallback.defaultSize.height
        )
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(
            launchesWindowPlayback ? .presented : .suppressed
        )
    }
}
