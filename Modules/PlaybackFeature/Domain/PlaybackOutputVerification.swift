import Foundation

public enum PlaybackOutputBoundary: String, Codable, Sendable, Equatable {
    case mediaSession
    case videoSampleStream
    case rendererInput
    case decoderBootstrap
    case timelineRate
    case realityKitBinding
    case videoComponent
    case displayedVideo
    case endedImageClearance
    case audioSampleStream
    case audioRenderer
    case audioSession
    case audioRoute
    case endedAudioSessionDeactivation
    case secondObservation
    case timelineAdvancement
    case videoSampleAdvancement
    case audioSampleAdvancement
    case ready
}

/// A read-only projection of one instant in the production playback path.
/// It diagnoses the first incomplete boundary without owning playback state.
public struct PlaybackOutputObservation: Codable, Sendable, Equatable {
    public var capturedAt: Date
    public var mediaSessionID: String?
    public var streamEpoch: UInt64
    public var lifecycle: ProductPlaybackLifecycle
    public var positionSeconds: Double
    public var videoSampleCount: UInt64
    public var acceptedRendererInputCount: UInt64
    public var decoderBootstrapComplete: Bool
    public var requestedPlaybackRate: Float
    public var actualTimebaseRate: Float
    public var realityKitRendererBound: Bool
    public var videoComponentReady: Bool
    public var displayedPixelBuffer: Bool
    public var hasAudio: Bool
    public var audioSampleBufferCount: UInt64
    public var audioRendererSampleBufferCount: UInt64
    public var audioRendererStreamEpoch: UInt64
    public var audioRendererStatus: String
    public var audioRendererVolume: Float
    public var audioRendererMuted: Bool
    public var audioRendererError: String?
    public var audioSessionActive: Bool
    public var audioSessionCategory: String
    public var audioSessionMode: String
    public var audioSessionOutputPortTypes: [String]
    public var systemOutputVolume: Float

    public init(
        capturedAt: Date = Date(),
        mediaSessionID: String?,
        streamEpoch: UInt64,
        lifecycle: ProductPlaybackLifecycle,
        positionSeconds: Double,
        videoSampleCount: UInt64,
        acceptedRendererInputCount: UInt64,
        decoderBootstrapComplete: Bool,
        requestedPlaybackRate: Float,
        actualTimebaseRate: Float,
        realityKitRendererBound: Bool,
        videoComponentReady: Bool,
        displayedPixelBuffer: Bool,
        hasAudio: Bool,
        audioSampleBufferCount: UInt64,
        audioRendererSampleBufferCount: UInt64,
        audioRendererStreamEpoch: UInt64,
        audioRendererStatus: String,
        audioRendererVolume: Float,
        audioRendererMuted: Bool,
        audioRendererError: String?,
        audioSessionActive: Bool,
        audioSessionCategory: String,
        audioSessionMode: String,
        audioSessionOutputPortTypes: [String],
        systemOutputVolume: Float
    ) {
        self.capturedAt = capturedAt
        self.mediaSessionID = mediaSessionID
        self.streamEpoch = streamEpoch
        self.lifecycle = lifecycle
        self.positionSeconds = positionSeconds
        self.videoSampleCount = videoSampleCount
        self.acceptedRendererInputCount = acceptedRendererInputCount
        self.decoderBootstrapComplete = decoderBootstrapComplete
        self.requestedPlaybackRate = requestedPlaybackRate
        self.actualTimebaseRate = actualTimebaseRate
        self.realityKitRendererBound = realityKitRendererBound
        self.videoComponentReady = videoComponentReady
        self.displayedPixelBuffer = displayedPixelBuffer
        self.hasAudio = hasAudio
        self.audioSampleBufferCount = audioSampleBufferCount
        self.audioRendererSampleBufferCount = audioRendererSampleBufferCount
        self.audioRendererStreamEpoch = audioRendererStreamEpoch
        self.audioRendererStatus = audioRendererStatus
        self.audioRendererVolume = audioRendererVolume
        self.audioRendererMuted = audioRendererMuted
        self.audioRendererError = audioRendererError
        self.audioSessionActive = audioSessionActive
        self.audioSessionCategory = audioSessionCategory
        self.audioSessionMode = audioSessionMode
        self.audioSessionOutputPortTypes = audioSessionOutputPortTypes
        self.systemOutputVolume = systemOutputVolume
    }
}

public enum PlaybackOutputVerification {
    public static func firstIncompleteBoundary(
        current: PlaybackOutputObservation,
        previous: PlaybackOutputObservation? = nil
    ) -> PlaybackOutputBoundary {
        guard current.mediaSessionID != nil else { return .mediaSession }
        guard current.videoSampleCount > 0 else { return .videoSampleStream }
        guard current.acceptedRendererInputCount > 0 else { return .rendererInput }
        if current.lifecycle == .ended {
            guard current.realityKitRendererBound else { return .realityKitBinding }
            guard current.displayedPixelBuffer == false else {
                return .endedImageClearance
            }
            guard current.audioSessionActive == false else {
                return .endedAudioSessionDeactivation
            }
            return .ready
        }
        guard current.decoderBootstrapComplete else { return .decoderBootstrap }
        if current.lifecycle == .playing,
           current.requestedPlaybackRate > 0,
           current.actualTimebaseRate <= 0 {
            return .timelineRate
        }
        guard current.realityKitRendererBound else { return .realityKitBinding }
        guard current.videoComponentReady else { return .videoComponent }
        guard current.displayedPixelBuffer else { return .displayedVideo }

        if current.hasAudio, current.lifecycle == .playing {
            guard current.audioSampleBufferCount > 0 else { return .audioSampleStream }
            guard current.audioRendererSampleBufferCount > 0,
                  current.audioRendererStatus == "rendering",
                  current.audioRendererVolume > 0,
                  current.audioRendererMuted == false,
                  current.audioRendererError == nil else { return .audioRenderer }
            guard current.audioSessionActive else { return .audioSession }
            guard current.audioSessionCategory == "AVAudioSessionCategoryPlayback",
                  current.audioSessionMode == "AVAudioSessionModeMoviePlayback",
                  current.audioSessionOutputPortTypes.isEmpty == false,
                  current.systemOutputVolume > 0 else { return .audioRoute }
        }

        guard current.lifecycle == .playing else { return .ready }
        guard let previous,
              previous.mediaSessionID == current.mediaSessionID,
              previous.streamEpoch == current.streamEpoch,
              previous.capturedAt < current.capturedAt else {
            return .secondObservation
        }
        guard current.positionSeconds > previous.positionSeconds else {
            return .timelineAdvancement
        }
        guard current.videoSampleCount > previous.videoSampleCount else {
            return .videoSampleAdvancement
        }
        if current.hasAudio,
           current.audioSampleBufferCount <= previous.audioSampleBufferCount {
            return .audioSampleAdvancement
        }
        return .ready
    }
}
