import Foundation

public enum PlaybackLifecycle: String, Codable, Sendable {
    case idle
    case opening
    case ready
    case playing
    case paused
    case ended
    case failed
}

public enum NodeOutcome: String, Codable, Sendable {
    case succeeded
    case failed
    case terminatedByCleanup
}

public enum PlaybackNode: Int, Codable, CaseIterable, Sendable {
    case sourceAcquisition = 1
    case mediaSessionAndRouteBinding
    case providerOpen
    case videoTrackModel
    case routeMediaEventStream
    case videoSampleStream
    case rendererInputCoordination
    case realityKitRendererBinding
    case rendererConsumerBinding
}

public enum FactAvailability: String, Codable, Sendable {
    case known
    case none
    case unknown
    case notExposed
    case unsupported
    case notAvailable
}

public struct ObservedStringFact: Codable, Equatable, Sendable {
    public var availability: FactAvailability
    public var value: String?

    public init(_ availability: FactAvailability, value: String? = nil) {
        self.availability = availability
        self.value = value
    }
}

public struct ObservedBooleanFact: Codable, Equatable, Sendable {
    public var availability: FactAvailability
    public var value: Bool?

    public init(_ availability: FactAvailability, value: Bool? = nil) {
        self.availability = availability
        self.value = value
    }
}

public struct VideoFormatSignalingSummary: Codable, Equatable, Sendable {
    public var provenance: String
    public var colorPrimaries: ObservedStringFact
    public var transferFunction: ObservedStringFact
    public var yCbCrMatrix: ObservedStringFact
    public var range: ObservedStringFact
    public var projectionKind: ObservedStringFact
    public var viewPackingKind: ObservedStringFact
    public var hasLeftStereoEyeView: ObservedBooleanFact
    public var hasRightStereoEyeView: ObservedBooleanFact
    public var masteringDisplayMetadata: ObservedBooleanFact
    public var contentLightLevelMetadata: ObservedBooleanFact
    public var hvcC: ObservedBooleanFact
    public var dvcC: ObservedBooleanFact
    public var dvvC: ObservedBooleanFact
    public var ambientViewingEnvironment: ObservedBooleanFact

    public init(
        provenance: String,
        colorPrimaries: ObservedStringFact = .init(.notExposed),
        transferFunction: ObservedStringFact = .init(.notExposed),
        yCbCrMatrix: ObservedStringFact = .init(.notExposed),
        range: ObservedStringFact = .init(.notExposed),
        projectionKind: ObservedStringFact = .init(.notExposed),
        viewPackingKind: ObservedStringFact = .init(.notExposed),
        hasLeftStereoEyeView: ObservedBooleanFact = .init(.notExposed),
        hasRightStereoEyeView: ObservedBooleanFact = .init(.notExposed),
        masteringDisplayMetadata: ObservedBooleanFact = .init(.notExposed),
        contentLightLevelMetadata: ObservedBooleanFact = .init(.notExposed),
        hvcC: ObservedBooleanFact = .init(.notExposed),
        dvcC: ObservedBooleanFact = .init(.notExposed),
        dvvC: ObservedBooleanFact = .init(.notExposed),
        ambientViewingEnvironment: ObservedBooleanFact = .init(.notExposed)
    ) {
        self.provenance = provenance
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.yCbCrMatrix = yCbCrMatrix
        self.range = range
        self.projectionKind = projectionKind
        self.viewPackingKind = viewPackingKind
        self.hasLeftStereoEyeView = hasLeftStereoEyeView
        self.hasRightStereoEyeView = hasRightStereoEyeView
        self.masteringDisplayMetadata = masteringDisplayMetadata
        self.contentLightLevelMetadata = contentLightLevelMetadata
        self.hvcC = hvcC
        self.dvcC = dvcC
        self.dvvC = dvvC
        self.ambientViewingEnvironment = ambientViewingEnvironment
    }

