public enum ProductPlaybackLifecycle: Sendable, Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case ended
    case failed
}

@MainActor
public protocol PlaybackRuntimeControlling: AnyObject {
    var productLifecycle: ProductPlaybackLifecycle { get }
    var playbackPosition: PlaybackModel.PlaybackPosition { get }
    var currentLaunchRequest: PlaybackLaunchRequest? { get }
    var prefetchedMetadata: PlaybackMediaMetadata? { get }
    var displayMediaProfile: PlaybackModel.MediaProfile? { get }
    var displayFileSizeInBytes: Int64? { get }
    var activeSessionID: String? { get }
    var actualPlaybackSeconds: Double { get }
    var didEndNaturally: Bool { get }
    var lastErrorMessage: String? { get set }
    var onMediaProfileResolved: ((PlaybackLaunchRequest, PlaybackModel.MediaProfile) -> Void)? { get set }

    func prepareForPlayback(_ request: PlaybackLaunchRequest)
    func applyPrefetchedMetadata(_ metadata: PlaybackMediaMetadata)
    func open(
        _ request: PlaybackLaunchRequest,
        startTimeSeconds: Double,
        initialSpeed: PlaybackModel.PlaybackSpeed
    ) async throws
    func setFormat(
        projection: PlaybackModel.ProjectionType,
        stereo: PlaybackModel.StereoLayout
    ) async throws
    func setSpeed(_ speed: PlaybackModel.PlaybackSpeed)
    func replay()
    func stop(releasingSourceAccess: Bool)
    func stopAndWait(releasingSourceAccess: Bool) async
}
