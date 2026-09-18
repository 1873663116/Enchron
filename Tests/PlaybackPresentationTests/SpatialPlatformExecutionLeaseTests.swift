import Foundation
@testable import Playback
import Testing

@MainActor
private final class ControlledSuspension {
    private var continuation: CheckedContinuation<Void, Never>?

    var isWaiting: Bool {
        continuation != nil
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
@Suite("Spatial platform execution lease")
struct SpatialPlatformExecutionLeaseTests {
    @Test("a stale action finishes before its replacement and runs no further work")
    func staleActionCompletesBeforeReplacementAction() async {
        let lane = SpatialPlatformSerializedActionLane()
        let suspension = ControlledSuspension()
        var requestAIsLive = true
        let cleanupBIsLive = true
        var actions: [String] = []

        let requestA = Task { @MainActor in
            let result: Bool? = await lane.perform(
                isLive: { requestAIsLive },
                operation: {
                    actions.append("A-system-started")
                    await suspension.wait()
                    actions.append("A-system-returned")
                    return true
                }
            )
            if result != nil {
                actions.append("A-post-invalidation")
            }
        }
        while suspension.isWaiting == false {
            await Task.yield()
        }

        requestAIsLive = false
        let cleanupB = Task { @MainActor in
            _ = await lane.perform(
                isLive: { cleanupBIsLive },
                operation: {
                    actions.append("B-open-window")
                    actions.append("B-mixed-immersion")
                    actions.append("B-dismiss-immersive")
                }
            )
        }
        await Task.yield()
        #expect(actions == ["A-system-started"])

        suspension.resume()
        await requestA.value
        await cleanupB.value
        #expect(
            actions == [
                "A-system-started",
                "A-system-returned",
                "B-open-window",
                "B-mixed-immersion",
                "B-dismiss-immersive"
            ]
        )
    }

    @Test("a retried execution reuses the open space instead of opening a second one")
    func capabilityRetrySkipsDuplicateOpen() async {
        let lane = SpatialPlatformSerializedActionLane()
        let suspension = ControlledSuspension()
        var firstExecutionIsLive = true
        let retryExecutionIsLive = true
        var platformResidencyIsOpen = false
        var openCallCount = 0
        var dismissCallCount = 0
        var provenance = SpatialPlatformImmersiveRequestProvenanceRegistry()
        let requestID = UUID()

        let firstExecution = Task { @MainActor in
            _ = await lane.perform(
                isLive: { firstExecutionIsLive },
                operation: {
                    openCallCount += 1
                    await suspension.wait()
                    platformResidencyIsOpen = true
                    provenance.recordOpenedSpace(for: requestID)
                }
            )
        }
        while suspension.isWaiting == false {
            await Task.yield()
        }

        firstExecutionIsLive = false
        let retryExecution = Task { @MainActor in
            _ = await lane.perform(
                isLive: { retryExecutionIsLive },
                operation: {
                    if platformResidencyIsOpen == false {
                        openCallCount += 1
                        platformResidencyIsOpen = true
                        provenance.recordOpenedSpace(for: requestID)
                    }
                }
            )
        }
        suspension.resume()
        await firstExecution.value
        await retryExecution.value

        #expect(platformResidencyIsOpen)
        #expect(openCallCount == 1)
        #expect(
            provenance.provenance(
                for: requestID,
                observingOpenSpace: platformResidencyIsOpen
            ) == .openedByRequest
        )

        _ = await lane.perform(
            isLive: { retryExecutionIsLive },
            operation: {
                dismissCallCount += 1
                platformResidencyIsOpen = false
            }
        )
        #expect(openCallCount == 1)
        #expect(dismissCallCount == 1)
        #expect(platformResidencyIsOpen == false)

        provenance.clear(requestID: requestID)
        #expect(
            provenance.provenance(for: requestID, observingOpenSpace: false) == nil
        )
    }

    @Test("a failed request leaves a space it did not open alone")
    func preexistingSpaceFailureDoesNotDismiss() {
        var provenance = SpatialPlatformImmersiveRequestProvenanceRegistry()
        let preexistingRequestID = UUID()
        var dismissCallCount = 0

        let preexisting = provenance.provenance(
            for: preexistingRequestID,
            observingOpenSpace: true
        )
        if preexisting == .openedByRequest {
            dismissCallCount += 1
        }
        #expect(dismissCallCount == 0)

        provenance.recordOpenedSpace(for: preexistingRequestID)
        provenance.retainOnly(requestID: UUID())
        #expect(
            provenance.provenance(
                for: preexistingRequestID,
                observingOpenSpace: false
            ) == nil
        )

        provenance.clear(requestID: preexistingRequestID)
        #expect(provenance.provenance(for: UUID(), observingOpenSpace: false) == nil)
    }

    @Test("an open confirmed after the baseline reports confirmed")
    func confirmedOpenReportsConfirmed() {
        var observation = SpatialPlatformImmersiveSpaceObservation()
        let baseline = observation.revision
        observation.record(.open)
        #expect(
            observation.openWaitOutcome(after: baseline) == .confirmed
        )
    }

    @Test("a space opened then immediately revoked reports revoked")
    func revokedOpenReportsRevoked() {
        var observation = SpatialPlatformImmersiveSpaceObservation()
        let baseline = observation.revision
        observation.record(.open)
        observation.record(.closed)
        #expect(
            observation.openWaitOutcome(after: baseline) == .revoked
        )
    }

    @Test("a stale closed residency without new observation stays pending")
    func staleClosedStaysPending() {
        var observation = SpatialPlatformImmersiveSpaceObservation()
        observation.record(.closed)
        let baseline = observation.revision
        #expect(
            observation.openWaitOutcome(after: baseline) == .pending
        )
    }

    @Test("no observation after the baseline stays pending")
    func silenceStaysPending() {
        let observation = SpatialPlatformImmersiveSpaceObservation()
        #expect(
            observation.openWaitOutcome(after: observation.revision)
                == .pending
        )
    }
}