    private enum CodingKeys: String, CodingKey {
        case provenance
        case colorPrimaries
        case transferFunction
        case yCbCrMatrix
        case range
        case projectionKind
        case viewPackingKind
        case hasLeftStereoEyeView
        case hasRightStereoEyeView
        case masteringDisplayMetadata
        case contentLightLevelMetadata
        case hvcC
        case dvcC
        case dvvC
        case ambientViewingEnvironment
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provenance = try values.decode(String.self, forKey: .provenance)
        colorPrimaries = try values.decode(ObservedStringFact.self, forKey: .colorPrimaries)
        transferFunction = try values.decode(ObservedStringFact.self, forKey: .transferFunction)
        yCbCrMatrix = try values.decode(ObservedStringFact.self, forKey: .yCbCrMatrix)
        range = try values.decode(ObservedStringFact.self, forKey: .range)
        projectionKind = try values.decodeIfPresent(
            ObservedStringFact.self,
            forKey: .projectionKind
        ) ?? .init(.notExposed)
        viewPackingKind = try values.decodeIfPresent(
            ObservedStringFact.self,
            forKey: .viewPackingKind
        ) ?? .init(.notExposed)
        hasLeftStereoEyeView = try values.decodeIfPresent(
            ObservedBooleanFact.self,
            forKey: .hasLeftStereoEyeView
        ) ?? .init(.notExposed)
        hasRightStereoEyeView = try values.decodeIfPresent(
            ObservedBooleanFact.self,
            forKey: .hasRightStereoEyeView
        ) ?? .init(.notExposed)
        masteringDisplayMetadata = try values.decode(
            ObservedBooleanFact.self,
            forKey: .masteringDisplayMetadata
        )
        contentLightLevelMetadata = try values.decode(
            ObservedBooleanFact.self,
            forKey: .contentLightLevelMetadata
        )
        hvcC = try values.decode(ObservedBooleanFact.self, forKey: .hvcC)
        dvcC = try values.decode(ObservedBooleanFact.self, forKey: .dvcC)
        dvvC = try values.decode(ObservedBooleanFact.self, forKey: .dvvC)
        ambientViewingEnvironment = try values.decode(
            ObservedBooleanFact.self,
            forKey: .ambientViewingEnvironment
        )
    }
}

public enum PlaybackOperationKind: String, Codable, Sendable {
    case open
    case play
    case pause
    case setRate
    case setStereoLayout
    case setProjection
    case seek
    case switchRoute
    case close
}

public enum PlaybackOperationState: String, Codable, Sendable {
    case running
    case completed
    case failed
    case terminatedByCleanup
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
    public var sourceRoute: PlaybackRoute?
    public var targetRoute: PlaybackRoute?
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
        sourceRoute: PlaybackRoute? = nil,
        targetRoute: PlaybackRoute? = nil,
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
        self.sourceRoute = sourceRoute
        self.targetRoute = targetRoute
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
    public var route: PlaybackRoute
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
        route: PlaybackRoute = .appleCompressed,
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
        self.route = route
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
    public let route: PlaybackRoute
    public let initialTimeSeconds: Double
    public let startsPaused: Bool
    public let initialRate: Float
    public var lifecycle: PlaybackLifecycle

    public init(
        mediaSessionID: String,
        source: MediaSourceRecord,
        route: PlaybackRoute,
        initialTimeSeconds: Double,
        startsPaused: Bool,
        initialRate: Float? = nil,
        lifecycle: PlaybackLifecycle = .opening
    ) {
        self.mediaSessionID = mediaSessionID
        self.source = source
        self.route = route
        self.initialTimeSeconds = initialTimeSeconds
        self.startsPaused = startsPaused
        self.initialRate = initialRate ?? (startsPaused ? 0 : 1)
        self.lifecycle = lifecycle
    }
}

public struct OpenRejectionRecord: Codable, Equatable, Sendable {
    public var requestedRoute: PlaybackRoute
    public var sourceSummary: String
    public var reason: String
    public var occupyingMediaSessionID: String?

