import Foundation


public enum PlaybackOperationKind: String, Codable, Sendable {
    case open
    case play
    case pause
    case setRate
    case setStereoLayout
    case setProjection
    case seek
    case close
}
public enum PlaybackOperationState: String, Codable, Sendable {
    case running
    case completed
    case failed
    case terminatedByCleanup
}

enum PlaybackArtifactEventName: String, CaseIterable, Sendable {
    case operationOpenStarted = "operation.open.started"
    case operationOpenCompleted = "operation.open.completed"
    case operationOpenFailed = "operation.open.failed"
    case operationOpenTerminatedByCleanup = "operation.open.terminatedByCleanup"
    case operationPlayStarted = "operation.play.started"
    case operationPlayCompleted = "operation.play.completed"
    case operationPlayFailed = "operation.play.failed"
    case operationPlayTerminatedByCleanup = "operation.play.terminatedByCleanup"
    case operationPauseStarted = "operation.pause.started"
    case operationPauseCompleted = "operation.pause.completed"
    case operationPauseFailed = "operation.pause.failed"
    case operationPauseTerminatedByCleanup = "operation.pause.terminatedByCleanup"
    case operationSetRateStarted = "operation.setRate.started"
    case operationSetRateCompleted = "operation.setRate.completed"
    case operationSetRateFailed = "operation.setRate.failed"
    case operationSetRateTerminatedByCleanup = "operation.setRate.terminatedByCleanup"
    case operationSetStereoLayoutStarted = "operation.setStereoLayout.started"
    case operationSetStereoLayoutCompleted = "operation.setStereoLayout.completed"
    case operationSetStereoLayoutFailed = "operation.setStereoLayout.failed"
    case operationSetStereoLayoutTerminatedByCleanup =
        "operation.setStereoLayout.terminatedByCleanup"
    case operationSetProjectionStarted = "operation.setProjection.started"
    case operationSetProjectionCompleted = "operation.setProjection.completed"
    case operationSetProjectionFailed = "operation.setProjection.failed"
    case operationSetProjectionTerminatedByCleanup =
        "operation.setProjection.terminatedByCleanup"
    case operationSeekStarted = "operation.seek.started"
    case operationSeekCompleted = "operation.seek.completed"
    case operationSeekFailed = "operation.seek.failed"
    case operationSeekTerminatedByCleanup = "operation.seek.terminatedByCleanup"
    case operationCloseStarted = "operation.close.started"
    case operationCloseCompleted = "operation.close.completed"
    case operationCloseFailed = "operation.close.failed"
    case operationCloseTerminatedByCleanup = "operation.close.terminatedByCleanup"
    case controlOpenRejected = "control.open.rejected"
    case controlPlayRejected = "control.play.rejected"
    case controlPauseRejected = "control.pause.rejected"
    case controlSetRateRejected = "control.setRate.rejected"
    case controlSetStereoLayoutRejected = "control.setStereoLayout.rejected"
    case controlSetProjectionRejected = "control.setProjection.rejected"
    case controlSeekRejected = "control.seek.rejected"
    case controlCloseRejected = "control.close.rejected"
    case providerFormatChanged = "provider.formatChanged"
    case providerFlush = "provider.flush"
    case videoRendererFailed = "videoRenderer.failed"
    case audioRendererFailed = "audioRenderer.failed"
    case videoRendererWarning = "videoRenderer.warning"
    case audioRendererWarning = "audioRenderer.warning"

    /// Resolves an operation kind to one complete, searchable started-event name.
    static func operationStarted(_ kind: PlaybackOperationKind) -> Self {
        switch kind {
        case .open: .operationOpenStarted
        case .play: .operationPlayStarted
        case .pause: .operationPauseStarted
        case .setRate: .operationSetRateStarted
        case .setStereoLayout: .operationSetStereoLayoutStarted
        case .setProjection: .operationSetProjectionStarted
        case .seek: .operationSeekStarted
        case .close: .operationCloseStarted
        }
    }

