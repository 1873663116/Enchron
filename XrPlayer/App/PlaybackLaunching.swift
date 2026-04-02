import Foundation

/// Unified entry point for all playback initiation paths.
///
/// Every call site — `FileBrowsingViewModel.selectFile`, `PlaylistView`,
/// smoke-test launch — must go through this protocol instead of calling
/// `appModel.startPlayback` + `videoViewModel.play` directly.
@MainActor
public protocol PlaybackLaunching: AnyObject {
    // MARK: - Immediate playback (existing)
    func beginPlayback(for url: URL)
    func beginPlayback(_ request: PlaybackLaunchRequest)
    func stopPlayback()

    // MARK: - Prepare-then-confirm flow (detail page)
    var currentPreparation: PreparationState? { get }
    func preparePlayback(_ request: PlaybackLaunchRequest)
    func confirmPlayback(_ prepared: PreparedPlayback)
    func cancelPreparedPlayback()
}