    public init(
        requestedRoute: PlaybackRoute,
        sourceSummary: String,
        reason: String,
        occupyingMediaSessionID: String?
    ) {
        self.requestedRoute = requestedRoute
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
    public var route: PlaybackRoute
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
        route: PlaybackRoute,
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
        self.route = route
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
    public var route: PlaybackRoute
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
        route: PlaybackRoute,
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
        self.route = route
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

public struct VideoTrackRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var route: PlaybackRoute
    public var videoTrackID: String
    public var rawSourceMapping: String
    public var codecName: String
    public var sourceSnapshotID: String
    public var dimensions: String
    public var nominalFrameRate: Double
    public var timebase: ObservedStringFact
    public var formatSummary: String
    public var selected: Bool
    public var notSelectedReason: String?

    public init(
        mediaSessionID: String,
        route: PlaybackRoute,
        videoTrackID: String,
        rawSourceMapping: String,
        codecName: String,
        sourceSnapshotID: String = "unknown",
        dimensions: String = "unknown",
        nominalFrameRate: Double = 0,
        timebase: ObservedStringFact = .init(.notExposed),
        formatSummary: String = "unknown",
        selected: Bool,
        notSelectedReason: String? = nil
    ) {
        self.mediaSessionID = mediaSessionID
        self.route = route
        self.videoTrackID = videoTrackID
        self.rawSourceMapping = rawSourceMapping
        self.codecName = codecName
        self.sourceSnapshotID = sourceSnapshotID
        self.dimensions = dimensions
        self.nominalFrameRate = nominalFrameRate
        self.timebase = timebase
        self.formatSummary = formatSummary
        self.selected = selected
        self.notSelectedReason = notSelectedReason
    }
}

public struct AudioTrackRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var audioTrackID: String
    public var rawStreamIndex: Int
    public var codecName: String
    public var sampleRate: Int
    public var channelCount: Int
    public var selected: Bool

    public init(
        mediaSessionID: String,
        audioTrackID: String,
        rawStreamIndex: Int,
        codecName: String,
        sampleRate: Int,
        channelCount: Int,
        selected: Bool
    ) {
        self.mediaSessionID = mediaSessionID
        self.audioTrackID = audioTrackID
        self.rawStreamIndex = rawStreamIndex
        self.codecName = codecName
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.selected = selected
    }
}

public struct SubtitleStateRecord: Codable, Equatable, Sendable {
    public var availableTracks: [PlaybackSubtitleTrack]
    public var selectedTrackID: PlaybackSubtitleTrack.ID?
    public var activeCueIDs: [PlaybackSubtitleCue.ID]
    public var streamEpoch: UInt64
    public var selectionGeneration: UInt64
    public var suppressesActiveCues: Bool

    public init(
        availableTracks: [PlaybackSubtitleTrack],
        selectedTrackID: PlaybackSubtitleTrack.ID?,
        activeCueIDs: [PlaybackSubtitleCue.ID],
        streamEpoch: UInt64,
        selectionGeneration: UInt64,
        suppressesActiveCues: Bool
    ) {
        self.availableTracks = availableTracks
        self.selectedTrackID = selectedTrackID
        self.activeCueIDs = activeCueIDs
        self.streamEpoch = streamEpoch
        self.selectionGeneration = selectionGeneration
        self.suppressesActiveCues = suppressesActiveCues
    }
}

public struct AudioSampleRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var audioTrackID: String
    public var streamEpoch: UInt64
    public var rawStreamIndex: Int
    public var presentationTimeSeconds: Double
    public var durationSeconds: Double
    public var sampleRate: Int
    public var channelCount: Int
    public var sampleCount: Int
    public var payloadOwnershipState: String

    public init(
        mediaSessionID: String,
        audioTrackID: String,
        streamEpoch: UInt64,
        rawStreamIndex: Int = -1,
        presentationTimeSeconds: Double,
        durationSeconds: Double,
        sampleRate: Int = 0,
        channelCount: Int = 0,
        sampleCount: Int,
        payloadOwnershipState: String = "unknown"
    ) {
        self.mediaSessionID = mediaSessionID
        self.audioTrackID = audioTrackID
        self.streamEpoch = streamEpoch
        self.rawStreamIndex = rawStreamIndex
        self.presentationTimeSeconds = presentationTimeSeconds
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.sampleCount = sampleCount
        self.payloadOwnershipState = payloadOwnershipState
    }

    private enum CodingKeys: String, CodingKey {
        case mediaSessionID
        case audioTrackID
        case streamEpoch
        case rawStreamIndex
        case presentationTimeSeconds
        case durationSeconds
        case sampleRate
        case channelCount
        case sampleCount
        case payloadOwnershipState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaSessionID = try container.decode(String.self, forKey: .mediaSessionID)
        audioTrackID = try container.decode(String.self, forKey: .audioTrackID)
        streamEpoch = try container.decode(UInt64.self, forKey: .streamEpoch)
        rawStreamIndex = try container.decodeIfPresent(
            Int.self,
            forKey: .rawStreamIndex
        ) ?? -1
        presentationTimeSeconds = try container.decode(
            Double.self,
            forKey: .presentationTimeSeconds
        )
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 0
        channelCount = try container.decodeIfPresent(Int.self, forKey: .channelCount) ?? 0
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        payloadOwnershipState = try container.decodeIfPresent(
            String.self,
            forKey: .payloadOwnershipState
        ) ?? "unknown"
    }
}

