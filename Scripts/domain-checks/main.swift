import Foundation
import MediaLibrary
import MediaSource
import PlaybackFeature
import PlaybackPresentation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("Domain contract failed: \(message)\n".utf8))
        exit(1)
    }
}

let shortInteraction = PlaybackSessionEvidence(
    durationSeconds: 3_600,
    positionSeconds: 120,
    actualPlaybackSeconds: 14.9,
    endedNaturally: false
)
require(
    ViewingStatePolicy.mutation(for: shortInteraction) == .unchanged,
    "a short interaction must not overwrite viewing state"
)

let resume = PlaybackSessionEvidence(
    durationSeconds: 3_600,
    positionSeconds: 1_800,
    actualPlaybackSeconds: 30,
    endedNaturally: false
)
require(
    ViewingStatePolicy.mutation(for: resume)
        == .save(.resumable(positionSeconds: 1_800, durationSeconds: 3_600)),
    "an eligible early exit must save a resume position"
)

let nearEnd = PlaybackSessionEvidence(
    durationSeconds: 3_600,
    positionSeconds: 3_300,
    actualPlaybackSeconds: 30,
    endedNaturally: false
)
require(
    ViewingStatePolicy.mutation(for: nearEnd) == .remove,
    "an early exit inside the near-end boundary must not remain resumable"
)

let naturalEnd = PlaybackSessionEvidence(
    durationSeconds: 900,
    positionSeconds: 900,
    actualPlaybackSeconds: 15,
    endedNaturally: true
)
require(
    ViewingStatePolicy.mutation(for: naturalEnd) == .save(.completed(durationSeconds: 900)),
    "only a natural end may persist completed state"
)

let names = ["Episode 10", "Episode 2", "Episode 01"]
let collection = names.enumerated().map { offset, name in
    (name, UUID(uuidString: "00000000-0000-0000-0000-00000000000\(offset)")!)
}.sorted {
    NaturalMediaNameOrder.lessThan($0.0, id: $0.1, $1.0, id: $1.1)
}
require(
    collection.map(\.0) == ["Episode 01", "Episode 2", "Episode 10"],
    "playback collection must use natural ascending name order"
)

let firstRemoteSource = try FileBrowsingDomain.ConnectionInfo.remote(
    sourceType: .smb,
    address: "192.0.2.10"
)
let recreatedRemoteSource = try FileBrowsingDomain.ConnectionInfo.remote(
    sourceType: .smb,
    address: "192.0.2.10"
)
require(
    MediaIdentity.remote(
        sourceKey: firstRemoteSource.mediaIdentitySourceKey,
        canonicalPath: "/Share/Episode 01.mkv"
    ) == MediaIdentity.remote(
        sourceKey: recreatedRemoteSource.mediaIdentitySourceKey,
        canonicalPath: "/Share/Episode 01.mkv"
    ),
    "equivalent remote source entries must share media identity"
)
let tenantOne = try FileBrowsingDomain.ConnectionInfo.remote(
    sourceType: .webDAV,
    address: "https://media.example.test/library",
    username: "tenant-one"
)
let tenantTwo = try FileBrowsingDomain.ConnectionInfo.remote(
    sourceType: .webDAV,
    address: "https://media.example.test/library",
    username: "tenant-two"
)
require(
    MediaIdentity.remote(sourceKey: tenantOne.mediaIdentitySourceKey, canonicalPath: "/video.mkv")
        != MediaIdentity.remote(sourceKey: tenantTwo.mediaIdentitySourceKey, canonicalPath: "/video.mkv"),
    "different remote account namespaces must not share media identity"
)

