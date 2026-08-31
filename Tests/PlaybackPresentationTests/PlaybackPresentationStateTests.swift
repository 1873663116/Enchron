import Foundation
import PlaybackCore
@testable import Playback
import RealityKit
import Testing
@testable import Enchron

@MainActor
@Suite("Playback presentation")
struct PlaybackPresentationStateTests {
    private struct PresentationRequestCase {
        let source: PlaybackPresentation
        let target: PlaybackPresentation
        let effect: SpatialPlatformEffect?
        let error: PlaybackPresentationTransitionError?
    }

    @Test("delivery accessibility exposes dynamic range and audio facts")
    func deliveryAccessibilityFacts() {
        var diagnostics = PlaybackDiagnostics()
        diagnostics.sourcePixelFormat = "420v"
        diagnostics.destinationPixelFormat = "x420"
        diagnostics.dolbyVisionProfile = 8
        diagnostics.dolbyVisionCrossCompatibilityID = 1
        diagnostics.dolbyVisionHasEnhancementLayer = false
        var snapshot = PlaybackDebugSnapshotV1()
        snapshot.lastAudioSample = AudioSampleRecord(
            mediaSessionID: "session-1",
            audioTrackID: "session-1.audio.2",
            streamEpoch: 3,
            presentationTimeSeconds: 1,
            durationSeconds: 0.1,
            sampleRate: 48_000,
            channelCount: 2,
            sampleCount: 4_800,
            deliveryObservation: AudioDeliveryObservation(
                providerKind: "FFmpegDecodedPCM",
                sourceCodecName: "truehd",
                mediaSubtype: "lpcm",
                formatID: "lpcm",
                formatFlags: 41,
                sourceSampleRate: 48_000,
                deliveredSampleRate: 48_000,
                sourceChannelCount: 2,
                deliveredChannelCount: 2,
                bitsPerChannel: 32,
                bytesPerFrame: 8,
                framesPerPacket: 1,
                isFloatPCM: true,
                isInterleaved: true,
                channelLayoutTag: nil,
                presentationTimestampsMonotonic: true,
                timestampObservationCount: 12,
                trueHDDecoderInputPacketCount: 120,
                trueHDDecoderBatchCount: 2,
                trueHDAggregatedDecoderBatchCount: 2,
                trueHDOutputSampleBufferCount: 1,
                trueHDLastDecoderBatchInputPacketCount: 60
            )
        )

        let fields = Set(
            PlaybackStateAccessibility.deliveryAccessibilityFields(
                diagnostics: diagnostics,
                debugSnapshot: snapshot
            )
        )

        #expect(fields.contains("sourcePixelFormat=420v"))
        #expect(fields.contains("destinationPixelFormat=x420"))
        #expect(fields.contains("dolbyVisionProfile=8"))
        #expect(fields.contains("dolbyVisionCrossCompatibilityID=1"))
        #expect(fields.contains("audioProviderKind=FFmpegDecodedPCM"))
        #expect(fields.contains("audioSourceCodec=truehd"))
        #expect(fields.contains("audioDeliveryIsFloatPCM=true"))
        #expect(fields.contains("audioDeliveryIsInterleaved=true"))
        #expect(fields.contains("audioDeliverySampleCount=4800"))
        #expect(fields.contains("audioDeliveryTimestampsMonotonic=true"))
        #expect(fields.contains("audioDeliveryTimestampObservationCount=12"))
        #expect(fields.contains("audioTrueHDDecoderInputPacketCount=120"))
        #expect(fields.contains("audioTrueHDDecoderBatchCount=2"))
        #expect(fields.contains("audioTrueHDAggregatedDecoderBatchCount=2"))
        #expect(fields.contains("audioTrueHDOutputSampleBufferCount=1"))
        #expect(fields.contains("audioTrueHDLastDecoderBatchInputPacketCount=60"))
    }