public struct AudioRendererStateRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var graphID: String
    public var rendererIdentity: String
    public var videoRendererIdentity: String
    public var synchronizerIdentity: String
    public var streamEpoch: UInt64
    public var enqueuedSampleBufferCount: UInt64
    public var enqueuedAudioFrameCount: UInt64
    public var volume: Float
    public var muted: Bool
    public var error: String?

    public init(
        mediaSessionID: String,
        graphID: String = "unknown",
        rendererIdentity: String,
        videoRendererIdentity: String = "unknown",
        synchronizerIdentity: String = "unknown",
        streamEpoch: UInt64,
        enqueuedSampleBufferCount: UInt64,
        enqueuedAudioFrameCount: UInt64,
        volume: Float,
        muted: Bool,
        error: String?
    ) {
        self.mediaSessionID = mediaSessionID
        self.graphID = graphID
        self.rendererIdentity = rendererIdentity
        self.videoRendererIdentity = videoRendererIdentity
        self.synchronizerIdentity = synchronizerIdentity
        self.streamEpoch = streamEpoch
        self.enqueuedSampleBufferCount = enqueuedSampleBufferCount
        self.enqueuedAudioFrameCount = enqueuedAudioFrameCount
        self.volume = volume
        self.muted = muted
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case mediaSessionID
        case graphID
        case rendererIdentity
        case videoRendererIdentity
        case synchronizerIdentity
        case streamEpoch
        case enqueuedSampleBufferCount
        case enqueuedAudioFrameCount
        case volume
        case muted
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaSessionID = try container.decode(String.self, forKey: .mediaSessionID)
        graphID = try container.decodeIfPresent(String.self, forKey: .graphID) ?? "unknown"
        rendererIdentity = try container.decode(String.self, forKey: .rendererIdentity)
        videoRendererIdentity = try container.decodeIfPresent(
            String.self,
            forKey: .videoRendererIdentity
        ) ?? "unknown"
        synchronizerIdentity = try container.decodeIfPresent(
            String.self,
            forKey: .synchronizerIdentity
        ) ?? "unknown"
        streamEpoch = try container.decode(UInt64.self, forKey: .streamEpoch)
        enqueuedSampleBufferCount = try container.decode(
            UInt64.self,
            forKey: .enqueuedSampleBufferCount
        )
        enqueuedAudioFrameCount = try container.decode(
            UInt64.self,
            forKey: .enqueuedAudioFrameCount
        )
        volume = try container.decode(Float.self, forKey: .volume)
        muted = try container.decode(Bool.self, forKey: .muted)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

public enum RouteMediaEventKind: String, Codable, Sendable {
    case sample
    case formatChanged
    case flush
    case end
    case error
}

public struct RouteMediaEventRecord: Codable, Equatable, Sendable {
    public var eventID: String
    public var mediaSessionID: String
    public var route: PlaybackRoute
    public var videoTrackID: String
    public var streamEpoch: UInt64
    public var formatRevision: UInt64
    public var kind: RouteMediaEventKind
    public var providerProvenance: String

    public init(
        eventID: String,
        mediaSessionID: String,
        route: PlaybackRoute,
        videoTrackID: String,
        streamEpoch: UInt64,
        formatRevision: UInt64,
        kind: RouteMediaEventKind,
        providerProvenance: String = "unknown"
    ) {
        self.eventID = eventID
        self.mediaSessionID = mediaSessionID
        self.route = route
        self.videoTrackID = videoTrackID
        self.streamEpoch = streamEpoch
        self.formatRevision = formatRevision
        self.kind = kind
        self.providerProvenance = providerProvenance
    }
}

public struct VideoSampleRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var route: PlaybackRoute
    public var videoTrackID: String
    public var sourceEventID: String
    public var streamEpoch: UInt64
    public var formatRevision: UInt64
    public var inputKind: RendererInputKind
    public var presentationTimeSeconds: Double
    public var decodeTimeSeconds: Double?
    public var durationSeconds: Double
    public var mediaSubtype: String
    public var dimensions: String
    public var sampleCount: Int
    public var formatIdentity: String
    public var syncSummary: String
    public var dependencySummary: String
    public var formatSignaling: VideoFormatSignalingSummary
    public var payloadOwnershipState: String

    public init(
        mediaSessionID: String,
        route: PlaybackRoute,
        videoTrackID: String,
        sourceEventID: String,
        streamEpoch: UInt64,
        formatRevision: UInt64,
        inputKind: RendererInputKind,
        presentationTimeSeconds: Double,
        decodeTimeSeconds: Double?,
        durationSeconds: Double,
        mediaSubtype: String,
        dimensions: String,
        sampleCount: Int = 1,
        formatIdentity: String = "unknown",
        syncSummary: String = "unknown",
        dependencySummary: String = "unknown",
        formatSignaling: VideoFormatSignalingSummary = .init(provenance: "sample"),
        payloadOwnershipState: String = "unknown"
    ) {
        self.mediaSessionID = mediaSessionID
        self.route = route
        self.videoTrackID = videoTrackID
        self.sourceEventID = sourceEventID
        self.streamEpoch = streamEpoch
        self.formatRevision = formatRevision
        self.inputKind = inputKind
        self.presentationTimeSeconds = presentationTimeSeconds
        self.decodeTimeSeconds = decodeTimeSeconds
        self.durationSeconds = durationSeconds
        self.mediaSubtype = mediaSubtype
        self.dimensions = dimensions
        self.sampleCount = sampleCount
        self.formatIdentity = formatIdentity
        self.syncSummary = syncSummary
        self.dependencySummary = dependencySummary
        self.formatSignaling = formatSignaling
        self.payloadOwnershipState = payloadOwnershipState
    }
}