    /// Resolves an operation kind and terminal state to one complete event name.
    static func operationFinished(
        _ kind: PlaybackOperationKind,
        as state: PlaybackOperationState
    ) -> Self {
        switch (kind, state) {
        case (_, .running):
            preconditionFailure("A running playback operation cannot be finished.")
        case (.open, .completed): .operationOpenCompleted
        case (.open, .failed): .operationOpenFailed
        case (.open, .terminatedByCleanup): .operationOpenTerminatedByCleanup
        case (.play, .completed): .operationPlayCompleted
        case (.play, .failed): .operationPlayFailed
        case (.play, .terminatedByCleanup): .operationPlayTerminatedByCleanup
        case (.pause, .completed): .operationPauseCompleted
        case (.pause, .failed): .operationPauseFailed
        case (.pause, .terminatedByCleanup): .operationPauseTerminatedByCleanup
        case (.setRate, .completed): .operationSetRateCompleted
        case (.setRate, .failed): .operationSetRateFailed
        case (.setRate, .terminatedByCleanup): .operationSetRateTerminatedByCleanup
        case (.setStereoLayout, .completed): .operationSetStereoLayoutCompleted
        case (.setStereoLayout, .failed): .operationSetStereoLayoutFailed
        case (.setStereoLayout, .terminatedByCleanup):
            .operationSetStereoLayoutTerminatedByCleanup
        case (.setProjection, .completed): .operationSetProjectionCompleted
        case (.setProjection, .failed): .operationSetProjectionFailed
        case (.setProjection, .terminatedByCleanup):
            .operationSetProjectionTerminatedByCleanup
        case (.seek, .completed): .operationSeekCompleted
        case (.seek, .failed): .operationSeekFailed
        case (.seek, .terminatedByCleanup): .operationSeekTerminatedByCleanup
        case (.close, .completed): .operationCloseCompleted
        case (.close, .failed): .operationCloseFailed
        case (.close, .terminatedByCleanup): .operationCloseTerminatedByCleanup
        }
    }

    /// Resolves a rejected control to one complete, searchable event name.
    static func controlRejected(_ kind: PlaybackOperationKind) -> Self {
        switch kind {
        case .open: .controlOpenRejected
        case .play: .controlPlayRejected
        case .pause: .controlPauseRejected
        case .setRate: .controlSetRateRejected
        case .setStereoLayout: .controlSetStereoLayoutRejected
        case .setProjection: .controlSetProjectionRejected
        case .seek: .controlSeekRejected
        case .close: .controlCloseRejected
        }
    }

    /// Resolves provider control events without constructing their names dynamically.
    static func providerControl(_ kind: MediaEventKind) -> Self {
        switch kind {
        case .formatChanged: .providerFormatChanged
        case .flush: .providerFlush
        case .sample, .end, .error:
            preconditionFailure(
                "Only provider formatChanged and flush events are control events."
            )
        }
    }

    /// Resolves renderer failures and warnings without constructing their names dynamically.
    static func renderer(
        _ kind: RendererFailureKind,
        warning: Bool
    ) -> Self {
        switch (kind, warning) {
        case (.video, false): .videoRendererFailed
        case (.audio, false): .audioRendererFailed
        case (.video, true): .videoRendererWarning
        case (.audio, true): .audioRendererWarning
        }
    }
}

public struct PlaybackOperationRecord: Codable, Equatable, Sendable {
    public var operationID: String
    public var mediaSessionID: String
    public var kind: PlaybackOperationKind
    public var state: PlaybackOperationState
    public var startedAt: Date
    public var completedAt: Date?
    public var targetTimeSeconds: Double?
    public var targetRate: Float?
    public var failure: String?

    public init(
        operationID: String = UUID().uuidString,
        mediaSessionID: String,
        kind: PlaybackOperationKind,
        state: PlaybackOperationState = .running,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        targetTimeSeconds: Double? = nil,
        targetRate: Float? = nil,
        failure: String? = nil
    ) {
        self.operationID = operationID
        self.mediaSessionID = mediaSessionID
        self.kind = kind
        self.state = state
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.targetTimeSeconds = targetTimeSeconds
        self.targetRate = targetRate
        self.failure = failure
    }

