import CoreGraphics
import DesignSystem
import PlaybackFeature
import PlaybackPresentation
import Testing
@testable import Enchron

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

    @Test("window width bounds derive from the rendered ornament width")
    func ornamentDrivenWindowWidths() {
        let layout = WindowPlaybackLayout.fallback

        #expect(DesignTokens.ControlBar.outerWidth == 728)
        #expect(layout.minimumSize == CGSize(width: 912, height: 513))
        #expect(layout.defaultSize == CGSize(width: 1_280, height: 720))
        #expect(layout.maximumSize == CGSize(width: 1_808, height: 1_017))
    }

    @Test("Portal uses bounded freeform geometry")
    func portalWindowUsesBoundedFreeformGeometry() {
        let videoLayout = WindowPlaybackLayout(aspectRatio: 1)

        #expect(
            WindowPlaybackGeometryPolicy(
                presentation: .portal,
                videoLayout: videoLayout
            ) == .freeform(
                defaultSize: PortalWindowLayout.defaultSize,
                minimumSize: PortalWindowLayout.minimumSize,
                maximumSize: PortalWindowLayout.maximumSize
            )
        )
        #expect(PortalWindowLayout.minimumSize == CGSize(width: 912, height: 513))
        #expect(PortalWindowLayout.defaultSize == CGSize(width: 1_280, height: 720))
        #expect(PortalWindowLayout.maximumSize == CGSize(width: 1_808, height: 1_017))
        #expect(PortalWindowLayout.contains(PortalWindowLayout.minimumSize))
        #expect(PortalWindowLayout.contains(PortalWindowLayout.maximumSize))
        #expect(
            PortalWindowLayout.contains(
                CGSize(width: 911, height: PortalWindowLayout.minimumSize.height)
            ) == false
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

    @Test("available canvas sizes resolve to a bounded source aspect surface")
    func fittedPlaybackWindowSizes() {
        let layout = WindowPlaybackLayout(aspectRatio: 4.0 / 3.0)
        let narrow = layout.sizeThatFits(
            CGSize(width: 1_000, height: 1_000)
        )
        let wide = layout.sizeThatFits(
            CGSize(width: 4_000, height: 800)
        )
        let tooSmall = layout.sizeThatFits(
            CGSize(width: 100, height: 100)
        )
        let tooLarge = layout.sizeThatFits(
            CGSize(width: 4_000, height: 4_000)
        )

        #expect(narrow == CGSize(width: 1_000, height: 750))
        #expect(abs(wide.width - 1_066.6666666666667) < 0.001)
        #expect(abs(wide.height - 800) < 0.001)
        #expect(tooSmall == layout.minimumSize)
        #expect(tooLarge == layout.maximumSize)
        #expect(layout.hasPlaybackAspectRatio(narrow))
        #expect(layout.hasPlaybackAspectRatio(wide))
        #expect(layout.hasPlaybackAspectRatio(tooSmall))
        #expect(layout.hasPlaybackAspectRatio(tooLarge))
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
            environment: .scenicThree,
            effect: .dark
        )

        #expect(requested.0 == .scenicThree)
        #expect(requested.1 == .dark)
        #expect(state.selectedDockEnvironment == .scenicThree)
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

    @Test("Skybox is a Dock target without a Light or Dark appearance")
    func selectingSkyboxRecordsNoAppearance() {
        var state = PlaybackTopActionsState()

        let requested = state.selectDockTarget(environment: .skybox, effect: nil)

        #expect(requested.0 == .skybox)
        #expect(requested.1 == nil)
        #expect(state.selectedDockEnvironment == .skybox)
        #expect(state.selectedEffect == nil)
    }
}
