import CoreGraphics
import Foundation

public enum ProductPlaybackLifecycle: String, Codable, Sendable, Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case ended
    case failed
}

public struct PlaybackRuntimeObservation: Sendable, Equatable {
    public enum Event: Sendable, Equatable {
        case diagnostics(
            position: PlaybackModel.PlaybackPosition,
            actualPlaybackSeconds: Double
        )
        case lifecycle(ProductPlaybackLifecycle)
        case seekCompleted(positionSeconds: Double)
        case stopped
    }

    public let generation: UInt64
    public let event: Event

    public init(generation: UInt64, event: Event) {
        self.generation = generation
        self.event = event
    }
}

@MainActor
public protocol PlaybackRuntimeControlling: AnyObject {
    var productLifecycle: ProductPlaybackLifecycle { get }
    var playbackPosition: PlaybackModel.PlaybackPosition { get }
    var currentLaunchRequest: PlaybackLaunchRequest? { get }
    var prefetchedMetadata: PlaybackMediaMetadata? { get }
    var displayMediaProfile: PlaybackModel.MediaProfile? { get }
    var displayFileSizeInBytes: Int64? { get }
    var activeMediaFormatProvenance: MediaFormatProvenance { get }
    var effectiveMediaFormatInterpretation: EffectiveMediaFormatInterpretation { get }
    var sourceVideoContentKind: PlaybackModel.SourceVideoContentKind { get }
    var sourceMediaFormatSummary: String { get }
    var effectiveContentIsPanoramic: Bool { get }
    var effectiveVideoFormatRevision: UInt64? { get }
    var requestsSpatialVideoMode: Bool { get }
    var activeSessionID: String? { get }
    var actualPlaybackSeconds: Double { get }
    var didEndNaturally: Bool { get }
    var availableAudioTracks: [PlaybackModel.AudioTrack] { get }
    var currentAudioTrackID: String? { get }
    var availableSubtitleTracks: [PlaybackModel.SubtitleTrack] { get }
    var currentSubtitleTrackID: String? { get }
    var lastErrorMessage: String? { get set }
    var observationGeneration: UInt64 { get }
    var onMediaProfileResolved: ((PlaybackLaunchRequest, PlaybackModel.MediaProfile) -> Void)? { get set }
    var onPlaybackObservation: ((PlaybackRuntimeObservation) -> Void)? { get set }

    func prepareForPlayback(_ request: PlaybackLaunchRequest)
    func applyPrefetchedMetadata(_ metadata: PlaybackMediaMetadata)
    func open(
        _ request: PlaybackLaunchRequest,
        startTimeSeconds: Double,
        initialSpeed: PlaybackModel.PlaybackSpeed,
        initialFormat: MediaFormat?
    ) async throws
    func setFormat(
        projection: PlaybackModel.ProjectionType,
        horizontalFieldOfViewDegrees: Int?,
        stereo: PlaybackModel.StereoLayout
    ) async throws
    func useSourceFormat() async throws
    func selectAudioTrack(_ track: PlaybackModel.AudioTrack) async throws
    func selectSubtitleTrack(_ track: PlaybackModel.SubtitleTrack?) async throws
    func setSpeed(_ speed: PlaybackModel.PlaybackSpeed)
    func replay()
    func displayedArtworkImage() -> CGImage?
    func stop(releasingSourceAccess: Bool)
    func stopAndWait(releasingSourceAccess: Bool) async
}

public extension PlaybackRuntimeControlling {
    func displayedArtworkImage() -> CGImage? { nil }

    func setFormat(
        projection: PlaybackModel.ProjectionType,
        stereo: PlaybackModel.StereoLayout
    ) async throws {
        try await setFormat(
            projection: projection,
            horizontalFieldOfViewDegrees: nil,
            stereo: stereo
        )
    }
}