    public func finishing(
        as state: PlaybackOperationState,
        failure: String? = nil,
        at date: Date = Date()
    ) -> Self {
        var result = self
        result.state = state
        result.completedAt = date
        result.failure = failure
        return result
    }
}

public struct RendererStateRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var graphID: String
    public var graphRevision: UInt64
    public var streamEpoch: UInt64
    public var rendererIdentity: String
    public var synchronizerIdentity: String
    public var timelineConfigured: Bool
    public var currentTimeSeconds: Double
    public var rate: Float
    public var rendererStatus: String
    public var rendererError: String?
    public var inputModel: String?
    public var displayedPixelBuffer: Bool
    public var flushCount: UInt64

    public init(
        mediaSessionID: String,
        graphID: String = "unknown",
        graphRevision: UInt64,
        streamEpoch: UInt64 = 1,
        rendererIdentity: String = "unknown",
        synchronizerIdentity: String = "unknown",
        timelineConfigured: Bool = false,
        currentTimeSeconds: Double,
        rate: Float,
        rendererStatus: String,
        rendererError: String?,
        inputModel: String?,
        displayedPixelBuffer: Bool,
        flushCount: UInt64
    ) {
        self.mediaSessionID = mediaSessionID
        self.graphID = graphID
        self.graphRevision = graphRevision
        self.streamEpoch = streamEpoch
        self.rendererIdentity = rendererIdentity
        self.synchronizerIdentity = synchronizerIdentity
        self.timelineConfigured = timelineConfigured
        self.currentTimeSeconds = currentTimeSeconds
        self.rate = rate
        self.rendererStatus = rendererStatus
        self.rendererError = rendererError
        self.inputModel = inputModel
        self.displayedPixelBuffer = displayedPixelBuffer
        self.flushCount = flushCount
    }
}

public struct PlaybackCleanupStateRecord: Codable, Equatable, Sendable {
    public var videoProviderCancelled = false
    public var audioProviderCancelled = false
    public var audioRendererFlushed = false
    public var videoRendererFlushed = false

    public init() {}
}

public struct MediaSourceRecord: Codable, Equatable, Sendable {
    public var locator: URL
    public var provenance: String
    public var privacySafeSummary: String
    public var accessRequirement: String

    public init(
        locator: URL,
        provenance: String,
        privacySafeSummary: String,
        accessRequirement: String
    ) {
        self.locator = locator
        self.provenance = provenance
        self.privacySafeSummary = privacySafeSummary
        self.accessRequirement = accessRequirement
    }
}

public struct MediaSessionRecord: Codable, Equatable, Sendable {
    public let mediaSessionID: String
    public let source: MediaSourceRecord
    public let initialTimeSeconds: Double
    public let startsPaused: Bool
    public let initialRate: Float
    public var lifecycle: PlaybackLifecycle

    public init(
        mediaSessionID: String,
        source: MediaSourceRecord,
        initialTimeSeconds: Double,
        startsPaused: Bool,
        initialRate: Float? = nil,
        lifecycle: PlaybackLifecycle = .opening
    ) {
        self.mediaSessionID = mediaSessionID
        self.source = source
        self.initialTimeSeconds = initialTimeSeconds
        self.startsPaused = startsPaused
        self.initialRate = initialRate ?? (startsPaused ? 0 : 1)
        self.lifecycle = lifecycle
    }
}

public struct OpenRejectionRecord: Codable, Equatable, Sendable {
    public var sourceSummary: String
    public var reason: String
    public var occupyingMediaSessionID: String?

    public init(
        sourceSummary: String,
        reason: String,
        occupyingMediaSessionID: String?
    ) {
        self.sourceSummary = sourceSummary
        self.reason = reason
        self.occupyingMediaSessionID = occupyingMediaSessionID
    }
}

