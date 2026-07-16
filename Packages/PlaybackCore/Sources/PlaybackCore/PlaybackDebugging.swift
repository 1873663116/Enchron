import Foundation

public struct PlaybackDebugEvent: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var sequenceNumber: UInt64
    public var timestamp: Date
    public var mediaSessionID: String?
    public var route: PlaybackRoute?
    public var node: PlaybackNode?
    public var kind: String
    public var outcome: NodeOutcome?
    public var details: [String: String]
}

public struct MediaSessionDebugSummary: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var sourceSummary: String
    public var sourceProvenance: String
    public var accessRequirement: String
    public var route: PlaybackRoute
    public var initialTimeSeconds: Double
    public var startsPaused: Bool
    public var initialRate: Float
    public var lifecycle: PlaybackLifecycle

    public init(_ session: MediaSessionRecord) {
        mediaSessionID = session.mediaSessionID
        sourceSummary = session.source.privacySafeSummary
        sourceProvenance = session.source.provenance
        accessRequirement = session.source.accessRequirement
        route = session.route
        initialTimeSeconds = session.initialTimeSeconds
        startsPaused = session.startsPaused
        initialRate = session.initialRate
        lifecycle = session.lifecycle
    }
}

public struct PlaybackDebugSnapshotV1: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var generatedAt = Date()
    public var lifecycle = PlaybackLifecycle.idle
    public var mediaSession: MediaSessionDebugSummary?
    public var lastMediaSession: MediaSessionDebugSummary?
    public var lastOpenRejection: OpenRejectionRecord?
    public var lastControlRejection: ControlRejectionRecord?
    public var lastFailure: PlaybackFailureRecord?
    public var currentOperation: PlaybackOperationRecord?
    public var lastCompletedOperation: PlaybackOperationRecord?
    public var lastOpenOperation: PlaybackOperationRecord?
    public var lastRouteSwitchOperation: PlaybackOperationRecord?
    public var providerOpen: ProviderOpenSnapshot?
    public var videoTrack: VideoTrackRecord?
    public var availableAudioTracks: [PlaybackAudioTrack] = []
    public var audioTrack: AudioTrackRecord?
    public var lastRouteEvent: RouteMediaEventRecord?
    public var lastVideoSample: VideoSampleRecord?
    public var lastAudioSample: AudioSampleRecord?
    public var lastRendererInput: RendererInputRecord?
    public var lastAcceptedRendererInput: RendererInputRecord?
    public var rendererState: RendererStateRecord?
    public var audioRendererState: AudioRendererStateRecord?
    public var cleanupState: PlaybackCleanupStateRecord?
    public var realityKitBinding: RealityKitBindingRecord?
    public var presentationBinding: PresentationBindingRecord?
    public var presentationState: PresentationStateRecord?
    public var platform: String?
    public var hardwareDisplayFacts = FactAvailability.notAvailable
    public var evidenceCorrelationIDs: [String] = []
    public var streamEpoch: UInt64 = 0
    public var formatRevision: UInt64 = 0
    public var sampleCount: UInt64 = 0
    public var audioSampleBufferCount: UInt64 = 0
    public var acceptedRendererInputCount: UInt64 = 0
    public var backpressureCount: UInt64 = 0
    public var staleRejectionCount: UInt64 = 0
    public var lastError: String?

    public init() {}
}

enum PlaybackCleanupStep {
    case videoProviderCancelled
    case audioProviderCancelled
    case audioRendererFlushed
    case videoRendererFlushed
}

