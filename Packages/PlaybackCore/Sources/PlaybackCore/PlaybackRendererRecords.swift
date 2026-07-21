import Foundation


public enum MediaEventKind: String, Codable, Sendable {
    case sample
    case formatChanged
    case flush
    case end
    case error
}

public struct MediaEventRecord: Codable, Equatable, Sendable {
    public var eventID: String
    public var mediaSessionID: String
    public var videoTrackID: String
    public var streamEpoch: UInt64
    public var formatRevision: UInt64
    public var kind: MediaEventKind
    public var providerProvenance: String

    public init(
        eventID: String,
        mediaSessionID: String,
        videoTrackID: String,
        streamEpoch: UInt64,
        formatRevision: UInt64,
        kind: MediaEventKind,
        providerProvenance: String = "unknown"
    ) {
        self.eventID = eventID
        self.mediaSessionID = mediaSessionID
        self.videoTrackID = videoTrackID
        self.streamEpoch = streamEpoch
        self.formatRevision = formatRevision
        self.kind = kind
        self.providerProvenance = providerProvenance
    }
}

public struct VideoSampleRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
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
    public var bindingID: String
    public var graphID: String
    public var rendererIdentity: String
    public var componentAttached: Bool
    public var componentRendererIdentity: String
    public var entityIdentity: String
    public var active: Bool

    public init(
        mediaSessionID: String,
        bindingID: String,
        graphID: String = "unknown",
        rendererIdentity: String,
        componentAttached: Bool = true,
        componentRendererIdentity: String = "unknown",
        entityIdentity: String,
        active: Bool
    ) {
        self.mediaSessionID = mediaSessionID
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

