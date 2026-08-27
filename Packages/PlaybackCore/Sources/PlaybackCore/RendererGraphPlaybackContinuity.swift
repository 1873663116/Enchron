import Foundation

public struct RendererGraphPlaybackObservation: Codable, Equatable, Sendable {
    public var graphRevision: UInt64
    public var acceptedInputCount: UInt64
    public var actualTimebaseRate: Float
    public var displayedFrameObservationCount: UInt64

    public init(
        graphRevision: UInt64,
        acceptedInputCount: UInt64,
        actualTimebaseRate: Float,
        displayedFrameObservationCount: UInt64
    ) {
        self.graphRevision = graphRevision
        self.acceptedInputCount = acceptedInputCount
        self.actualTimebaseRate = actualTimebaseRate
        self.displayedFrameObservationCount = displayedFrameObservationCount
    }
}

public enum RendererGraphPlaybackContinuity: String, Codable, Equatable, Sendable {
    case ready
    case wrongGraphRevision
    case awaitingAcceptedSample
    case awaitingActualTimebaseRate
    case awaitingDisplayedFrameAdvance

    public var explicitPlayMayContinue: Bool {
        switch self {
        case .ready, .awaitingDisplayedFrameAdvance:
            true
        case .wrongGraphRevision, .awaitingAcceptedSample,
                .awaitingActualTimebaseRate:
            false
        }
    }

    public static func evaluate(
        baseline: RendererGraphPlaybackObservation,
        current: RendererGraphPlaybackObservation,
        requiredGraphRevision: UInt64,
        requiredDisplayedFrameAdvances: UInt64 = 2
    ) -> Self {
        guard baseline.graphRevision == requiredGraphRevision,
              current.graphRevision == requiredGraphRevision else {
            return .wrongGraphRevision
        }
        guard current.acceptedInputCount > baseline.acceptedInputCount else {
            return .awaitingAcceptedSample
        }
        guard current.actualTimebaseRate > 0 else {
            return .awaitingActualTimebaseRate
        }
        guard current.displayedFrameObservationCount >= baseline.displayedFrameObservationCount
                + requiredDisplayedFrameAdvances else {
            return .awaitingDisplayedFrameAdvance
        }
        return .ready
    }
}
