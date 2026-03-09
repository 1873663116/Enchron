import Foundation

/// Unified entry point for all playback initiation paths.
///
/// Every call site — `FileBrowsingViewModel.selectFile`, `PlaylistView`,
/// smoke-test launch — must go through this protocol instead of calling
/// `appModel.startPlayback` + `videoViewModel.play` directly.
@MainActor
public protocol PlaybackLaunching: AnyObject {
    func beginPlayback(for url: URL)
}