let panoramicFormat = MediaFormat(projection: .equirectangular360, stereoLayout: .mono)
require(
    PlaybackPresentationAvailability.presentation(afterApplying: panoramicFormat) == .portal,
    "applying a panoramic format must land in Portal"
)
require(
    PlaybackPresentation.portal.enterImmersiveTarget == .panorama,
    "Portal must preserve access to the panoramic presentation"
)
require(
    PlaybackPresentation.window.enterImmersiveTarget == .docked,
    "Window must enter Docked"
)
require(
    PlaybackPresentation.docked.exitImmersiveTarget == .window
        && PlaybackPresentation.panorama.exitImmersiveTarget == .portal,
    "immersive presentations must exit within their content family"
)
require(
    PlaybackDockedPlacement.defaultDistance == 4.0
        && PlaybackDockedPlacement().distanceMeters == 4.0,
    "Docked placement defaults must preserve the specified four-meter distance"
)
require(
    PlaybackScreenSize.scaleStep == 0.05,
    "Docked Screen Size must advance in five-percent steps"
)
require(
    PlaybackDockedPlacement.distanceStep == 0.5,
    "Docked Distance must advance in half-meter steps"
)
require(
    PlaybackDockedPlacement.elevationStep == 5.0,
    "Docked Elevation must advance in five-degree steps"
)
let endedTransport = PlaybackTransportAvailability(lifecycle: .ended)
require(endedTransport.primaryAction == .replay, "Ended must expose Replay as the primary action")
require(!endedTransport.canSkipForward, "Ended must disable forward skip at the media end")
require(!endedTransport.canStepForward, "Ended must disable next-frame at the media end")
require(
    PlaybackEndPolicy.action(for: .stop) == .stayEnded,
    "Stop end behavior must retain the ended session without an automatic action"
)

