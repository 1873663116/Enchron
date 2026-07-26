import Foundation
import PlaybackPresentation
import PlaybackFeature
import Testing
@testable import Enchron

@Suite("Playback presentation")
struct PlaybackPresentationStateTests {
    #if os(visionOS)
    @Test("ended and replaced sessions invalidate the previous Media Session")
    @MainActor
    func lifecycleEventsShareTheProductionInvalidationPath() {
        #expect(
            SpatialPlatformEffectCoordinator.invalidatedMediaSessionID(
                for: .ended(id: "session-a")
            ) == "session-a"
        )
        #expect(
            SpatialPlatformEffectCoordinator.invalidatedMediaSessionID(
                for: .replaced(previousID: "session-a", currentID: "session-b")
            ) == "session-a"
        )
        #expect(
            SpatialPlatformEffectCoordinator.invalidatedMediaSessionID(
                for: .activated(id: "session-b")
            ) == nil
        )
    }

    @Test("stop invalidates an in-flight execution and cleanup executes once")
    @MainActor
    func stopReplacesInFlightExecution() throws {
        let model = PlaybackPresentationModel()
        var registry = SpatialPlatformExecutionLeaseRegistry<String>()
        let rootID = UUID()
        var actions: [String] = []

        registry.register("root", id: rootID)
        _ = try model.requestPresentation(
            .panorama,
            playbackContext: playingContext()
        )
        let requestA = try #require(model.pendingSpatialPlatformEffect)
        let claimAValue = registry.claim(
            requestID: requestA.id,
            mediaSessionID: requestA.playbackTransportPlan?.mediaSessionID
        )
        let claimA = try #require(claimAValue)
        #expect(
            model.claimSpatialPlatformEffect(
                requestA.id,
                executionID: claimA.lease.executionID
            )
        )
        if registry.isLive(claimA.lease),
           model.isSpatialPlatformEffectCurrent(
            requestA.id,
            executionID: claimA.lease.executionID
           ) {
            actions.append("A-before-suspension")
        }

        model.requestStoppedPlaybackCleanup()
        _ = registry.invalidateActiveExecution()
        let requestB = try #require(model.pendingSpatialPlatformEffect)
        #expect(requestB.id != requestA.id)
        #expect(!registry.isLive(claimA.lease))
        #expect(
            !model.isSpatialPlatformEffectCurrent(
                requestA.id,
                executionID: claimA.lease.executionID
            )
        )
        if registry.isLive(claimA.lease) {
            actions.append("A-after-invalidation")
        }

        let claimBValue = registry.claim(requestID: requestB.id, mediaSessionID: nil)
        let claimB = try #require(claimBValue)
        #expect(
            model.claimSpatialPlatformEffect(
                requestB.id,
                executionID: claimB.lease.executionID
            )
        )
        #expect(
            !model.claimSpatialPlatformEffect(
                requestB.id,
                executionID: UUID()
            )
        )
        actions.append("B")
        #expect(
            model.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: requestA.id,
                        executionID: claimA.lease.executionID,
                        mediaSessionID:
                            requestA.playbackTransportPlan?.mediaSessionID,
                        outcome: .succeeded
                    )
                )
            ) == .ignored
        )
        #expect(
            model.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: requestB.id,
                        executionID: claimB.lease.executionID,
                        outcome: .succeeded
                    )
                )
            ) == .effectCompleted
        )
        #expect(actions == ["A-before-suspension", "B"])
    }

    @Test("root replacement invalidates captured actions and retries the current request")
    @MainActor
    func rootReplacementRetriesCurrentRequest() throws {
        let model = PlaybackPresentationModel()
        var registry = SpatialPlatformExecutionLeaseRegistry<String>()
        let firstRootID = UUID()
        let secondRootID = UUID()

        try model.requestEnvironmentPreview(
            environment: .enchron,
            effect: .day
        )
        let request = try #require(model.pendingSpatialPlatformEffect)
        registry.register("first-root", id: firstRootID)
        let firstClaimValue = registry.claim(requestID: request.id, mediaSessionID: nil)
        let firstClaim = try #require(firstClaimValue)
        #expect(
            model.claimSpatialPlatformEffect(
                request.id,
                executionID: firstClaim.lease.executionID
            )
        )

        let invalidatedValue = registry.unregister(id: firstRootID)
        let invalidated = try #require(invalidatedValue)
        #expect(invalidated == firstClaim.lease)
        #expect(!registry.isLive(firstClaim.lease))
        #expect(
            model.receiveSpatialPlatformResult(
                .effectExecutionAbandoned(
                    requestID: request.id,
                    executionID: firstClaim.lease.executionID
                )
            ) == .platformFactRecorded
        )
        #expect(model.pendingSpatialPlatformEffect?.id == request.id)

        registry.register("second-root", id: secondRootID)
        let secondClaimValue = registry.claim(requestID: request.id, mediaSessionID: nil)
        let secondClaim = try #require(secondClaimValue)
        #expect(secondClaim.capability == "second-root")
        #expect(
            model.claimSpatialPlatformEffect(
                request.id,
                executionID: secondClaim.lease.executionID
            )
        )
        #expect(
            model.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: request.id,
                        executionID: firstClaim.lease.executionID,
                        outcome: .succeeded
                    )
                )
            ) == .ignored
        )
        #expect(model.pendingSpatialPlatformEffect?.id == request.id)
        #expect(
            model.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: request.id,
                        executionID: secondClaim.lease.executionID,
                        outcome: .succeeded
                    )
                )
            ) == .effectCompleted
        )
    }
    #endif

    @Test("ended transport exposes Replay and disables forward movement")
    func endedTransportContract() {
        let transport = PlaybackTransportAvailability(lifecycle: .ended)

        #expect(transport.primaryAction == .replay)
        #expect(!transport.canSkipForward)
        #expect(!transport.canStepForward)
        #expect(PlaybackEndPolicy.action(for: .stop) == .stayEnded)
    }

    @Test("direct dock uses the active environment")
    @MainActor
    func directDockUsesActiveEnvironment() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.enchron, effect: .night)

        _ = try model.requestPresentation(.docked, playbackContext: playingContext())
        let request = try #require(model.pendingSpatialPlatformEffect)
        let resolution = try completePendingEffect(model)

        #expect(resolution == .presentationCommitted(.docked))
        #expect(model.snapshot.presentation == .docked)
        #expect(
            model.snapshot.environmentContext == .active(
                environment: .enchron,
                effect: .night
            )
        )
        #expect(
            model.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: request.id,
                        executionID: UUID(),
                        mediaSessionID: request.playbackTransportPlan?.mediaSessionID,
                        outcome: .succeeded
                    )
                )
            ) == .ignored
        )
    }

    @Test("direct dock opens the default environment when none is active")
    @MainActor
    func directDockUsesDefaultEnvironment() throws {
        let model = PlaybackPresentationModel()

        _ = try model.requestPresentation(
            .docked,
            effect: .night,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

        #expect(model.presentation == .docked)
        #expect(
            model.environmentContext == .active(
                environment: .enchron,
                effect: .night
            )
        )
    }

    @Test("undock restores the active environment that preceded Docked")
    @MainActor
    func undockKeepsEnvironment() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.enchron, effect: .night)
        _ = try model.requestPresentation(.docked, playbackContext: playingContext())
        _ = try completePendingEffect(model)

        _ = try model.requestPresentation(.window, playbackContext: playingContext())
        _ = try completePendingEffect(model)

        #expect(model.presentation == .window)
        #expect(
            model.environmentContext == .active(
                environment: .enchron,
                effect: .night
            )
        )
    }

    @Test("temporary Default Environment closes when Docked returns to Window")
    @MainActor
    func undockClosesTemporaryDefaultEnvironment() throws {
        let model = PlaybackPresentationModel()
        _ = try model.requestPresentation(
            .docked,
            effect: .night,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

        _ = try model.requestPresentation(.window, playbackContext: playingContext())
        #expect(
            model.pendingSpatialPlatformEffect?.effect
                == .presentWindowPlayback(
                    keepsEnvironmentOpen: false,
                    immersiveSpaceAlreadyClosed: false
                )
        )
        _ = try completePendingEffect(model)

        #expect(model.presentation == .window)
        #expect(model.environmentContext == .none)
    }

    @Test("failed Docked transitions do not leak or discard the pre-Docked context")
    @MainActor
    func failedDockedTransitionsPreserveContext() throws {
        let inactiveModel = PlaybackPresentationModel()
        _ = try inactiveModel.requestPresentation(
            .docked,
            effect: .night,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(
            inactiveModel,
            outcome: .failed(.playbackPauseFailed)
        )
        #expect(inactiveModel.presentation == .window)
        #expect(inactiveModel.environmentContext == .none)

        let activeModel = PlaybackPresentationModel()
        try activeModel.activateEnvironment(.enchron, effect: .night)
        _ = try activeModel.requestPresentation(
            .docked,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(activeModel)
        _ = try activeModel.requestPresentation(
            .window,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(
            activeModel,
            outcome: .failed(.windowPlaybackSurfaceUnavailable)
        )
        #expect(activeModel.presentation == .docked)
        #expect(
            activeModel.environmentContext == .active(
                environment: .enchron,
                effect: .night
            )
        )

        _ = try activeModel.requestPresentation(
            .window,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(activeModel)
        #expect(
            activeModel.environmentContext == .active(
                environment: .enchron,
                effect: .night
            )
        )
    }

    @Test("panorama rollback restores window and its environment context")
    @MainActor
    func panoramaRollbackRestoresPreviousState() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.enchron, effect: .night)

        _ = try model.requestPresentation(.panorama, playbackContext: playingContext())
        let resolution = try completePendingEffect(
            model,
            outcome: .failed(.spatialPlaybackSurfaceUnavailable)
        )

        #expect(
            resolution == .presentationRolledBack(
                .spatialPlaybackSurfaceUnavailable
            )
        )
        #expect(model.presentation == .window)
        #expect(
            model.environmentContext == .active(
                environment: .enchron,
                effect: .night
            )
        )
        #expect(model.transition == nil)
    }

    @Test("a transition rejects a second product command")
    @MainActor
    func transitionRejectsSecondCommand() throws {
        let model = PlaybackPresentationModel()
        _ = try model.requestPresentation(.panorama, playbackContext: playingContext())
        let request = try #require(model.pendingSpatialPlatformEffect)
        #expect(
            model.claimSpatialPlatformEffect(
                request.id,
                executionID: UUID()
            )
        )

        #expect(throws: PlaybackPresentationTransitionError.transitionInFlight) {
            try model.requestPresentation(.docked, playbackContext: playingContext())
        }
    }

    @Test("docked and panorama cannot transition directly")
    @MainActor
    func spatialPresentationsReturnThroughWindow() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.enchron, effect: .day)
        _ = try model.requestPresentation(.docked, playbackContext: playingContext())
        _ = try completePendingEffect(model)

        #expect(throws: PlaybackPresentationTransitionError.directSpatialTransitionNotSupported) {
            try model.requestPresentation(.panorama, playbackContext: playingContext())
        }
    }

    @Test("stopping playback restores window while retaining the chosen environment")
    @MainActor
    func playbackStopRestoresWindow() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.enchron, effect: .night)
        _ = try model.requestPresentation(.docked, playbackContext: playingContext())
        _ = try completePendingEffect(model)

        model.requestStoppedPlaybackCleanup()
        #expect(
            model.pendingSpatialPlatformEffect?.effect
                == .normalizeStoppedSpatialPlayback(keepsEnvironmentOpen: true)
        )
        _ = try completePendingEffect(model)

        #expect(model.presentation == .window)
        #expect(
            model.environmentContext == .active(
                environment: .enchron,
                effect: .night
            )
        )
        #expect(model.transition == nil)
    }

    @Test("stopping Docked playback closes a temporary Default Environment")
    @MainActor
    func playbackStopClosesTemporaryDefaultEnvironment() throws {
        let model = PlaybackPresentationModel()
        _ = try model.requestPresentation(
            .docked,
            effect: .night,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

        model.requestStoppedPlaybackCleanup()
        #expect(
            model.pendingSpatialPlatformEffect?.effect
                == .normalizeStoppedSpatialPlayback(keepsEnvironmentOpen: false)
        )
        _ = try completePendingEffect(model)

        #expect(model.presentation == .window)
        #expect(model.environmentContext == .none)
    }

    @Test("stopping playback cancels an in-flight presentation transition")
    @MainActor
    func playbackStopCancelsTransition() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.enchron, effect: .night)
        _ = try model.requestPresentation(.docked, playbackContext: playingContext())
        let staleRequest = try #require(model.pendingSpatialPlatformEffect)

        model.requestStoppedPlaybackCleanup()
        let cleanupRequest = try #require(model.pendingSpatialPlatformEffect)

        #expect(model.presentation == .window)
        #expect(
            model.environmentContext == .active(
                environment: .enchron,
                effect: .night
            )
        )
        #expect(model.transition == nil)
        #expect(cleanupRequest.id != staleRequest.id)
        #expect(
            model.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: staleRequest.id,
                        executionID: UUID(),
                        mediaSessionID: staleRequest.playbackTransportPlan?.mediaSessionID,
                        outcome: .succeeded
                    )
                )
            ) == .ignored
        )
        _ = try completePendingEffect(model)
    }

    @Test("the active environment cannot be removed while docked")
    @MainActor
    func dockedPresentationRequiresEnvironment() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.enchron, effect: .night)
        _ = try model.requestPresentation(.docked, playbackContext: playingContext())
        _ = try completePendingEffect(model)

        #expect(throws: PlaybackPresentationTransitionError.dockedPresentationRequiresEnvironment) {
            try model.deactivateEnvironment()
        }
        #expect(
            model.environmentContext == .active(
                environment: .enchron,
                effect: .night
            )
        )
    }

    @Test("a late result cannot replace a newer pending effect")
    @MainActor
    func lateResultIsIgnored() throws {
        let model = PlaybackPresentationModel()
        _ = try model.requestPresentation(.panorama, playbackContext: playingContext())
        let staleRequest = try #require(model.pendingSpatialPlatformEffect)
        _ = try completePendingEffect(
            model,
            outcome: .failed(.spatialPlaybackSurfaceUnavailable)
        )

        _ = try model.requestPresentation(
            .docked,
            effect: .day,
            playbackContext: playingContext(mediaSessionID: "new-session")
        )
        let currentRequest = try #require(model.pendingSpatialPlatformEffect)

        #expect(
            model.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: staleRequest.id,
                        executionID: UUID(),
                        mediaSessionID: staleRequest.playbackTransportPlan?.mediaSessionID,
                        outcome: .succeeded
                    )
                )
            ) == .ignored
        )
        #expect(model.pendingSpatialPlatformEffect?.id == currentRequest.id)
        #expect(model.presentation == .window)
    }

    @Test("Media Session invalidation normalizes issued spatial effects before new work")
    @MainActor
    func mediaSessionInvalidationQueuesNormalization() throws {
        let model = PlaybackPresentationModel()
        _ = try model.requestPresentation(
            .panorama,
            playbackContext: playingContext(mediaSessionID: "session-a")
        )
        let requestA = try #require(model.pendingSpatialPlatformEffect)
        let executionA = UUID()
        #expect(
            model.claimSpatialPlatformEffect(
                requestA.id,
                executionID: executionA
            )
        )

        #expect(
            model.receiveSpatialPlatformResult(
                .mediaSessionInvalidated(
                    requestID: requestA.id,
                    executionID: executionA,
                    requiresPlatformNormalization: true
                )
            ) == .presentationRolledBack(.mediaSessionChanged)
        )
        let cleanup = try #require(model.pendingSpatialPlatformEffect)
        #expect(model.presentation == .window)
        #expect(
            cleanup.effect
                == .normalizeInvalidatedSpatialPlayback(
                    keepsEnvironmentOpen: false
                )
        )
        #expect(cleanup.playbackTransportPlan == nil)
        #expect(
            model.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: requestA.id,
                        executionID: executionA,
                        mediaSessionID: "session-a",
                        outcome: .succeeded
                    )
                )
            ) == .ignored
        )
        #expect(try completePendingEffect(model) == .effectCompleted)
        #expect(model.pendingSpatialPlatformEffect == nil)
    }

    @Test("Media Session invalidation without issued platform effects needs no cleanup")
    @MainActor
    func mediaSessionInvalidationBeforePlatformEffects() throws {
        let model = PlaybackPresentationModel()
        _ = try model.requestPresentation(
            .panorama,
            playbackContext: playingContext(mediaSessionID: "session-a")
        )
        let request = try #require(model.pendingSpatialPlatformEffect)
        let executionID = UUID()
        #expect(
            model.claimSpatialPlatformEffect(
                request.id,
                executionID: executionID
            )
        )

        #expect(
            model.receiveSpatialPlatformResult(
                .mediaSessionInvalidated(
                    requestID: request.id,
                    executionID: executionID,
                    requiresPlatformNormalization: false
                )
            ) == .presentationRolledBack(.mediaSessionChanged)
        )
        #expect(model.presentation == .window)
        #expect(model.pendingSpatialPlatformEffect == nil)
    }

    @Test("unexpected Docked and Panorama disappearance requests same-session recovery")
    @MainActor
    func unexpectedSpatialDisappearanceRequestsRecovery() throws {
        for presentation in [PlaybackPresentation.docked, .panorama] {
            let model = PlaybackPresentationModel()
            let context = playingContext(mediaSessionID: "\(presentation.rawValue)-session")
            _ = try model.requestPresentation(
                presentation,
                effect: presentation == .docked ? .day : nil,
                playbackContext: context
            )
            _ = try completePendingEffect(model)

            #expect(
                model.receiveSpatialPlatformResult(
                    .immersiveSpaceDisappeared(context)
                ) == .spatialRecoveryRequested(presentation)
            )
            let request = try #require(model.pendingSpatialPlatformEffect)
            #expect(request.effect == .recoverSpatialPlayback(presentation))
            #expect(model.recoveryIntent?.presentation == presentation)
            #expect(model.recoveryIntent?.mediaSessionID == context.mediaSessionID)
            #expect(model.recoveryIntent?.wasPlaying == true)
            #expect(
                request.playbackTransportPlan?.beforeEffect
                    == .pause(mediaSessionID: context.mediaSessionID)
            )
            #expect(
                request.playbackTransportPlan?.afterSuccess
                    == .resume(mediaSessionID: context.mediaSessionID)
            )
            #expect(request.playbackTransportPlan?.afterFailure == nil)

            #expect(
                try completePendingEffect(model)
                    == .spatialRecoveryCompleted(presentation)
            )
            #expect(model.presentation == presentation)
            #expect(model.recoveryIntent == nil)
        }
    }

    @Test("Window and Environment preview disappearance do not recover playback")
    @MainActor
    func nonPlaybackImmersiveDisappearanceDoesNotRecover() throws {
        let windowModel = PlaybackPresentationModel()
        #expect(
            windowModel.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(playingContext())
            ) == .platformFactRecorded
        )
        #expect(windowModel.pendingSpatialPlatformEffect == nil)

        let previewModel = PlaybackPresentationModel()
        try previewModel.requestEnvironmentPreview(
            environment: .enchron,
            effect: .night
        )
        _ = try completePendingEffect(previewModel)
        #expect(
            previewModel.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(playingContext())
            ) == .platformFactRecorded
        )
        #expect(previewModel.presentation == .window)
        #expect(previewModel.recoveryIntent == nil)
        #expect(previewModel.pendingSpatialPlatformEffect == nil)
    }

    @Test("expected immersive dismissal does not start recovery")
    @MainActor
    func expectedDismissalDoesNotRecover() throws {
        let model = PlaybackPresentationModel()
        let context = playingContext()
        _ = try model.requestPresentation(
            .docked,
            effect: .day,
            playbackContext: context
        )
        _ = try completePendingEffect(model)
        _ = try model.requestPresentation(.window, playbackContext: context)
        let dismissalRequest = try #require(model.pendingSpatialPlatformEffect)

        #expect(
            model.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(context)
            ) == .platformFactRecorded
        )
        #expect(model.recoveryIntent == nil)
        #expect(model.pendingSpatialPlatformEffect?.id == dismissalRequest.id)
        #expect(try completePendingEffect(model) == .presentationCommitted(.window))
    }

    @Test("paused recovery never emits pause or resume transport")
    @MainActor
    func pausedRecoveryPreservesPausedBehavior() throws {
        let model = PlaybackPresentationModel()
        let context = SpatialPlaybackTransitionContext(
            mediaSessionID: "paused-session",
            wasPlaying: false
        )
        _ = try model.requestPresentation(.panorama, playbackContext: context)
        _ = try completePendingEffect(model)
        _ = model.receiveSpatialPlatformResult(.immersiveSpaceDisappeared(context))

        let request = try #require(model.pendingSpatialPlatformEffect)
        #expect(request.playbackTransportPlan?.beforeEffect == nil)
        #expect(request.playbackTransportPlan?.afterSuccess == nil)
        #expect(request.playbackTransportPlan?.afterFailure == nil)
        #expect(model.recoveryIntent?.wasPlaying == false)
    }

    @Test("recovery failure settles once in Window and ignores stale session results")
    @MainActor
    func recoveryFailureIsBoundedAndSessionBound() throws {
        let model = PlaybackPresentationModel()
        let oldContext = playingContext(mediaSessionID: "old-session")
        _ = try model.requestPresentation(.panorama, playbackContext: oldContext)
        _ = try completePendingEffect(model)
        _ = model.receiveSpatialPlatformResult(.immersiveSpaceDisappeared(oldContext))
        let recoveryRequest = try #require(model.pendingSpatialPlatformEffect)
        let recoveryExecutionID = UUID()
        #expect(
            model.claimSpatialPlatformEffect(
                recoveryRequest.id,
                executionID: recoveryExecutionID
            )
        )

        #expect(
            model.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: recoveryRequest.id,
                        executionID: recoveryExecutionID,
                        mediaSessionID: "new-session",
                        outcome: .succeeded
                    )
                )
            ) == .ignored
        )
        #expect(model.pendingSpatialPlatformEffect?.id == recoveryRequest.id)

        #expect(
            model.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: recoveryRequest.id,
                        executionID: recoveryExecutionID,
                        mediaSessionID: oldContext.mediaSessionID,
                        outcome: .failed(.mediaSessionChanged)
                    )
                )
            ) == .spatialRecoveryFailed(.mediaSessionChanged)
        )
        #expect(model.presentation == .window)
        #expect(model.environmentContext == .none)
        #expect(model.recoveryIntent == nil)
        #expect(model.pendingSpatialPlatformEffect == nil)

        #expect(
            model.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(oldContext)
            ) == .platformFactRecorded
        )
        #expect(model.pendingSpatialPlatformEffect == nil)
        #expect(
            model.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: recoveryRequest.id,
                        executionID: recoveryExecutionID,
                        mediaSessionID: oldContext.mediaSessionID,
                        outcome: .succeeded
                    )
                )
            ) == .ignored
        )
    }

    @Test("Environment Card residency is singleton, idempotent, and scene-driven")
    @MainActor
    func environmentCardResidency() throws {
        let model = PlaybackPresentationModel()

        #expect(try model.requestEnvironmentCard())
        let firstRequest = try #require(model.pendingSpatialPlatformEffect)
        #expect(firstRequest.effect == .presentEnvironmentCard)
        #expect(model.environmentCardResidency == .opening)
        #expect(try model.requestEnvironmentCard() == false)
        _ = try completePendingEffect(model)

        #expect(
            model.receiveSpatialPlatformResult(.environmentCardAppeared)
                == .platformFactRecorded
        )
        #expect(model.environmentCardResidency == .open)

        #expect(try model.requestEnvironmentCard())
        let focusRequest = try #require(model.pendingSpatialPlatformEffect)
        #expect(focusRequest.effect == .presentEnvironmentCard)
        #expect(focusRequest.id != firstRequest.id)
        #expect(model.environmentCardResidency == .open)
        _ = try completePendingEffect(model)

        #expect(
            model.receiveSpatialPlatformResult(.environmentCardDisappeared)
                == .platformFactRecorded
        )
        #expect(
            model.receiveSpatialPlatformResult(.environmentCardDisappeared)
                == .platformFactRecorded
        )
        #expect(model.environmentCardResidency == .closed)
    }

    @Test("Panorama has no Environment Card entry")
    @MainActor
    func panoramaRejectsEnvironmentCard() throws {
        let model = PlaybackPresentationModel()
        _ = try model.requestPresentation(.panorama, playbackContext: playingContext())
        _ = try completePendingEffect(model)

        #expect(throws: PlaybackPresentationTransitionError.environmentCardUnavailableInPanorama) {
            try model.requestEnvironmentCard()
        }
        #expect(model.environmentCardResidency == .closed)
        #expect(model.pendingSpatialPlatformEffect == nil)
    }

    @Test("Docked queues Window then Environment Card under one paused transaction")
    @MainActor
    func dockedEnvironmentCardSequence() throws {
        let model = PlaybackPresentationModel()
        let context = playingContext()
        _ = try model.requestPresentation(
            .docked,
            effect: .night,
            playbackContext: context
        )
        _ = try completePendingEffect(model)

        #expect(try model.requestEnvironmentCard(playbackContext: context))
        let windowRequest = try #require(model.pendingSpatialPlatformEffect)
        #expect(
            windowRequest.effect
                == .presentWindowPlayback(
                    keepsEnvironmentOpen: false,
                    immersiveSpaceAlreadyClosed: false
                )
        )
        #expect(
            windowRequest.playbackTransportPlan?.beforeEffect
                == .pause(mediaSessionID: context.mediaSessionID)
        )
        #expect(windowRequest.playbackTransportPlan?.afterSuccess == nil)

        #expect(
            try completePendingEffect(model)
                == .presentationCommitted(.window)
        )
        let cardRequest = try #require(model.pendingSpatialPlatformEffect)
        #expect(cardRequest.effect == .presentEnvironmentCard)
        #expect(cardRequest.playbackTransportPlan?.beforeEffect == nil)
        #expect(
            cardRequest.playbackTransportPlan?.afterSuccess
                == .resume(mediaSessionID: context.mediaSessionID)
        )
        #expect(model.presentation == .window)
        #expect(model.environmentContext == .none)

        _ = try completePendingEffect(model)
        #expect(model.environmentCardEntryPending == false)
        #expect(model.environmentCardResidency == .opening)
    }

    @Test("pause failure rolls back before the platform effect can commit")
    @MainActor
    func pauseFailureRollsBackTransition() throws {
        let model = PlaybackPresentationModel()
        _ = try model.requestPresentation(.panorama, playbackContext: playingContext())

        #expect(
            try completePendingEffect(
                model,
                outcome: .failed(.playbackPauseFailed)
            ) == .presentationRolledBack(.playbackPauseFailed)
        )
        #expect(model.presentation == .window)
        #expect(model.transition == nil)
        #expect(model.pendingSpatialPlatformEffect == nil)
    }

    @Test("resume failure is recorded after commit without rolling presentation back")
    @MainActor
    func resumeFailureDoesNotRollbackCommittedPresentation() throws {
        let model = PlaybackPresentationModel()
        let context = playingContext()
        _ = try model.requestPresentation(.panorama, playbackContext: context)
        let request = try #require(model.pendingSpatialPlatformEffect)
        let executionID = UUID()
        _ = try completePendingEffect(model, executionID: executionID)
        let failure = SpatialPlaybackTransportFailure(
            requestID: request.id,
            executionID: executionID,
            mediaSessionID: context.mediaSessionID,
            intent: .resume(mediaSessionID: context.mediaSessionID),
            reason: .operationRejected
        )

        #expect(
            model.receiveSpatialPlatformResult(.playbackTransportFailed(failure))
                == .playbackTransportFailureRecorded
        )
        #expect(model.presentation == .panorama)
        #expect(model.lastPlaybackTransportFailure == failure)
        #expect(
            model.receiveSpatialPlatformResult(.playbackTransportFailed(failure))
                == .ignored
        )
    }

    @MainActor
    private func completePendingEffect(
        _ model: PlaybackPresentationModel,
        executionID: UUID = UUID(),
        outcome: SpatialPlatformEffectOutcome = .succeeded
    ) throws -> SpatialPlatformEffectResolution {
        let request = try #require(model.pendingSpatialPlatformEffect)
        #expect(
            model.claimSpatialPlatformEffect(
                request.id,
                executionID: executionID
            )
        )
        #expect(
            model.claimSpatialPlatformEffect(
                request.id,
                executionID: UUID()
            ) == false
        )
        return model.receiveSpatialPlatformResult(
            .effectCompleted(
                SpatialPlatformEffectResult(
                    requestID: request.id,
                    executionID: executionID,
                    mediaSessionID: request.playbackTransportPlan?.mediaSessionID,
                    outcome: outcome
                )
            )
        )
    }

    private func playingContext(
        mediaSessionID: String = "test-media-session"
    ) -> SpatialPlaybackTransitionContext {
        SpatialPlaybackTransitionContext(
            mediaSessionID: mediaSessionID,
            wasPlaying: true
        )
    }
}
