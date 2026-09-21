import Foundation
import Testing
@testable import Playback

@MainActor
private enum PresentationContract {
    static let playingContext = SpatialPlaybackTransitionContext(
        mediaSessionID: "domain-playing-session",
        wasPlaying: true
    )

    static let pausedContext = SpatialPlaybackTransitionContext(
        mediaSessionID: "domain-paused-session",
        wasPlaying: false
    )

    static func pendingRequest(
        _ model: PlaybackPresentationModel
    ) throws -> SpatialPlatformEffectRequest {
        try #require(
            model.pendingSpatialPlatformEffect,
            "a product command must publish one pending platform effect"
        )
    }

    @discardableResult
    static func completePendingEffect(
        _ model: PlaybackPresentationModel,
        executionID: UUID = UUID(),
        outcome: SpatialPlatformEffectOutcome = .succeeded
    ) throws -> SpatialPlatformEffectResolution {
        let request = try pendingRequest(model)
        #expect(
            model.claimSpatialPlatformEffect(request.id, executionID: executionID),
            "the pending platform effect must be claimable exactly once"
        )
        #expect(
            model.claimSpatialPlatformEffect(request.id, executionID: UUID()) == false,
            "duplicate View updates must not execute the same platform effect twice"
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

    static func driveThroughDockingRollback() throws -> (
        model: PlaybackPresentationModel,
        firstRequest: SpatialPlatformEffectRequest
    ) {
        let model = PlaybackPresentationModel()
        _ = try model.requestPresentation(
            .docked,
            environment: .quietRoom,
            effect: .dark,
            playbackContext: playingContext
        )
        let firstRequest = try pendingRequest(model)
        try completePendingEffect(
            model,
            outcome: .failed(.spatialPlaybackSurfaceUnavailable)
        )
        return (model, firstRequest)
    }

    static func driveThroughEnvironmentCommit() throws -> (
        model: PlaybackPresentationModel,
        activeEnvironment: EnvironmentContext
    ) {
        let (model, _) = try driveThroughDockingRollback()
        let activeEnvironment = EnvironmentContext.active(
            environment: .placeholderRed,
            effect: .dark
        )
        try model.activateEnvironment(.placeholderRed, effect: .dark)
        _ = try model.requestPresentation(
            .docked,
            environment: .placeholderGreen,
            effect: .light,
            playbackContext: playingContext
        )
        try completePendingEffect(model)
        _ = try model.requestPresentation(.window, playbackContext: playingContext)
        try completePendingEffect(model)
        model.requestStoppedPlaybackCleanup()
        try completePendingEffect(model)
        return (model, activeEnvironment)
    }

    static func driveThroughPanoramaEdges() throws -> PlaybackPresentationModel {
        let (model, _) = try driveThroughEnvironmentCommit()
        _ = try model.requestPresentation(.portal, playbackContext: playingContext)
        try completePendingEffect(model)
        _ = try model.requestPresentation(.panorama, playbackContext: playingContext)
        try completePendingEffect(
            model,
            outcome: .failed(.spatialPlaybackSurfaceUnavailable)
        )
        _ = try model.requestPresentation(.panorama, playbackContext: playingContext)
        try completePendingEffect(model)
        _ = try model.requestPresentation(.portal, playbackContext: playingContext)
        try completePendingEffect(model)
        _ = try model.requestPresentation(.window, playbackContext: playingContext)
        try completePendingEffect(model)
        return model
    }

    static func driveThroughEnvironmentPreview() throws -> PlaybackPresentationModel {
        let model = try driveThroughPanoramaEdges()
        try model.deactivateEnvironment()
        model.setActiveEnvironmentEffect(.dark)
        try model.requestEnvironmentPreview(environment: .ocean, effect: .dark)
        try completePendingEffect(model)
        try model.requestEnvironmentPreviewDismissal()
        try completePendingEffect(model)
        return model
    }

    static func driveThroughEnvironmentCard() throws -> PlaybackPresentationModel {
        let model = try driveThroughEnvironmentPreview()
        _ = try model.requestEnvironmentCard()
        try completePendingEffect(model)
        model.receiveSpatialPlatformResult(.environmentCardAppeared)
        _ = try model.requestEnvironmentCard()
        try completePendingEffect(model)
        model.receiveSpatialPlatformResult(.environmentCardDisappeared)
        model.receiveSpatialPlatformResult(.environmentCardDisappeared)
        return model
    }
}

