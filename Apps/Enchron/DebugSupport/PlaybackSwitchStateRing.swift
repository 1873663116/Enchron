#if DEBUG
import Foundation
import PlaybackCore
import Playback

nonisolated struct PlaybackSwitchTraceContext: Codable, Equatable, Sendable {
    var logicalSessionID: String
    var settledPresentation: PlaybackPresentation
    var targetPresentation: PlaybackPresentation?
}

nonisolated struct PlaybackSwitchByteStreamCounters: Codable, Equatable, Sendable {
    var scope: UInt64
    var acceptedConnectionCount: UInt64
    var requestCount: UInt64
}

nonisolated enum PlaybackSwitchKind: String, Codable, Equatable, Sendable {
    case presentation
    case format
}

nonisolated enum PlaybackSwitchStateRecordEvent: String, Codable, Equatable, Sendable {
    case rendererSample
    case presentationChanged
    case formatChanged
}

nonisolated struct PlaybackSwitchStateRecord: Codable, Equatable, Sendable {
    var sequence: UInt64
    var monotonicNanoseconds: UInt64
    var event: PlaybackSwitchStateRecordEvent
    var sampleTrigger: PlaybackSwitchSampleTrigger
    var switchID: UInt64?
    var switchKind: PlaybackSwitchKind?
    var logicalSessionID: String
    var settledPresentation: PlaybackPresentation
    var targetPresentation: PlaybackPresentation?
    var technicalSessionID: String
    var rendererIdentity: UInt64
    var departingRendererIdentity: UInt64?
    var graphRevision: UInt64
    var lifecycle: PlaybackLifecycle
    var acceptedInputCount: UInt64
    var displayedFrameObservationCount: UInt64
    var requestedRate: Float
    var actualTimebaseRate: Float
    var effectiveTimebaseRate: Float
    var streamEpoch: UInt64
    var flushCount: UInt64
    var byteStreamCounters: PlaybackSwitchByteStreamCounters?
}

nonisolated struct PlaybackSwitchStateSnapshot: Codable, Equatable, Sendable {
    var capacity: Int
    var generation: UInt64
    var isArmed: Bool
    var overwrittenRecordCount: UInt64
    var records: [PlaybackSwitchStateRecord]
}

