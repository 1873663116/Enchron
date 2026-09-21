import CoreGraphics
import DesignSystem
@testable import Playback
import RealityKit
import Testing
import simd
@testable import Enchron

@MainActor
@Suite("Window playback page geometry")
struct WindowPlaybackPageGeometryTests {
    @Test("window playback bounds use the source display aspect ratio")
    func playbackWindowSizePolicy() {
        let portrait = WindowPlaybackLayout(
            resolution: .init(width: 1_080, height: 1_920),
            stereoLayout: .mono
        )

        #expect(abs(portrait.aspectRatio - 0.5625) < 0.001)
        #expect(portrait.hasPlaybackAspectRatio(portrait.minimumSize))
        #expect(portrait.hasPlaybackAspectRatio(portrait.defaultSize))
        #expect(portrait.hasPlaybackAspectRatio(portrait.maximumSize))
        #expect(portrait.contains(portrait.minimumSize))
        #expect(portrait.contains(portrait.defaultSize))
        #expect(portrait.contains(portrait.maximumSize))
    }

    @Test("stereo packing resolves the displayed video dimensions")
    func stereoscopicDisplayAspectRatio() {
        let sideBySide = WindowPlaybackLayout(
            resolution: .init(width: 3_840, height: 1_080),
            stereoLayout: .sideBySide
        )
        let topBottom = WindowPlaybackLayout(
            resolution: .init(width: 1_920, height: 2_160),
            stereoLayout: .topBottom
        )

        #expect(abs(sideBySide.aspectRatio - 16.0 / 9.0) < 0.001)
        #expect(abs(topBottom.aspectRatio - 16.0 / 9.0) < 0.001)
    }

    @Test("non-square pixels use the per-eye display aspect ratio")
    func nonSquarePixelStereoDisplayAspectRatio() {
        let topBottom = WindowPlaybackLayout(
            resolution: .init(width: 8_192, height: 4_096),
            pixelAspectRatio: .init(horizontalSpacing: 1, verticalSpacing: 4),
            stereoLayout: .topBottom
        )

        #expect(abs(topBottom.aspectRatio - 1) < 0.001)
    }

    @Test("window tiers come from a target area, not from the ornament width")
    func areaDrivenWindowTiers() {
        let layout = WindowPlaybackLayout.fallback

        #expect(layout.minimumSize == CGSize(width: 912, height: 513))
        #expect(layout.defaultSize == CGSize(width: 1_280, height: 720))
        #expect(layout.maximumSize == CGSize(width: 1_808, height: 1_017))
    }

    @Test("every tier carries the video's shape across the ratio range")
    func everyTierKeepsTheSourceShape() {
        for ratio in stride(from: 0.3, through: 4.0, by: 0.05) {
            let layout = WindowPlaybackLayout(aspectRatio: CGFloat(ratio))

            #expect(layout.hasPlaybackAspectRatio(layout.minimumSize))
            #expect(layout.hasPlaybackAspectRatio(layout.defaultSize))
            #expect(layout.hasPlaybackAspectRatio(layout.maximumSize))
        }
    }

    @Test("tiers never invert and never leave the ceiling")
    func tiersStayOrderedAndBounded() {
        let ceiling = WindowPlaybackLayout.maximumExtent

        for ratio in stride(from: 0.3, through: 4.0, by: 0.05) {
            let layout = WindowPlaybackLayout(aspectRatio: CGFloat(ratio))
            let tiers = [layout.minimumSize, layout.defaultSize, layout.maximumSize]

            for (smaller, larger) in zip(tiers, tiers.dropFirst()) {
                #expect(smaller.width <= larger.width + 0.001)
                #expect(smaller.height <= larger.height + 0.001)
            }
            for tier in tiers {
                #expect(tier.width <= ceiling + 0.001)
                #expect(tier.height <= ceiling + 0.001)
            }
        }
    }

