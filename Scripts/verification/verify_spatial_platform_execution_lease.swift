import Foundation

private func require(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else {
        fatalError(message)
    }
}

@main
private enum SpatialPlatformExecutionLeaseChecks {
    static func main() async {
        stopReplacementInvalidatesSuspendedExecution()
        rootReplacementInvalidatesCapturedCapability()
        await staleActionCompletesBeforeReplacementAction()
        await capabilityRetrySkipsDuplicateOpen()
        preexistingSpaceFailureDoesNotDismiss()
        print("Spatial platform execution lease contracts passed")
    }

    private static func stopReplacementInvalidatesSuspendedExecution() {
        var registry = SpatialPlatformExecutionLeaseRegistry<String>()
        let rootID = UUID()
        let requestA = UUID()
        let cleanupB = UUID()
        var actions: [String] = []

        registry.register("root", id: rootID)
        let claimA = registry.claim(requestID: requestA, mediaSessionID: "session")
        require(claimA != nil, "request A must be claimable")
        guard let claimA else { return }

        if registry.isLive(claimA.lease) {
            actions.append("A-before-suspension")
        }
        let invalidated = registry.invalidateActiveExecution()
        require(invalidated == claimA.lease, "stop must invalidate request A")
        if registry.isLive(claimA.lease) {
            actions.append("A-after-invalidation")
        }

        let claimB = registry.claim(requestID: cleanupB, mediaSessionID: nil)
        require(claimB != nil, "cleanup B must drain without waiting for request A")
        guard let claimB else { return }
        if registry.isLive(claimB.lease) {
            actions.append("B")
        }
        require(
            registry.claim(requestID: cleanupB, mediaSessionID: nil) == nil,
            "cleanup B must be claimed exactly once"
        )
        require(
            actions == ["A-before-suspension", "B"],
            "request A performed a platform action after invalidation"
        )
    }

    private static func rootReplacementInvalidatesCapturedCapability() {
        var registry = SpatialPlatformExecutionLeaseRegistry<String>()
        let requestID = UUID()
        let firstRootID = UUID()
        let secondRootID = UUID()

        registry.register("first-root", id: firstRootID)
        let firstClaim = registry.claim(requestID: requestID, mediaSessionID: nil)
        require(firstClaim != nil, "the first root must claim the request")
        guard let firstClaim else { return }

        let invalidated = registry.unregister(id: firstRootID)
        require(
            invalidated == firstClaim.lease,
            "unregister must invalidate the captured capability generation"
        )
        require(
            registry.isLive(firstClaim.lease) == false,
            "a stale completion must not regain liveness"
        )
        require(
            registry.claim(requestID: requestID, mediaSessionID: nil) == nil,
            "the request must remain queued while no capable root exists"
        )

        registry.register("second-root", id: secondRootID)
        let retry = registry.claim(requestID: requestID, mediaSessionID: nil)
        require(retry?.capability == "second-root", "a new root must retry the request")
        require(
            retry?.lease.executionID != firstClaim.lease.executionID,
            "a retried request must use a new execution identity"
        )
        require(
            registry.isLive(firstClaim.lease) == false,
            "the old execution must remain stale after retry"
        )
    }

    @MainActor
    private static func staleActionCompletesBeforeReplacementAction() async {
        let lane = SpatialPlatformSerializedActionLane()
        let suspension = ControlledSuspension()
        var requestAIsLive = true
        var cleanupBIsLive = true
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
        require(
            actions == ["A-system-started"],
            "cleanup B overtook request A's already-issued system action"
        )

        suspension.resume()
        await requestA.value
        await cleanupB.value
        cleanupBIsLive = false
        require(
            actions == [
                "A-system-started",
                "A-system-returned",
                "B-open-window",
                "B-mixed-immersion",
                "B-dismiss-immersive",
            ],
            "the stale action lane ran post-invalidation work or duplicated cleanup B"
        )
    }

    @MainActor
    private static func capabilityRetrySkipsDuplicateOpen() async {
        let lane = SpatialPlatformSerializedActionLane()
        let suspension = ControlledSuspension()
        var firstExecutionIsLive = true
        var retryExecutionIsLive = true
        var platformResidencyIsOpen = false
        var openCallCount = 0
        var dismissCallCount = 0
        var provenance =
            SpatialPlatformImmersiveRequestProvenanceRegistry()
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

        require(
            platformResidencyIsOpen && openCallCount == 1,
            "a retried execution issued a duplicate immersive open"
        )
        require(
            provenance.provenance(
                for: requestID,
                observingOpenSpace: platformResidencyIsOpen
            ) == .openedByRequest,
            "retry lost request-level immersive-space provenance"
        )
        _ = await lane.perform(
            isLive: { retryExecutionIsLive },
            operation: {
                dismissCallCount += 1
                platformResidencyIsOpen = false
            }
        )
        retryExecutionIsLive = false
        require(
            openCallCount == 1
                && dismissCallCount == 1
                && platformResidencyIsOpen == false,
            "retry failure did not normalize the request-opened space exactly once"
        )
        provenance.clear(requestID: requestID)
        require(
            provenance.provenance(
                for: requestID,
                observingOpenSpace: false
            ) == nil,
            "settled request provenance was not cleared"
        )
    }

    private static func preexistingSpaceFailureDoesNotDismiss() {
        var provenance =
            SpatialPlatformImmersiveRequestProvenanceRegistry()
        let preexistingRequestID = UUID()
        var dismissCallCount = 0
        let preexistingProvenance = provenance.provenance(
            for: preexistingRequestID,
            observingOpenSpace: true
        )
        if preexistingProvenance == .openedByRequest {
            dismissCallCount += 1
        }
        require(
            dismissCallCount == 0,
            "a failed request dismissed a genuinely pre-existing immersive space"
        )

        provenance.recordOpenedSpace(for: preexistingRequestID)
        let replacementRequestID = UUID()
        provenance.retainOnly(requestID: replacementRequestID)
        require(
            provenance.provenance(
                for: preexistingRequestID,
                observingOpenSpace: false
            ) == nil,
            "replaced request provenance survived into a new request"
        )
        provenance.clear(requestID: preexistingRequestID)
        require(
            provenance.provenance(
                for: UUID(),
                observingOpenSpace: false
            ) == nil,
            "request provenance leaked to a new product request"
        )
    }
}

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