nonisolated final class PlaybackSwitchStateRing: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var storage: [PlaybackSwitchStateRecord?]
    private var writeIndex = 0
    private var count = 0
    private var generation: UInt64 = 0
    private var armed = false
    private var overwrittenRecordCount: UInt64 = 0
    private var nextSequence: UInt64 = 0
    private var nextSwitchID: UInt64 = 0
    private var context: PlaybackSwitchTraceContext?
    private var byteStreamCounters: PlaybackSwitchByteStreamCounters?
    private var lastRendererSample: PlaybackSwitchRendererSample?
    private var activeSwitchID: UInt64?
    private var activeSwitchKind: PlaybackSwitchKind?

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    @discardableResult
    func arm(
        context: PlaybackSwitchTraceContext,
        byteStreamCounters: PlaybackSwitchByteStreamCounters? = nil
    ) -> UInt64 {
        lock.withLock {
            generation &+= 1
            armed = true
            storage = Array(repeating: nil, count: capacity)
            writeIndex = 0
            count = 0
            overwrittenRecordCount = 0
            nextSequence = 0
            nextSwitchID = 0
            self.context = context
            self.byteStreamCounters = byteStreamCounters
            lastRendererSample = nil
            activeSwitchID = nil
            activeSwitchKind = nil
            return generation
        }
    }

    @discardableResult
    func disarm(generation expectedGeneration: UInt64) -> Bool {
        lock.withLock {
            guard armed, generation == expectedGeneration else { return false }
            armed = false
            return true
        }
    }

    func record(_ sample: PlaybackSwitchRendererSample) {
        record(sample, byteStreamCounters: nil)
    }

    func record(
        _ sample: PlaybackSwitchRendererSample,
        byteStreamCounters: PlaybackSwitchByteStreamCounters?
    ) {
        lock.withLock {
            guard armed, let context else { return }
            if let byteStreamCounters {
                self.byteStreamCounters = byteStreamCounters
            }
            lastRendererSample = sample
            append(record(
                event: .rendererSample,
                sample: sample,
                context: context
            ))
        }
    }

    func updateByteStreamCounters(_ counters: PlaybackSwitchByteStreamCounters) {
        lock.withLock {
            guard armed else { return }
            byteStreamCounters = counters
        }
    }

    func settlePresentation(_ presentation: PlaybackPresentation) {
        lock.withLock {
            guard armed, var context else { return }
            context.settledPresentation = presentation
            context.targetPresentation = nil
            self.context = context
            activeSwitchID = nil
            activeSwitchKind = nil
        }
    }

    @discardableResult
    func beginSwitch(
        kind: PlaybackSwitchKind,
        targetPresentation: PlaybackPresentation?,
        at monotonicNanoseconds: UInt64
    ) -> UInt64? {
        lock.withLock {
            guard armed, var context, let lastRendererSample else { return nil }
            nextSwitchID &+= 1
            activeSwitchID = nextSwitchID
            activeSwitchKind = kind
            context.targetPresentation = targetPresentation
            self.context = context
            var markerSample = lastRendererSample
            markerSample.monotonicNanoseconds = monotonicNanoseconds
            append(record(
                event: kind == .presentation ? .presentationChanged : .formatChanged,
                sample: markerSample,
                context: context
            ))
            return nextSwitchID
        }
    }

    func snapshot() -> PlaybackSwitchStateSnapshot {
        lock.withLock {
            let start = count == capacity ? writeIndex : 0
            let records = (0..<count).compactMap { offset in
                storage[(start + offset) % capacity]
            }
            return PlaybackSwitchStateSnapshot(
                capacity: capacity,
                generation: generation,
                isArmed: armed,
                overwrittenRecordCount: overwrittenRecordCount,
                records: records
            )
        }
    }

    private func record(
        event: PlaybackSwitchStateRecordEvent,
        sample: PlaybackSwitchRendererSample,
        context: PlaybackSwitchTraceContext
    ) -> PlaybackSwitchStateRecord {
        let record = PlaybackSwitchStateRecord(
            sequence: nextSequence,
            monotonicNanoseconds: sample.monotonicNanoseconds,
            event: event,
            sampleTrigger: sample.trigger,
            switchID: activeSwitchID,
            switchKind: activeSwitchKind,
            logicalSessionID: context.logicalSessionID,
            settledPresentation: context.settledPresentation,
            targetPresentation: context.targetPresentation,
            technicalSessionID: sample.technicalSessionID,
            rendererIdentity: sample.rendererIdentity,
            departingRendererIdentity: sample.departingRendererIdentity,
            graphRevision: sample.graphRevision,
            lifecycle: sample.lifecycle,
            acceptedInputCount: sample.acceptedInputCount,
            displayedFrameObservationCount: sample.displayedFrameObservationCount,
            requestedRate: sample.requestedRate,
            actualTimebaseRate: sample.actualTimebaseRate,
            effectiveTimebaseRate: sample.effectiveTimebaseRate,
            streamEpoch: sample.streamEpoch,
            flushCount: sample.flushCount,
            byteStreamCounters: byteStreamCounters
        )
        nextSequence &+= 1
        return record
    }

    private func append(_ record: PlaybackSwitchStateRecord) {
        storage[writeIndex] = record
        writeIndex = (writeIndex + 1) % capacity
        if count < capacity {
            count += 1
        } else {
            overwrittenRecordCount &+= 1
        }
    }
}

nonisolated struct PlaybackSwitchDerivedMetrics: Codable, Equatable, Sendable {
    var switchID: UInt64
    var switchDurationNanoseconds: UInt64?
    var longestDisplayProgressStallNanoseconds: UInt64?
    var timebaseRateReachedZero: Bool
    var timebaseRateZeroDurationNanoseconds: UInt64
    var graphChangeCount: Int
    var byteStreamAcceptedConnectionDelta: UInt64?
    var byteStreamRequestDelta: UInt64?
    var isLeftCensored: Bool
    var isRightCensored: Bool
}