    @Test("a side-by-side override no longer drives the window past the ceiling")
    func sideBySideOverrideStaysBounded() {
        let forced = WindowPlaybackLayout(
            resolution: .init(width: 1_920, height: 1_080),
            stereoLayout: .sideBySide
        )

        #expect(abs(forced.aspectRatio - 8.0 / 9.0) < 0.001)
        #expect(forced.defaultSize.width == 905)
        #expect(abs(forced.defaultSize.height - 1_018.125) < 0.01)
        #expect(forced.maximumSize.height <= WindowPlaybackLayout.maximumExtent)
        #expect(forced.hasPlaybackAspectRatio(forced.defaultSize))
    }

    @Test("portrait content rises to the width floor rather than growing bars")
    func portraitContentMeetsTheWidthFloor() {
        let portrait = WindowPlaybackLayout(
            resolution: .init(width: 1_080, height: 1_920),
            stereoLayout: .mono
        )

        #expect(portrait.defaultSize.width == WindowPlaybackLayout.minimumWidth)
        #expect(abs(portrait.defaultSize.height - 1_333.3333) < 0.01)
        #expect(portrait.hasPlaybackAspectRatio(portrait.defaultSize))
        #expect(abs(portrait.maximumSize.height - WindowPlaybackLayout.maximumExtent) < 0.001)
    }

    @Test("a top-bottom override lands on the ceiling instead of overshooting")
    func topBottomOverrideLandsOnTheCeiling() {
        let flat = WindowPlaybackLayout(
            resolution: .init(width: 1_920, height: 1_080),
            stereoLayout: .topBottom
        )

        #expect(abs(flat.aspectRatio - 32.0 / 9.0) < 0.001)
        #expect(abs(flat.maximumSize.width - WindowPlaybackLayout.maximumExtent) < 0.001)
        #expect(flat.hasPlaybackAspectRatio(flat.maximumSize))
    }