@MainActor
struct SpatialPlaybackPresentationContractTests {
    @Test("presentation availability keeps each content family inside its own edges")
    func presentationAvailabilityKeepsContentFamilyEdges() {
        let panoramicFormat = MediaFormat(projection: .equirectangular360, stereoLayout: .mono)

        #expect(
            PlaybackPresentationAvailability.presentation(afterApplying: panoramicFormat)
                == .portal,
            "applying a panoramic format must land in Portal"
        )
        #expect(
            PlaybackPresentation.portal.enterImmersiveTarget == .panorama,
            "Portal must preserve access to the panoramic presentation"
        )
        #expect(
            PlaybackPresentation.window.enterImmersiveTarget == .docked,
            "Window must enter Docked"
        )
        #expect(
            PlaybackPresentation.docked.exitImmersiveTarget == .window
                && PlaybackPresentation.panorama.exitImmersiveTarget == .portal,
            "immersive presentations must exit within their content family"
        )
    }

    @Test("docked placement exposes its specified defaults and adjustment steps")
    func dockedPlacementExposesDefaultsAndSteps() {
        #expect(
            PlaybackDockedPlacementLimits.fallback.defaultDistance == 12
                && PlaybackDockedPlacement().distanceMeters == 12,
            "Docked placement defaults must fall back to the shared placeholder limits when no environment-specific limits are given"
        )
        #expect(
            PlaybackDockedPlacementLimits.screenHeightStep == 0.25,
            "Docked Screen Height must advance in quarter-meter steps"
        )
        #expect(
            PlaybackDockedPlacementLimits.distanceStep == 0.5,
            "Docked Distance must advance in half-meter steps"
        )
        #expect(
            PlaybackDockedPlacementLimits.elevationStep == 5.0,
            "Docked Elevation must advance in five-degree steps"
        )
    }

    @Test("ended playback withdraws every forward transport affordance")
    func endedPlaybackWithdrawsForwardTransport() {
        let endedTransport = PlaybackTransportAvailability(lifecycle: .ended)

        #expect(
            endedTransport.primaryAction == .replay,
            "Ended must expose Replay as the primary action under the replay affordance"
        )
        #expect(
            endedTransport.primaryActionEnabled,
            "Replay must remain tappable at the media end"
        )
        #expect(
            !endedTransport.canSkipForward,
            "Ended must disable forward skip at the media end"
        )
        #expect(
            !endedTransport.canStepForward,
            "Ended must disable next-frame at the media end"
        )
    }

    @Test("capability loss abandons the execution and keeps the product request")
    func capabilityLossAbandonsExecutionAndKeepsRequest() throws {
        let retryModel = PlaybackPresentationModel()
        try retryModel.requestEnvironmentPreview(environment: .ocean, effect: .light)
        let retryRequest = try PresentationContract.pendingRequest(retryModel)
        let abandonedExecutionID = UUID()

        #expect(
            retryModel.claimSpatialPlatformEffect(
                retryRequest.id,
                executionID: abandonedExecutionID
            ),
            "the first capability generation must claim the pending request"
        )
        #expect(
            retryModel.receiveSpatialPlatformResult(
                .effectExecutionAbandoned(
                    requestID: retryRequest.id,
                    executionID: abandonedExecutionID
                )
            ) == .platformFactRecorded
                && retryModel.pendingSpatialPlatformEffect?.id == retryRequest.id,
            "capability loss must abandon only the execution, not the product request"
        )

        let retryExecutionID = UUID()
        #expect(
            retryModel.claimSpatialPlatformEffect(
                retryRequest.id,
                executionID: retryExecutionID
            ),
            "a new capability generation must reclaim the still-current request"
        )
        #expect(
            retryModel.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: retryRequest.id,
                        executionID: abandonedExecutionID,
                        outcome: .succeeded
                    )
                )
            ) == .ignored
                && retryModel.pendingSpatialPlatformEffect?.id == retryRequest.id,
            "a stale completion must not settle a newer execution of the same request"
        )
        #expect(
            retryModel.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: retryRequest.id,
                        executionID: retryExecutionID,
                        outcome: .succeeded
                    )
                )
            ) == .effectCompleted,
            "the current execution must settle the retried request"
        )
    }

    @Test("stop cleanup replaces the in-flight request and its execution identity")
    func stopCleanupReplacesInFlightRequest() throws {
        let stopReplacementModel = PlaybackPresentationModel()
        stopReplacementModel.prepareColdPlaybackLaunch(for: .panoramic)
        _ = try stopReplacementModel.requestPresentation(
            .panorama,
            playbackContext: PresentationContract.playingContext
        )
        let replacedRequest = try PresentationContract.pendingRequest(stopReplacementModel)
        let replacedExecutionID = UUID()

        #expect(
            stopReplacementModel.claimSpatialPlatformEffect(
                replacedRequest.id,
                executionID: replacedExecutionID
            ),
            "the request replaced by stop must begin as the active execution"
        )

        stopReplacementModel.requestStoppedPlaybackCleanup()
        let cleanupRequest = try PresentationContract.pendingRequest(stopReplacementModel)

        #expect(
            cleanupRequest.id != replacedRequest.id
                && stopReplacementModel.isSpatialPlatformEffectCurrent(
                    replacedRequest.id,
                    executionID: replacedExecutionID
                ) == false,
            "stop cleanup must immediately invalidate the old execution identity"
        )
        #expect(
            stopReplacementModel.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: replacedRequest.id,
                        executionID: replacedExecutionID,
                        mediaSessionID: replacedRequest.playbackTransportPlan?.mediaSessionID,
                        outcome: .succeeded
                    )
                )
            ) == .ignored,
            "an in-flight request replaced by stop must not settle after resuming"
        )
        #expect(
            try PresentationContract.completePendingEffect(stopReplacementModel)
                == .effectCompleted,
            "the replacement cleanup request must remain claimable exactly once"
        )
    }

    @Test("media session invalidation settles Window through one normalization request")
    func mediaSessionInvalidationSettlesWindow() throws {
        let sessionReplacementModel = PlaybackPresentationModel()
        sessionReplacementModel.prepareColdPlaybackLaunch(for: .panoramic)
        _ = try sessionReplacementModel.requestPresentation(
            .panorama,
            playbackContext: SpatialPlaybackTransitionContext(
                mediaSessionID: "replacement-session-a",
                wasPlaying: true
            )
        )
        let replacedSessionRequest = try PresentationContract.pendingRequest(
            sessionReplacementModel
        )
        let replacedSessionExecutionID = UUID()

        #expect(
            sessionReplacementModel.claimSpatialPlatformEffect(
                replacedSessionRequest.id,
                executionID: replacedSessionExecutionID
            ),
            "the old Media Session effect must be actively claimed"
        )
        #expect(
            sessionReplacementModel.receiveSpatialPlatformResult(
                .mediaSessionInvalidated(
                    requestID: replacedSessionRequest.id,
                    executionID: replacedSessionExecutionID,
                    requiresPlatformNormalization: true
                )
            ) == .presentationRolledBack(.mediaSessionChanged)
                && sessionReplacementModel.presentation == .window,
            "Media Session invalidation must invalidate the old transition and settle Window"
        )

        let sessionCleanupRequest = try PresentationContract.pendingRequest(
            sessionReplacementModel
        )
        #expect(
            sessionCleanupRequest.effect
                == .normalizeInvalidatedSpatialPlayback(keepsEnvironmentOpen: false)
                && sessionCleanupRequest.playbackTransportPlan == nil,
            "issued spatial effects require one session-agnostic normalization request"
        )
        #expect(
            sessionReplacementModel.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: replacedSessionRequest.id,
                        executionID: replacedSessionExecutionID,
                        mediaSessionID: "replacement-session-a",
                        outcome: .succeeded
                    )
                )
            ) == .ignored,
            "the replaced Media Session execution must not commit or resume"
        )
        #expect(
            try PresentationContract.completePendingEffect(sessionReplacementModel)
                == .effectCompleted
                && sessionReplacementModel.pendingSpatialPlatformEffect == nil,
            "session normalization must execute and settle exactly once"
        )
    }

    @Test("a failed Docking effect rolls back to Window without leaking its environment")
    func failedDockingEffectRollsBackToWindow() throws {
        let presentationModel = PlaybackPresentationModel()

        #expect(
            presentationModel.environmentContext == .none
                && presentationModel.currentEnvironmentEffect == .inactiveFallback
                && presentationModel.currentEnvironmentEffect == .light,
            "an inactive Environment Context must use deterministic Light fallback without stored Effect"
        )

        let requestedDock = try presentationModel.requestPresentation(
            .docked,
            environment: .quietRoom,
            effect: .dark,
            playbackContext: PresentationContract.playingContext
        )
        #expect(
            requestedDock.targetEnvironment.environment == .quietRoom
                && requestedDock.targetEnvironment.effect == nil,
            "Docking into Quiet Room carries no Effect whatever the Dock menu requested"
        )

        let firstRequest = try PresentationContract.pendingRequest(presentationModel)
        #expect(
            firstRequest.effect == .enterImmersivePlayback(.flat),
            "Docked must request the existing spatial playback platform effect"
        )
        #expect(
            firstRequest.playbackTransportPlan?.beforeEffect == nil
                && firstRequest.playbackTransportPlan?.afterSuccess
                == .resume(mediaSessionID: PresentationContract.playingContext.mediaSessionID)
                && firstRequest.playbackTransportPlan?.afterFailure == nil,
            "presentation transitions must keep playing media and resume it after a successful commit"
        )

        do {
            _ = try presentationModel.requestPresentation(
                .panorama,
                playbackContext: PresentationContract.playingContext
            )
            Issue.record("a second presentation transition must not begin while one is pending")
        } catch PlaybackPresentationTransitionError.transitionInFlight {
        } catch {
            Issue.record("a second presentation transition failed for an unexpected reason")
        }

        #expect(
            try PresentationContract.completePendingEffect(
                presentationModel,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            ) == .presentationRolledBack(.spatialPlaybackSurfaceUnavailable),
            "a failed platform effect must roll back its product transition"
        )
        #expect(
            presentationModel.presentation == .window
                && presentationModel.environmentContext == .none
                && presentationModel.transition == nil
                && presentationModel.pendingSpatialPlatformEffect == nil,
            "a failed Docking effect must restore Window without leaking its explicit Quiet Room"
        )
    }

    @Test("an explicit Quiet Room closes with the presentation that created it")
    func explicitQuietRoomClosesWithItsPresentation() throws {
        let temporaryEnvironmentModel = PlaybackPresentationModel()
        _ = try temporaryEnvironmentModel.requestPresentation(
            .docked,
            environment: .quietRoom,
            effect: .dark,
            playbackContext: PresentationContract.playingContext
        )
        try PresentationContract.completePendingEffect(temporaryEnvironmentModel)
        _ = try temporaryEnvironmentModel.requestPresentation(
            .window,
            playbackContext: PresentationContract.playingContext
        )

        #expect(
            try PresentationContract.pendingRequest(temporaryEnvironmentModel).effect
                == .exitImmersivePlayback(.flat, keepsEnvironmentOpen: false),
            "Window must close the explicit Quiet Room created only for Docking"
        )

        try PresentationContract.completePendingEffect(temporaryEnvironmentModel)
        #expect(
            temporaryEnvironmentModel.presentation == .window
                && temporaryEnvironmentModel.environmentContext == .none,
            "none -> Docked -> Window must restore Environment Context.none"
        )

        _ = try temporaryEnvironmentModel.requestPresentation(
            .docked,
            environment: .quietRoom,
            effect: .light,
            playbackContext: PresentationContract.playingContext
        )
        try PresentationContract.completePendingEffect(temporaryEnvironmentModel)
        temporaryEnvironmentModel.requestStoppedPlaybackCleanup()

        #expect(
            try PresentationContract.pendingRequest(temporaryEnvironmentModel).effect
                == .normalizeStoppedSpatialPlayback(keepsEnvironmentOpen: false),
            "stopping temporary Docking must close its Environment"
        )

        try PresentationContract.completePendingEffect(temporaryEnvironmentModel)
        #expect(
            temporaryEnvironmentModel.environmentContext == .none,
            "stopping temporary Docking must restore Environment Context.none"
        )
    }

    @Test("an active Environment Context survives Docking and stopped playback")
    func activeEnvironmentContextSurvivesDockingAndStop() throws {
        let (presentationModel, firstRequest) =
            try PresentationContract.driveThroughDockingRollback()
        let activeEnvironment = EnvironmentContext.active(
            environment: .placeholderRed,
            effect: .dark
        )

        try presentationModel.activateEnvironment(.placeholderRed, effect: .dark)
        #expect(
            presentationModel.snapshot.environmentContext.environment == .placeholderRed
                && presentationModel.snapshot.environmentContext.effect == .dark,
            "Environment Context must carry Environment identity and Environment Effect together"
        )

        let pendingDock = try presentationModel.requestPresentation(
            .docked,
            environment: .placeholderGreen,
            effect: .light,
            playbackContext: PresentationContract.playingContext
        )
        #expect(
            pendingDock.targetEnvironment == .active(
                environment: .placeholderGreen,
                effect: .light
            ),
            "Docking must use the environment and appearance selected by the Dock menu"
        )
        #expect(
            presentationModel.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: firstRequest.id,
                        executionID: UUID(),
                        mediaSessionID: firstRequest.playbackTransportPlan?.mediaSessionID,
                        outcome: .succeeded
                    )
                )
            ) == .ignored,
            "a late result must not resolve a newer platform effect"
        )

        let activeDockRequest = try PresentationContract.pendingRequest(presentationModel)
        #expect(
            presentationModel.pendingSpatialPlatformEffect?.id == activeDockRequest.id,
            "a late result must leave the current request pending"
        )
        #expect(
            try PresentationContract.completePendingEffect(presentationModel)
                == .presentationCommitted(.docked),
            "a successful Docked platform effect must commit Docked"
        )
        #expect(
            presentationModel.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: activeDockRequest.id,
                        executionID: UUID(),
                        mediaSessionID: activeDockRequest.playbackTransportPlan?.mediaSessionID,
                        outcome: .succeeded
                    )
                )
            ) == .ignored,
            "a duplicate result must not re-commit an already completed transition"
        )
        #expect(
            presentationModel.presentation == .docked
                && presentationModel.environmentContext.environment == .placeholderGreen,
            "committing Docked must keep the Dock menu environment"
        )

        do {
            _ = try presentationModel.requestPresentation(
                .panorama,
                playbackContext: PresentationContract.playingContext
            )
            Issue.record("Docked must not transition directly to Panorama")
        } catch PlaybackPresentationTransitionError.illegalEdge(
            source: .docked,
            target: .panorama
        ) {
        } catch {
            Issue.record("Docked-to-Panorama failed for an unexpected reason")
        }

        _ = try presentationModel.requestPresentation(
            .window,
            playbackContext: PresentationContract.playingContext
        )
        #expect(
            try PresentationContract.pendingRequest(presentationModel).effect
                == .exitImmersivePlayback(.flat, keepsEnvironmentOpen: true),
            "returning to Window with an active Environment must keep its immersive space"
        )
        #expect(
            try PresentationContract.completePendingEffect(presentationModel)
                == .presentationCommitted(.window),
            "a successful Window platform effect must commit Window"
        )

        presentationModel.requestStoppedPlaybackCleanup()
        #expect(
            try PresentationContract.pendingRequest(presentationModel).effect
                == .normalizeStoppedSpatialPlayback(keepsEnvironmentOpen: true),
            "stopping after an active pre-Docked Environment must keep that Environment"
        )

        try PresentationContract.completePendingEffect(presentationModel)
        #expect(
            presentationModel.environmentContext == activeEnvironment,
            "stopping Docked playback must restore the exact active pre-Docked Context"
        )
    }

    @Test("Panorama rolls back inside its own content family and refuses Docked")
    func panoramaRollsBackInsideItsContentFamily() throws {
        let (presentationModel, _) = try PresentationContract.driveThroughEnvironmentCommit()

        _ = try presentationModel.requestPresentation(
            .portal,
            playbackContext: PresentationContract.playingContext
        )
        try PresentationContract.completePendingEffect(presentationModel)
        _ = try presentationModel.requestPresentation(
            .panorama,
            playbackContext: PresentationContract.playingContext
        )
        try PresentationContract.completePendingEffect(
            presentationModel,
            outcome: .failed(.spatialPlaybackSurfaceUnavailable)
        )

        #expect(
            presentationModel.presentation == .portal
                && presentationModel.transition == nil,
            "Panorama rollback must restore Portal and clear the transition"
        )

        _ = try presentationModel.requestPresentation(
            .panorama,
            playbackContext: PresentationContract.playingContext
        )
        try PresentationContract.completePendingEffect(presentationModel)

        do {
            _ = try presentationModel.requestPresentation(
                .docked,
                playbackContext: PresentationContract.playingContext
            )
            Issue.record("Panorama must not transition directly to Docked")
        } catch PlaybackPresentationTransitionError.illegalEdge(
            source: .panorama,
            target: .docked
        ) {
        } catch {
            Issue.record("Panorama-to-Docked failed for an unexpected reason")
        }
    }

    @Test("Environment preview owns its explicit identity and immersive residency")
    func environmentPreviewOwnsItsIdentityAndResidency() throws {
        let presentationModel = try PresentationContract.driveThroughPanoramaEdges()

        try presentationModel.deactivateEnvironment()
        presentationModel.setActiveEnvironmentEffect(.dark)
        #expect(
            presentationModel.environmentContext == .none
                && presentationModel.currentEnvironmentEffect == .light,
            "setting an Effect without an active Environment Context must not create global Effect state"
        )

        try presentationModel.requestEnvironmentPreview(environment: .ocean, effect: .dark)
        #expect(
            try PresentationContract.pendingRequest(presentationModel).effect
                == .presentEnvironmentPreview,
            "Environment preview must use the same pending platform effect channel"
        )

        try PresentationContract.completePendingEffect(presentationModel)
        #expect(
            presentationModel.environmentContext == EnvironmentContext.active(
                environment: .ocean,
                effect: .dark
            )
                && presentationModel.immersiveSpaceResidency == .open,
            "Environment preview success must retain its explicit identity and Effect"
        )

        try presentationModel.requestEnvironmentPreviewDismissal()
        try PresentationContract.completePendingEffect(presentationModel)
        #expect(
            presentationModel.environmentContext == .none
                && presentationModel.immersiveSpaceResidency == .closed,
            "Environment preview dismissal must clear its active context after success"
        )
    }

    @Test("Environment Card residency stays singleton across present, focus and close")
    func environmentCardResidencyStaysSingleton() throws {
        let presentationModel = try PresentationContract.driveThroughEnvironmentPreview()

        let didRequestFirstCard = try presentationModel.requestEnvironmentCard()
        #expect(
            didRequestFirstCard,
            "Window must publish one Environment Card focus/present request"
        )

        let firstCardRequest = try PresentationContract.pendingRequest(presentationModel)
        let didRepeatOpeningCardRequest = try presentationModel.requestEnvironmentCard()
        #expect(
            firstCardRequest.effect == .presentEnvironmentCard
                && presentationModel.environmentCardResidency == .opening
                && didRepeatOpeningCardRequest == false,
            "Environment Card opening must be singleton and repeated requests must be no-op"
        )

        do {
            try presentationModel.requestEnvironmentPreview(
                environment: .ocean,
                effect: .light
            )
            Issue.record("a second platform effect must not be emitted while one is pending")
        } catch PlaybackPresentationTransitionError.platformEffectInFlight {
        } catch {
            Issue.record("a second platform effect failed for an unexpected reason")
        }

        try PresentationContract.completePendingEffect(presentationModel)
        #expect(
            presentationModel.receiveSpatialPlatformResult(.environmentCardAppeared)
                == .platformFactRecorded
                && presentationModel.environmentCardResidency == .open,
            "Environment Card residency must settle from the Scene appeared fact"
        )

        let didRequestCardFocus = try presentationModel.requestEnvironmentCard()
        #expect(
            didRequestCardFocus,
            "requesting an open singleton Card must publish a focus request"
        )

        let focusCardRequest = try PresentationContract.pendingRequest(presentationModel)
        #expect(
            focusCardRequest.effect == .presentEnvironmentCard
                && focusCardRequest.id != firstCardRequest.id,
            "an open singleton Card must be focused through a new request without a second residency"
        )

        try PresentationContract.completePendingEffect(presentationModel)
        presentationModel.receiveSpatialPlatformResult(.environmentCardDisappeared)
        presentationModel.receiveSpatialPlatformResult(.environmentCardDisappeared)
        #expect(
            presentationModel.environmentCardResidency == .closed,
            "Environment Card close facts must be repeat-safe"
        )
    }

    @Test("Docked Card entry returns to Window before it queues Card focus")
    func dockedCardEntryReturnsToWindowFirst() throws {
        let dockedCardModel = PlaybackPresentationModel()
        _ = try dockedCardModel.requestPresentation(
            .docked,
            environment: .quietRoom,
            effect: .dark,
            playbackContext: PresentationContract.playingContext
        )
        try PresentationContract.completePendingEffect(dockedCardModel)

        let didRequestDockedCard = try dockedCardModel.requestEnvironmentCard(
            playbackContext: PresentationContract.playingContext
        )
        #expect(
            didRequestDockedCard,
            "Docked Card entry must begin an owner-coordinated sequence"
        )

        let cardWindowRequest = try PresentationContract.pendingRequest(dockedCardModel)
        #expect(
            cardWindowRequest.effect
                == .exitImmersivePlayback(.flat, keepsEnvironmentOpen: false)
                && cardWindowRequest.playbackTransportPlan?.beforeEffect == nil
                && cardWindowRequest.playbackTransportPlan?.afterSuccess
                == .resume(mediaSessionID: PresentationContract.playingContext.mediaSessionID),
            "Docked Card entry must return to Window and restore its playback intent"
        )

        try PresentationContract.completePendingEffect(dockedCardModel)
        let queuedCardRequest = try PresentationContract.pendingRequest(dockedCardModel)
        #expect(
            dockedCardModel.presentation == .window
                && dockedCardModel.environmentContext == .none
                && queuedCardRequest.effect == .presentEnvironmentCard
                && queuedCardRequest.playbackTransportPlan?.beforeEffect == nil
                && queuedCardRequest.playbackTransportPlan?.afterSuccess == nil
                && queuedCardRequest.playbackTransportPlan?.afterFailure == nil,
            "Docked Card entry must queue Card focus while playback remains paused"
        )
        try PresentationContract.completePendingEffect(dockedCardModel)
    }

    @Test("Panorama refuses Environment Card entry")
    func panoramaRefusesEnvironmentCardEntry() throws {
        let panoramaCardModel = PlaybackPresentationModel()
        panoramaCardModel.prepareColdPlaybackLaunch(for: .panoramic)
        _ = try panoramaCardModel.requestPresentation(
            .panorama,
            playbackContext: PresentationContract.pausedContext
        )
        try PresentationContract.completePendingEffect(panoramaCardModel)

        do {
            _ = try panoramaCardModel.requestEnvironmentCard()
            Issue.record("Panorama must not expose Environment Card entry")
        } catch PlaybackPresentationTransitionError.environmentCardUnavailableInPanorama {
        } catch {
            Issue.record("Panorama Card validation failed for an unexpected reason")
        }
    }

    @Test("a closed immersive space in Window queues no playback collapse")
    func closedImmersiveSpaceInWindowQueuesNoCollapse() throws {
        let presentationModel = try PresentationContract.driveThroughEnvironmentCard()

        #expect(
            presentationModel.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(PresentationContract.playingContext)
            ) == .platformFactRecorded
                && presentationModel.pendingSpatialPlatformEffect == nil,
            "Window and Environment preview residency queue no playback collapse"
        )
    }

    @Test("a failed pause rolls back before any platform presentation commits")
    func failedPauseRollsBackBeforeCommit() throws {
        let pauseFailureModel = PlaybackPresentationModel()
        pauseFailureModel.prepareColdPlaybackLaunch(for: .panoramic)
        _ = try pauseFailureModel.requestPresentation(
            .panorama,
            playbackContext: PresentationContract.playingContext
        )

        #expect(
            try PresentationContract.completePendingEffect(
                pauseFailureModel,
                outcome: .failed(.playbackPauseFailed)
            ) == .presentationRolledBack(.playbackPauseFailed)
                && pauseFailureModel.presentation == .portal
                && pauseFailureModel.transition == nil,
            "a failed pause must roll back before any platform presentation can commit"
        )
    }

    @Test("an unscheduled resume failure never reaches the presentation")
    func unscheduledResumeFailureNeverReachesPresentation() throws {
        let resumeFailureModel = PlaybackPresentationModel()
        resumeFailureModel.prepareColdPlaybackLaunch(for: .panoramic)
        _ = try resumeFailureModel.requestPresentation(
            .panorama,
            playbackContext: PresentationContract.playingContext
        )
        let resumeFailureRequest = try PresentationContract.pendingRequest(resumeFailureModel)
        let resumeFailureExecutionID = UUID()
        try PresentationContract.completePendingEffect(
            resumeFailureModel,
            executionID: resumeFailureExecutionID
        )
        let resumeFailure = SpatialPlaybackTransportFailure(
            requestID: resumeFailureRequest.id,
            executionID: resumeFailureExecutionID,
            mediaSessionID: PresentationContract.playingContext.mediaSessionID,
            intent: .resume(
                mediaSessionID: PresentationContract.playingContext.mediaSessionID
            ),
            reason: .operationRejected
        )

        #expect(
            resumeFailureModel.receiveSpatialPlatformResult(
                .playbackTransportFailed(resumeFailure)
            ) == .ignored
                && resumeFailureModel.presentation == .panorama
                && resumeFailureModel.lastPlaybackTransportFailure == nil
                && resumeFailureModel.receiveSpatialPlatformResult(
                    .playbackTransportFailed(resumeFailure)
                ) == .ignored,
            "a resume result that no current presentation request scheduled must be ignored"
        )
    }

    @Test("system-closed Docked playback collapses to Window exactly once")
    func systemClosedDockedPlaybackCollapsesToWindowOnce() throws {
        let dockedCollapseModel = PlaybackPresentationModel()
        _ = try dockedCollapseModel.requestPresentation(
            .docked,
            environment: .quietRoom,
            effect: .light,
            playbackContext: PresentationContract.playingContext
        )
        try PresentationContract.completePendingEffect(dockedCollapseModel)

        #expect(
            dockedCollapseModel.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(PresentationContract.playingContext)
            ) == .platformFactRecorded,
            "system-closed Docked playback must record the closure before collapsing"
        )

        let dockedCollapseRequest = try PresentationContract.pendingRequest(dockedCollapseModel)
        let dockedCollapseExecutionID = UUID()
        #expect(
            dockedCollapseRequest.effect == .collapseImmersivePlayback(.flat)
                && dockedCollapseRequest.playbackTransportPlan?.beforeEffect == nil
                && dockedCollapseRequest.playbackTransportPlan?.afterSuccess
                == .resume(mediaSessionID: PresentationContract.playingContext.mediaSessionID)
                && dockedCollapseRequest.playbackTransportPlan?.afterFailure == nil
                && dockedCollapseModel.transition?.previousPresentation == .docked
                && dockedCollapseModel.transition?.targetPresentation == .window
                && dockedCollapseModel.transition?.previousEnvironment == EnvironmentContext.none
                && dockedCollapseModel.transition?.targetEnvironment == EnvironmentContext.none,
            "system-closed Docked playback must collapse to Window and restore playing intent"
        )
        #expect(
            dockedCollapseModel.claimSpatialPlatformEffect(
                dockedCollapseRequest.id,
                executionID: dockedCollapseExecutionID
            ),
            "the collapse effect must be claimable exactly once"
        )
        #expect(
            dockedCollapseModel.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: dockedCollapseRequest.id,
                        executionID: dockedCollapseExecutionID,
                        mediaSessionID: "replacement-session",
                        outcome: .succeeded
                    )
                )
            ) == .ignored
                && dockedCollapseModel.pendingSpatialPlatformEffect?.id
                == dockedCollapseRequest.id,
            "a result for another Media Session must not resolve collapse"
        )
        #expect(
            dockedCollapseModel.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: dockedCollapseRequest.id,
                        executionID: dockedCollapseExecutionID,
                        mediaSessionID: PresentationContract.playingContext.mediaSessionID,
                        outcome: .succeeded
                    )
                )
            ) == .presentationCommitted(.window)
                && dockedCollapseModel.presentation == .window
                && dockedCollapseModel.environmentContext == .none
                && dockedCollapseModel.immersiveSpaceResidency == .closed,
            "successful Docked collapse must commit Window with closed immersive residency"
        )
        #expect(
            dockedCollapseModel.receiveSpatialPlatformResult(
                .effectCompleted(
                    SpatialPlatformEffectResult(
                        requestID: dockedCollapseRequest.id,
                        executionID: dockedCollapseExecutionID,
                        mediaSessionID: PresentationContract.playingContext.mediaSessionID,
                        outcome: .succeeded
                    )
                )
            ) == .ignored,
            "duplicate collapse results must be ignored"
        )
    }

    @Test("system-closed Panorama playback collapses to Portal without resuming")
    func systemClosedPanoramaPlaybackCollapsesToPortal() throws {
        let panoramaCollapseModel = PlaybackPresentationModel()
        panoramaCollapseModel.prepareColdPlaybackLaunch(for: .panoramic)
        _ = try panoramaCollapseModel.requestPresentation(
            .panorama,
            playbackContext: PresentationContract.pausedContext
        )
        try PresentationContract.completePendingEffect(panoramaCollapseModel)

        #expect(
            panoramaCollapseModel.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(PresentationContract.pausedContext)
            ) == .platformFactRecorded,
            "system-closed Panorama playback must record the closure before collapsing"
        )

        let panoramaCollapseRequest = try PresentationContract.pendingRequest(
            panoramaCollapseModel
        )
        #expect(
            panoramaCollapseRequest.effect == .collapseImmersivePlayback(.panoramic)
                && panoramaCollapseRequest.playbackTransportPlan?.beforeEffect == nil
                && panoramaCollapseRequest.playbackTransportPlan?.afterSuccess == nil
                && panoramaCollapseRequest.playbackTransportPlan?.afterFailure == nil,
            "paused Panorama collapse schedules no playback transport action"
        )
        #expect(
            try PresentationContract.completePendingEffect(panoramaCollapseModel)
                == .presentationCommitted(.portal)
                && panoramaCollapseModel.presentation == .portal
                && panoramaCollapseModel.environmentContext == .none
                && panoramaCollapseModel.immersiveSpaceResidency == .closed,
            "successful Panorama collapse must commit Portal without resuming paused playback"
        )
        #expect(
            panoramaCollapseModel.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(PresentationContract.pausedContext)
            ) == .platformFactRecorded
                && panoramaCollapseModel.pendingSpatialPlatformEffect == nil,
            "a duplicate closed-space callback queues no second collapse"
        )
    }

    @Test("an app-requested immersive exit keeps its in-flight request")
    func appRequestedImmersiveExitKeepsInFlightRequest() throws {
        let expectedDismissalModel = PlaybackPresentationModel()
        _ = try expectedDismissalModel.requestPresentation(
            .docked,
            environment: .quietRoom,
            effect: .light,
            playbackContext: PresentationContract.playingContext
        )
        try PresentationContract.completePendingEffect(expectedDismissalModel)
        _ = try expectedDismissalModel.requestPresentation(
            .window,
            playbackContext: PresentationContract.playingContext
        )
        let expectedDismissalRequest = try PresentationContract.pendingRequest(
            expectedDismissalModel
        )

        #expect(
            expectedDismissalModel.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(PresentationContract.playingContext)
            ) == .platformFactRecorded
                && expectedDismissalModel.pendingSpatialPlatformEffect?.id
                == expectedDismissalRequest.id,
            "an app-requested exit preserves its in-flight request"
        )
    }
}
