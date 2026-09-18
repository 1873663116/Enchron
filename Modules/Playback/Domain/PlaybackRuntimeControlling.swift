import CoreGraphics
import Dispatch
import Foundation
import PlaybackCore

public enum ProductPlaybackLifecycle: String, Codable, Sendable, Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case ended
    case failed
}

public enum PlaybackLoadingStage: String, CaseIterable, Codable, Sendable, Equatable {
    case opening
    case seeking
    case recovering
    case starved
}

public enum PlaybackSeekIndicationDelay {
    public static let duration: Duration = .milliseconds(500)
}

public enum PlaybackLoadingVisibility: String, Codable, Sendable, Equatable {
    case none
    case loading
}

public struct PlaybackOpeningEvidence: Codable, Sendable, Equatable {
    public var runtimeGeneration: UInt64
    public var requestID: String
    public var technicalSessionID: String?

    public init(
        runtimeGeneration: UInt64,
        requestID: String,
        technicalSessionID: String?
    ) {
        self.runtimeGeneration = runtimeGeneration
        self.requestID = requestID
        self.technicalSessionID = technicalSessionID
    }
}

public struct PlaybackSeekingEvidence: Codable, Sendable, Equatable {
    public var runtimeGeneration: UInt64
    public var technicalSessionID: String
    public var targetSeconds: Double
    public var startedAtMillis: UInt64

    public init(
        runtimeGeneration: UInt64,
        technicalSessionID: String,
        targetSeconds: Double,
        startedAtMillis: UInt64
    ) {
        self.runtimeGeneration = runtimeGeneration
        self.technicalSessionID = technicalSessionID
        self.targetSeconds = targetSeconds
        self.startedAtMillis = startedAtMillis
    }
}

public struct PlaybackStarvationEvidence: Codable, Sendable, Equatable {
    public var runtimeGeneration: UInt64
    public var technicalSessionID: String
    public var deliveryContinuity: PlaybackDeliveryContinuityEvidence

    public init(
        runtimeGeneration: UInt64,
        technicalSessionID: String,
        deliveryContinuity: PlaybackDeliveryContinuityEvidence
    ) {
        self.runtimeGeneration = runtimeGeneration
        self.technicalSessionID = technicalSessionID
        self.deliveryContinuity = deliveryContinuity
    }
}

public struct PlaybackRecoveryEvidence: Codable, Sendable, Equatable {
    public var runtimeGeneration: UInt64
    public var technicalSessionID: String
    public var startedAtMillis: UInt64

    public init(
        runtimeGeneration: UInt64,
        technicalSessionID: String,
        startedAtMillis: UInt64
    ) {
        self.runtimeGeneration = runtimeGeneration
        self.technicalSessionID = technicalSessionID
        self.startedAtMillis = startedAtMillis
    }
}

public enum PlaybackLoadingCausalEvidence: Codable, Sendable, Equatable {
    case opening(PlaybackOpeningEvidence)
    case seeking(PlaybackSeekingEvidence)
    case recovering(PlaybackRecoveryEvidence)
    case starved(PlaybackStarvationEvidence)

    public var stage: PlaybackLoadingStage {
        switch self {
        case .opening:
            .opening
        case .seeking:
            .seeking
        case .recovering:
            .recovering
        case .starved:
            .starved
        }
    }
}

public enum PlaybackLoadingState: Codable, Sendable, Equatable {
    case none
    case loading(PlaybackLoadingCausalEvidence)

    public var visibility: PlaybackLoadingVisibility {
        switch self {
        case .none:
            .none
        case .loading:
            .loading
        }
    }

    public var stage: PlaybackLoadingStage? {
        guard case .loading(let evidence) = self else { return nil }
        return evidence.stage
    }

    public var causalEvidence: PlaybackLoadingCausalEvidence? {
        guard case .loading(let evidence) = self else { return nil }
        return evidence
    }
}

struct PlaybackLoadingStateMachine {
    private(set) var state = PlaybackLoadingState.none
    private var runtimeGeneration: UInt64?
    private var requestID = ""
    private var technicalSessionID: String?

    mutating func beginOpening(
        runtimeGeneration: UInt64,
        requestID: String,
        technicalSessionID: String? = nil
    ) {
        self.runtimeGeneration = runtimeGeneration
        self.requestID = requestID
        self.technicalSessionID = technicalSessionID
        state = .loading(.opening(PlaybackOpeningEvidence(
            runtimeGeneration: runtimeGeneration,
            requestID: requestID,
            technicalSessionID: technicalSessionID
        )))
    }

    mutating func bindTechnicalSession(
        _ technicalSessionID: String,
        runtimeGeneration: UInt64
    ) {
        guard self.runtimeGeneration == runtimeGeneration else { return }
        self.technicalSessionID = technicalSessionID
        guard state.stage == .opening else { return }
        state = .loading(.opening(PlaybackOpeningEvidence(
            runtimeGeneration: runtimeGeneration,
            requestID: requestID,
            technicalSessionID: technicalSessionID
        )))
    }