    @Test("the browser window is a fixed 16:9 that owes nothing to playback")
    func browserWindowIsFixedSixteenByNine() {
        #expect(
            BrowserWindowLayout.minimumSize
                == CGSize(width: 1_088, height: 612)
        )
        #expect(BrowserWindowLayout.defaultSize == CGSize(width: 1_536, height: 864))
        #expect(BrowserWindowLayout.maximumSize == CGSize(width: 1_808, height: 1_017))
    }

    @Test("Portal locks the chrome window to the fallback aspect, not the video's")
    func portalWindowLocksToTheFallbackAspect() {
        let videoLayout = WindowPlaybackLayout(aspectRatio: 1)

        #expect(
            WindowPlaybackGeometryPolicy(
                presentation: .portal,
                videoLayout: videoLayout
            ) == .aspectLocked(.fallback)
        )
        #expect(
            WindowPlaybackGeometryPolicy(
                presentation: .portal,
                videoLayout: videoLayout
            ) != WindowPlaybackGeometryPolicy(
                presentation: .window,
                videoLayout: videoLayout
            )
        )
        #expect(
            WindowPlaybackGeometryPolicy(
                presentation: .portal,
                videoLayout: .fallback
            ) == WindowPlaybackGeometryPolicy(
                presentation: .window,
                videoLayout: .fallback
            )
        )
    }

    @Test("Window keeps the effective per-eye aspect lock")
    func flatWindowUsesEffectivePerEyeAspectGeometry() {
        let sideBySide = WindowPlaybackLayout(
            resolution: .init(width: 3_840, height: 1_080),
            stereoLayout: .sideBySide
        )

        #expect(
            WindowPlaybackGeometryPolicy(
                presentation: .window,
                videoLayout: sideBySide
            ) == .aspectLocked(sideBySide)
        )
        #expect(abs(sideBySide.aspectRatio - 16.0 / 9.0) < 0.001)
    }

    @Test("audio-only playback uses a compact window tier")
    func audioOnlyWindowUsesCompactGeometry() {
        let policy = WindowPlaybackGeometryPolicy.audioOnly
        let idealWidth = policy.idealSize?.width ?? .infinity

        #expect(policy.minimumSize == CGSize(width: 750, height: 380))
        #expect(policy.idealSize == CGSize(width: 800, height: 450))
        #expect(policy.maximumSize == CGSize(width: 960, height: 540))
        #expect(idealWidth < WindowPlaybackLayout.fallback.defaultSize.width)
    }

    @Test("window geometry diagnostics describe the policy supplied to the root view")
    func windowGeometryDiagnosticSnapshot() {
        let layout = WindowPlaybackLayout(aspectRatio: 4.0 / 3.0)
        let snapshot = WindowPlaybackGeometryPolicy
            .aspectLocked(layout)
            .diagnosticSnapshot

        #expect(snapshot.policyKind == .aspectLocked)
        #expect(snapshot.requestedIdealWidth == layout.defaultSize.width)
        #expect(snapshot.requestedIdealHeight == layout.defaultSize.height)
        #expect(snapshot.minimumWidth == layout.minimumSize.width)
        #expect(snapshot.minimumHeight == layout.minimumSize.height)
        #expect(snapshot.maximumWidth == layout.maximumSize.width)
        #expect(snapshot.maximumHeight == layout.maximumSize.height)
        #expect(snapshot.resizingRestriction == .uniform)
    }

    @Test("audio window geometry diagnostics expose exact control-plane fields")
    func audioWindowGeometryControlPlaneFields() {
        let fields = WindowPlaybackGeometryPolicy.audioOnly
            .diagnosticSnapshot
            .accessibilityFields

        #expect(fields == [
            "windowGeometryPolicyKind=audioOnly",
            "windowGeometryRequestedIdealWidth=800.0",
            "windowGeometryRequestedIdealHeight=450.0",
            "windowGeometryMinimumWidth=750.0",
            "windowGeometryMinimumHeight=380.0",
            "windowGeometryMaximumWidth=960.0",
            "windowGeometryMaximumHeight=540.0",
            "windowGeometryResizingRestriction=uniform"
        ])
    }

    @Test("a 4:3 source sits inside its tiers without touching both ceilings")
    func fourByThreeSourceStaysInsideItsTiers() {
        let layout = WindowPlaybackLayout(aspectRatio: 4.0 / 3.0)

        #expect(layout.minimumSize.width == 790)
        #expect(layout.defaultSize.width == 1_109)
        #expect(layout.maximumSize.width == 1_566)
        #expect(layout.hasPlaybackAspectRatio(layout.minimumSize))
        #expect(layout.hasPlaybackAspectRatio(layout.defaultSize))
        #expect(layout.hasPlaybackAspectRatio(layout.maximumSize))
        #expect(layout.maximumSize.height < WindowPlaybackLayout.maximumExtent)
    }

    @Test("immersive playback visibility includes an active Docked handoff")
    func immersivePlaybackControlsAttachmentPolicy() {
        #expect(
            ImmersivePlaybackControlsAttachmentPolicy.isVisible(
                presentation: .window,
                controlsVisible: true,
                transitionIsActive: false
            ) == false
        )
        #expect(
            ImmersivePlaybackControlsAttachmentPolicy.isVisible(
                presentation: .portal,
                controlsVisible: true,
                transitionIsActive: false
            )
            == false
        )
        #expect(
            ImmersivePlaybackControlsAttachmentPolicy.isVisible(
                presentation: .docked,
                controlsVisible: false,
                transitionIsActive: false
            )
            == false
        )
        #expect(
            ImmersivePlaybackControlsAttachmentPolicy.isVisible(
                presentation: .docked,
                controlsVisible: true,
                transitionIsActive: true
            )
        )
        #expect(
            ImmersivePlaybackControlsAttachmentPolicy.isVisible(
                presentation: .docked,
                controlsVisible: true,
                transitionIsActive: false
            )
        )
        #expect(
            ImmersivePlaybackControlsAttachmentPolicy.isVisible(
                presentation: .panorama,
                controlsVisible: true,
                transitionIsActive: true
            ) == false
        )
        #expect(
            ImmersivePlaybackControlsAttachmentPolicy.isVisible(
                presentation: .panorama,
                controlsVisible: true,
                transitionIsActive: false
            )
        )
    }

    @Test("immersive controls place only on visibility rising edges")
    func immersiveControlsPlacementUsesVisibilityRisingEdges() {
        var state = ImmersivePlaybackControlsPlacementState()

        #expect(state.setVisible(false) == .none)
        #expect(state.setVisible(true) == .place(revision: 1))
        #expect(state.setVisible(true) == .none)
        #expect(state.setVisible(false) == .hide(lastPlacementRevision: 1))
        #expect(state.setVisible(false) == .none)
        #expect(state.setVisible(true) == .place(revision: 2))
        #expect(state.setVisible(true) == .none)
    }

    @Test("immersive controls fall back once when head tracking is unavailable")
    func immersiveControlsPlacementFallsBackOnVisibilityRisingEdge() {
        var state = ImmersivePlaybackControlsPlacementState()

        #expect(state.setVisible(true) == .place(revision: 1))
        #expect(
            state.resolvePlacement(headAnchorIsAvailable: false)
                == .fallback(revision: 1)
        )
        #expect(state.resolvePlacement(headAnchorIsAvailable: true) == nil)
        #expect(state.setVisible(true) == .none)

        #expect(state.setVisible(false) == .hide(lastPlacementRevision: 1))
        #expect(state.setVisible(true) == .place(revision: 2))
        #expect(
            state.resolvePlacement(headAnchorIsAvailable: true)
                == .headAnchor(revision: 2)
        )
    }

    @Test("immersive controls keep their bottom edge horizontal without moving the summon position")
    func immersiveControlsPlacementRemovesRoll() {
        let yaws: [Float] = [-.pi, -.pi / 3, 0, .pi / 3, .pi]
        let pitches: [Float] = [-.pi / 2, -.pi / 2 + 1e-6, -.pi / 5, 0,
                                .pi / 5, .pi / 2 - 1e-6, .pi / 2]
        for yaw in yaws {
            for pitch in pitches {
                for roll: Float in [-.pi / 2, -.pi / 6, 0, .pi / 6, .pi / 2] {
                    let head = headTransform(
                        yaw: yaw,
                        pitch: pitch,
                        roll: roll,
                        position: [0.4, 1.5, -0.3]
                    )
                    let headRotation = simd_quatf(head)

                    let placement = ImmersivePlaybackControlsPlacementGeometry.transform(
                        originFromAnchorTransform: head,
                        forwardOffsetMeters: ImmersivePlaybackControlsAttachmentController
                            .forwardOffsetMeters,
                        verticalOffsetMeters: ImmersivePlaybackControlsAttachmentController
                            .verticalOffsetMeters
                    )

                    let right = placement.rotation.act(SIMD3<Float>(1, 0, 0))
                    #expect(abs(right.y) < 1e-4)
                    #expect(abs(simd_length(right) - 1) < 1e-4)
                    let forward = placement.rotation.act(SIMD3<Float>(0, 0, -1))
                    #expect(simd_distance(forward, headRotation.act(SIMD3<Float>(0, 0, -1))) < 1e-4)

                    let expected = SIMD3<Float>(0.4, 1.5, -0.3)
                        + headRotation.act(
                            SIMD3<Float>(
                                0,
                                ImmersivePlaybackControlsAttachmentController.verticalOffsetMeters,
                                ImmersivePlaybackControlsAttachmentController.forwardOffsetMeters
                            )
                        )
                    #expect(simd_distance(placement.translation, expected) < 1e-4)
                }
            }
        }
    }

    @Test("immersive controls stay below the wearer's view when looking straight up")
    func immersiveControlsPlacementFollowsSupineGaze() {
        let supine = headTransform(yaw: 0, pitch: .pi / 2, roll: 0, position: [0, 0.4, 0])
        let forwardOffset = ImmersivePlaybackControlsAttachmentController.forwardOffsetMeters
        let verticalOffset = ImmersivePlaybackControlsAttachmentController.verticalOffsetMeters

        let placement = ImmersivePlaybackControlsPlacementGeometry.transform(
            originFromAnchorTransform: supine,
            forwardOffsetMeters: forwardOffset,
            verticalOffsetMeters: verticalOffset
        )

        #expect(abs(placement.translation.x) < 1e-4)
        #expect(abs(placement.translation.y - (0.4 - forwardOffset)) < 1e-4)
        #expect(abs(placement.translation.z - verticalOffset) < 1e-4)
        let panelUp = placement.rotation.act(SIMD3<Float>(0, 1, 0))
        #expect(abs(panelUp.z - 1) < 1e-4)
    }

    @Test("immersive controls sit below eye level at a fixed world height")
    func immersiveControlsPlacementMeasuresHeightInWorldSpace() {
        let level = headTransform(yaw: 0, pitch: 0, roll: 0, position: [0, 1.5, 0])
        let forwardOffset = ImmersivePlaybackControlsAttachmentController.forwardOffsetMeters
        let verticalOffset = ImmersivePlaybackControlsAttachmentController.verticalOffsetMeters

        let levelPlacement = ImmersivePlaybackControlsPlacementGeometry.transform(
            originFromAnchorTransform: level,
            forwardOffsetMeters: forwardOffset,
            verticalOffsetMeters: verticalOffset
        )

        #expect(abs(levelPlacement.translation.y - (1.5 + verticalOffset)) < 1e-4)
        #expect(verticalOffset < -0.22)
        #expect(atan(-verticalOffset / -forwardOffset) < 23 * .pi / 180)
    }

    private func headTransform(
        yaw: Float,
        pitch: Float,
        roll: Float,
        position: SIMD3<Float>
    ) -> simd_float4x4 {
        let rotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
        var matrix = simd_float4x4(rotation)
        matrix.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
        return matrix
    }

    @Test("Video Format editing snapshots the committed selection when editing begins")
    func videoFormatEditingSnapshotsSelection() {
        var state = PlaybackVideoFormatEditingState(
            projection: .customAngle,
            horizontalFieldOfViewDegrees: 220,
            stereoLayout: .sideBySide
        )

        state.beginEditing()
        state.projection = .equirectangular360
        state.horizontalFieldOfViewDegrees = 280
        state.stereoLayout = .mono
        state.discard()

        #expect(state.projection == .customAngle)
        #expect(state.horizontalFieldOfViewDegrees == 220)
        #expect(state.stereoLayout == .sideBySide)
    }

    @Test("Portal top actions include Enter Panorama and Video Format")
    func portalTopActionsIncludePanoramaEntryAndVideoFormat() {
        let composition = PlaybackTopActionsComposition(
            immersiveEntryTarget: .panorama
        )

        #expect(composition.showsPanoramaEntry)
        #expect(composition.showsVideoFormat)
        #expect(composition.showsDock == false)
    }

    @Test("applying Video Format commits the draft as the next editing baseline")
    func applyingVideoFormatCommitsDraft() {
        var state = PlaybackVideoFormatEditingState()

        state.beginEditing()
        state.projection = .customAngle
        state.horizontalFieldOfViewDegrees = 240
        state.stereoLayout = .topBottom

        let committed = state.commit()

        #expect(
            committed == PlaybackVideoFormatSelection(
                projection: .customAngle,
                horizontalFieldOfViewDegrees: 240,
                stereoLayout: .topBottom
            )
        )

        state.beginEditing()
        state.projection = .flat
        state.stereoLayout = .mono
        state.discard()

        #expect(state.projection == .customAngle)
        #expect(state.horizontalFieldOfViewDegrees == 240)
        #expect(state.stereoLayout == .topBottom)
    }

    @Test("committed Video Format synchronization waits for editing to finish")
    func videoFormatSynchronizationWaitsForEditing() {
        var state = PlaybackVideoFormatEditingState(
            projection: .equirectangular180,
            stereoLayout: .sideBySide
        )
        let sourceSelection = PlaybackVideoFormatSelection(
            projection: .flat,
            horizontalFieldOfViewDegrees: nil,
            stereoLayout: .mono
        )

        state.synchronizeCommittedVideoFormat(sourceSelection)
        #expect(state.projection == .flat)
        #expect(state.stereoLayout == .mono)

        state.beginEditing()
        state.projection = .equirectangular360
        state.synchronizeCommittedVideoFormat(
            PlaybackVideoFormatSelection(
                projection: .equirectangular180,
                horizontalFieldOfViewDegrees: nil,
                stereoLayout: .sideBySide
            )
        )
        #expect(state.projection == .equirectangular360)

        state.discard()
        #expect(state.projection == .flat)
        #expect(state.stereoLayout == .mono)
    }

    @Test("cancelling Video Format closes the menu and discards its draft")
    func cancellingVideoFormatDiscardsItsDraft() {
        var state = PlaybackTopActionsState()

        state.toggleMenu(.videoFormat)
        state.projection = .equirectangular360
        state.stereoLayout = .sideBySide

        let selectionToApply = state.finishVideoFormatEditing(.cancel)

        #expect(selectionToApply == nil)
        #expect(state.presentedMenu == nil)
        #expect(state.projection == .flat)
        #expect(state.stereoLayout == .mono)
    }

    @Test("source format synchronization never overwrites an open draft")
    func sourceFormatSynchronizationWaitsUntilEditingEnds() {
        var state = PlaybackTopActionsState(
            projection: .equirectangular180,
            stereoLayout: .sideBySide
        )
        state.toggleMenu(.videoFormat)
        state.projection = .equirectangular360

        state.synchronizeCommittedVideoFormat(
            .init(projection: .flat, horizontalFieldOfViewDegrees: nil, stereoLayout: .mono)
        )
        #expect(state.projection == .equirectangular360)

        _ = state.finishVideoFormatEditing(.cancel)
        state.synchronizeCommittedVideoFormat(
            .init(projection: .flat, horizontalFieldOfViewDegrees: nil, stereoLayout: .mono)
        )
        #expect(state.projection == .flat)
        #expect(state.stereoLayout == .mono)
    }

    @Test("selecting a Dock target records its environment and appearance")
    func selectingDockTargetRecordsEnvironmentAndAppearance() {
        var state = PlaybackTopActionsState()

        state.toggleMenu(.dock)

        let requested = state.selectDockTarget(
            environment: .placeholderGreen,
            effect: .dark
        )

        #expect(requested.0 == .placeholderGreen)
        #expect(requested.1 == .dark)
        #expect(state.selectedDockEnvironment == .placeholderGreen)
        #expect(state.selectedEffect == .dark)
        #expect(state.presentedMenu == nil)
    }

    @Test("switching top menus preserves one region owner and discards format drafts")
    func switchingTopMenusPreservesOneRegionOwner() {
        var state = PlaybackTopActionsState()

        state.toggleMenu(.videoFormat)
        state.projection = .equirectangular360
        state.toggleMenu(.dock)

        #expect(state.presentedMenu == .dock)
        #expect(state.projection == .flat)

        state.toggleMenu(.dock)
        #expect(state.presentedMenu == nil)
    }

    @Test("Quiet Room is the default Dock target and carries no Light or Dark appearance")
    func selectingQuietRoomRecordsNoAppearance() {
        var state = PlaybackTopActionsState()

        let requested = state.selectDockTarget(environment: .quietRoom, effect: nil)

        #expect(requested.0 == .quietRoom)
        #expect(requested.1 == nil)
        #expect(state.selectedDockEnvironment == .quietRoom)
        #expect(state.selectedEffect == nil)
        #expect(state.selectedDockEnvironment.supportsDarkAppearance == false)
    }
}