try await MainActor.run {
    @MainActor
    func pendingRequest(
        _ model: PlaybackPresentationModel
    ) -> SpatialPlatformEffectRequest {
        guard let request = model.pendingSpatialPlatformEffect else {
            require(false, "a product command must publish one pending platform effect")
            fatalError()
        }
        return request
    }

    @MainActor
    @discardableResult
    func completePendingEffect(
        _ model: PlaybackPresentationModel,
        executionID: UUID = UUID(),
        outcome: SpatialPlatformEffectOutcome = .succeeded
    ) -> SpatialPlatformEffectResolution {
        let request = pendingRequest(model)
        require(
            model.claimSpatialPlatformEffect(
                request.id,
                executionID: executionID
            ),
            "the pending platform effect must be claimable exactly once"
        )
        require(
            model.claimSpatialPlatformEffect(
                request.id,
                executionID: UUID()
            ) == false,
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

    let playingContext = SpatialPlaybackTransitionContext(
        mediaSessionID: "domain-playing-session",
        wasPlaying: true
    )
    let pausedContext = SpatialPlaybackTransitionContext(
        mediaSessionID: "domain-paused-session",
        wasPlaying: false
    )

    let retryModel = PlaybackPresentationModel()
    try retryModel.requestEnvironmentPreview(
        environment: .scenicOne,
        effect: .light
    )
    let retryRequest = pendingRequest(retryModel)
    let abandonedExecutionID = UUID()
    require(
        retryModel.claimSpatialPlatformEffect(
            retryRequest.id,
            executionID: abandonedExecutionID
        ),
        "the first capability generation must claim the pending request"
    )
    require(
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
    require(
        retryModel.claimSpatialPlatformEffect(
            retryRequest.id,
            executionID: retryExecutionID
        ),
        "a new capability generation must reclaim the still-current request"
    )
    require(
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
    require(
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

    let stopReplacementModel = PlaybackPresentationModel()
    stopReplacementModel.prepareColdPlaybackLaunch(for: .panoramic)
    _ = try stopReplacementModel.requestPresentation(
        .panorama,
        playbackContext: playingContext
    )
    let replacedRequest = pendingRequest(stopReplacementModel)
    let replacedExecutionID = UUID()
    require(
        stopReplacementModel.claimSpatialPlatformEffect(
            replacedRequest.id,
            executionID: replacedExecutionID
        ),
        "the request replaced by stop must begin as the active execution"
    )
    stopReplacementModel.requestStoppedPlaybackCleanup()
    let cleanupRequest = pendingRequest(stopReplacementModel)
    require(
        cleanupRequest.id != replacedRequest.id
            && stopReplacementModel.isSpatialPlatformEffectCurrent(
                replacedRequest.id,
                executionID: replacedExecutionID
            ) == false,
        "stop cleanup must immediately invalidate the old execution identity"
    )
    require(
        stopReplacementModel.receiveSpatialPlatformResult(
            .effectCompleted(
                SpatialPlatformEffectResult(
                    requestID: replacedRequest.id,
                    executionID: replacedExecutionID,
                    mediaSessionID:
                        replacedRequest.playbackTransportPlan?.mediaSessionID,
                    outcome: .succeeded
                )
            )
        ) == .ignored,
        "an in-flight request replaced by stop must not settle after resuming"
    )
    require(
        completePendingEffect(stopReplacementModel) == .effectCompleted,
        "the replacement cleanup request must remain claimable exactly once"
    )

    let sessionReplacementModel = PlaybackPresentationModel()
    sessionReplacementModel.prepareColdPlaybackLaunch(for: .panoramic)
    _ = try sessionReplacementModel.requestPresentation(
        .panorama,
        playbackContext: SpatialPlaybackTransitionContext(
            mediaSessionID: "replacement-session-a",
            wasPlaying: true
        )
    )
    let replacedSessionRequest = pendingRequest(sessionReplacementModel)
    let replacedSessionExecutionID = UUID()
    require(
        sessionReplacementModel.claimSpatialPlatformEffect(
            replacedSessionRequest.id,
            executionID: replacedSessionExecutionID
        ),
        "the old Media Session effect must be actively claimed"
    )
    require(
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
    let sessionCleanupRequest = pendingRequest(sessionReplacementModel)
    require(
        sessionCleanupRequest.effect
            == .normalizeInvalidatedSpatialPlayback(
                keepsEnvironmentOpen: false
            )
            && sessionCleanupRequest.playbackTransportPlan == nil,
        "issued spatial effects require one session-agnostic normalization request"
    )
    require(
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
    require(
        completePendingEffect(sessionReplacementModel) == .effectCompleted
            && sessionReplacementModel.pendingSpatialPlatformEffect == nil,
        "session normalization must execute and settle exactly once"
    )
    let presentationModel = PlaybackPresentationModel()
    require(
        presentationModel.environmentContext == .none
            && presentationModel.currentEnvironmentEffect == .inactiveFallback
            && presentationModel.currentEnvironmentEffect == .light,
        "an inactive Environment Context must use deterministic Light fallback without stored Effect"
    )

    let requestedDock = try presentationModel.requestPresentation(
        .docked,
        effect: .dark,
        playbackContext: playingContext
    )
    require(
        requestedDock.targetEnvironment.environment == presentationModel.defaultEnvironment
            && requestedDock.targetEnvironment.effect == .dark,
        "Docking without an active Environment Context must use its requested Effect"
    )
    let firstRequest = pendingRequest(presentationModel)
    require(
        firstRequest.effect == .enterImmersivePlayback(.flat),
        "Docked must request the existing spatial playback platform effect"
    )
    require(
        firstRequest.playbackTransportPlan?.beforeEffect == nil
            && firstRequest.playbackTransportPlan?.afterSuccess
            == .resume(mediaSessionID: playingContext.mediaSessionID)
            && firstRequest.playbackTransportPlan?.afterFailure == nil,
        "presentation transitions must keep playing media and resume it after a successful commit"
    )
    do {
        _ = try presentationModel.requestPresentation(
            .panorama,
            playbackContext: playingContext
        )
        require(false, "a second presentation transition must not begin while one is pending")
    } catch PlaybackPresentationTransitionError.transitionInFlight {
    } catch {
        require(false, "a second presentation transition failed for an unexpected reason")
    }
    require(
        completePendingEffect(
            presentationModel,
            outcome: .failed(.spatialPlaybackSurfaceUnavailable)
        ) == .presentationRolledBack(.spatialPlaybackSurfaceUnavailable),
        "a failed platform effect must roll back its product transition"
    )
    require(
        presentationModel.presentation == .window
            && presentationModel.environmentContext == .none
            && presentationModel.transition == nil
            && presentationModel.pendingSpatialPlatformEffect == nil,
        "a failed Docking effect must restore Window without leaking its temporary Default Environment"
    )

    let temporaryEnvironmentModel = PlaybackPresentationModel()
    _ = try temporaryEnvironmentModel.requestPresentation(
        .docked,
        effect: .dark,
        playbackContext: playingContext
    )
    _ = completePendingEffect(temporaryEnvironmentModel)
    _ = try temporaryEnvironmentModel.requestPresentation(
        .window,
        playbackContext: playingContext
    )
    require(
        pendingRequest(temporaryEnvironmentModel).effect
            == .exitImmersivePlayback(
                .flat,
                keepsEnvironmentOpen: false
            ),
        "Window must close a temporary Default Environment created only for Docking"
    )
    _ = completePendingEffect(temporaryEnvironmentModel)
    require(
        temporaryEnvironmentModel.presentation == .window
            && temporaryEnvironmentModel.environmentContext == .none,
        "none -> Docked -> Window must restore Environment Context.none"
    )
    _ = try temporaryEnvironmentModel.requestPresentation(
        .docked,
        effect: .light,
        playbackContext: playingContext
    )
    _ = completePendingEffect(temporaryEnvironmentModel)
    temporaryEnvironmentModel.requestStoppedPlaybackCleanup()
    require(
        pendingRequest(temporaryEnvironmentModel).effect
            == .normalizeStoppedSpatialPlayback(keepsEnvironmentOpen: false),
        "stopping temporary Docking must close its Environment"
    )
    _ = completePendingEffect(temporaryEnvironmentModel)
    require(
        temporaryEnvironmentModel.environmentContext == .none,
        "stopping temporary Docking must restore Environment Context.none"
    )

    let defaultEnvironmentBeforeActivation = presentationModel.defaultEnvironment
    let activeEnvironment = EnvironmentContext.active(
        environment: .scenicTwo,
        effect: .dark
    )
    try presentationModel.activateEnvironment(.scenicTwo, effect: .dark)
    require(
        presentationModel.snapshot.environmentContext.environment == .scenicTwo
            && presentationModel.snapshot.environmentContext.effect == .dark
            && presentationModel.defaultEnvironment == defaultEnvironmentBeforeActivation,
        "Environment Context must carry Environment identity and Environment Effect together"
    )

    let pendingDock = try presentationModel.requestPresentation(
        .docked,
        environment: .scenicThree,
        effect: .light,
        playbackContext: playingContext
    )
    require(
        pendingDock.targetEnvironment == .active(
            environment: .scenicThree,
            effect: .light
        ),
        "Docking must use the environment and appearance selected by the Dock menu"
    )
    require(
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
    let activeDockRequest = pendingRequest(presentationModel)
    require(
        presentationModel.pendingSpatialPlatformEffect?.id == activeDockRequest.id,
        "a late result must leave the current request pending"
    )
    require(
        completePendingEffect(presentationModel) == .presentationCommitted(.docked),
        "a successful Docked platform effect must commit Docked"
    )
    require(
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
    require(
        presentationModel.presentation == .docked
            && presentationModel.defaultEnvironment == defaultEnvironmentBeforeActivation,
        "committing Docked must not rewrite Default Environment identity"
    )
    do {
        _ = try presentationModel.requestPresentation(
            .panorama,
            playbackContext: playingContext
        )
        require(false, "Docked must not transition directly to Panorama")
    } catch PlaybackPresentationTransitionError.illegalEdge(
        source: .docked,
        target: .panorama
    ) {
    } catch {
        require(false, "Docked-to-Panorama failed for an unexpected reason")
    }

    _ = try presentationModel.requestPresentation(
        .window,
        playbackContext: playingContext
    )
    require(
        pendingRequest(presentationModel).effect
            == .exitImmersivePlayback(
                .flat,
                keepsEnvironmentOpen: true
            ),
        "returning to Window with an active Environment must keep its immersive space"
    )
    require(
        completePendingEffect(presentationModel) == .presentationCommitted(.window),
        "a successful Window platform effect must commit Window"
    )
    presentationModel.requestStoppedPlaybackCleanup()
    require(
        pendingRequest(presentationModel).effect
            == .normalizeStoppedSpatialPlayback(keepsEnvironmentOpen: true),
        "stopping after an active pre-Docked Environment must keep that Environment"
    )
    _ = completePendingEffect(presentationModel)
    require(
        presentationModel.environmentContext == activeEnvironment,
        "stopping Docked playback must restore the exact active pre-Docked Context"
    )
    _ = try presentationModel.requestPresentation(
        .portal,
        playbackContext: playingContext
    )
    _ = completePendingEffect(presentationModel)
    _ = try presentationModel.requestPresentation(
        .panorama,
        playbackContext: playingContext
    )
    _ = completePendingEffect(
        presentationModel,
        outcome: .failed(.spatialPlaybackSurfaceUnavailable)
    )
    require(
        presentationModel.presentation == .portal
            && presentationModel.transition == nil,
        "Panorama rollback must restore Portal and clear the transition"
    )
    _ = try presentationModel.requestPresentation(
        .panorama,
        playbackContext: playingContext
    )
    _ = completePendingEffect(presentationModel)
    do {
        _ = try presentationModel.requestPresentation(
            .docked,
            playbackContext: playingContext
        )
        require(false, "Panorama must not transition directly to Docked")
    } catch PlaybackPresentationTransitionError.illegalEdge(
        source: .panorama,
        target: .docked
    ) {
    } catch {
        require(false, "Panorama-to-Docked failed for an unexpected reason")
    }
    _ = try presentationModel.requestPresentation(
        .portal,
        playbackContext: playingContext
    )
    _ = completePendingEffect(presentationModel)
    _ = try presentationModel.requestPresentation(
        .window,
        playbackContext: playingContext
    )
    _ = completePendingEffect(presentationModel)

    try presentationModel.deactivateEnvironment()
    presentationModel.setActiveEnvironmentEffect(.dark)
    require(
        presentationModel.environmentContext == .none
            && presentationModel.currentEnvironmentEffect == .light,
        "setting an Effect without an active Environment Context must not create global Effect state"
    )

    try presentationModel.requestEnvironmentPreview(
        environment: .scenicOne,
        effect: .dark
    )
    require(
        pendingRequest(presentationModel).effect == .presentEnvironmentPreview,
        "Environment preview must use the same pending platform effect channel"
    )
    _ = completePendingEffect(presentationModel)
    require(
        presentationModel.environmentContext == activeEnvironment
            && presentationModel.immersiveSpaceResidency == .open,
        "Environment preview success must retain its explicit identity and Effect"
    )
    try presentationModel.requestEnvironmentPreviewDismissal()
    _ = completePendingEffect(presentationModel)
    require(
        presentationModel.environmentContext == .none
            && presentationModel.immersiveSpaceResidency == .closed,
        "Environment preview dismissal must clear its active context after success"
    )
    let didRequestFirstCard = try presentationModel.requestEnvironmentCard()
    require(
        didRequestFirstCard,
        "Window must publish one Environment Card focus/present request"
    )
    let firstCardRequest = pendingRequest(presentationModel)
    let didRepeatOpeningCardRequest = try presentationModel.requestEnvironmentCard()
    require(
        firstCardRequest.effect == .presentEnvironmentCard
            && presentationModel.environmentCardResidency == .opening
            && didRepeatOpeningCardRequest == false,
        "Environment Card opening must be singleton and repeated requests must be no-op"
    )
    do {
        try presentationModel.requestEnvironmentPreview(
            environment: .scenicOne,
            effect: .light
        )
        require(false, "a second platform effect must not be emitted while one is pending")
    } catch PlaybackPresentationTransitionError.platformEffectInFlight {
    } catch {
        require(false, "a second platform effect failed for an unexpected reason")
    }
    _ = completePendingEffect(presentationModel)
    require(
        presentationModel.receiveSpatialPlatformResult(.environmentCardAppeared)
            == .platformFactRecorded
            && presentationModel.environmentCardResidency == .open,
        "Environment Card residency must settle from the Scene appeared fact"
    )
    let didRequestCardFocus = try presentationModel.requestEnvironmentCard()
    require(
        didRequestCardFocus,
        "requesting an open singleton Card must publish a focus request"
    )
    let focusCardRequest = pendingRequest(presentationModel)
    require(
        focusCardRequest.effect == .presentEnvironmentCard
            && focusCardRequest.id != firstCardRequest.id,
        "an open singleton Card must be focused through a new request without a second residency"
    )
    _ = completePendingEffect(presentationModel)
    _ = presentationModel.receiveSpatialPlatformResult(.environmentCardDisappeared)
    _ = presentationModel.receiveSpatialPlatformResult(.environmentCardDisappeared)
    require(
        presentationModel.environmentCardResidency == .closed,
        "Environment Card close facts must be repeat-safe"
    )

    let dockedCardModel = PlaybackPresentationModel()
    _ = try dockedCardModel.requestPresentation(
        .docked,
        effect: .dark,
        playbackContext: playingContext
    )
    _ = completePendingEffect(dockedCardModel)
    let didRequestDockedCard = try dockedCardModel.requestEnvironmentCard(
        playbackContext: playingContext
    )
    require(
        didRequestDockedCard,
        "Docked Card entry must begin an owner-coordinated sequence"
    )
    let cardWindowRequest = pendingRequest(dockedCardModel)
    require(
        cardWindowRequest.effect
            == .exitImmersivePlayback(
                .flat,
                keepsEnvironmentOpen: false
            )
            && cardWindowRequest.playbackTransportPlan?.beforeEffect == nil
            && cardWindowRequest.playbackTransportPlan?.afterSuccess
                == .resume(mediaSessionID: playingContext.mediaSessionID),
        "Docked Card entry must return to Window and restore its playback intent"
    )
    _ = completePendingEffect(dockedCardModel)
    let queuedCardRequest = pendingRequest(dockedCardModel)
    require(
        dockedCardModel.presentation == .window
            && dockedCardModel.environmentContext == .none
            && queuedCardRequest.effect == .presentEnvironmentCard
            && queuedCardRequest.playbackTransportPlan?.beforeEffect == nil
            && queuedCardRequest.playbackTransportPlan?.afterSuccess == nil
            && queuedCardRequest.playbackTransportPlan?.afterFailure == nil,
        "Docked Card entry must queue Card focus while playback remains paused"
    )
    _ = completePendingEffect(dockedCardModel)

    let panoramaCardModel = PlaybackPresentationModel()
    panoramaCardModel.prepareColdPlaybackLaunch(for: .panoramic)
    _ = try panoramaCardModel.requestPresentation(
        .panorama,
        playbackContext: pausedContext
    )
    _ = completePendingEffect(panoramaCardModel)
    do {
        _ = try panoramaCardModel.requestEnvironmentCard()
        require(false, "Panorama must not expose Environment Card entry")
    } catch PlaybackPresentationTransitionError.environmentCardUnavailableInPanorama {
    } catch {
        require(false, "Panorama Card validation failed for an unexpected reason")
    }

    require(
        presentationModel.receiveSpatialPlatformResult(
            .immersiveSpaceDisappeared(playingContext)
        ) == .platformFactRecorded
            && presentationModel.pendingSpatialPlatformEffect == nil,
        "Window and Environment preview residency queue no playback collapse"
    )

    let pauseFailureModel = PlaybackPresentationModel()
    pauseFailureModel.prepareColdPlaybackLaunch(for: .panoramic)
    _ = try pauseFailureModel.requestPresentation(
        .panorama,
        playbackContext: playingContext
    )
    require(
        completePendingEffect(
            pauseFailureModel,
            outcome: .failed(.playbackPauseFailed)
        ) == .presentationRolledBack(.playbackPauseFailed)
            && pauseFailureModel.presentation == .portal
            && pauseFailureModel.transition == nil,
        "a failed pause must roll back before any platform presentation can commit"
    )

    let resumeFailureModel = PlaybackPresentationModel()
    resumeFailureModel.prepareColdPlaybackLaunch(for: .panoramic)
    _ = try resumeFailureModel.requestPresentation(
        .panorama,
        playbackContext: playingContext
    )
    let resumeFailureRequest = pendingRequest(resumeFailureModel)
    let resumeFailureExecutionID = UUID()
    _ = completePendingEffect(
        resumeFailureModel,
        executionID: resumeFailureExecutionID
    )
    let resumeFailure = SpatialPlaybackTransportFailure(
        requestID: resumeFailureRequest.id,
        executionID: resumeFailureExecutionID,
        mediaSessionID: playingContext.mediaSessionID,
        intent: .resume(mediaSessionID: playingContext.mediaSessionID),
        reason: .operationRejected
    )
    require(
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

    let dockedCollapseModel = PlaybackPresentationModel()
    _ = try dockedCollapseModel.requestPresentation(
        .docked,
        effect: .light,
        playbackContext: playingContext
    )
    _ = completePendingEffect(dockedCollapseModel)
    require(
        dockedCollapseModel.receiveSpatialPlatformResult(
            .immersiveSpaceDisappeared(playingContext)
        ) == .platformFactRecorded,
        "system-closed Docked playback must record the closure before collapsing"
    )
    let dockedCollapseRequest = pendingRequest(dockedCollapseModel)
    let dockedCollapseExecutionID = UUID()
    require(
        dockedCollapseRequest.effect == .collapseImmersivePlayback(.flat)
            && dockedCollapseRequest.playbackTransportPlan?.beforeEffect == nil
            && dockedCollapseRequest.playbackTransportPlan?.afterSuccess
                == .resume(mediaSessionID: playingContext.mediaSessionID)
            && dockedCollapseRequest.playbackTransportPlan?.afterFailure == nil
            && dockedCollapseModel.transition?.previousPresentation == .docked
            && dockedCollapseModel.transition?.targetPresentation == .window
            && dockedCollapseModel.transition?.previousEnvironment == EnvironmentContext.none
            && dockedCollapseModel.transition?.targetEnvironment == EnvironmentContext.none,
        "system-closed Docked playback must collapse to Window and restore playing intent"
    )
    require(
        dockedCollapseModel.claimSpatialPlatformEffect(
            dockedCollapseRequest.id,
            executionID: dockedCollapseExecutionID
        ),
        "the collapse effect must be claimable exactly once"
    )
    require(
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
    require(
        dockedCollapseModel.receiveSpatialPlatformResult(
            .effectCompleted(
                SpatialPlatformEffectResult(
                    requestID: dockedCollapseRequest.id,
                    executionID: dockedCollapseExecutionID,
                    mediaSessionID: playingContext.mediaSessionID,
                    outcome: .succeeded
                )
            )
        ) == .presentationCommitted(.window)
            && dockedCollapseModel.presentation == .window
            && dockedCollapseModel.environmentContext == .none
            && dockedCollapseModel.immersiveSpaceResidency == .closed,
        "successful Docked collapse must commit Window with closed immersive residency"
    )
    require(
        dockedCollapseModel.receiveSpatialPlatformResult(
            .effectCompleted(
                SpatialPlatformEffectResult(
                    requestID: dockedCollapseRequest.id,
                    executionID: dockedCollapseExecutionID,
                    mediaSessionID: playingContext.mediaSessionID,
                    outcome: .succeeded
                )
            )
        ) == .ignored,
        "duplicate collapse results must be ignored"
    )

    let panoramaCollapseModel = PlaybackPresentationModel()
    panoramaCollapseModel.prepareColdPlaybackLaunch(for: .panoramic)
    _ = try panoramaCollapseModel.requestPresentation(
        .panorama,
        playbackContext: pausedContext
    )
    _ = completePendingEffect(panoramaCollapseModel)
    require(
        panoramaCollapseModel.receiveSpatialPlatformResult(
            .immersiveSpaceDisappeared(pausedContext)
        ) == .platformFactRecorded,
        "system-closed Panorama playback must record the closure before collapsing"
    )
    let panoramaCollapseRequest = pendingRequest(panoramaCollapseModel)
    require(
        panoramaCollapseRequest.effect == .collapseImmersivePlayback(.panoramic)
            && panoramaCollapseRequest.playbackTransportPlan?.beforeEffect == nil
            && panoramaCollapseRequest.playbackTransportPlan?.afterSuccess == nil
            && panoramaCollapseRequest.playbackTransportPlan?.afterFailure == nil,
        "paused Panorama collapse schedules no playback transport action"
    )
    require(
        completePendingEffect(panoramaCollapseModel)
            == .presentationCommitted(.portal)
            && panoramaCollapseModel.presentation == .portal
            && panoramaCollapseModel.environmentContext == .none
            && panoramaCollapseModel.immersiveSpaceResidency == .closed,
        "successful Panorama collapse must commit Portal without resuming paused playback"
    )
    require(
        panoramaCollapseModel.receiveSpatialPlatformResult(
            .immersiveSpaceDisappeared(pausedContext)
        ) == .platformFactRecorded
            && panoramaCollapseModel.pendingSpatialPlatformEffect == nil,
        "a duplicate closed-space callback queues no second collapse"
    )

    let expectedDismissalModel = PlaybackPresentationModel()
    _ = try expectedDismissalModel.requestPresentation(
        .docked,
        effect: .light,
        playbackContext: playingContext
    )
    _ = completePendingEffect(expectedDismissalModel)
    _ = try expectedDismissalModel.requestPresentation(
        .window,
        playbackContext: playingContext
    )
    let expectedDismissalRequest = pendingRequest(expectedDismissalModel)
    require(
        expectedDismissalModel.receiveSpatialPlatformResult(
            .immersiveSpaceDisappeared(playingContext)
        ) == .platformFactRecorded
            && expectedDismissalModel.pendingSpatialPlatformEffect?.id
                == expectedDismissalRequest.id,
        "an app-requested exit preserves its in-flight request"
    )
}

let normalizedCustomAngle = MediaFormatPolicy.normalized(
    .init(
        projection: .customAngle,
        horizontalFieldOfViewDegrees: 237,
        stereoLayout: .mono
    )
)
require(
    normalizedCustomAngle.horizontalFieldOfViewDegrees == 240,
    "Custom Angle must snap to a supported ten-degree increment"
)

private let leaseCounter = LockedCounter()
private let lease = MediaAccessLease { leaseCounter.increment() }
lease.release()
lease.release()
require(leaseCounter.value == 1, "media access lease must release exactly once")

let suiteName = "app.scenicOne.domain-checks.\(UUID().uuidString)"
guard let defaults = UserDefaults(suiteName: suiteName) else {
    fatalError("Unable to create isolated UserDefaults suite")
}
defer { defaults.removePersistentDomain(forName: suiteName) }
let mediaIdentity = MediaIdentity.local(resourceIdentifier: Data([0x01]))
let originalVersion = VersionedMediaIdentity(
    mediaIdentity: mediaIdentity,
    contentRevision: .file(
        resourceIdentifier: Data([0x01]),
        sizeInBytes: 1_000,
        modifiedAt: Date(timeIntervalSince1970: 100)
    )
)
let replacementVersion = VersionedMediaIdentity(
    mediaIdentity: mediaIdentity,
    contentRevision: .file(
        resourceIdentifier: Data([0x01]),
        sizeInBytes: 2_000,
        modifiedAt: Date(timeIntervalSince1970: 200)
    )
)
let stateStore = MediaStateStore(suiteName: suiteName)
await stateStore.applyViewingMutation(
    .save(.resumable(positionSeconds: 120, durationSeconds: 3_600)),
    for: originalVersion
)
await stateStore.saveFormat(panoramicFormat, for: originalVersion)
let storedOriginal = await stateStore.loadValidated(for: originalVersion)
require(
    storedOriginal?.viewingStatus
        == .resumable(positionSeconds: 120, durationSeconds: 3_600),
    "viewing state and format must share the versioned media key"
)
await stateStore.applyViewingMutation(.remove, for: originalVersion)
let stateAfterStartOver = await stateStore.loadValidated(for: originalVersion)
require(
    stateAfterStartOver?.viewingStatus == nil
        && stateAfterStartOver?.formatPreference == panoramicFormat,
    "Start Over must clear viewing state without discarding media format"
)
await stateStore.applyViewingMutation(
    .save(.resumable(positionSeconds: 120, durationSeconds: 3_600)),
    for: originalVersion
)
let browserProjection = await stateStore.viewingProjection(for: mediaIdentity)
require(
    browserProjection == .resumable(positionSeconds: 120, durationSeconds: 3_600),
    "browser projection must read last-known viewing state without revision validation"
)
let storedReplacement = await stateStore.loadValidated(for: replacementVersion)
require(
    storedReplacement == nil,
    "a changed Content Revision must invalidate persisted media state"
)

var accumulator = ActualPlaybackAccumulator()
let observationStart = Date(timeIntervalSince1970: 100)
accumulator.record(positionSeconds: 10, at: observationStart, isPlaying: true, playbackRate: 1)
accumulator.record(
    positionSeconds: 11,
    at: observationStart.addingTimeInterval(1),
    isPlaying: true,
    playbackRate: 1
)
accumulator.markDiscontinuity()
accumulator.record(
    positionSeconds: 3_000,
    at: observationStart.addingTimeInterval(2),
    isPlaying: true,
    playbackRate: 1
)
accumulator.record(
    positionSeconds: 3_001,
    at: observationStart.addingTimeInterval(3),
    isPlaying: true,
    playbackRate: 1
)
require(
    abs(accumulator.seconds - 2) < 0.001,
    "a seek discontinuity must not count skipped media as actual playback"
)

print("Enchron domain contracts passed")

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int { lock.withLock { storedValue } }

    func increment() {
        lock.withLock { storedValue += 1 }
    }
}

private func requireSendable<T: Sendable>(_: T) {}