nonisolated struct PlaybackSwitchStateAnalysis: Codable, Equatable, Sendable {
    var switches: [PlaybackSwitchDerivedMetrics]

    static func derive(from snapshot: PlaybackSwitchStateSnapshot) -> Self {
        let markers = snapshot.records.indices.filter {
            snapshot.records[$0].event != .rendererSample
        }
        return Self(switches: markers.compactMap { markerIndex in
            deriveSwitch(from: snapshot, markerIndex: markerIndex)
        })
    }

    private struct GraphKey: Hashable {
        var technicalSessionID: String
        var rendererIdentity: UInt64
        var graphRevision: UInt64
    }

    private static func deriveSwitch(
        from snapshot: PlaybackSwitchStateSnapshot,
        markerIndex: Int
    ) -> PlaybackSwitchDerivedMetrics? {
        let marker = snapshot.records[markerIndex]
        guard let switchID = marker.switchID else { return nil }
        let records = Array(snapshot.records[markerIndex...])
        let baselineGraph = graphKey(marker)
        let endIndex = records.indices.dropFirst().first {
            graphKey(records[$0]) != baselineGraph
                && records[$0].displayedFrameObservationCount > 0
        }
        let analyzedRecords = endIndex.map { Array(records[...$0]) } ?? records

        var seenGraphs: Set<GraphKey> = [baselineGraph]
        var lastDisplayedByGraph: [GraphKey: UInt64] = [
            baselineGraph: marker.displayedFrameObservationCount
        ]
        var lastDisplayProgressAt = marker.monotonicNanoseconds
        var longestStall: UInt64 = 0
        var zeroDuration: UInt64 = 0

        for index in analyzedRecords.indices.dropFirst() {
            let previous = analyzedRecords[index - 1]
            let current = analyzedRecords[index]
            if previous.lifecycle == .playing,
               previous.requestedRate > 0,
               previous.actualTimebaseRate == 0 {
                zeroDuration &+= current.monotonicNanoseconds - previous.monotonicNanoseconds
            }

            let currentGraph = graphKey(current)
            seenGraphs.insert(currentGraph)
            let priorDisplayCount = lastDisplayedByGraph[currentGraph]
            let displayAdvanced = priorDisplayCount.map {
                current.displayedFrameObservationCount > $0
            } ?? (current.displayedFrameObservationCount > 0)
            if displayAdvanced {
                longestStall = max(
                    longestStall,
                    current.monotonicNanoseconds - lastDisplayProgressAt
                )
                lastDisplayProgressAt = current.monotonicNanoseconds
            }
            lastDisplayedByGraph[currentGraph] = current.displayedFrameObservationCount
        }
        if let last = analyzedRecords.last {
            longestStall = max(
                longestStall,
                last.monotonicNanoseconds - lastDisplayProgressAt
            )
        }

        let firstCounters = analyzedRecords.first?.byteStreamCounters
        let lastCounters = analyzedRecords.last?.byteStreamCounters
        let counterDelta: (UInt64?, UInt64?) = {
            guard let firstCounters, let lastCounters,
                  firstCounters.scope == lastCounters.scope,
                  lastCounters.acceptedConnectionCount >= firstCounters.acceptedConnectionCount,
                  lastCounters.requestCount >= firstCounters.requestCount else {
                return (nil, nil)
            }
            return (
                lastCounters.acceptedConnectionCount - firstCounters.acceptedConnectionCount,
                lastCounters.requestCount - firstCounters.requestCount
            )
        }()
        let endRecord = endIndex.map { records[$0] }
        return PlaybackSwitchDerivedMetrics(
            switchID: switchID,
            switchDurationNanoseconds: endRecord.map {
                $0.monotonicNanoseconds - marker.monotonicNanoseconds
            },
            longestDisplayProgressStallNanoseconds: analyzedRecords.isEmpty ? nil : longestStall,
            timebaseRateReachedZero: zeroDuration > 0,
            timebaseRateZeroDurationNanoseconds: zeroDuration,
            graphChangeCount: max(0, seenGraphs.count - 1),
            byteStreamAcceptedConnectionDelta: counterDelta.0,
            byteStreamRequestDelta: counterDelta.1,
            isLeftCensored: snapshot.overwrittenRecordCount > 0,
            isRightCensored: endRecord == nil
        )
    }

    private static func graphKey(_ record: PlaybackSwitchStateRecord) -> GraphKey {
        GraphKey(
            technicalSessionID: record.technicalSessionID,
            rendererIdentity: record.rendererIdentity,
            graphRevision: record.graphRevision
        )
    }
}
#endif
