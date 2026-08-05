import Foundation
import PlaybackPresentation
import PlaybackFeature
import Testing
@testable import Enchron

@Suite("Playback presentation")
struct PlaybackPresentationStateTests {
    @Test("Spatial acceptance isolates its playback state from the user's media state")
    func spatialAcceptanceUsesItsOwnMediaStateSuite() {
        #expect(
            EnchronApplication.mediaStateSuiteName(
                isUITesting: false,
                environment: [
                    "ENCHRON_SPATIAL_ACCEPTANCE": "1",
                    "ENCHRON_TEST_MEDIA_STATE_SUITE": "1"
                ]
            ) == "app.enchron.spatial-acceptance"
        )
        #expect(
            EnchronApplication.mediaStateSuiteName(
                isUITesting: false,
                environment: ["ENCHRON_SPATIAL_ACCEPTANCE": "1"]
            ) == nil
        )
    }

    @Test("Spatial playback observation reports the actual entity opacity")
    func spatialPlaybackObservationReportsEntityOpacity() {
        #expect(
            SpatialPlaybackSurfaceObservation.absent.accessibilityFields
                .contains("surfaceOpacity=0.0000")
        )
    }

    @Test("Panorama requires a RealityKit content type matching the selected projection")
    func panoramaRequiresMatchingRealityKitContentType() {
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .equirectangular360,
                observedContentType: "equirectangular"
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .equirectangular180,
                observedContentType: "halfEquirectangular"
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .fisheye,
                observedContentType: "parametricImmersive"
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .equirectangular360,
                observedContentType: "invalid"
            ) == false
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .equirectangular360,
                observedContentType: "unobserved"
            ) == false
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .equirectangular360,
                observedContentType: "halfEquirectangular"
            ) == false
        )
    }

    @Test("Panorama refreshes after every RealityKit event that can make its target usable")
    func panoramaRefreshesForEveryTargetReadinessEvent() {
        #expect(
            SpatialPresentationRefreshTrigger.allCases == [
                .viewingModeDidChange,
                .immersiveViewingModeDidChange,
                .immersiveViewingModeDidTransition,
                .spatialVideoModeDidChange,
                .renderingStatusDidChange,
                .contentTypeDidChange
            ]
        )
    }

    @Test("Panorama requests progressive only after its target reports portal activation")
    func panoramaTargetBootstrapRequestsProgressiveOnce() {
        var state = PanoramaTargetBootstrapState.awaitingPortalActivation
        let firstRequest = state.receivePortalActivation()
        let duplicateRequest = state.receivePortalActivation()
        #expect(firstRequest)
        #expect(duplicateRequest == false)
        #expect(state == .requestingProgressive)
        state.receiveProgressiveChange()
        #expect(state == .progressiveConfirmed)
    }

    @Test("Panorama target is not settled until progressive mode is confirmed")
    func panoramaTargetBootstrapRequiresProgressiveConfirmation() {
        var state = PanoramaTargetBootstrapState.awaitingPortalActivation
        #expect(state != .progressiveConfirmed)
        _ = state.receivePortalActivation()
        #expect(state != .progressiveConfirmed)
        state.receiveProgressiveChange()
        #expect(state == .progressiveConfirmed)
    }

    @Test("Panorama requires the selected viewing mode to be observed")
    func panoramaViewingModeSettlement() {
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: .mono,
                observedViewingMode: nil,
                requiresObservedMode: true
            ) == false
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: .mono,
                observedViewingMode: "mono",
                requiresObservedMode: true
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: .mono,
                observedViewingMode: "stereo",
                requiresObservedMode: true
            ) == false
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: .mono,
                observedViewingMode: nil,
                requiresObservedMode: false
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: .sideBySide,
                observedViewingMode: nil
            ) == false
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: .topBottom,
                observedViewingMode: "stereo"
            )
        )
    }

    @Test("Flat Window does not require immersive mode confirmation")
    func flatWindowImmersiveModeSettlement() {
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.immersiveViewingModeMatches(
                projection: .flat,
                requiresTransitionConfirmation: true,
                desiredImmersiveViewingMode: "portal",
                observedImmersiveViewingMode: nil
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.immersiveViewingModeMatches(
                projection: .equirectangular360,
                requiresTransitionConfirmation: true,
                desiredImmersiveViewingMode: "portal",
                observedImmersiveViewingMode: nil
            ) == false
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.immersiveViewingModeMatches(
                projection: .equirectangular360,
                requiresTransitionConfirmation: true,
                desiredImmersiveViewingMode: "portal",
                observedImmersiveViewingMode: "portal"
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.immersiveViewingModeMatches(
                projection: .equirectangular360,
                requiresTransitionConfirmation: false,
                desiredImmersiveViewingMode: "portal",
                observedImmersiveViewingMode: nil
            )
        )
    }

    @Test("progressive immersion preserves open-cycle amount policy")
    func progressiveImmersionOpeningPolicy() {
        #expect(
            SpatialImmersiveSpacePolicy.progressiveImmersionRange
                == (0.3...1.0)
        )
        #expect(
            SpatialImmersiveSpacePolicy.openingInitialAmount(
                for: .environment,
                lastObservedAmount: nil
            ) == nil
        )
        #expect(
            SpatialImmersiveSpacePolicy.openingInitialAmount(
                for: .environment,
                lastObservedAmount: 0.62
            ) == 0.62
        )
        #expect(
            SpatialImmersiveSpacePolicy.openingInitialAmount(
                for: .playback(.docked),
                lastObservedAmount: 0.62
            ) == 0.62
        )
        #expect(
            SpatialImmersiveSpacePolicy.openingInitialAmount(
                for: .playback(.panorama),
                lastObservedAmount: 0.62
            ) == 1.0
        )
        #expect(
            SpatialImmersiveSpacePolicy.normalized(-1.0) == 0.3
        )
        #expect(
            SpatialImmersiveSpacePolicy.normalized(2.0) == 1.0
        )
    }

    @Test("Panorama return restores the Environment immersion amount")
    @MainActor
    func panoramaReturnRestoresEnvironmentImmersionAmount() throws {
        let appModel = AppModel()
        appModel.recordImmersionAmount(0.62)
        try appModel.activateEnvironment(.scenicOne, effect: .night)

        _ = try appModel.requestPlaybackPresentation(
            .panorama,
            mediaSessionID: "test-media-session",
            wasPlaying: true
        )
        _ = try completePendingEffect(appModel)
        appModel.recordImmersionAmount(0.41)

        _ = try appModel.requestPlaybackPresentation(
            .window,
            mediaSessionID: "test-media-session",
            wasPlaying: true
        )
        _ = try completePendingEffect(appModel)

        #expect(appModel.immersiveSpaceOpeningInitialAmount == 0.62)
        #expect(appModel.immersiveSpaceStyleRevision == 1)
    }

    @Test("Window keeps its renderer while the source fades")
    func windowSourceKeepsRendererUntilTransferBegins() {
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: .window,
                targetPresentation: .panorama,
                sourceRendererMayRelease: false
            )
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: .window,
                targetPresentation: .panorama,
                sourceRendererMayRelease: true
            ) == false
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: .window,
                targetPresentation: .docked,
                sourceRendererMayRelease: false
            )
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: .window,
                targetPresentation: .docked,
                sourceRendererMayRelease: true
            ) == false
        )
    }

    @Test("Window-to-Panorama confirms source progressive mode before creating a new target graph")
    @MainActor
    func windowToPanoramaUsesTargetOwnedProgressiveConfirmation() throws {
        let appModel = AppModel()

        let transition = try appModel.requestPlaybackPresentation(
            .panorama,
            mediaSessionID: "test-media-session",
            wasPlaying: true
        )

        #expect(transition.requiresWindowPortalToProgressiveChange)
        #expect(transition.keepsCurrentRendererGraph == false)
        #expect(
            appModel.pendingSpatialPlatformEffect?.effect
                == .presentSpatialPlayback(.panorama)
        )
        #expect(
            appModel.pendingSpatialPlatformEffect?
                .requiresWindowPortalToProgressiveChange == true
        )
        #expect(
            appModel.pendingSpatialPlatformEffect?
                .keepsCurrentRendererGraph == false
        )
        #expect(
            appModel.windowPortalToProgressiveChangeIsConfirmed(
                for: transition.id
            ) == false
        )

        appModel.recordWindowPortalToProgressiveChange(for: transition.id)

        #expect(
            appModel.windowPortalToProgressiveChangeIsConfirmed(for: transition.id)
        )
    }

    @Test("Window-to-Panorama creates a distinct renderer graph for the target component")
    func windowToPanoramaCreatesNewRendererGraph() {
        let transition = PlaybackPresentationTransition(
            previousPresentation: .window,
            targetPresentation: .panorama,
            previousEnvironment: .none,
            targetEnvironment: .none
        )
        let dockedTransition = PlaybackPresentationTransition(
            previousPresentation: .window,
            targetPresentation: .docked,
            previousEnvironment: .none,
            targetEnvironment: .active(environment: .scenicOne, effect: .day)
        )

        #expect(transition.keepsCurrentRendererGraph == false)
        #expect(dockedTransition.keepsCurrentRendererGraph == false)
    }

    @Test("A Window target waits for the departing spatial surface to release the renderer")
    func windowTargetWaitsForSpatialRendererRelease() {
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: .panorama,
                targetPresentation: .window,
                sourceRendererMayRelease: false
            ) == false
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: .panorama,
                targetPresentation: .window,
                sourceRendererMayRelease: true
            )
        )
    }

    @Test("Presentation transition does not show the media loading spinner")
    func presentationTransitionDoesNotShowLoadingSpinner() {
        #expect(
            WindowPlaybackLoadingVisibility.shouldShow(
                hasPlaybackError: false,
                presentationState: .placeholder,
                isPresentationTransitionActive: true
            ) == false
        )
        #expect(
            WindowPlaybackLoadingVisibility.shouldShow(
                hasPlaybackError: false,
                presentationState: .placeholder,
                isPresentationTransitionActive: false
            )
        )
    }

    @Test("Presentation transition keeps the target transparent until commit")
    func presentationTransitionKeepsTargetTransparentUntilCommit() {
        let transition = PlaybackPresentationTransition(
            previousPresentation: .window,
            targetPresentation: .panorama,
            previousEnvironment: .none,
            targetEnvironment: .none
        )

        #expect(
            PlaybackPresentationTransitionAppearance.opacity(
                for: .window,
                settledPresentation: .window,
                transition: transition
            ) == 0
        )
        #expect(
            PlaybackPresentationTransitionAppearance.acceptsInput(
                for: .window,
                settledPresentation: .window,
                transition: transition
            ) == false
        )
        #expect(
            PlaybackPresentationTransitionAppearance.opacity(
                for: .panorama,
                settledPresentation: .window,
                transition: transition
            ) == PlaybackPresentationTransitionAppearance.targetPreparationOpacity
        )
        #expect(
            PlaybackPresentationTransitionAppearance.acceptsInput(
                for: .panorama,
                settledPresentation: .window,
                transition: transition
            ) == false
        )

        #expect(
            PlaybackPresentationTransitionAppearance.opacity(
                for: .panorama,
                settledPresentation: .panorama,
                transition: nil
            ) == 1
        )
        #expect(
            PlaybackPresentationTransitionAppearance.acceptsInput(
                for: .panorama,
                settledPresentation: .panorama,
                transition: nil
            )
        )
    }

    @Test("scrub target stays visible until the reported position catches up")
    func scrubTargetLatchSettlesFromPosition() {
        let oldPosition: CGFloat = 0.18
        let target = PlaybackSeekPresentation.pendingTarget(
            for: 0.82,
            livePositionAvailable: true
        )
        #expect(target == 0.82)
        #expect(
            PlaybackSeekPresentation.displayProgress(
                isDragging: false,
                isTimelineDragging: false,
                localProgress: target ?? 0,
                pendingTarget: target,
                liveProgress: oldPosition
            ) == 0.82
        )
        #expect(
            !PlaybackSeekPresentation.target(
                target ?? 0,
                matches: oldPosition
            )
        )
        #expect(
            PlaybackSeekPresentation.target(
                target ?? 0,
                matches: 0.82
            )
        )
        #expect(
            PlaybackSeekPresentation.pendingTarget(
                for: 0.82,
                livePositionAvailable: false
            ) == nil
        )
        #expect(
            PlaybackSeekPresentation.elapsedSeconds(
                for: 0.5,
                duration: 100
            ) == 50
        )
        #expect(
            PlaybackSeekPresentation.elapsedSeconds(
                for: 0.5,
                duration: 0
            ) == nil
        )
    }

    @Test("environment card reveal motion stays within the approved range")
    func environmentCardRevealMotionContract() {
        #expect(EnvironmentCardRevealMotion.initialScale == 0.985)
        #expect((0.22...0.32).contains(EnvironmentCardRevealMotion.standardDuration))
        #expect((0.10...0.15).contains(EnvironmentCardRevealMotion.crossFadeDuration))
    }

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

    @Test("Immersive Space operations require a new matching lifecycle observation")
    func immersiveSpaceOperationRequiresNewLifecycleObservation() {
        var observation = SpatialPlatformImmersiveSpaceObservation()

        observation.record(.open)
        let dismissalStartedAfterRevision = observation.revision

        #expect(
            !observation.confirms(
                .closed,
                after: dismissalStartedAfterRevision
            )
        )

        observation.record(.closed)

        #expect(
            observation.confirms(
                .closed,
                after: dismissalStartedAfterRevision
            )
        )

        let openingStartedAfterRevision = observation.revision
        #expect(
            !observation.confirms(
                .open,
                after: openingStartedAfterRevision
            )
        )

        observation.record(.open)

        #expect(
            observation.confirms(
                .open,
                after: openingStartedAfterRevision
            )
        )
    }

    @Test("Player Controls Window operations require a new matching lifecycle observation")
    func playerControlsWindowOperationRequiresNewLifecycleObservation() {
        var observation = SpatialPlatformWindowObservation()

        observation.record(.open, for: .playerControls)
        let openingStartedAfterRevision = observation.revision(for: .playerControls)

        #expect(
            !observation.confirms(
                .open,
                for: .playerControls,
                after: openingStartedAfterRevision
            )
        )

        observation.record(.closed, for: .playerControls)
        #expect(
            !observation.confirms(
                .open,
                for: .playerControls,
                after: openingStartedAfterRevision
            )
        )

        observation.record(.open, for: .playerControls)
        #expect(
            observation.confirms(
                .open,
                for: .playerControls,
                after: openingStartedAfterRevision
            )
        )
    }

    @Test("Immersive Space lifecycle revision changes only for appearance events")
    @MainActor
    func immersiveSpaceLifecycleRevisionTracksAppearanceEvents() {
        let appModel = AppModel()

        _ = appModel.receiveSpatialPlatformResult(.immersiveSpaceAppeared)
        #expect(appModel.immersiveSpaceLifecycleRevision == 1)

        _ = appModel.receiveSpatialPlatformResult(.environmentCardAppeared)
        #expect(appModel.immersiveSpaceLifecycleRevision == 1)

        _ = appModel.receiveSpatialPlatformResult(
            .immersiveSpaceDisappeared(nil)
        )
        #expect(appModel.immersiveSpaceLifecycleRevision == 2)
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
            environment: .scenicOne,
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

    @Test("seek events preserve the specified lifecycle intent")
    func seekIntentMatrix() {
        let cases: [(PlaybackSeekEvent, ProductPlaybackLifecycle, PlaybackAfterSeekIntent)] = [
            (PlaybackSeekEvent.progressBar, ProductPlaybackLifecycle.playing, PlaybackAfterSeekIntent.preserveCurrentPlaybackIntent),
            (.progressBar, .paused, .preserveCurrentPlaybackIntent),
            (.skip, .playing, .preserveCurrentPlaybackIntent),
            (.skip, .paused, .preserveCurrentPlaybackIntent),
            (.precisionTimeline, .playing, .pause),
            (.precisionTimeline, .paused, .pause),
            (.frameStep, .playing, .pause),
            (.frameStep, .paused, .pause),
            (.progressBar, .ended, .pause),
            (.skip, .ended, .pause),
            (.precisionTimeline, .ended, .pause),
            (.frameStep, .ended, .pause),
        ]
        for (event, lifecycle, expected) in cases {
            #expect(
                PlaybackSeekPolicy.intent(
                    for: event,
                    lifecycle: lifecycle,
                    targetBoundary: .beforeEnd
                ) == expected
            )
        }
    }

    @Test("every seek event targeting the media end resolves to Ended")
    func seekToEndMatrix() {
        for event in PlaybackSeekEvent.allCases {
            for lifecycle in [
                ProductPlaybackLifecycle.playing,
                .paused,
                .ended,
            ] {
                #expect(
                    PlaybackSeekPolicy.intent(
                        for: event,
                        lifecycle: lifecycle,
                        targetBoundary: .end
                    ) == .ended
                )
            }
        }
    }

    @Test("playback output verification reports the first incomplete production boundary")
    func playbackOutputFirstIncompleteBoundary() {
        var observation = completeOutputObservation()
        observation.decoderBootstrapComplete = false
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: observation)
                == .decoderBootstrap
        )

        observation.decoderBootstrapComplete = true
        observation.actualTimebaseRate = 0
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: observation)
                == .timelineRate
        )

        observation.actualTimebaseRate = 1
        observation.displayedPixelBuffer = false
        observation.audioSessionActive = false
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: observation)
                == .displayedVideo
        )

        observation.displayedPixelBuffer = true
        observation.audioRendererStatus = "unknown"
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: observation)
                == .audioRenderer
        )

        observation.audioRendererStatus = "rendering"
        observation.audioRendererMuted = true
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: observation)
                == .audioRenderer
        )

        observation.audioRendererMuted = false
        observation.audioRendererVolume = 0
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: observation)
                == .audioRenderer
        )

        observation.audioRendererVolume = 1
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: observation)
                == .audioSession
        )

        observation.audioSessionActive = true
        observation.audioSessionOutputPortTypes = []
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: observation)
                == .audioRoute
        )

        observation.audioSessionOutputPortTypes = ["BuiltInSpeaker"]
        observation.systemOutputVolume = 0
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: observation)
                == .audioRoute
        )

        observation.lifecycle = .paused
        observation.actualTimebaseRate = 0
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: observation)
                == .ready
        )
    }

    @Test("playing output requires two observations from the same session and epoch")
    func playbackOutputRequiresContinuousAdvancement() {
        let previous = completeOutputObservation(
            capturedAt: Date(timeIntervalSince1970: 100),
            position: 10,
            videoSamples: 100,
            audioSamples: 200
        )
        let current = completeOutputObservation(
            capturedAt: Date(timeIntervalSince1970: 101),
            position: 11,
            videoSamples: 130,
            audioSamples: 240
        )

        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: current)
                == .secondObservation
        )
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(
                current: current,
                previous: previous
            ) == .ready
        )
    }

    @Test("Ended output requires a cleared image and a deactivated audio session")
    func endedOutputContract() {
        var observation = completeOutputObservation()
        observation.lifecycle = .ended
        observation.displayedPixelBuffer = false
        observation.audioSessionActive = false
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: observation)
                == .ready
        )

        observation.displayedPixelBuffer = true
        #expect(
            PlaybackOutputVerification.firstIncompleteBoundary(current: observation)
                == .endedImageClearance
        )
    }

    private func completeOutputObservation(
        capturedAt: Date = Date(timeIntervalSince1970: 101),
        position: Double = 11,
        videoSamples: UInt64 = 130,
        audioSamples: UInt64 = 240
    ) -> PlaybackOutputObservation {
        PlaybackOutputObservation(
            capturedAt: capturedAt,
            mediaSessionID: "session-a",
            streamEpoch: 3,
            lifecycle: .playing,
            positionSeconds: position,
            videoSampleCount: videoSamples,
            acceptedRendererInputCount: videoSamples,
            decoderBootstrapComplete: true,
            requestedPlaybackRate: 1,
            actualTimebaseRate: 1,
            realityKitRendererBound: true,
            videoComponentReady: true,
            displayedPixelBuffer: true,
            hasAudio: true,
            audioSampleBufferCount: audioSamples,
            audioRendererSampleBufferCount: audioSamples,
            audioRendererStreamEpoch: 3,
            audioRendererStatus: "rendering",
            audioRendererVolume: 1,
            audioRendererMuted: false,
            audioRendererError: nil,
            audioSessionActive: true,
            audioSessionCategory: "AVAudioSessionCategoryPlayback",
            audioSessionMode: "AVAudioSessionModeMoviePlayback",
            audioSessionOutputPortTypes: ["BuiltInSpeaker"],
            systemOutputVolume: 1
        )
    }

    @Test("direct Dock uses the environment and appearance selected by its menu")
    @MainActor
    func directDockUsesSelectedTarget() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.scenicTwo, effect: .night)

        _ = try model.requestPresentation(
            .docked,
            environment: .scenicThree,
            effect: .day,
            playbackContext: playingContext()
        )
        let request = try #require(model.pendingSpatialPlatformEffect)
        let resolution = try completePendingEffect(model)

        #expect(resolution == .presentationCommitted(.docked))
        #expect(model.snapshot.presentation == .docked)
        #expect(
            model.snapshot.environmentContext == .active(
                environment: .scenicThree,
                effect: .day
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

    @Test("Skybox is an independent Dock target without an appearance effect")
    @MainActor
    func directDockUsesSkybox() throws {
        let model = PlaybackPresentationModel(defaultEnvironment: .scenicTwo)

        _ = try model.requestPresentation(
            .docked,
            environment: .skybox,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

        #expect(model.presentation == .docked)
        #expect(
            model.environmentContext == .active(
                environment: .skybox,
                effect: nil
            )
        )
        #expect(model.defaultEnvironment == .scenicTwo)
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
                environment: .scenicOne,
                effect: .night
            )
        )
    }

    @Test("undock restores the active environment that preceded Docked")
    @MainActor
    func undockKeepsEnvironment() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.scenicTwo, effect: .night)
        _ = try model.requestPresentation(
            .docked,
            environment: .scenicThree,
            effect: .day,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

        _ = try model.requestPresentation(.window, playbackContext: playingContext())
        _ = try completePendingEffect(model)

        #expect(model.presentation == .window)
        #expect(
            model.environmentContext == .active(
                environment: .scenicTwo,
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
        try activeModel.activateEnvironment(.scenicOne, effect: .night)
        _ = try activeModel.requestPresentation(
            .docked,
            environment: .scenicThree,
            effect: .day,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(activeModel)
        _ = try activeModel.requestPresentation(
            .window,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(
            activeModel,
            outcome: .failed(.mainWindowUnavailable)
        )
        #expect(activeModel.presentation == .docked)
        #expect(
            activeModel.environmentContext == .active(
                environment: .scenicThree,
                effect: .day
            )
        )

        _ = try activeModel.requestPresentation(
            .window,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(activeModel)
        #expect(
            activeModel.environmentContext == .active(
                environment: .scenicOne,
                effect: .night
            )
        )
    }

    @Test("panorama rollback restores window and its environment context")
    @MainActor
    func panoramaRollbackRestoresPreviousState() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.scenicOne, effect: .night)

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
                environment: .scenicOne,
                effect: .night
            )
        )
        #expect(model.transition == nil)
    }

    @Test("Panorama suspends the active environment and restores it on return")
    @MainActor
    func panoramaSuspendsAndRestoresActiveEnvironment() throws {
        let model = PlaybackPresentationModel()
        let priorEnvironment = EnvironmentContext.active(
            environment: .scenicOne,
            effect: .night
        )
        try model.activateEnvironment(.scenicOne, effect: .night)

        let enter = try model.requestPresentation(
            .panorama,
            playbackContext: playingContext()
        )
        #expect(enter.previousEnvironment == priorEnvironment)
        #expect(enter.targetEnvironment == .none)
        _ = try completePendingEffect(model)
        #expect(model.presentation == .panorama)
        #expect(model.environmentContext == .none)

        let leave = try model.requestPresentation(
            .window,
            playbackContext: playingContext()
        )
        #expect(leave.previousEnvironment == .none)
        #expect(leave.targetEnvironment == priorEnvironment)
        _ = try completePendingEffect(model)
        #expect(model.presentation == .window)
        #expect(model.environmentContext == priorEnvironment)
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
        try model.activateEnvironment(.scenicOne, effect: .day)
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
        try model.activateEnvironment(.scenicOne, effect: .night)
        _ = try model.requestPresentation(
            .docked,
            environment: .scenicOne,
            effect: .night,
            playbackContext: playingContext()
        )
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
                environment: .scenicOne,
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
        try model.activateEnvironment(.scenicOne, effect: .night)
        _ = try model.requestPresentation(.docked, playbackContext: playingContext())
        let staleRequest = try #require(model.pendingSpatialPlatformEffect)

        model.requestStoppedPlaybackCleanup()
        let cleanupRequest = try #require(model.pendingSpatialPlatformEffect)

        #expect(model.presentation == .window)
        #expect(
            model.environmentContext == .active(
                environment: .scenicOne,
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
        try model.activateEnvironment(.scenicOne, effect: .night)
        _ = try model.requestPresentation(
            .docked,
            environment: .scenicOne,
            effect: .night,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

        #expect(throws: PlaybackPresentationTransitionError.dockedPresentationRequiresEnvironment) {
            try model.deactivateEnvironment()
        }
        #expect(
            model.environmentContext == .active(
                environment: .scenicOne,
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
            #expect(request.playbackTransportPlan?.afterSuccess == nil)
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
            environment: .scenicOne,
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
        #expect(cardRequest.playbackTransportPlan?.afterSuccess == nil)
        #expect(cardRequest.playbackTransportPlan?.afterFailure == nil)
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

    @Test("an unscheduled resume result is ignored after presentation commit")
    @MainActor
    func unscheduledResumeResultIsIgnored() throws {
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
                == .ignored
        )
        #expect(model.presentation == .panorama)
        #expect(model.lastPlaybackTransportFailure == nil)
        #expect(
            model.receiveSpatialPlatformResult(.playbackTransportFailed(failure))
                == .ignored
        )
    }

    @Test("presentation transitions pause once and never schedule automatic resume")
    @MainActor
    func presentationTransitionsRemainPausedAfterCommitAndRollback() throws {
        for target in [PlaybackPresentation.docked, .panorama] {
            let model = PlaybackPresentationModel()
            let context = playingContext(mediaSessionID: "\(target.rawValue)-session")
            _ = try model.requestPresentation(
                target,
                effect: target == .docked ? .day : nil,
                playbackContext: context
            )
            let entry = try #require(model.pendingSpatialPlatformEffect)
            #expect(
                entry.playbackTransportPlan?.beforeEffect
                    == .pause(mediaSessionID: context.mediaSessionID)
            )
            #expect(entry.playbackTransportPlan?.afterSuccess == nil)
            #expect(entry.playbackTransportPlan?.afterFailure == nil)
            #expect(try completePendingEffect(model) == .presentationCommitted(target))

            let pausedContext = SpatialPlaybackTransitionContext(
                mediaSessionID: context.mediaSessionID,
                wasPlaying: false
            )
            _ = try model.requestPresentation(.window, playbackContext: pausedContext)
            let returnRequest = try #require(model.pendingSpatialPlatformEffect)
            #expect(returnRequest.playbackTransportPlan?.beforeEffect == nil)
            #expect(returnRequest.playbackTransportPlan?.afterSuccess == nil)
            #expect(returnRequest.playbackTransportPlan?.afterFailure == nil)
            #expect(try completePendingEffect(model) == .presentationCommitted(.window))
        }

        let rollbackModel = PlaybackPresentationModel()
        let rollbackContext = playingContext(mediaSessionID: "rollback-session")
        _ = try rollbackModel.requestPresentation(
            .panorama,
            playbackContext: rollbackContext
        )
        let rollbackRequest = try #require(rollbackModel.pendingSpatialPlatformEffect)
        #expect(
            rollbackRequest.playbackTransportPlan?.beforeEffect
                == .pause(mediaSessionID: rollbackContext.mediaSessionID)
        )
        #expect(rollbackRequest.playbackTransportPlan?.afterSuccess == nil)
        #expect(rollbackRequest.playbackTransportPlan?.afterFailure == nil)
        #expect(
            try completePendingEffect(
                rollbackModel,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            ) == .presentationRolledBack(.spatialPlaybackSurfaceUnavailable)
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

    @MainActor
    private func completePendingEffect(
        _ appModel: AppModel,
        executionID: UUID = UUID(),
        outcome: SpatialPlatformEffectOutcome = .succeeded
    ) throws -> SpatialPlatformEffectResolution {
        let request = try #require(
            appModel.playbackPresentationModel.pendingSpatialPlatformEffect
        )
        #expect(
            appModel.claimSpatialPlatformEffect(
                request.id,
                executionID: executionID
            )
        )
        return appModel.receiveSpatialPlatformResult(
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