    @Test("immersive resident resolves each issue to its existing product location")
    func immersiveResidentIssueLocation() {
        #expect(
            PlaybackIssuePresentationScope.immersiveResident.resolve(
                .environmentLoadingFailed
            ) == .immersiveSpace
        )
        #expect(
            PlaybackIssuePresentationScope.immersiveResident.resolve(
                .capabilityUnavailable(.videoDecoderUnavailable)
            ) == .playerDeck
        )
        #expect(
            PlaybackIssuePresentationScope.immersiveResident.resolve(
                .mediaRequestFailed
            ) == nil
        )
    }

    @Test("Immersive playback entry pushes a resident window")
    func immersivePlaybackEntryPushesResidentWindow() {
        for family in [PresentationContentFamily.flat, .panoramic] {
            #expect(
                SpatialPlatformPlaybackWindowPolicy.action(
                    for: .enterImmersivePlayback(family),
                    residentWindowState: .absent
                ) == .pushResidentWindow
            )
        }
    }

    @Test("Immersive playback exit dismisses an open resident window")
    func immersivePlaybackExitDismissesOpenResidentWindow() {
        for family in [PresentationContentFamily.flat, .panoramic] {
            #expect(
                SpatialPlatformPlaybackWindowPolicy.action(
                    for: .exitImmersivePlayback(family),
                    residentWindowState: .open
                ) == .dismissResidentWindow
            )
        }
    }

    @Test("Immersive playback collapse dismisses an open resident window")
    func immersivePlaybackCollapseDismissesOpenResidentWindow() {
        for family in [PresentationContentFamily.flat, .panoramic] {
            #expect(
                SpatialPlatformPlaybackWindowPolicy.action(
                    for: .collapseImmersivePlayback(family),
                    residentWindowState: .open
                ) == .dismissResidentWindow
            )
        }
    }

    @Test("Immersive playback exit opens the playback window without an open resident window")
    func immersivePlaybackExitOpensPlaybackWindowWithoutOpenResidentWindow() {
        for family in [PresentationContentFamily.flat, .panoramic] {
            #expect(
                SpatialPlatformPlaybackWindowPolicy.action(
                    for: .exitImmersivePlayback(family),
                    residentWindowState: .absent
                ) == .openPlaybackWindow
            )
        }
    }

    @Test("Window session reconciliation swaps scenes only from the owning host window")
    func windowSessionReconciliationSwapsScenesOnlyFromOwningHostWindow() {
        #expect(
            PlaybackWindowSessionReconciliationPolicy.handover(
                hostWindow: .main,
                sessionIsActive: true
            ) == PlaybackWindowHandover(incoming: .playback, outgoing: .main)
        )
        #expect(
            PlaybackWindowSessionReconciliationPolicy.handover(
                hostWindow: .main,
                sessionIsActive: false
            ) == nil
        )
        #expect(
            PlaybackWindowSessionReconciliationPolicy.handover(
                hostWindow: .playback,
                sessionIsActive: false
            ) == PlaybackWindowHandover(incoming: .main, outgoing: .playback)
        )
        #expect(
            PlaybackWindowSessionReconciliationPolicy.handover(
                hostWindow: .playback,
                sessionIsActive: true
            ) == nil
        )
        for sessionIsActive in [true, false] {
            #expect(
                PlaybackWindowSessionReconciliationPolicy.handover(
                    hostWindow: .immersivePlaybackResident,
                    sessionIsActive: sessionIsActive
                ) == nil
            )
        }
    }

    @Test("Every handover names the window that must arrive before the other leaves")
    func everyHandoverNamesTheWindowThatMustArriveBeforeTheOtherLeaves() {
        let hosts: [SpatialPlatformWindowIdentity] = [
            .main, .playback, .immersivePlaybackResident
        ]
        for host in hosts {
            for sessionIsActive in [true, false] {
                guard let handover = PlaybackWindowSessionReconciliationPolicy
                    .handover(hostWindow: host, sessionIsActive: sessionIsActive)
                else { continue }
                #expect(handover.outgoing == host)
                #expect(handover.incoming != handover.outgoing)
            }
        }
    }

    @Test("Immersive playback exit reveals the Main Window only after spatial teardown and target activation")
    func immersivePlaybackExitWaitsToRevealActivatedWindowTarget() {
        #expect(
            SpatialPlatformImmersiveExitWindowRevealPolicy.shouldRevealMainWindow(
                sourceRendererIsReleased: false,
                targetSessionIsActivated: false
            ) == false
        )
        #expect(
            SpatialPlatformImmersiveExitWindowRevealPolicy.shouldRevealMainWindow(
                sourceRendererIsReleased: true,
                targetSessionIsActivated: false
            ) == false
        )
        #expect(
            SpatialPlatformImmersiveExitWindowRevealPolicy.shouldRevealMainWindow(
                sourceRendererIsReleased: true,
                targetSessionIsActivated: true
            )
        )
        #expect(
            SpatialPlatformImmersiveExitWindowRevealPolicy.shouldBeginVisualCutover(
                transition: nil,
                surfacePresentation: .portal,
                targetSurfacePixelIdentityIsCurrent: true
            ) == false
        )
        let panoramaExit = PlaybackPresentationTransition(
            previousPresentation: .panorama,
            targetPresentation: .portal,
            previousEnvironment: .none,
            targetEnvironment: .none
        )
        #expect(
            SpatialPlatformImmersiveExitWindowRevealPolicy.shouldBeginVisualCutover(
                transition: panoramaExit,
                surfacePresentation: .portal,
                targetSurfacePixelIdentityIsCurrent: false
            ) == false
        )
        #expect(
            SpatialPlatformImmersiveExitWindowRevealPolicy.shouldBeginVisualCutover(
                transition: panoramaExit,
                surfacePresentation: .portal,
                targetSurfacePixelIdentityIsCurrent: true
            )
        )
        let dockedExit = PlaybackPresentationTransition(
            previousPresentation: .docked,
            targetPresentation: .window,
            previousEnvironment: .none,
            targetEnvironment: .none
        )
        #expect(
            SpatialPlatformImmersiveExitWindowRevealPolicy.shouldBeginVisualCutover(
                transition: dockedExit,
                surfacePresentation: .window,
                targetSurfacePixelIdentityIsCurrent: true
            )
        )
        #expect(
            SpatialPlatformImmersiveExitWindowRevealPolicy.shouldBeginVisualCutover(
                transition: dockedExit,
                surfacePresentation: .portal,
                targetSurfacePixelIdentityIsCurrent: true
            ) == false
        )
        #expect(
            SpatialPlatformImmersiveExitWindowRevealPolicy
                .shouldShowLastFrameBridge(
                    family: .panoramic,
                    targetIsSettled: false,
                    hasCapturedFrame: true
                )
        )
        #expect(
            SpatialPlatformImmersiveExitWindowRevealPolicy
                .shouldShowLastFrameBridge(
                    family: .panoramic,
                    targetIsSettled: true,
                    hasCapturedFrame: true
                ) == false
        )
        #expect(
            SpatialPlatformImmersiveExitWindowRevealPolicy
                .shouldShowLastFrameBridge(
                    family: .flat,
                    targetIsSettled: false,
                    hasCapturedFrame: true
                ) == false
        )
    }

    @Test("Immersive playback collapse opens the main window without an open resident window")
    func immersivePlaybackCollapseOpensMainWindowWithoutOpenResidentWindow() {
        for family in [PresentationContentFamily.flat, .panoramic] {
            #expect(
                SpatialPlatformPlaybackWindowPolicy.action(
                    for: .collapseImmersivePlayback(family),
                    residentWindowState: .absent
                ) == .openPlaybackWindow
            )
        }
    }

    @Test("every Panorama exit refreshes the retained Portal viewport")
    func portalViewportRefreshPolicy() {
        #expect(
            PortalPlaybackViewportRefreshPolicy.requiresRefresh(
                for: .collapseImmersivePlayback(.panoramic)
            )
        )
        #expect(
            PortalPlaybackViewportRefreshPolicy.requiresRefresh(
                for: .collapseImmersivePlayback(.flat)
            ) == false
        )
        #expect(
            PortalPlaybackViewportRefreshPolicy.requiresRefresh(
                for: .exitImmersivePlayback(.panoramic)
            )
        )
        #expect(
            PortalPlaybackViewportRefreshPolicy.requiresRefresh(
                for: .exitImmersivePlayback(.flat)
            ) == false
        )
        #expect(
            PortalPlaybackViewportRefreshPolicy.requiresRefresh(
                for: .normalizeSpatialPlayback
            ) == false
        )
    }

    @Test("Portal viewport refresh completes only after its requested revision applies")
    func portalViewportRefreshState() {
        var state = PortalPlaybackViewportRefreshState()

        let first = state.request()
        #expect(first == 1)
        #expect(state.hasApplied(first) == false)

        state.recordApplied(first + 1)
        #expect(state.hasApplied(first) == false)

        state.recordApplied(first)
        #expect(state.hasApplied(first))

        let second = state.request()
        #expect(second == 2)
        #expect(state.hasApplied(second) == false)
    }

    @Test("RealityView hosts keep identities independent of their shared Entity")
    func realityViewHostIdentityIsStableAndUnique() {
        let first = PlaybackRealityViewHostIdentity()
        let second = PlaybackRealityViewHostIdentity()

        #expect(first != second)
        #expect(first.description == first.description)
        #expect(first.description.hasPrefix("EnchronRealityView.spatial#"))
    }

    @Test("Only a live RealityView can acquire an unowned Entity topology")
    func realityViewTopologyWritePolicy() {
        #expect(
            PlaybackRealityViewTopologyWritePolicy.decision(
                currentHostIsActive: false,
                entityIsActive: false,
                entityIsInCurrentHost: false
            ) == .inactiveHost
        )
        #expect(
            PlaybackRealityViewTopologyWritePolicy.decision(
                currentHostIsActive: true,
                entityIsActive: true,
                entityIsInCurrentHost: false
            ) == .entityOwnedByAnotherActiveHost
        )
        #expect(
            PlaybackRealityViewTopologyWritePolicy.decision(
                currentHostIsActive: true,
                entityIsActive: false,
                entityIsInCurrentHost: false
            ) == .allowed
        )
        #expect(
            PlaybackRealityViewTopologyWritePolicy.decision(
                currentHostIsActive: true,
                entityIsActive: true,
                entityIsInCurrentHost: true
            ) == .allowed
        )
    }

    @Test("RealityView scheduling retains one trailing update")
    func realityViewUpdateSchedulingState() {
        var state = PlaybackRealityViewUpdateSchedulingState()

        #expect(state.submit() == .start)
        #expect(state.submit() == .queueLatest)
        #expect(state.submit() == .queueLatest)
        #expect(state.complete() == .startLatest)
        #expect(state.complete() == .idle)

        #expect(state.submit() == .start)
        state.cancel()
        #expect(state.complete() == .idle)
    }

    @Test("Spatial playback normalization restores the retained playback Window")
    func spatialPlaybackNormalizationRestoresRetainedPlaybackWindow() {
        #expect(
            SpatialPlatformPlaybackWindowPolicy.action(
                for: .normalizeSpatialPlayback,
                residentWindowState: .open
            ) == .dismissResidentWindow
        )
        #expect(
            SpatialPlatformPlaybackWindowPolicy.action(
                for: .normalizeSpatialPlayback,
                residentWindowState: .closing
            ) == .dismissResidentWindow
        )
        #expect(
            SpatialPlatformPlaybackWindowPolicy.action(
                for: .normalizeSpatialPlayback,
                residentWindowState: .absent
            ) == .openPlaybackWindow
        )
    }

    @Test("Spatial invalidation dismisses a resident Window that is still opening")
    func spatialInvalidationDismissesOpeningResidentWindow() {
        #expect(
            SpatialPlatformPlaybackWindowPolicy.action(
                for: .normalizeSpatialPlayback,
                residentWindowState: .opening
            ) == .dismissResidentWindow
        )
    }

    @Test("Main glass hosts the browser unless a scene operation is in flight")
    func browserSurfaceFollowsSettledSceneState() {
        #expect(BrowserWindowSurfacePolicy.showsBrowser(
            hasActivePlaybackRequest: false,
            transitionIsActive: false,
            immersiveSpaceResidency: .closed
        ))
        #expect(BrowserWindowSurfacePolicy.showsBrowser(
            hasActivePlaybackRequest: true,
            transitionIsActive: false,
            immersiveSpaceResidency: .closed
        ))
        #expect(BrowserWindowSurfacePolicy.showsBrowser(
            hasActivePlaybackRequest: true,
            transitionIsActive: true,
            immersiveSpaceResidency: .closed
        ) == false)
        #expect(BrowserWindowSurfacePolicy.showsBrowser(
            hasActivePlaybackRequest: true,
            transitionIsActive: false,
            immersiveSpaceResidency: .open
        ) == false)
    }

    @Test("Stopped playback restores the browser default window size")
    func stoppedPlaybackRestoresBrowserDefaultWindowSize() {
        #expect(BrowserWindowGeometryPolicy.shouldRequestDefaultSize(
            hasActivePlaybackRequest: false,
            transitionIsActive: false,
            immersiveSpaceResidency: .closed
        ))
    }

    @Test("Dismissing active Window playback preserves its window size")
    func dismissingActiveWindowPlaybackPreservesWindowSize() {
        #expect(BrowserWindowGeometryPolicy.shouldRequestDefaultSize(
            hasActivePlaybackRequest: true,
            transitionIsActive: false,
            immersiveSpaceResidency: .closed
        ) == false)
    }

    @Test("An active presentation transition preserves the window size")
    func activePresentationTransitionPreservesWindowSize() {
        #expect(BrowserWindowGeometryPolicy.shouldRequestDefaultSize(
            hasActivePlaybackRequest: false,
            transitionIsActive: true,
            immersiveSpaceResidency: .closed
        ) == false)
    }

    @Test("An open immersive space preserves the window size")
    func openImmersiveSpacePreservesWindowSize() {
        #expect(BrowserWindowGeometryPolicy.shouldRequestDefaultSize(
            hasActivePlaybackRequest: false,
            transitionIsActive: false,
            immersiveSpaceResidency: .open
        ) == false)
    }

    @Test("The active-playback recovery browser preserves the window size")
    func activePlaybackRecoveryBrowserPreservesWindowSize() {
        let state = (
            hasActivePlaybackRequest: true,
            transitionIsActive: false,
            immersiveSpaceResidency: SpatialPlatformImmersiveSpaceResidency.closed
        )

        #expect(BrowserWindowSurfacePolicy.showsBrowser(
            hasActivePlaybackRequest: state.hasActivePlaybackRequest,
            transitionIsActive: state.transitionIsActive,
            immersiveSpaceResidency: state.immersiveSpaceResidency
        ))
        #expect(BrowserWindowGeometryPolicy.shouldRequestDefaultSize(
            hasActivePlaybackRequest: state.hasActivePlaybackRequest,
            transitionIsActive: state.transitionIsActive,
            immersiveSpaceResidency: state.immersiveSpaceResidency
        ) == false)
    }

    @Test("A missing system Immersive Space reconciles settled immersive playback")
    @MainActor
    func missingSystemImmersiveSpaceReconcilesSettledPlayback() throws {
        for presentation in [
            PlaybackPresentation.docked,
            .panorama
        ] {
            #expect(
                SpatialPlatformImmersiveSpaceReconciliationPolicy
                    .shouldRecordDisappearance(
                        immersiveSpaceResidency: .open,
                        presentation: presentation,
                        transitionIsActive: false,
                        hasPendingSpatialPlatformEffect: false,
                        hasConnectedImmersiveSpaceScene: false
                    )
            )
        }

        #expect(
            SpatialPlatformImmersiveSpaceReconciliationPolicy
                .shouldRecordDisappearance(
                    immersiveSpaceResidency: .open,
                    presentation: .docked,
                    transitionIsActive: false,
                    hasPendingSpatialPlatformEffect: false,
                    hasConnectedImmersiveSpaceScene: true
                ) == false
        )
        #expect(
            SpatialPlatformImmersiveSpaceReconciliationPolicy
                .shouldRecordDisappearance(
                    immersiveSpaceResidency: .open,
                    presentation: .docked,
                    transitionIsActive: true,
                    hasPendingSpatialPlatformEffect: false,
                    hasConnectedImmersiveSpaceScene: false
                ) == false
        )
        #expect(
            SpatialPlatformImmersiveSpaceReconciliationPolicy
                .shouldRecordDisappearance(
                    immersiveSpaceResidency: .open,
                    presentation: .docked,
                    transitionIsActive: false,
                    hasPendingSpatialPlatformEffect: true,
                    hasConnectedImmersiveSpaceScene: false
                ) == false
        )
        #expect(
            SpatialPlatformImmersiveSpaceReconciliationPolicy
                .shouldRecordDisappearance(
                    immersiveSpaceResidency: .open,
                    presentation: .window,
                    transitionIsActive: false,
                    hasPendingSpatialPlatformEffect: false,
                    hasConnectedImmersiveSpaceScene: false
                ) == false
        )
        #expect(
            SpatialPlatformImmersiveSpaceReconciliationPolicy
                .shouldRecordDisappearance(
                    immersiveSpaceResidency: .closed,
                    presentation: .docked,
                    transitionIsActive: false,
                    hasPendingSpatialPlatformEffect: false,
                    hasConnectedImmersiveSpaceScene: false
                ) == false
        )

        let playbackModel = try settledModel(in: .docked)
        let appModel = PlaybackSessionModel(playbackPresentationModel: playbackModel)
        let coordinator = SpatialPlatformEffectCoordinator(
            session: appModel,
            playbackRuntime: PlaybackRuntime(),
            playbackVideoEntityStore: PlaybackVideoEntityStore()
        )

        coordinator.reconcileImmersiveSpaceResidency(
            hasConnectedImmersiveSpaceScene: false
        )

        #expect(appModel.playbackPresentation == .window)
        #expect(appModel.immersiveSpaceResidency == .closed)
        #expect(appModel.presentationTransition == nil)
        #expect(appModel.pendingSpatialPlatformEffect == nil)
        #expect(BrowserWindowSurfacePolicy.showsBrowser(
            hasActivePlaybackRequest: true,
            transitionIsActive: false,
            immersiveSpaceResidency: appModel.immersiveSpaceResidency
        ))
    }

    @Test("Panorama tap shell follows 180 and 360 degree projection coverage")
    @MainActor
    func panoramaTapShellFollowsProjectionCoverage() {
        let surface = PlaybackPanoramaInteractionSurface.makeEntity()

        PlaybackPanoramaInteractionSurface.configure(
            surface,
            projection: .equirectangular180,
            horizontalFieldOfViewDegrees: 180
        )
        let frontNames = Set(surface.children.map(\.name))
        #expect(frontNames.count == 5)
        #expect(frontNames.contains("EnchronPanoramaInput.front"))
        #expect(frontNames.contains("EnchronPanoramaInput.back") == false)

        PlaybackPanoramaInteractionSurface.configure(
            surface,
            projection: .equirectangular360,
            horizontalFieldOfViewDegrees: 360
        )
        let fullNames = Set(surface.children.map(\.name))
        #expect(fullNames.count == 6)
        #expect(fullNames.contains("EnchronPanoramaInput.back"))
    }

    @Test("Panorama tap shell surrounds the eye positions a wearer can occupy")
    @MainActor
    func panoramaTapShellSurroundsWearerEyePositions() throws {
        for projection in [
            PlaybackModel.ProjectionType.equirectangular360,
            .equirectangular180
        ] {
            let surface = Entity()
            PlaybackPanoramaInteractionSurface.configure(
                surface,
                projection: projection,
                horizontalFieldOfViewDegrees:
                    projection == .equirectangular180 ? 180 : 360
            )
            var panelBounds: [BoundingBox] = []
            for panel in surface.children {
                let collision = try #require(panel.components[CollisionComponent.self])
                let shape = try #require(collision.shapes.first)
                panelBounds.append(
                    shape.bounds.transformed(
                        by: panel.transformMatrix(relativeTo: surface)
                    )
                )
            }
            let shellBounds = panelBounds.reduce(BoundingBox()) { $0.union($1) }

            for eyeHeight in [Float(0.9), 1.2, 1.7] {
                let eye = SIMD3<Float>(0, eyeHeight, 0)
                #expect(
                    shellBounds.contains(eye),
                    "\(projection) shell excludes an eye at \(eyeHeight)m"
                )
                for bounds in panelBounds {
                    #expect(
                        bounds.contains(eye) == false,
                        "\(projection) panel contains an eye at \(eyeHeight)m"
                    )
                }
            }
        }
    }

    @Test("Default docked placement lands on the authored surface anchor")
    @MainActor
    func defaultDockedPlacementLandsOnTheAuthoredAnchor() {
        let anchor = Entity()
        anchor.position = [
            0,
            0.9296054,
            -Float(PlaybackDockedPlacement.defaultDistance)
        ]
        let screen = Entity()

        PlaybackSurfacePlacement.dock(
            screen,
            to: anchor,
            transform: PlaybackSurfaceTransform(
                distance: PlaybackDockedPlacement.defaultDistance,
                elevationDegrees: PlaybackDockedPlacement.defaultElevationDegrees,
                scale: 1
            )
        )

        let placed = screen.position(relativeTo: nil)
        let authored = anchor.position(relativeTo: nil)
        #expect(abs(placed.x - authored.x) < 0.001)
        #expect(abs(placed.y - authored.y) < 0.001)
        #expect(abs(placed.z - authored.z) < 0.001)
    }

    @Test("Docked elevation swings the screen around the wearer's eye height")
    @MainActor
    func dockedElevationSwingsAroundTheWearerEyeHeight() {
        let anchor = Entity()
        anchor.position = [0, 0.9296054, -4]
        let screen = Entity()

        PlaybackSurfacePlacement.dock(
            screen,
            to: anchor,
            transform: PlaybackSurfaceTransform(
                distance: 4,
                elevationDegrees: 30,
                scale: 1
            )
        )

        let placed = screen.position(relativeTo: nil)
        #expect(abs(placed.y - (0.9296054 + 2)) < 0.001)
        #expect(abs(placed.z - -4 * cos(.pi / 6)) < 0.001)
    }

    @Test("A surface that never settles releases its wait instead of hanging")
    @MainActor
    func unsettledPresentationReleasesItsWait() async {
        let runtime = PlaybackRuntime()

        let settled = await runtime.waitUntilPresentationSettled(
            to: .panorama,
            allowsPendingSessionStart: true,
            deadline: .milliseconds(120)
        )

        #expect(settled == false)
    }

    #if DEBUG
    @Test("The settlement-timeout fault is consumed by exactly one wait")
    @MainActor
    func settlementTimeoutFaultIsOneShot() async {
        let runtime = PlaybackRuntime()
        runtime.debugArmPresentationSettlementFault(.timeout)

        #expect(runtime.debugPendingPresentationSettlementFault == .timeout)
        #expect(
            await runtime.waitUntilPresentationSettled(
                to: .panorama,
                allowsPendingSessionStart: true,
                deadline: .seconds(10)
            ) == false
        )
        #expect(runtime.debugPendingPresentationSettlementFault == nil)
    }
    #endif

    @Test("A confirmed source restoration rolls back instead of stopping playback")
    func confirmedPresentationRestorationUsesRollbackPolicy() {
        #expect(
            SpatialPlatformPresentationFailurePolicy.shouldStopPlayback(
                effect: .enterImmersivePlayback(.panoramic),
                recovery: .previousPresentationRestored
            ) == false
        )
        #expect(
            SpatialPlatformPresentationFailurePolicy.shouldStopPlayback(
                effect: .enterImmersivePlayback(.panoramic),
                recovery: .unavailable
            )
        )
    }

    @Test("An unreported immersive viewing mode is re-requested once it stalls")
    @MainActor
    func stalledImmersiveViewingModeIsRequestedAgain() {
        let retry = PlaybackModeRequestRetry()
        let entity = Entity()
        let start = Date()
        func action(at offset: TimeInterval) -> PlaybackModeRecoveryAction {
            retry.recoveryAction(
                entity: entity,
                presentation: .panorama,
                desiredImmersiveViewingMode: "progressive",
                actualImmersiveViewingMode: nil,
                desiredSpatialVideoMode: "stereo",
                actualSpatialVideoMode: "stereo",
                now: start.addingTimeInterval(offset)
            )
        }

        #expect(action(at: 0) == .none)
        #expect(action(at: 1) == .none)
        #expect(action(at: PlaybackModeRequestRetry.unreportedModeWindow - 0.5) == .none)
        #expect(action(at: PlaybackModeRequestRetry.unreportedModeWindow) == .requestModesAgain)
    }

    @Test("A mode reported before the stall window keeps the wait intact")
    @MainActor
    func reportedImmersiveViewingModeClearsTheStall() {
        let retry = PlaybackModeRequestRetry()
        let entity = Entity()
        let start = Date()

        #expect(
            retry.recoveryAction(
                entity: entity,
                presentation: .panorama,
                desiredImmersiveViewingMode: "progressive",
                actualImmersiveViewingMode: nil,
                desiredSpatialVideoMode: "stereo",
                actualSpatialVideoMode: "stereo",
                now: start
            ) == .none
        )
        #expect(
            retry.recoveryAction(
                entity: entity,
                presentation: .panorama,
                desiredImmersiveViewingMode: "progressive",
                actualImmersiveViewingMode: "progressive",
                desiredSpatialVideoMode: "stereo",
                actualSpatialVideoMode: "stereo",
                now: start.addingTimeInterval(1)
            ) == .none
        )
        #expect(
            retry.recoveryAction(
                entity: entity,
                presentation: .panorama,
                desiredImmersiveViewingMode: "progressive",
                actualImmersiveViewingMode: nil,
                desiredSpatialVideoMode: "stereo",
                actualSpatialVideoMode: "stereo",
                now: start.addingTimeInterval(1.5)
            ) == .none
        )
    }

    @Test("A persisted user format remains effective after source discovery")
    @MainActor
    func coldLaunchSourceDiscoveryPreservesUserOverride() {
        let runtime = PlaybackRuntime()

        runtime.publishEffectiveFormatAfterSourceDiscovery(
            MediaFormat(
                projection: .equirectangular180,
                stereoLayout: .sideBySide
            )
        )

        #expect(runtime.activeMediaFormatProvenance == .userOverride)
        #expect(runtime.effectiveProjectionType == .equirectangular180)
        #expect(runtime.effectiveStereoLayout == .sideBySide)
        #expect(runtime.effectiveMediaFormatInterpretation.source.contentKind == .rectilinear)
    }

    @Test(
        "Effective Media Format resolves only within the main-window column",
        arguments: [
            (
                true,
                PlaybackPresentation.window,
                EffectiveMediaFormatPresentationResolution.switchToPortal
            ),
            (true, .portal, .unchanged),
            (true, .docked, .unchanged),
            (true, .panorama, .unchanged),
            (false, .window, .unchanged),
            (false, .portal, .returnToWindow),
            (false, .docked, .unchanged),
            (false, .panorama, .unchanged)
        ]
    )
    func effectiveMediaFormatPresentationResolution(
        isPanoramic: Bool,
        presentation: PlaybackPresentation,
        expected: EffectiveMediaFormatPresentationResolution
    ) {
        let interpretation = MediaFormatInterpretationResolver.resolve(
            source: SourceMediaFormatFact(
                contentKind: isPanoramic ? .halfEquirectangular : .rectilinear,
                projection: isPanoramic ? .equirectangular180 : .flat,
                stereoLayout: .mono
            ),
            override: nil
        )

        #expect(
            EffectiveMediaFormatPresentationResolver.resolve(
                interpretation,
                from: presentation
            ) == expected
        )
    }

    @Test(
        "Panel format editor follows the main-window presentation column",
        arguments: [
            (PlaybackPresentation.window, true),
            (.portal, true),
            (.docked, false),
            (.panorama, false)
        ]
    )
    func panelFormatEditorFollowsTheMainWindowPresentationColumn(
        presentation: PlaybackPresentation,
        expected: Bool
    ) {
        #expect(
            PlaybackPanelSettingsPolicy.showsVideoFormatEditor(
                for: presentation
            ) == expected
        )
    }

    @Test("Immersive panel settings collapse to Docked placement controls")
    func immersivePanelSettingsCollapseToDockedPlacementControls() {
        #expect(
            PlaybackPanelSettingsPolicy.showsVideoFormatEditor(for: .docked)
                == false
        )
        #expect(PlaybackPanelSettingsPolicy.showsPlacementControls(for: .docked))
        #expect(PlaybackPanelSettingsPolicy.settingsAreAvailable(for: .docked))

        #expect(
            PlaybackPanelSettingsPolicy.showsVideoFormatEditor(for: .panorama)
                == false
        )
        #expect(
            PlaybackPanelSettingsPolicy.showsPlacementControls(for: .panorama)
                == false
        )
        #expect(
            PlaybackPanelSettingsPolicy.settingsAreAvailable(for: .panorama)
                == false
        )
    }

    @Test("Applying Media Format selects a main-window presentation")
    func appliedMediaFormatSelectsMainWindowPresentation() {
        #expect(
            PlaybackPresentationAvailability.presentation(afterApplying: .standard)
                == .window
        )
        #expect(
            PlaybackPresentationAvailability.presentation(
                afterApplying: MediaFormat(
                    projection: .equirectangular180,
                    stereoLayout: .mono
                )
            ) == .portal
        )
    }

    @Test("A persisted panoramic family cold launch lands in Portal")
    @MainActor
    func persistedPanoramicFamilyColdLaunchLandsInPortal() throws {
        let application = EnchronApplication(environment: [:])
        let startEntry = try #require(
            application.playbackLauncher.onPlaybackModeEntryStarted
        )

        let deliveredMode = startEntry(.panorama, true)

        #expect(deliveredMode == .panorama)
        #expect(application.playbackSessionModel.playbackPresentation == .portal)
        #expect(application.playbackSessionModel.presentationTransition == nil)
        #expect(application.playbackSessionModel.pendingSpatialPlatformEffect == nil)
    }

    @Test("Presentation settlement belongs to the replacement technical session")
    func presentationSettlementUsesTechnicalSessionIdentity() {
        let record = PresentationStateRecord(
            mediaSessionID: "technical-session-b",
            requestedMode: PlaybackPresentation.panorama.rawValue,
            phase: PlaybackPresentationSettlementPhase.settled.rawValue,
            platform: "visionOS",
            displayedPixelBuffer: true
        )

        #expect(
            PlaybackRuntime.presentationTransitionCanCommit(
                record: record,
                presentation: .panorama,
                activeTechnicalSessionID: "technical-session-b",
                lifecycle: .paused
            )
        )
        #expect(
            PlaybackRuntime.presentationTransitionCanCommit(
                record: record,
                presentation: .panorama,
                activeTechnicalSessionID: "technical-session-b",
                lifecycle: .ended
            )
        )
        #expect(
            !PlaybackRuntime.presentationTransitionCanCommit(
                record: record,
                presentation: .panorama,
                activeTechnicalSessionID: "logical-session-a",
                lifecycle: .paused
            )
        )

        let attachedOnlyRecord = PresentationStateRecord(
            mediaSessionID: "technical-session-b",
            requestedMode: PlaybackPresentation.portal.rawValue,
            phase: PlaybackPresentationSettlementPhase.surfaceAttached.rawValue,
            platform: "visionOS"
        )
        #expect(
            !PlaybackRuntime.presentationTransitionCanCommit(
                record: attachedOnlyRecord,
                presentation: .portal,
                activeTechnicalSessionID: "technical-session-b",
                lifecycle: .ended
            )
        )

        let missingPixelRecord = PresentationStateRecord(
            mediaSessionID: "technical-session-b",
            requestedMode: PlaybackPresentation.panorama.rawValue,
            phase: PlaybackPresentationSettlementPhase.settled.rawValue,
            platform: "visionOS",
            displayedPixelBuffer: false
        )
        #expect(
            !PlaybackRuntime.presentationTransitionCanCommit(
                record: missingPixelRecord,
                presentation: .panorama,
                activeTechnicalSessionID: "technical-session-b",
                lifecycle: .ended
            )
        )
    }

    @Test("Window surface cutover requires the current technical session, component, and stream")
    func windowSurfaceCutoverUsesExactPixelIdentity() {
        let record = PresentationStateRecord(
            mediaSessionID: "technical-session-b",
            requestedMode: PlaybackPresentation.portal.rawValue,
            phase: PlaybackPresentationSettlementPhase.settled.rawValue,
            platform: "visionOS",
            displayedPixelBuffer: true
        )
        func accepts(
            technicalSessionID: String? = "technical-session-b",
            componentRevision: UInt64 = 7,
            streamEpoch: UInt64? = 11
        ) -> Bool {
            PlaybackRuntime.presentationSurfacePixelIdentityIsCurrent(
                record: record,
                presentation: .portal,
                reported: PlaybackPresentationSurfacePixelIdentity(
                    technicalSessionID: technicalSessionID,
                    videoComponentRevision: componentRevision,
                    streamEpoch: streamEpoch
                ),
                current: PlaybackPresentationSurfacePixelIdentity(
                    technicalSessionID: "technical-session-b",
                    videoComponentRevision: 7,
                    streamEpoch: 11
                ),
                lifecycle: .playing
            )
        }

        #expect(accepts())
        #expect(accepts(technicalSessionID: "technical-session-a") == false)
        #expect(accepts(componentRevision: 6) == false)
        #expect(accepts(streamEpoch: 10) == false)
    }

    @Test("Portal-to-Panorama pixel-proof reveal is readiness gated and identity scoped")
    func portalToPanoramaPixelProofRevealIsReadinessGatedAndIdentityScoped() throws {
        func readiness(
            componentIsReady: Bool = true,
            immersiveModeMatches: Bool = true,
            projectionIsAdopted: Bool = true,
            viewingModeMatches: Bool = true,
            spatialModeMatches: Bool = true,
            displayedPixelBuffer: Bool = false
        ) -> SpatialPresentationReadiness {
            SpatialPresentationReadiness(
                componentIsReady: componentIsReady,
                immersiveModeMatches: immersiveModeMatches,
                projectionIsAdopted: projectionIsAdopted,
                viewingModeMatches: viewingModeMatches,
                spatialModeMatches: spatialModeMatches,
                displayedPixelBuffer: displayedPixelBuffer
            )
        }

        func revealTarget(
            transition: PlaybackPresentationTransition,
            technicalSessionID: String = "technical-session",
            videoComponentRevision: UInt64 = 7,
            entityID: String = "panorama-entity"
        ) throws -> PortalToPanoramaRevealTarget {
            try #require(
                PortalToPanoramaRevealTarget(
                    transition: transition,
                    technicalSessionID: technicalSessionID,
                    videoComponentRevision: videoComponentRevision,
                    entityID: entityID
                )
            )
        }

        let transition = PlaybackPresentationTransition(
            previousPresentation: .portal,
            targetPresentation: .panorama,
            previousEnvironment: .none,
            targetEnvironment: .none
        )
        let target = try revealTarget(transition: transition)
        let nonPixelReadinessFailures = [
            readiness(componentIsReady: false),
            readiness(immersiveModeMatches: false),
            readiness(projectionIsAdopted: false),
            readiness(viewingModeMatches: false),
            readiness(spatialModeMatches: false)
        ]

        for incompleteReadiness in nonPixelReadinessFailures {
            var revealState = PortalToPanoramaTargetRevealState()
            #expect(incompleteReadiness.isReadyToRevealForPixelProof == false)
            #expect(incompleteReadiness.isSettled == false)
            #expect(revealState.admit(target, when: incompleteReadiness) == false)
        }

        let readyWithoutPixels = readiness()
        var revealState = PortalToPanoramaTargetRevealState()
        #expect(readyWithoutPixels.isReadyToRevealForPixelProof)
        #expect(readyWithoutPixels.isSettled == false)
        let firstAdmission = revealState.admit(target, when: readyWithoutPixels)
        #expect(firstAdmission)
        #expect(
            revealState.opacity(
                for: target,
                otherwise: PlaybackPresentationTransitionAppearance
                    .targetPreparationOpacity
            ) == 1
        )
        let repeatedAdmission = revealState.admit(target, when: readyWithoutPixels)
        #expect(repeatedAdmission == false)
        #expect(
            revealState.opacity(
                for: target,
                otherwise: PlaybackPresentationTransitionAppearance
                    .targetPreparationOpacity
            ) == 1
        )

        let readyWithPixels = readiness(displayedPixelBuffer: true)
        #expect(readyWithPixels.isReadyToRevealForPixelProof == false)
        #expect(readyWithPixels.isSettled)

        let anotherTransition = PlaybackPresentationTransition(
            previousPresentation: .portal,
            targetPresentation: .panorama,
            previousEnvironment: .none,
            targetEnvironment: .none
        )
        let identityChanges = try [
            revealTarget(transition: anotherTransition),
            revealTarget(
                transition: transition,
                technicalSessionID: "replacement-technical-session"
            ),
            revealTarget(
                transition: transition,
                videoComponentRevision: 8
            ),
            revealTarget(
                transition: transition,
                entityID: "replacement-panorama-entity"
            )
        ]

        for currentTarget in identityChanges {
            #expect(currentTarget != target)
            #expect(
                revealState.opacity(
                    for: currentTarget,
                    otherwise: PlaybackPresentationTransitionAppearance
                        .targetPreparationOpacity
                ) == PlaybackPresentationTransitionAppearance.targetPreparationOpacity
            )
        }

        let nonPortalToPanoramaTransition = PlaybackPresentationTransition(
            previousPresentation: .window,
            targetPresentation: .docked,
            previousEnvironment: .none,
            targetEnvironment: .none
        )
        #expect(
            PortalToPanoramaRevealTarget(
                transition: nonPortalToPanoramaTransition,
                technicalSessionID: "technical-session",
                videoComponentRevision: 7,
                entityID: "panorama-entity"
            ) == nil
        )
    }

    @Test("Spatial first-frame update drive stops only for current pixels or lost viability")
    func spatialFirstFrameUpdateDriveUsesCurrentRendererPixels() {
        #expect(
            SpatialFirstFrameUpdateDrivePolicy.decide(
                surfaceCanStillSettle: true,
                currentRendererHasPixels: false
            ) == .requestUpdate
        )
        #expect(
            SpatialFirstFrameUpdateDrivePolicy.decide(
                surfaceCanStillSettle: true,
                currentRendererHasPixels: true
            ) == .firstFrameArrived
        )
        #expect(
            SpatialFirstFrameUpdateDrivePolicy.decide(
                surfaceCanStillSettle: false,
                currentRendererHasPixels: false
            ) == .surfaceNoLongerViable
        )
    }

    @Test("Portal preserves spatial depth while flat Window remains planar")
    func portalRealityViewHasProjectedMediaDepth() {
        #expect(
            WindowPlaybackSurfaceGeometry.realityViewDepth(for: .window)
                == WindowPlaybackSurfaceGeometry.flatWindowDepth
        )
        #expect(
            WindowPlaybackSurfaceGeometry.realityViewDepth(for: .portal)
                == WindowPlaybackSurfaceGeometry.projectedPortalDepth
        )
        #expect(WindowPlaybackSurfaceGeometry.projectedPortalDepth > 0)
    }

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
                sourceContentKind: .rectilinear,
                provenance: .userOverride,
                observedContentType: "equirectangular"
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .equirectangular180,
                sourceContentKind: .rectilinear,
                provenance: .userOverride,
                observedContentType: "halfEquirectangular"
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .customAngle,
                sourceContentKind: .rectilinear,
                provenance: .userOverride,
                observedContentType: "equirectangular"
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .equirectangular360,
                sourceContentKind: .rectilinear,
                provenance: .userOverride,
                observedContentType: "invalid"
            ) == false
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .equirectangular360,
                sourceContentKind: .rectilinear,
                provenance: .userOverride,
                observedContentType: "unobserved"
            ) == false
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .equirectangular360,
                sourceContentKind: .rectilinear,
                provenance: .userOverride,
                observedContentType: "halfEquirectangular"
            ) == false
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .flat,
                sourceContentKind: .parametricImmersive,
                provenance: .source,
                observedContentType: "parametricImmersive"
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .flat,
                sourceContentKind: .appleImmersiveVideo,
                provenance: .source,
                observedContentType: "immersive"
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: .flat,
                sourceContentKind: .appleImmersiveVideo,
                provenance: .source,
                observedContentType: "mono"
            ) == false
        )
    }

    @Test("An explicit override can settle from renderer signaling and actual RealityKit modes")
    func explicitPanoramaOverrideUsesAdoptionProofWhenContentTypeIsNotReplayed() {
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy
                .explicitOverrideAdoptionIsConfirmed(
                    projection: .equirectangular180,
                    stereoLayout: .sideBySide,
                    provenance: .userOverride,
                    acceptedRendererProjectionKind: "HalfEquirectangular",
                    desiredImmersiveViewingMode: "progressive",
                    observedImmersiveViewingMode: "progressive",
                    observedViewingMode: "stereo"
                )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy
                .explicitOverrideAdoptionIsConfirmed(
                    projection: .equirectangular180,
                    stereoLayout: .sideBySide,
                    provenance: .source,
                    acceptedRendererProjectionKind: "HalfEquirectangular",
                    desiredImmersiveViewingMode: "progressive",
                    observedImmersiveViewingMode: "progressive",
                    observedViewingMode: "stereo"
                ) == false
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy
                .explicitOverrideAdoptionIsConfirmed(
                    projection: .equirectangular180,
                    stereoLayout: .sideBySide,
                    provenance: .userOverride,
                    acceptedRendererProjectionKind: "Equirectangular",
                    desiredImmersiveViewingMode: "progressive",
                    observedImmersiveViewingMode: "progressive",
                    observedViewingMode: "stereo"
                ) == false
        )
    }

    @Test("Panorama returns to Portal and Portal expands back to Panorama")
    func panoramaAndPortalAreExplicitPresentations() throws {
        let model = PlaybackPresentationModel()
        let context = SpatialPlaybackTransitionContext(
            mediaSessionID: "portal-test-session",
            wasPlaying: true
        )
        model.prepareColdPlaybackLaunch(for: .panoramic)

        _ = try model.requestPresentation(.panorama, playbackContext: context)
        _ = try completePendingEffect(model)
        _ = try model.requestPresentation(.portal, playbackContext: context)
        #expect(
            model.pendingSpatialPlatformEffect?.effect
                == .exitImmersivePlayback(
                    .panoramic,
                    keepsEnvironmentOpen: false
                )
        )
        _ = try completePendingEffect(model)
        #expect(model.presentation == .portal)

        _ = try model.requestPresentation(.panorama, playbackContext: context)
        #expect(
            model.pendingSpatialPlatformEffect?.effect
                == .enterImmersivePlayback(.panoramic)
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
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: .multiview,
                observedViewingMode: "stereo"
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: .multiview,
                observedViewingMode: "mono"
            ) == false
        )
    }

    @Test("Flat Window does not require immersive mode confirmation")
    func flatWindowImmersiveModeSettlement() {
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.immersiveViewingModeMatches(
                contentIsPanoramic: false,
                requiresTransitionConfirmation: true,
                desiredImmersiveViewingMode: "portal",
                observedImmersiveViewingMode: nil
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.immersiveViewingModeMatches(
                contentIsPanoramic: true,
                requiresTransitionConfirmation: true,
                desiredImmersiveViewingMode: "portal",
                observedImmersiveViewingMode: nil
            ) == false
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.immersiveViewingModeMatches(
                contentIsPanoramic: true,
                requiresTransitionConfirmation: true,
                desiredImmersiveViewingMode: "portal",
                observedImmersiveViewingMode: "portal"
            )
        )
        #expect(
            SpatialPlaybackSurfaceSettlementPolicy.immersiveViewingModeMatches(
                contentIsPanoramic: true,
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

    @Test("Panorama return to Portal restores the Environment immersion amount")
    @MainActor
    func panoramaReturnRestoresEnvironmentImmersionAmount() throws {
        let appModel = PlaybackSessionModel()
        appModel.prepareColdPlaybackLaunch(for: .panoramic)
        appModel.recordImmersionAmount(0.62)
        try appModel.activateEnvironment(.scenicOne, effect: .dark)

        _ = try appModel.requestPlaybackPresentation(
            .panorama,
            mediaSessionID: "test-media-session",
            wasPlaying: true
        )
        _ = try completePendingEffect(appModel)
        appModel.recordImmersionAmount(0.41)

        _ = try appModel.requestPlaybackPresentation(
            .portal,
            mediaSessionID: "test-media-session",
            wasPlaying: true
        )
        _ = try completePendingEffect(appModel)

        #expect(appModel.playbackPresentation == .portal)
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
                sourceRendererMayRelease: false,
                targetRendererMayBind: false
            )
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: .window,
                targetPresentation: .panorama,
                sourceRendererMayRelease: true,
                targetRendererMayBind: false
            ) == false
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: .window,
                targetPresentation: .docked,
                sourceRendererMayRelease: false,
                targetRendererMayBind: false
            )
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: .window,
                targetPresentation: .docked,
                sourceRendererMayRelease: true,
                targetRendererMayBind: false
            ) == false
        )
    }

    @Test("Portal-to-Panorama gates binding and visible cutover in order")
    @MainActor
    func portalToPanoramaGatesReplacementTargetAfterSourceRelease() throws {
        let appModel = PlaybackSessionModel()
        appModel.prepareColdPlaybackLaunch(for: .panoramic)
        appModel.showControls = true

        _ = try appModel.requestPlaybackPresentation(
            .panorama,
            mediaSessionID: "test-media-session",
            wasPlaying: true
        )

        #expect(
            appModel.pendingSpatialPlatformEffect?.effect
                == .enterImmersivePlayback(.panoramic)
        )
        #expect(appModel.presentationSourceRendererMayRelease == false)
        #expect(appModel.presentationTargetRendererMayBind == false)
        #expect(appModel.presentationVisualCutoverMayBegin == false)
        #expect(appModel.beginPresentationVisualCutover() == false)
        #expect(appModel.allowPresentationTargetRendererBinding() == false)
        #expect(appModel.allowPresentationSourceRendererRelease())
        #expect(appModel.presentationTargetRendererMayBind == false)
        #expect(appModel.allowPresentationTargetRendererBinding())
        #expect(appModel.presentationVisualCutoverMayBegin == false)
        #expect(appModel.showControls)
        #expect(appModel.beginPresentationVisualCutover())
        #expect(appModel.presentationVisualCutoverMayBegin)
        #expect(appModel.showControls)
        appModel.finishPresentationVisualCutover()
        #expect(appModel.showControls == false)
    }

    @Test("Docked Environment Card initializes the same transition timing gates")
    @MainActor
    func dockedEnvironmentCardInitializesTransitionAppearance() throws {
        let appModel = PlaybackSessionModel(
            playbackPresentationModel: try settledModel(in: .docked)
        )

        #expect(
            try appModel.requestEnvironmentCard(
                mediaSessionID: "test-media-session",
                wasPlaying: true
            )
        )
        #expect(appModel.presentationTransition?.targetPresentation == .window)
        #expect(
            appModel.presentationTransitionRemainingTime(
                until: PlaybackPresentationTransitionAppearance.sourceFadeDuration
            ) != nil
        )
        #expect(appModel.presentationSourceRendererMayRelease == false)
        #expect(appModel.presentationTargetRendererMayBind == false)
        #expect(appModel.presentationVisualCutoverMayBegin == false)
    }

    @Test("A Window target waits for the departing spatial surface to release the renderer")
    func windowTargetWaitsForSpatialRendererRelease() {
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: .panorama,
                targetPresentation: .window,
                sourceRendererMayRelease: false,
                targetRendererMayBind: false
            ) == false
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: .panorama,
                targetPresentation: .window,
                sourceRendererMayRelease: true,
                targetRendererMayBind: false
            ) == false
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: .panorama,
                targetPresentation: .window,
                sourceRendererMayRelease: true,
                targetRendererMayBind: true
            )
        )
    }

    @Test("Portal and Panorama bind the replacement renderer only after source release")
    func portalAndPanoramaBindReplacementAcrossRealityViewRoots() {
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .portal,
                previousPresentation: .portal,
                targetPresentation: .panorama,
                sourceRendererMayRelease: false,
                targetRendererMayBind: false
            )
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .panorama,
                previousPresentation: .portal,
                targetPresentation: .panorama,
                sourceRendererMayRelease: false,
                targetRendererMayBind: false
            ) == false
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .portal,
                previousPresentation: .portal,
                targetPresentation: .panorama,
                sourceRendererMayRelease: true,
                targetRendererMayBind: false
            ) == false
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .panorama,
                previousPresentation: .portal,
                targetPresentation: .panorama,
                sourceRendererMayRelease: true,
                targetRendererMayBind: true
            )
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .portal,
                previousPresentation: .panorama,
                targetPresentation: .portal,
                sourceRendererMayRelease: false,
                targetRendererMayBind: false
            ) == false
        )
        #expect(
            PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .portal,
                previousPresentation: .panorama,
                targetPresentation: .portal,
                sourceRendererMayRelease: true,
                targetRendererMayBind: true
            )
        )
    }

    @Test("Window and Portal keep binding the same main-window RealityView")
    func windowAndPortalNeverTransferAcrossRoots() {
        for sourceRendererMayRelease in [false, true] {
            #expect(
                PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                    for: .window,
                    previousPresentation: .window,
                    targetPresentation: .portal,
                    sourceRendererMayRelease: sourceRendererMayRelease,
                    targetRendererMayBind: false
                )
            )
            #expect(
                PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                    for: .portal,
                    previousPresentation: .window,
                    targetPresentation: .portal,
                    sourceRendererMayRelease: sourceRendererMayRelease,
                    targetRendererMayBind: false
                )
            )
        }
    }

    @Test("Presentation transition does not show the media loading spinner")
    func presentationTransitionDoesNotShowLoadingSpinner() {
        #expect(
            WindowPlaybackLoadingVisibility.shouldShow(
                hasPlaybackError: false,
                loadingVisibility: .loading,
                isPresentationTransitionActive: true
            ) == false
        )
        #expect(
            WindowPlaybackLoadingVisibility.shouldShow(
                hasPlaybackError: false,
                loadingVisibility: .loading,
                isPresentationTransitionActive: false
            )
        )
        #expect(
            WindowPlaybackLoadingVisibility.shouldShow(
                hasPlaybackError: false,
                loadingVisibility: .none,
                isPresentationTransitionActive: false
            ) == false
        )
        #expect(
            WindowPlaybackLoadingVisibility.shouldShow(
                hasPlaybackError: true,
                loadingVisibility: .loading,
                isPresentationTransitionActive: false
            ) == false
        )
    }

    @Test("Presentation transition keeps source visible until the visual cutover")
    func presentationTransitionKeepsSourceVisibleUntilVisualCutover() {
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
                transition: transition,
                visualCutoverMayBegin: false
            ) == 1
        )
        #expect(
            PlaybackPresentationTransitionAppearance.windowVideoEntityOpacity(
                for: .window,
                settledPresentation: .window,
                transition: transition,
                visualCutoverMayBegin: true
            ) == 1
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
                transition: transition,
                visualCutoverMayBegin: false
            ) == PlaybackPresentationTransitionAppearance.targetPreparationOpacity
        )
        #expect(
            PlaybackPresentationTransitionAppearance.opacity(
                for: .window,
                settledPresentation: .window,
                transition: transition,
                visualCutoverMayBegin: true
            ) == 0
        )
        #expect(
            PlaybackPresentationTransitionAppearance.opacity(
                for: .panorama,
                settledPresentation: .window,
                transition: transition,
                visualCutoverMayBegin: true
            ) == 1
        )
        #expect(
            PlaybackPresentationTransitionAppearance.windowSceneHostOpacity(
                for: .window,
                settledPresentation: .panorama,
                transition: .init(
                    previousPresentation: .panorama,
                    targetPresentation: .window,
                    previousEnvironment: .none,
                    targetEnvironment: .none
                )
            ) == 1
        )
        #expect(
            PlaybackPresentationTransitionAppearance.shouldAnimateWindowVideoEntity(
                transition: .init(
                    previousPresentation: .panorama,
                    targetPresentation: .portal,
                    previousEnvironment: .none,
                    targetEnvironment: .none
                ),
                visualCutoverMayBegin: true
            ) == false
        )
        #expect(
            PlaybackPresentationTransitionAppearance.shouldAnimateWindowVideoEntity(
                transition: transition,
                visualCutoverMayBegin: true
            )
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

    @Test("progress track clicks map the scrubber travel to seek targets")
    func progressTrackClicksMapToSeekTargets() {
        let travelWidth: CGFloat = 660
        let thumbDiameter: CGFloat = 20

        #expect(
            PlaybackSeekPresentation.target(
                at: 10,
                travelWidth: travelWidth,
                thumbDiameter: thumbDiameter
            ) == 0
        )
        #expect(
            PlaybackSeekPresentation.target(
                at: 340,
                travelWidth: travelWidth,
                thumbDiameter: thumbDiameter
            ) == 0.5
        )
        #expect(
            PlaybackSeekPresentation.target(
                at: 670,
                travelWidth: travelWidth,
                thumbDiameter: thumbDiameter
            ) == 1
        )
        #expect(
            PlaybackSeekPresentation.target(
                at: -40,
                travelWidth: travelWidth,
                thumbDiameter: thumbDiameter
            ) == 0
        )
        #expect(
            PlaybackSeekPresentation.target(
                at: 720,
                travelWidth: travelWidth,
                thumbDiameter: thumbDiameter
            ) == 1
        )
    }

    @Test("environment card reveal motion stays within the approved range")
    func environmentCardRevealMotionContract() {
        #expect(EnvironmentCardRevealMotion.initialScale == 0.985)
        #expect((0.22...0.32).contains(EnvironmentCardRevealMotion.standardDuration))
        #expect((0.10...0.15).contains(EnvironmentCardRevealMotion.crossFadeDuration))
    }

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

    @Test("Resident Window observations are independent from the Main Window")
    func residentWindowObservationsAreIndependentFromMainWindow() {
        var observation = SpatialPlatformWindowObservation()

        observation.record(.open, for: .main)

        #expect(observation.residency(for: .immersivePlaybackResident) == nil)
        #expect(observation.revision(for: .immersivePlaybackResident) == 0)

        observation.record(.open, for: .immersivePlaybackResident)

        #expect(observation.residency(for: .immersivePlaybackResident) == .open)
        #expect(observation.revision(for: .immersivePlaybackResident) == 1)
        #expect(observation.residency(for: .main) == .open)
        #expect(observation.revision(for: .main) == 1)

        observation.record(.closed, for: .immersivePlaybackResident)

        #expect(
            observation.residency(for: .immersivePlaybackResident) == .closed
        )
        #expect(observation.revision(for: .immersivePlaybackResident) == 2)
        #expect(observation.residency(for: .main) == .open)
        #expect(observation.revision(for: .main) == 1)
    }

    @Test("Immersive Space lifecycle revision changes only for appearance events")
    @MainActor
    func immersiveSpaceLifecycleRevisionTracksAppearanceEvents() {
        let appModel = PlaybackSessionModel()

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
        model.prepareColdPlaybackLaunch(for: .panoramic)
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

    @Test("an active platform execution adopts the new scene root's actions")
    @MainActor
    func activeExecutionAdoptsNewSceneActions() throws {
        var registry = SpatialPlatformExecutionLeaseRegistry<String>()
        let firstRootID = UUID()
        let secondRootID = UUID()
        let requestID = UUID()

        registry.register("first-root", id: firstRootID)
        let firstClaimValue = registry.claim(requestID: requestID, mediaSessionID: nil)
        let firstClaim = try #require(firstClaimValue)

        #expect(registry.unregister(id: firstRootID) == nil)
        #expect(registry.registeredCapabilityCount == 0)
        #expect(registry.isLive(firstClaim.lease))

        registry.register("second-root", id: secondRootID)
        #expect(registry.registeredCapabilityCount == 1)
        #expect(registry.currentCapability == "second-root")
        #expect(registry.isLive(firstClaim.lease))
        #expect(registry.claim(requestID: requestID, mediaSessionID: nil) == nil)

        registry.finish(firstClaim.lease)
        #expect(!registry.isLive(firstClaim.lease))
        let secondClaimValue = registry.claim(requestID: requestID, mediaSessionID: nil)
        let secondClaim = try #require(secondClaimValue)
        #expect(secondClaim.capability == "second-root")
        #expect(secondClaim.lease.executionID != firstClaim.lease.executionID)
    }

    @Test("the same scene identity refreshes actions without restarting its execution")
    @MainActor
    func sameSceneIdentityRefreshPreservesActiveExecution() throws {
        var registry = SpatialPlatformExecutionLeaseRegistry<String>()
        let residentRootID = UUID()
        let requestID = UUID()

        registry.register(
            "resident-actions-before-refresh",
            id: residentRootID,
            makePreferred: true
        )
        let originalClaimValue = registry.claim(requestID: requestID, mediaSessionID: nil)
        let originalClaim = try #require(originalClaimValue)

        #expect(registry.unregister(id: residentRootID) == nil)
        #expect(registry.registeredCapabilityCount == 0)
        #expect(
            registry.register(
                "resident-actions-after-refresh",
                id: residentRootID,
                makePreferred: true
            ) == nil
        )

        #expect(registry.registeredCapabilityCount == 1)
        #expect(registry.currentCapability == "resident-actions-after-refresh")
        #expect(registry.isLive(originalClaim.lease))
        #expect(registry.claim(requestID: requestID, mediaSessionID: nil) == nil)

        registry.finish(originalClaim.lease)
        let nextClaimValue = registry.claim(requestID: UUID(), mediaSessionID: nil)
        let nextClaim = try #require(nextClaimValue)
        #expect(nextClaim.capability == "resident-actions-after-refresh")
        #expect(nextClaim.lease.executionID != originalClaim.lease.executionID)
    }

    @Test("an abandoned request waits for an external change before draining again")
    func abandonedRequestDoesNotImmediatelyReclaimItself() {
        let requestID = UUID()

        #expect(
            SpatialPlatformExecutionDrainPolicy.shouldDrainAfterFinish(
                executedRequestID: requestID,
                pendingRequestID: requestID
            ) == false
        )
        #expect(
            SpatialPlatformExecutionDrainPolicy.shouldDrainAfterFinish(
                executedRequestID: requestID,
                pendingRequestID: nil
            ) == false
        )
        #expect(
            SpatialPlatformExecutionDrainPolicy.shouldDrainAfterFinish(
                executedRequestID: requestID,
                pendingRequestID: UUID()
            )
        )
    }

    @Test("a pushed Window can become the preferred platform action source")
    @MainActor
    func pushedWindowBecomesPreferredPlatformActionSource() throws {
        var registry = SpatialPlatformExecutionLeaseRegistry<String>()
        let mainRootID = UUID()
        let immersiveRootID = UUID()
        let residentRootID = UUID()
        let requestID = UUID()

        registry.register("main-root", id: mainRootID)
        let mainClaimValue = registry.claim(
            requestID: requestID,
            mediaSessionID: nil
        )
        let mainClaim = try #require(mainClaimValue)

        registry.register("immersive-root", id: immersiveRootID)
        registry.register(
            "resident-root",
            id: residentRootID,
            makePreferred: true
        )

        #expect(registry.currentCapability == "resident-root")
        #expect(registry.isLive(mainClaim.lease))

        registry.unregister(
            id: residentRootID,
            preferredFallbackID: mainRootID
        )

        #expect(registry.currentCapability == "main-root")
        #expect(registry.isLive(mainClaim.lease))
    }

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
            (.frameStep, .ended, .pause)
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
                .ended
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

    @Test("Every ordered pair produces its exact effect or rejection")
    @MainActor
    func everyOrderedPairProducesItsExactEffectOrRejection() throws {
        let cases: [PresentationRequestCase] = [
            .init(source: .window, target: .window, effect: nil, error: .alreadyPresented),
            .init(
                source: .window,
                target: .docked,
                effect: .enterImmersivePlayback(.flat),
                error: nil
            ),
            .init(
                source: .window,
                target: .portal,
                effect: .swapWindowPlaybackProjection(to: .panoramic),
                error: nil
            ),
            .init(
                source: .window,
                target: .panorama,
                effect: nil,
                error: .illegalEdge(source: .window, target: .panorama)
            ),
            .init(
                source: .docked,
                target: .window,
                effect: .exitImmersivePlayback(.flat, keepsEnvironmentOpen: false),
                error: nil
            ),
            .init(source: .docked, target: .docked, effect: nil, error: .alreadyPresented),
            .init(
                source: .docked,
                target: .portal,
                effect: nil,
                error: .illegalEdge(source: .docked, target: .portal)
            ),
            .init(
                source: .docked,
                target: .panorama,
                effect: nil,
                error: .illegalEdge(source: .docked, target: .panorama)
            ),
            .init(
                source: .portal,
                target: .window,
                effect: .swapWindowPlaybackProjection(to: .flat),
                error: nil
            ),
            .init(
                source: .portal,
                target: .docked,
                effect: nil,
                error: .illegalEdge(source: .portal, target: .docked)
            ),
            .init(source: .portal, target: .portal, effect: nil, error: .alreadyPresented),
            .init(
                source: .portal,
                target: .panorama,
                effect: .enterImmersivePlayback(.panoramic),
                error: nil
            ),
            .init(
                source: .panorama,
                target: .window,
                effect: nil,
                error: .illegalEdge(source: .panorama, target: .window)
            ),
            .init(
                source: .panorama,
                target: .docked,
                effect: nil,
                error: .illegalEdge(source: .panorama, target: .docked)
            ),
            .init(
                source: .panorama,
                target: .portal,
                effect: .exitImmersivePlayback(.panoramic, keepsEnvironmentOpen: false),
                error: nil
            ),
            .init(source: .panorama, target: .panorama, effect: nil, error: .alreadyPresented)
        ]

        for testCase in cases {
            let mediaSessionID = "\(testCase.source.rawValue)-to-\(testCase.target.rawValue)"
            let model = try settledModel(in: testCase.source)

            do {
                let transition = try model.requestPresentation(
                    testCase.target,
                    playbackContext: playingContext(mediaSessionID: mediaSessionID)
                )
                #expect(testCase.error == nil)
                #expect(transition.previousPresentation == testCase.source)
                #expect(transition.targetPresentation == testCase.target)
                #expect(model.pendingSpatialPlatformEffect?.effect == testCase.effect)
                #expect(model.pendingSpatialPlatformEffect?.playbackTransportPlan?.beforeEffect == nil)
                #expect(
                    model.pendingSpatialPlatformEffect?.playbackTransportPlan?.afterSuccess
                        == .resume(mediaSessionID: mediaSessionID)
                )
                #expect(model.pendingSpatialPlatformEffect?.playbackTransportPlan?.afterFailure == nil)
            } catch let error as PlaybackPresentationTransitionError {
                #expect(error == testCase.error)
                #expect(testCase.effect == nil)
                #expect(model.presentation == testCase.source)
                #expect(model.transition == nil)
                #expect(model.pendingSpatialPlatformEffect == nil)
            }
        }
    }

    @Test("Paused legal requests carry no resume action")
    @MainActor
    func pausedLegalRequestsCarryNoResumeAction() throws {
        let cases: [(source: PlaybackPresentation, target: PlaybackPresentation)] = [
            (.window, .docked),
            (.docked, .window),
            (.window, .portal),
            (.portal, .window),
            (.portal, .panorama),
            (.panorama, .portal)
        ]

        for testCase in cases {
            let model = try settledModel(in: testCase.source)
            _ = try model.requestPresentation(
                testCase.target,
                playbackContext: SpatialPlaybackTransitionContext(
                    mediaSessionID: "paused-\(testCase.source.rawValue)-to-\(testCase.target.rawValue)",
                    wasPlaying: false
                )
            )
            #expect(model.pendingSpatialPlatformEffect?.playbackTransportPlan?.beforeEffect == nil)
            #expect(model.pendingSpatialPlatformEffect?.playbackTransportPlan?.afterSuccess == nil)
            #expect(model.pendingSpatialPlatformEffect?.playbackTransportPlan?.afterFailure == nil)
        }
    }

    @Test("direct Dock uses the environment and appearance selected by its menu")
    @MainActor
    func directDockUsesSelectedTarget() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.scenicTwo, effect: .dark)

        _ = try model.requestPresentation(
            .docked,
            environment: .scenicThree,
            effect: .light,
            playbackContext: playingContext()
        )
        let request = try #require(model.pendingSpatialPlatformEffect)
        let resolution = try completePendingEffect(model)

        #expect(resolution == .presentationCommitted(.docked))
        #expect(model.snapshot.presentation == .docked)
        #expect(
            model.snapshot.environmentContext == .active(
                environment: .scenicThree,
                effect: .light
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
            effect: .dark,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

        #expect(model.presentation == .docked)
        #expect(
            model.environmentContext == .active(
                environment: .scenicOne,
                effect: .dark
            )
        )
    }

    @Test("undock restores the active environment that preceded Docked")
    @MainActor
    func undockKeepsEnvironment() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.scenicTwo, effect: .dark)
        _ = try model.requestPresentation(
            .docked,
            environment: .scenicThree,
            effect: .light,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

        _ = try model.requestPresentation(.window, playbackContext: playingContext())
        _ = try completePendingEffect(model)

        #expect(model.presentation == .window)
        #expect(
            model.environmentContext == .active(
                environment: .scenicTwo,
                effect: .dark
            )
        )
    }

    @Test("temporary Default Environment closes when Docked returns to Window")
    @MainActor
    func undockClosesTemporaryDefaultEnvironment() throws {
        let model = PlaybackPresentationModel()
        _ = try model.requestPresentation(
            .docked,
            effect: .dark,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

        _ = try model.requestPresentation(.window, playbackContext: playingContext())
        #expect(
            model.pendingSpatialPlatformEffect?.effect
                == .exitImmersivePlayback(
                    .flat,
                    keepsEnvironmentOpen: false
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
            effect: .dark,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(
            inactiveModel,
            outcome: .failed(.playbackPauseFailed)
        )
        #expect(inactiveModel.presentation == .window)
        #expect(inactiveModel.environmentContext == .none)

        let activeModel = PlaybackPresentationModel()
        try activeModel.activateEnvironment(.scenicOne, effect: .dark)
        _ = try activeModel.requestPresentation(
            .docked,
            environment: .scenicThree,
            effect: .light,
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
                effect: .light
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
                effect: .dark
            )
        )
    }

    @Test("Panorama rollback restores Portal and its environment context")
    @MainActor
    func panoramaRollbackRestoresPreviousState() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.scenicOne, effect: .dark)
        _ = try model.requestPresentation(
            .portal,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

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
        #expect(model.presentation == .portal)
        #expect(
            model.environmentContext == .active(
                environment: .scenicOne,
                effect: .dark
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
            effect: .dark
        )
        try model.activateEnvironment(.scenicOne, effect: .dark)
        _ = try model.requestPresentation(
            .portal,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

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
            .portal,
            playbackContext: playingContext()
        )
        #expect(leave.previousEnvironment == .none)
        #expect(leave.targetEnvironment == priorEnvironment)
        _ = try completePendingEffect(model)
        #expect(model.presentation == .portal)
        #expect(model.environmentContext == priorEnvironment)
    }

    @Test("a transition rejects a second product command")
    @MainActor
    func transitionRejectsSecondCommand() throws {
        let model = PlaybackPresentationModel()
        model.prepareColdPlaybackLaunch(for: .panoramic)
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

    @Test("stopping playback restores window while retaining the chosen environment")
    @MainActor
    func playbackStopRestoresWindow() throws {
        let model = PlaybackPresentationModel()
        try model.activateEnvironment(.scenicOne, effect: .dark)
        _ = try model.requestPresentation(
            .docked,
            environment: .scenicOne,
            effect: .dark,
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
                effect: .dark
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
            effect: .dark,
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
        try model.activateEnvironment(.scenicOne, effect: .dark)
        _ = try model.requestPresentation(.docked, playbackContext: playingContext())
        let staleRequest = try #require(model.pendingSpatialPlatformEffect)

        model.requestStoppedPlaybackCleanup()
        let cleanupRequest = try #require(model.pendingSpatialPlatformEffect)

        #expect(model.presentation == .window)
        #expect(
            model.environmentContext == .active(
                environment: .scenicOne,
                effect: .dark
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
        try model.activateEnvironment(.scenicOne, effect: .dark)
        _ = try model.requestPresentation(
            .docked,
            environment: .scenicOne,
            effect: .dark,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

        #expect(throws: PlaybackPresentationTransitionError.dockedPresentationRequiresEnvironment) {
            try model.deactivateEnvironment()
        }
        #expect(
            model.environmentContext == .active(
                environment: .scenicOne,
                effect: .dark
            )
        )
    }

    @Test("a late result cannot replace a newer pending effect")
    @MainActor
    func lateResultIsIgnored() throws {
        let model = PlaybackPresentationModel()
        model.prepareColdPlaybackLaunch(for: .panoramic)
        _ = try model.requestPresentation(.panorama, playbackContext: playingContext())
        let staleRequest = try #require(model.pendingSpatialPlatformEffect)
        _ = try completePendingEffect(
            model,
            outcome: .failed(.spatialPlaybackSurfaceUnavailable)
        )

        _ = try model.requestPresentation(
            .window,
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
        #expect(model.presentation == .portal)
    }

    @Test("Media Session invalidation normalizes issued spatial effects before new work")
    @MainActor
    func mediaSessionInvalidationQueuesNormalization() throws {
        let model = PlaybackPresentationModel()
        model.prepareColdPlaybackLaunch(for: .panoramic)
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
        model.prepareColdPlaybackLaunch(for: .panoramic)
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

    @Test("system-closed Panorama falls back to Portal")
    @MainActor
    func systemClosedPanoramaFallsBackToPortal() throws {
        let model = PlaybackPresentationModel()
        let context = playingContext(mediaSessionID: "panorama-collapse-session")
        try model.activateEnvironment(.scenicOne, effect: .dark)
        _ = try model.requestPresentation(.portal, playbackContext: context)
        _ = try completePendingEffect(model)
        _ = try model.requestPresentation(.panorama, playbackContext: context)
        _ = try completePendingEffect(model)

        #expect(
            model.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(context)
            ) == .platformFactRecorded
        )

        let transition = try #require(model.transition)
        #expect(transition.previousPresentation == .panorama)
        #expect(transition.targetPresentation == .portal)
        #expect(transition.previousEnvironment == .none)
        #expect(transition.targetEnvironment == .none)
        #expect(model.environmentContext == .none)
        #expect(model.panoramaReturnEnvironmentContext == nil)
        let request = try #require(model.pendingSpatialPlatformEffect)
        #expect(request.effect == .collapseImmersivePlayback(.panoramic))
        #expect(request.playbackTransportPlan?.mediaSessionID == context.mediaSessionID)
        #expect(request.playbackTransportPlan?.beforeEffect == nil)
        #expect(
            request.playbackTransportPlan?.afterSuccess
                == .resume(mediaSessionID: context.mediaSessionID)
        )
        #expect(request.playbackTransportPlan?.afterFailure == nil)
        #expect(try completePendingEffect(model) == .presentationCommitted(.portal))
        #expect(model.presentation == .portal)
        #expect(model.environmentContext == .none)
        #expect(model.immersiveSpaceResidency == .closed)
    }

    @Test("system-closed Docked playback falls back to Window")
    @MainActor
    func systemClosedDockedFallsBackToWindow() throws {
        let model = PlaybackPresentationModel()
        let context = playingContext(mediaSessionID: "docked-collapse-session")
        _ = try model.requestPresentation(
            .docked,
            effect: .light,
            playbackContext: context
        )
        _ = try completePendingEffect(model)

        #expect(
            model.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(context)
            ) == .platformFactRecorded
        )
        let transition = try #require(model.transition)
        #expect(transition.previousPresentation == .docked)
        #expect(transition.targetPresentation == .window)
        #expect(transition.previousEnvironment == .none)
        #expect(transition.targetEnvironment == .none)
        #expect(
            model.pendingSpatialPlatformEffect?.effect
                == .collapseImmersivePlayback(.flat)
        )
        #expect(try completePendingEffect(model) == .presentationCommitted(.window))
        #expect(model.presentation == .window)
        #expect(model.environmentContext == .none)
        #expect(model.immersiveSpaceResidency == .closed)
    }

    @Test("system collapse keeps paused playback paused")
    @MainActor
    func systemCollapsePreservesPausedPlayback() throws {
        let model = PlaybackPresentationModel()
        let context = SpatialPlaybackTransitionContext(
            mediaSessionID: "paused-session",
            wasPlaying: false
        )
        model.prepareColdPlaybackLaunch(for: .panoramic)
        _ = try model.requestPresentation(.panorama, playbackContext: context)
        _ = try completePendingEffect(model)
        _ = model.receiveSpatialPlatformResult(.immersiveSpaceDisappeared(context))

        let request = try #require(model.pendingSpatialPlatformEffect)
        #expect(request.playbackTransportPlan?.beforeEffect == nil)
        #expect(request.playbackTransportPlan?.afterSuccess == nil)
        #expect(request.playbackTransportPlan?.afterFailure == nil)
        #expect(request.effect == .collapseImmersivePlayback(.panoramic))
        #expect(try completePendingEffect(model) == .presentationCommitted(.portal))
    }

    @Test("an app-requested immersive exit owns its disappearance callback")
    @MainActor
    func appRequestedExitInFlightDoesNotDoubleFire() throws {
        let model = PlaybackPresentationModel()
        let context = playingContext(mediaSessionID: "app-exit-session")
        try model.activateEnvironment(.scenicOne, effect: .dark)
        _ = try model.requestPresentation(.docked, playbackContext: context)
        _ = try completePendingEffect(model)
        _ = try model.requestPresentation(.window, playbackContext: context)
        let exitRequest = try #require(model.pendingSpatialPlatformEffect)
        #expect(
            exitRequest.effect
                == .exitImmersivePlayback(
                    .flat,
                    keepsEnvironmentOpen: true
                )
        )

        #expect(
            model.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(context)
            ) == .platformFactRecorded
        )
        #expect(model.pendingSpatialPlatformEffect?.id == exitRequest.id)
        #expect(
            model.transition?.previousEnvironment == EnvironmentContext.none
        )
        #expect(
            model.transition?.targetEnvironment == EnvironmentContext.none
        )
        #expect(try completePendingEffect(model) == .presentationCommitted(.window))
        #expect(model.environmentContext == .none)
        #expect(model.immersiveSpaceResidency == .closed)
    }

    @Test("stopped cleanup normalization request remains pending after immersive disappearance")
    @MainActor
    func stoppedCleanupNormalizationRequestRemainsPending() throws {
        let model = PlaybackPresentationModel()
        let context = playingContext(mediaSessionID: "stopped-cleanup-session")
        _ = try model.requestPresentation(
            .docked,
            effect: .dark,
            playbackContext: context
        )
        _ = try completePendingEffect(model)
        model.requestStoppedPlaybackCleanup()
        let cleanupRequest = try #require(model.pendingSpatialPlatformEffect)

        #expect(
            model.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(context)
            ) == .platformFactRecorded
        )
        #expect(model.pendingSpatialPlatformEffect?.id == cleanupRequest.id)
        #expect(
            cleanupRequest.effect
                == .normalizeStoppedSpatialPlayback(
                    keepsEnvironmentOpen: false
                )
        )
    }

    @Test("system closure without playback context resets stopped presentation state")
    @MainActor
    func systemClosureWithoutContextQueuesNoEffect() throws {
        let model = PlaybackPresentationModel()
        model.prepareColdPlaybackLaunch(for: .panoramic)
        _ = try model.requestPresentation(
            .panorama,
            playbackContext: playingContext()
        )
        _ = try completePendingEffect(model)

        #expect(
            model.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(nil)
            ) == .platformFactRecorded
        )
        #expect(model.presentation == .window)
        #expect(model.environmentContext == .none)
        #expect(model.transition == nil)
        #expect(model.pendingSpatialPlatformEffect == nil)
    }

    @Test("duplicate system closure keeps the first collapse request")
    @MainActor
    func duplicateSystemClosureIsIdempotent() throws {
        let model = PlaybackPresentationModel()
        let context = playingContext(mediaSessionID: "duplicate-collapse-session")
        _ = try model.requestPresentation(
            .docked,
            effect: .light,
            playbackContext: context
        )
        _ = try completePendingEffect(model)
        _ = model.receiveSpatialPlatformResult(
            .immersiveSpaceDisappeared(context)
        )
        let collapseRequest = try #require(model.pendingSpatialPlatformEffect)

        #expect(
            model.receiveSpatialPlatformResult(
                .immersiveSpaceDisappeared(context)
            ) == .platformFactRecorded
        )
        #expect(model.pendingSpatialPlatformEffect?.id == collapseRequest.id)
        #expect(
            model.pendingSpatialPlatformEffect?.effect
                == .collapseImmersivePlayback(.flat)
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
        model.prepareColdPlaybackLaunch(for: .panoramic)
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
            effect: .dark,
            playbackContext: context
        )
        _ = try completePendingEffect(model)

        #expect(try model.requestEnvironmentCard(playbackContext: context))
        let windowRequest = try #require(model.pendingSpatialPlatformEffect)
        #expect(
            windowRequest.effect
                == .exitImmersivePlayback(
                    .flat,
                    keepsEnvironmentOpen: false
                )
        )
        #expect(
            windowRequest.playbackTransportPlan?.beforeEffect == nil
        )
        #expect(
            windowRequest.playbackTransportPlan?.afterSuccess
                == .resume(mediaSessionID: context.mediaSessionID)
        )

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
        model.prepareColdPlaybackLaunch(for: .panoramic)
        _ = try model.requestPresentation(.panorama, playbackContext: playingContext())

        #expect(
            try completePendingEffect(
                model,
                outcome: .failed(.playbackPauseFailed)
            ) == .presentationRolledBack(.playbackPauseFailed)
        )
        #expect(model.presentation == .portal)
        #expect(model.transition == nil)
        #expect(model.pendingSpatialPlatformEffect == nil)
    }

    @Test("an unscheduled resume result is ignored after presentation commit")
    @MainActor
    func unscheduledResumeResultIsIgnored() throws {
        let model = PlaybackPresentationModel()
        let context = playingContext()
        model.prepareColdPlaybackLaunch(for: .panoramic)
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

    @Test("presentation transitions retire directly and restore prior playback intent")
    @MainActor
    func presentationTransitionsRemainPausedAfterCommitAndRollback() throws {
        for target in [PlaybackPresentation.docked, .panorama] {
            let model = PlaybackPresentationModel()
            let context = playingContext(mediaSessionID: "\(target.rawValue)-session")
            if target == .panorama {
                model.prepareColdPlaybackLaunch(for: .panoramic)
            }
            _ = try model.requestPresentation(
                target,
                effect: target == .docked ? .light : nil,
                playbackContext: context
            )
            let entry = try #require(model.pendingSpatialPlatformEffect)
            #expect(entry.playbackTransportPlan?.beforeEffect == nil)
            #expect(
                entry.playbackTransportPlan?.afterSuccess
                    == .resume(mediaSessionID: context.mediaSessionID)
            )
            #expect(entry.playbackTransportPlan?.afterFailure == nil)
            #expect(try completePendingEffect(model) == .presentationCommitted(target))

            let pausedContext = SpatialPlaybackTransitionContext(
                mediaSessionID: context.mediaSessionID,
                wasPlaying: false
            )
            let returnTarget = try #require(target.exitImmersiveTarget)
            _ = try model.requestPresentation(returnTarget, playbackContext: pausedContext)
            let returnRequest = try #require(model.pendingSpatialPlatformEffect)
            #expect(returnRequest.playbackTransportPlan?.beforeEffect == nil)
            #expect(returnRequest.playbackTransportPlan?.afterSuccess == nil)
            #expect(returnRequest.playbackTransportPlan?.afterFailure == nil)
            #expect(
                try completePendingEffect(model)
                    == .presentationCommitted(returnTarget)
            )
        }

        let rollbackModel = PlaybackPresentationModel()
        let rollbackContext = playingContext(mediaSessionID: "rollback-session")
        rollbackModel.prepareColdPlaybackLaunch(for: .panoramic)
        _ = try rollbackModel.requestPresentation(
            .panorama,
            playbackContext: rollbackContext
        )
        let rollbackRequest = try #require(rollbackModel.pendingSpatialPlatformEffect)
        #expect(
            rollbackRequest.playbackTransportPlan?.beforeEffect == nil
        )
        #expect(
            rollbackRequest.playbackTransportPlan?.afterSuccess
                == .resume(mediaSessionID: rollbackContext.mediaSessionID)
        )
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
    private func settledModel(
        in presentation: PlaybackPresentation
    ) throws -> PlaybackPresentationModel {
        let model = PlaybackPresentationModel()
        switch presentation {
        case .window:
            break
        case .portal:
            model.prepareColdPlaybackLaunch(for: .panoramic)
        case .docked:
            _ = try model.requestPresentation(
                .docked,
                playbackContext: playingContext()
            )
            _ = try completePendingEffect(model)
        case .panorama:
            model.prepareColdPlaybackLaunch(for: .panoramic)
            _ = try model.requestPresentation(
                .panorama,
                playbackContext: playingContext()
            )
            _ = try completePendingEffect(model)
        }
        return model
    }

    @MainActor
    private func completePendingEffect(
        _ appModel: PlaybackSessionModel,
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