    mutating func beginSeek(
        targetSeconds: Double,
        technicalSessionID: String,
        runtimeGeneration: UInt64
    ) {
        guard self.runtimeGeneration == runtimeGeneration,
              self.technicalSessionID == technicalSessionID else { return }
        state = .loading(.seeking(PlaybackSeekingEvidence(
            runtimeGeneration: runtimeGeneration,
            technicalSessionID: technicalSessionID,
            targetSeconds: targetSeconds,
            startedAtMillis: DispatchTime.now().uptimeNanoseconds / 1_000_000
        )))
    }

    mutating func endSeek(
        technicalSessionID: String,
        runtimeGeneration: UInt64
    ) {
        guard self.runtimeGeneration == runtimeGeneration,
              self.technicalSessionID == technicalSessionID,
              state.stage == .seeking else { return }
        state = .none
    }

    mutating func beginRecovery(
        technicalSessionID: String,
        runtimeGeneration: UInt64
    ) {
        guard self.runtimeGeneration == runtimeGeneration,
              self.technicalSessionID == technicalSessionID else { return }
        state = .loading(.recovering(PlaybackRecoveryEvidence(
            runtimeGeneration: runtimeGeneration,
            technicalSessionID: technicalSessionID,
            startedAtMillis: DispatchTime.now().uptimeNanoseconds / 1_000_000
        )))
    }

    mutating func endRecovery(
        technicalSessionID: String,
        runtimeGeneration: UInt64
    ) {
        guard self.runtimeGeneration == runtimeGeneration,
              self.technicalSessionID == technicalSessionID,
              state.stage == .recovering else { return }
        state = .none
    }

    mutating func presentationBecameUsable(
        technicalSessionID: String,
        runtimeGeneration: UInt64
    ) {
        guard self.runtimeGeneration == runtimeGeneration,
              self.technicalSessionID == technicalSessionID,
              state.stage == .opening else { return }
        state = .none
    }

    mutating func receive(
        _ observation: PlaybackDeliveryContinuityObservation,
        technicalSessionID: String,
        runtimeGeneration: UInt64,
        lifecycle: ProductPlaybackLifecycle
    ) {
        guard self.runtimeGeneration == runtimeGeneration,
              self.technicalSessionID == technicalSessionID else { return }
        switch observation.phase {
        case .starved:
            guard state.stage != .seeking,
                  lifecycle == .playing,
                  let evidence = observation.evidence else { return }
            state = .loading(.starved(PlaybackStarvationEvidence(
                runtimeGeneration: runtimeGeneration,
                technicalSessionID: technicalSessionID,
                deliveryContinuity: evidence
            )))
        case .recovered:
            if case .loading(.recovering) = state {
                state = .none
                return
            }
            guard case .loading(.starved(let current)) = state,
                  current.technicalSessionID == technicalSessionID,
                  current.deliveryContinuity.incidentID
                    == observation.evidence?.incidentID else { return }
            state = .none
        case .inactive:
            clearTransientLoading()
        }
    }

    mutating func clearTransientLoading() {
        guard state.stage == .starved || state.stage == .recovering else { return }
        state = .none
    }

    mutating func clearStage() {
        state = .none
    }

    mutating func clear() {
        state = .none
        runtimeGeneration = nil
        requestID = ""
        technicalSessionID = nil
    }
}

public struct PlaybackRuntimeObservation: Sendable, Equatable {
    public enum Event: Sendable, Equatable {
        case diagnostics(
            position: PlaybackModel.PlaybackPosition,
            actualPlaybackSeconds: Double
        )
        case lifecycle(ProductPlaybackLifecycle)
        case activeFailure(PlaybackActiveFailure)
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
    var effectiveMediaFormatInterpretation: EffectiveMediaFormatInterpretation { get }
    var mediaKind: PlaybackMediaKind { get }
    var activeSessionID: String? { get }
    var actualPlaybackSeconds: Double { get }
    var didEndNaturally: Bool { get }
    var availableAudioTracks: [PlaybackModel.AudioTrack] { get }
    var currentAudioTrackID: String? { get }
    var availableSubtitleTracks: [PlaybackModel.SubtitleTrack] { get }
    var currentSubtitleTrackID: String? { get }
    var userVisibleIssue: PlaybackUserVisibleIssue? { get }
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
        stereo: PlaybackModel.StereoLayout,
        usesDolbyVisionFallback: Bool
    ) async throws
    func useSourceFormat() async throws
    func selectAudioTrack(_ track: PlaybackModel.AudioTrack) async throws
    func selectSubtitleTrack(_ track: PlaybackModel.SubtitleTrack?) async throws
    func replay()
    func displayedArtworkImage() -> CGImage?
    func leavePlayback(reason: PlaybackLeaveReason)
    func leavePlaybackAndWait(reason: PlaybackLeaveReason) async
    func stopForNextRequest(releasingSourceAccess: Bool)
    func setUserVisibleIssue(_ issue: PlaybackUserVisibleIssue?)
}

public extension PlaybackRuntimeControlling {
    func displayedArtworkImage() -> CGImage? { nil }
}