public struct ControlRejectionRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var kind: PlaybackOperationKind
    public var reason: String
    public var targetTimeSeconds: Double?
    public var targetRate: Float?

    public init(
        mediaSessionID: String,
        kind: PlaybackOperationKind,
        reason: String,
        targetTimeSeconds: Double? = nil,
        targetRate: Float? = nil
    ) {
        self.mediaSessionID = mediaSessionID
        self.kind = kind
        self.reason = reason
        self.targetTimeSeconds = targetTimeSeconds
        self.targetRate = targetRate
    }
}

public struct PlaybackFailureRecord: Codable, Equatable, Sendable {
    public var failureID: String
    public var mediaSessionID: String
    public var node: PlaybackNode
    public var stage: String
    public var errorType: String
    public var message: String
    public var recoverability: String
    public var rendererKind: String?
    public var requiresFlushToResumeDecoding: Bool?

    public init(
        failureID: String = UUID().uuidString,
        mediaSessionID: String,
        node: PlaybackNode,
        stage: String,
        errorType: String,
        message: String,
        recoverability: String,
        rendererKind: String? = nil,
        requiresFlushToResumeDecoding: Bool? = nil
    ) {
        self.failureID = failureID
        self.mediaSessionID = mediaSessionID
        self.node = node
        self.stage = stage
        self.errorType = errorType
        self.message = message
        self.recoverability = recoverability
        self.rendererKind = rendererKind
        self.requiresFlushToResumeDecoding = requiresFlushToResumeDecoding
    }
}

public enum OpenAdmission: Equatable, Sendable {
    case accepted(MediaSessionRecord)
    case rejected(OpenRejectionRecord)
}

public struct ProviderOpenSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var snapshotID: String
    public var mediaSessionID: String
    public var sourceSummary: String
    public var providerKind: String
    public var openStatus: String
    public var containerFormat: String
    public var durationSeconds: Double
    public var seekability: ObservedStringFact
    public var observedVideoTrackCount: Int
    public var selectedRawTrackMapping: ObservedStringFact
    public var codecName: String
    public var codecTag: String
    public var codecProfile: ObservedStringFact
    public var codecLevel: ObservedStringFact
    public var dimensions: String
    public var nominalFrameRate: Double
    public var timebase: ObservedStringFact
    public var codecConfigurationSummary: ObservedStringFact
    public var formatSignaling: VideoFormatSignalingSummary

    public init(
        schemaVersion: Int = 1,
        snapshotID: String = UUID().uuidString,
        mediaSessionID: String,
        sourceSummary: String = "unknown",
        providerKind: String,
        openStatus: String = "opened",
        containerFormat: String = "unknown",
        durationSeconds: Double = 0,
        seekability: ObservedStringFact = .init(.unknown),
        observedVideoTrackCount: Int = 1,
        selectedRawTrackMapping: ObservedStringFact = .init(.notExposed),
        codecName: String = "unknown",
        codecTag: String = "unknown",
        codecProfile: ObservedStringFact = .init(.notExposed),
        codecLevel: ObservedStringFact = .init(.notExposed),
        dimensions: String = "unknown",
        nominalFrameRate: Double = 0,
        timebase: ObservedStringFact = .init(.notExposed),
        codecConfigurationSummary: ObservedStringFact = .init(.notExposed),
        formatSignaling: VideoFormatSignalingSummary = .init(provenance: "providerOpen")
    ) {
        self.schemaVersion = schemaVersion
        self.snapshotID = snapshotID
        self.mediaSessionID = mediaSessionID
        self.sourceSummary = sourceSummary
        self.providerKind = providerKind
        self.openStatus = openStatus
        self.containerFormat = containerFormat
        self.durationSeconds = durationSeconds
        self.seekability = seekability
        self.observedVideoTrackCount = observedVideoTrackCount
        self.selectedRawTrackMapping = selectedRawTrackMapping
        self.codecName = codecName
        self.codecTag = codecTag
        self.codecProfile = codecProfile
        self.codecLevel = codecLevel
        self.dimensions = dimensions
        self.nominalFrameRate = nominalFrameRate
        self.timebase = timebase
        self.codecConfigurationSummary = codecConfigurationSummary
        self.formatSignaling = formatSignaling
    }
}
