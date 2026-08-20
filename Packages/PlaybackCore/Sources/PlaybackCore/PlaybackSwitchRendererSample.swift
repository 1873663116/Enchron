#if DEBUG
import Foundation

struct PlaybackSwitchRendererGraphIdentity: Sendable {
    var renderer: UInt64
    var departingRenderer: UInt64?
    var revision: UInt64
}

public enum PlaybackSwitchSampleTrigger: String, Codable, Equatable, Sendable {
    case periodic
    case graphChanged
    case lifecycleChanged
    case firstInputAccepted
}

public struct PlaybackSwitchRendererSample: Codable, Equatable, Sendable {
    public var monotonicNanoseconds: UInt64
    public var trigger: PlaybackSwitchSampleTrigger
    public var technicalSessionID: String
    public var rendererIdentity: UInt64
    public var departingRendererIdentity: UInt64?
    public var graphRevision: UInt64
    public var lifecycle: PlaybackLifecycle
    public var acceptedInputCount: UInt64
    public var displayedFrameObservationCount: UInt64
    public var requestedRate: Float
    public var actualTimebaseRate: Float
    public var effectiveTimebaseRate: Float
    public var streamEpoch: UInt64
    public var flushCount: UInt64

    public init(
        monotonicNanoseconds: UInt64,
        trigger: PlaybackSwitchSampleTrigger,
        technicalSessionID: String,
        rendererIdentity: UInt64,
        graphRevision: UInt64,
        lifecycle: PlaybackLifecycle,
        acceptedInputCount: UInt64,
        displayedFrameObservationCount: UInt64,
        requestedRate: Float,
        actualTimebaseRate: Float,
        effectiveTimebaseRate: Float,
        streamEpoch: UInt64,
        flushCount: UInt64,
        departingRendererIdentity: UInt64? = nil
    ) {
        self.monotonicNanoseconds = monotonicNanoseconds
        self.trigger = trigger
        self.technicalSessionID = technicalSessionID
        self.rendererIdentity = rendererIdentity
        self.departingRendererIdentity = departingRendererIdentity
        self.graphRevision = graphRevision
        self.lifecycle = lifecycle
        self.acceptedInputCount = acceptedInputCount
        self.displayedFrameObservationCount = displayedFrameObservationCount
        self.requestedRate = requestedRate
        self.actualTimebaseRate = actualTimebaseRate
        self.effectiveTimebaseRate = effectiveTimebaseRate
        self.streamEpoch = streamEpoch
        self.flushCount = flushCount
    }
}

public protocol PlaybackSwitchRendererSampleSink: AnyObject, Sendable {
    func recordPlaybackSwitchRendererSample(_ sample: PlaybackSwitchRendererSample)
}
#endif