public enum RendererInputOutcome: String, Codable, Sendable {
    case accepted
    case deferredByBackpressure
    case rejectedAsStale
    case failed
}

public struct RendererInputRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var route: PlaybackRoute
    public var sourceEventID: String
    public var videoTrackID: String
    public var streamEpoch: UInt64
    public var formatRevision: UInt64
    public var graphRevision: UInt64
    public var inputKind: RendererInputKind
    public var timelineConfiguredBeforeFirstEnqueue: Bool
    public var action: String
    public var outcome: RendererInputOutcome

    public init(
        mediaSessionID: String,
        route: PlaybackRoute,
        sourceEventID: String,
        videoTrackID: String = "unknown",
        streamEpoch: UInt64,
        formatRevision: UInt64 = 1,
        graphRevision: UInt64,
        inputKind: RendererInputKind = .compressed,
        timelineConfiguredBeforeFirstEnqueue: Bool = false,
        action: String,
        outcome: RendererInputOutcome
    ) {
        self.mediaSessionID = mediaSessionID
        self.route = route
        self.sourceEventID = sourceEventID
        self.videoTrackID = videoTrackID
        self.streamEpoch = streamEpoch
        self.formatRevision = formatRevision
        self.graphRevision = graphRevision
        self.inputKind = inputKind
        self.timelineConfiguredBeforeFirstEnqueue = timelineConfiguredBeforeFirstEnqueue
        self.action = action
        self.outcome = outcome
    }
}

public struct RealityKitBindingRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var route: PlaybackRoute
    public var bindingID: String
    public var graphID: String
    public var rendererIdentity: String
    public var componentAttached: Bool
    public var componentRendererIdentity: String
    public var entityIdentity: String
    public var active: Bool

    public init(
        mediaSessionID: String,
        route: PlaybackRoute,
        bindingID: String,
        graphID: String = "unknown",
        rendererIdentity: String,
        componentAttached: Bool = true,
        componentRendererIdentity: String = "unknown",
        entityIdentity: String,
        active: Bool
    ) {
        self.mediaSessionID = mediaSessionID
        self.route = route
        self.bindingID = bindingID
        self.graphID = graphID
        self.rendererIdentity = rendererIdentity
        self.componentAttached = componentAttached
        self.componentRendererIdentity = componentRendererIdentity
        self.entityIdentity = entityIdentity
        self.active = active
    }
}