public final class PlaybackDiagnosticsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var currentSnapshot = PlaybackDebugSnapshotV1()
    private var sequenceNumber: UInt64 = 0
    private var subscribers: [UUID: AsyncStream<PlaybackDebugEvent>.Continuation] = [:]
    private var observers: [UUID: @Sendable (PlaybackDebugEvent) -> Void] = [:]

    public init() {}

    deinit {
        lock.lock()
        let continuations = Array(subscribers.values)
        observers.removeAll()
        subscribers.removeAll()
        lock.unlock()
        continuations.forEach { $0.finish() }
    }

    public func snapshot() -> PlaybackDebugSnapshotV1 {
        lock.lock()
        defer { lock.unlock() }
        var result = currentSnapshot
        result.generatedAt = Date()
        return result
    }

    public func events() -> AsyncStream<PlaybackDebugEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
            lock.lock()
            subscribers[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.removeSubscriber(id)
            }
        }
    }

    @discardableResult
    public func emit(
        mediaSessionID: String? = nil,
        route: PlaybackRoute? = nil,
        node: PlaybackNode? = nil,
        kind: String,
        outcome: NodeOutcome? = nil,
        details: [String: String] = [:]
    ) -> PlaybackDebugEvent {
        lock.lock()
        sequenceNumber += 1
        let event = PlaybackDebugEvent(
            schemaVersion: 1,
            sequenceNumber: sequenceNumber,
            timestamp: Date(),
            mediaSessionID: mediaSessionID,
            route: route,
            node: node,
            kind: kind,
            outcome: outcome,
            details: details
        )
        let continuations = Array(subscribers.values)
        let eventObservers = Array(observers.values)
        lock.unlock()
        for continuation in continuations {
            continuation.yield(event)
        }
        for observer in eventObservers {
            observer(event)
        }
        return event
    }

    func addEventObserver(
        _ observer: @escaping @Sendable (PlaybackDebugEvent) -> Void
    ) -> UUID {
        let id = UUID()
        lock.lock()
        observers[id] = observer
        lock.unlock()
        return id
    }

    func removeEventObserver(_ id: UUID) {
        lock.lock()
        observers.removeValue(forKey: id)
        lock.unlock()
    }

    public func recordSession(_ session: MediaSessionRecord?) {
        lock.lock()
        defer { lock.unlock() }
        if let session {
            currentSnapshot.mediaSession = MediaSessionDebugSummary(session)
            currentSnapshot.lifecycle = session.lifecycle
        } else {
            currentSnapshot.lastMediaSession = currentSnapshot.mediaSession
            currentSnapshot.mediaSession = nil
            currentSnapshot.lifecycle = .idle
        }
    }

    public func recordProviderOpen(_ record: ProviderOpenSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.providerOpen = record
    }

    public func recordOpenRejection(_ record: OpenRejectionRecord) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.lastOpenRejection = record
    }

    public func recordControlRejection(_ record: ControlRejectionRecord) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.lastControlRejection = record
    }

    public func recordFailure(_ record: PlaybackFailureRecord) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.lastFailure = record
        currentSnapshot.lastError = record.message
    }

    public func recordOperation(_ record: PlaybackOperationRecord) {
        lock.lock()
        defer { lock.unlock() }
        if record.state == .running {
            currentSnapshot.currentOperation = record
        } else {
            if currentSnapshot.currentOperation?.operationID == record.operationID {
                currentSnapshot.currentOperation = nil
            }
            currentSnapshot.lastCompletedOperation = record
            if record.kind == .open {
                currentSnapshot.lastOpenOperation = record
            }
            if record.kind == .switchRoute {
                currentSnapshot.lastRouteSwitchOperation = record
            }
        }
    }

    public func recordVideoTrack(_ record: VideoTrackRecord) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.videoTrack = record
    }

    public func recordAudioTrack(_ record: AudioTrackRecord?) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.audioTrack = record
    }

    public func recordAvailableAudioTracks(_ tracks: [PlaybackAudioTrack]) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.availableAudioTracks = tracks
    }

    public func recordRouteEvent(_ record: RouteMediaEventRecord) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.lastRouteEvent = record
        currentSnapshot.streamEpoch = record.streamEpoch
        currentSnapshot.formatRevision = record.formatRevision
    }

    public func recordVideoSample(_ record: VideoSampleRecord) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.lastVideoSample = record
        currentSnapshot.streamEpoch = record.streamEpoch
        currentSnapshot.formatRevision = record.formatRevision
        currentSnapshot.sampleCount += 1
    }

    public func recordAudioSample(_ record: AudioSampleRecord) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.lastAudioSample = record
        currentSnapshot.audioSampleBufferCount += 1
    }

    public func recordRendererInput(_ record: RendererInputRecord) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.lastRendererInput = record
        switch record.outcome {
        case .accepted:
            currentSnapshot.lastAcceptedRendererInput = record
            currentSnapshot.acceptedRendererInputCount += 1
        case .deferredByBackpressure:
            currentSnapshot.backpressureCount += 1
        case .rejectedAsStale:
            currentSnapshot.staleRejectionCount += 1
        case .failed:
            break
        }
    }

    public func recordRendererState(_ record: RendererStateRecord) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.rendererState = record
    }

    public func recordAudioRendererState(_ record: AudioRendererStateRecord?) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.audioRendererState = record
    }

    func recordCleanupStep(_ step: PlaybackCleanupStep) {
        lock.lock()
        defer { lock.unlock() }
        var state = currentSnapshot.cleanupState ?? PlaybackCleanupStateRecord()
        switch step {
        case .videoProviderCancelled:
            state.videoProviderCancelled = true
        case .audioProviderCancelled:
            state.audioProviderCancelled = true
        case .audioRendererFlushed:
            state.audioRendererFlushed = true
        case .videoRendererFlushed:
            state.videoRendererFlushed = true
        }
        currentSnapshot.cleanupState = state
    }

    public func recordRealityKitBinding(_ record: RealityKitBindingRecord?) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.realityKitBinding = record
    }

    public func recordPresentationBinding(_ record: PresentationBindingRecord?) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.presentationBinding = record
    }

    public func recordPresentationState(_ record: PresentationStateRecord?) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.presentationState = record
    }

    public func recordPlatform(
        _ platform: String,
        hardwareDisplayFacts: FactAvailability
    ) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.platform = platform
        currentSnapshot.hardwareDisplayFacts = hardwareDisplayFacts
    }

    public func correlateEvidenceID(_ evidenceID: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !currentSnapshot.evidenceCorrelationIDs.contains(evidenceID) else { return }
        currentSnapshot.evidenceCorrelationIDs.append(evidenceID)
    }

    public func recordError(_ message: String?) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.lastError = message
    }

    public func recordStaleRejection() {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot.staleRejectionCount += 1
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot = PlaybackDebugSnapshotV1()
    }

    private func removeSubscriber(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        subscribers.removeValue(forKey: id)
    }
}