public struct PresentationBindingRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var route: PlaybackRoute
    public var presentationBindingID: String
    public var rendererBindingID: String
    public var realityViewIdentity: String
    public var entityAttached: Bool
    public var platform: String
    public var provenance: String
    public var appAdapterKind: String
    public var sceneContainer: ObservedStringFact
    public var sceneLifecycle: ObservedStringFact

    public init(
        mediaSessionID: String,
        route: PlaybackRoute,
        presentationBindingID: String,
        rendererBindingID: String = "unknown",
        realityViewIdentity: String,
        entityAttached: Bool,
        platform: String,
        provenance: String,
        appAdapterKind: String = "unknown",
        sceneContainer: ObservedStringFact = .init(.notExposed),
        sceneLifecycle: ObservedStringFact = .init(.notExposed)
    ) {
        self.mediaSessionID = mediaSessionID
        self.route = route
        self.presentationBindingID = presentationBindingID
        self.rendererBindingID = rendererBindingID
        self.realityViewIdentity = realityViewIdentity
        self.entityAttached = entityAttached
        self.platform = platform
        self.provenance = provenance
        self.appAdapterKind = appAdapterKind
        self.sceneContainer = sceneContainer
        self.sceneLifecycle = sceneLifecycle
    }
}

public struct PresentationStateRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var route: PlaybackRoute
    public var requestedMode: String
    public var phase: String
    public var platform: String
    public var sceneContainer: ObservedStringFact
    public var realityViewIdentity: ObservedStringFact
    public var entityParentIdentity: ObservedStringFact
    public var desiredImmersiveViewingMode: ObservedStringFact
    public var actualImmersiveViewingMode: ObservedStringFact
    public var desiredViewingMode: ObservedStringFact
    public var actualViewingMode: ObservedStringFact
    public var desiredSpatialVideoMode: ObservedStringFact
    public var actualSpatialVideoMode: ObservedStringFact
    public var transitionResult: ObservedStringFact
    public var transitionError: ObservedStringFact

    public init(
        mediaSessionID: String,
        route: PlaybackRoute,
        requestedMode: String,
        phase: String,
        platform: String,
        sceneContainer: ObservedStringFact = .init(.notExposed),
        realityViewIdentity: ObservedStringFact = .init(.notExposed),
        entityParentIdentity: ObservedStringFact = .init(.notExposed),
        desiredImmersiveViewingMode: ObservedStringFact = .init(.notExposed),
        actualImmersiveViewingMode: ObservedStringFact = .init(.notExposed),
        desiredViewingMode: ObservedStringFact = .init(.notExposed),
        actualViewingMode: ObservedStringFact = .init(.notExposed),
        desiredSpatialVideoMode: ObservedStringFact = .init(.notExposed),
        actualSpatialVideoMode: ObservedStringFact = .init(.notExposed),
        transitionResult: ObservedStringFact = .init(.notExposed),
        transitionError: ObservedStringFact = .init(.none)
    ) {
        self.mediaSessionID = mediaSessionID
        self.route = route
        self.requestedMode = requestedMode
        self.phase = phase
        self.platform = platform
        self.sceneContainer = sceneContainer
        self.realityViewIdentity = realityViewIdentity
        self.entityParentIdentity = entityParentIdentity
        self.desiredImmersiveViewingMode = desiredImmersiveViewingMode
        self.actualImmersiveViewingMode = actualImmersiveViewingMode
        self.desiredViewingMode = desiredViewingMode
        self.actualViewingMode = actualViewingMode
        self.desiredSpatialVideoMode = desiredSpatialVideoMode
        self.actualSpatialVideoMode = actualSpatialVideoMode
        self.transitionResult = transitionResult
        self.transitionError = transitionError
    }
}

private enum PlaybackDebugSnapshotV1CodingKey: String, CodingKey {
    case schemaVersion
    case generatedAt
    case lifecycle
    case mediaSession
    case lastMediaSession
    case lastOpenRejection
    case lastControlRejection
    case lastFailure
    case currentOperation
    case lastCompletedOperation
    case lastOpenOperation
    case lastRouteSwitchOperation
    case providerOpen
    case videoTrack
    case availableAudioTracks
    case audioTrack
    case subtitleState
    case lastRouteEvent
    case lastVideoSample
    case lastAudioSample
    case lastRendererInput
    case lastAcceptedRendererInput
    case rendererState
    case audioRendererState
    case realityKitBinding
    case presentationBinding
    case presentationState
    case platform
    case hardwareDisplayFacts
    case evidenceCorrelationIDs
    case streamEpoch
    case formatRevision
    case sampleCount
    case audioSampleBufferCount
    case acceptedRendererInputCount
    case backpressureCount
    case staleRejectionCount
    case lastError
}

extension PlaybackDebugSnapshotV1 {

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: PlaybackDebugSnapshotV1CodingKey.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        lifecycle = try container.decode(PlaybackLifecycle.self, forKey: .lifecycle)
        mediaSession = try container.decodeIfPresent(
            MediaSessionDebugSummary.self,
            forKey: .mediaSession
        )
        lastMediaSession = try container.decodeIfPresent(
            MediaSessionDebugSummary.self,
            forKey: .lastMediaSession
        )
        lastOpenRejection = try container.decodeIfPresent(
            OpenRejectionRecord.self,
            forKey: .lastOpenRejection
        )
        lastControlRejection = try container.decodeIfPresent(
            ControlRejectionRecord.self,
            forKey: .lastControlRejection
        )
        lastFailure = try container.decodeIfPresent(
            PlaybackFailureRecord.self,
            forKey: .lastFailure
        )
        currentOperation = try container.decodeIfPresent(
            PlaybackOperationRecord.self,
            forKey: .currentOperation
        )
        lastCompletedOperation = try container.decodeIfPresent(
            PlaybackOperationRecord.self,
            forKey: .lastCompletedOperation
        )
        lastOpenOperation = try container.decodeIfPresent(
            PlaybackOperationRecord.self,
            forKey: .lastOpenOperation
        )
        lastRouteSwitchOperation = try container.decodeIfPresent(
            PlaybackOperationRecord.self,
            forKey: .lastRouteSwitchOperation
        )
        providerOpen = try container.decodeIfPresent(
            ProviderOpenSnapshot.self,
            forKey: .providerOpen
        )
        videoTrack = try container.decodeIfPresent(VideoTrackRecord.self, forKey: .videoTrack)
        availableAudioTracks = try container.decodeIfPresent(
            [PlaybackAudioTrack].self,
            forKey: .availableAudioTracks
        ) ?? []
        audioTrack = try container.decodeIfPresent(AudioTrackRecord.self, forKey: .audioTrack)
        subtitleState = try container.decodeIfPresent(
            SubtitleStateRecord.self,
            forKey: .subtitleState
        )
        lastRouteEvent = try container.decodeIfPresent(
            RouteMediaEventRecord.self,
            forKey: .lastRouteEvent
        )
        lastVideoSample = try container.decodeIfPresent(
            VideoSampleRecord.self,
            forKey: .lastVideoSample
        )
        lastAudioSample = try container.decodeIfPresent(
            AudioSampleRecord.self,
            forKey: .lastAudioSample
        )
        lastRendererInput = try container.decodeIfPresent(
            RendererInputRecord.self,
            forKey: .lastRendererInput
        )
        lastAcceptedRendererInput = try container.decodeIfPresent(
            RendererInputRecord.self,
            forKey: .lastAcceptedRendererInput
        )
        rendererState = try container.decodeIfPresent(
            RendererStateRecord.self,
            forKey: .rendererState
        )
        audioRendererState = try container.decodeIfPresent(
            AudioRendererStateRecord.self,
            forKey: .audioRendererState
        )
        realityKitBinding = try container.decodeIfPresent(
            RealityKitBindingRecord.self,
            forKey: .realityKitBinding
        )
        presentationBinding = try container.decodeIfPresent(
            PresentationBindingRecord.self,
            forKey: .presentationBinding
        )
        presentationState = try container.decodeIfPresent(
            PresentationStateRecord.self,
            forKey: .presentationState
        )
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        hardwareDisplayFacts = try container.decode(
            FactAvailability.self,
            forKey: .hardwareDisplayFacts
        )
        evidenceCorrelationIDs = try container.decode(
            [String].self,
            forKey: .evidenceCorrelationIDs
        )
        streamEpoch = try container.decode(UInt64.self, forKey: .streamEpoch)
        formatRevision = try container.decode(UInt64.self, forKey: .formatRevision)
        sampleCount = try container.decode(UInt64.self, forKey: .sampleCount)
        audioSampleBufferCount = try container.decode(
            UInt64.self,
            forKey: .audioSampleBufferCount
        )
        acceptedRendererInputCount = try container.decode(
            UInt64.self,
            forKey: .acceptedRendererInputCount
        )
        backpressureCount = try container.decode(UInt64.self, forKey: .backpressureCount)
        staleRejectionCount = try container.decode(
            UInt64.self,
            forKey: .staleRejectionCount
        )
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}
