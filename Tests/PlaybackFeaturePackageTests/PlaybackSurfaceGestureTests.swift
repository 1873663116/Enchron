import Testing
@testable import Playback

struct PlaybackSurfaceGestureTests {
    @Test("hidden single tap waits before showing controls")
    func singleTapWaits() {
        var state = PlaybackSurfaceGestureState()
        let context = context()
        #expect(state.begin(at: 0, width: 600, context: context).isEmpty)
        #expect(state.end(at: 0.1, context: context).isEmpty)
        #expect(state.phase == .waitingForSecondTap)
        #expect(state.advance(to: 0.39, context: context).isEmpty)
        #expect(state.advance(to: 0.41, context: context) == [.toggleControls])
        #expect(state.phase == .idle)
    }

    @Test("hidden double tap toggles transport without controls")
    func doubleTapTogglesPlayback() {
        var state = PlaybackSurfaceGestureState()
        let context = context()
        _ = state.begin(at: 0, width: 600, context: context)
        _ = state.end(at: 0.05, context: context)
        _ = state.begin(at: 0.15, width: 600, context: context)
        #expect(state.end(at: 0.2, context: context) == [.togglePlayback])
        #expect(state.phase == .idle)
        #expect(state.advance(to: 1, context: context).isEmpty)
    }

    @Test("second contact suppresses the pending single tap deadline")
    func secondContactSuppressesDeadline() {
        var state = PlaybackSurfaceGestureState()
        let context = context()
        _ = state.begin(at: 0, width: 600, context: context)
        _ = state.end(at: 0.05, context: context)
        _ = state.begin(at: 0.3, width: 600, context: context)
        #expect(state.advance(to: 0.36, context: context).isEmpty)
        #expect(state.end(at: 0.4, context: context) == [.togglePlayback])
    }

    @Test("visible controls lock the whole double tap sequence to dismissal")
    func visibleControlsLockSequence() {
        var state = PlaybackSurfaceGestureState()
        var context = context()
        context.controlsVisible = true
        _ = state.begin(at: 0, width: 600, context: context)
        #expect(state.end(at: 0.05, context: context) == [.dismissControls])
        context.controlsVisible = false
        _ = state.begin(at: 0.15, width: 600, context: context)
        #expect(state.end(at: 0.2, context: context).isEmpty)
        #expect(state.advance(to: 1, context: context).isEmpty)
        _ = state.begin(at: 2, width: 600, context: context)
        _ = state.end(at: 2.05, context: context)
        #expect(state.advance(to: 2.4, context: context) == [.toggleControls])
    }

    @Test("visible controls ignore a drag and a long contact")
    func visibleControlsRejectShortcuts() {
        var state = PlaybackSurfaceGestureState()
        var context = context()
        context.controlsVisible = true
        _ = state.begin(at: 0, width: 600, context: context)
        #expect(state.update(horizontal: 100, vertical: 0, at: 0.1, context: context).isEmpty)
        #expect(state.end(at: 0.2, context: context).isEmpty)
        _ = state.begin(at: 1, width: 600, context: context)
        #expect(state.advance(to: 1.4, context: context).isEmpty)
        #expect(state.end(at: 1.5, context: context).isEmpty)
        _ = state.begin(at: 2, width: 600, context: context)
        #expect(state.end(at: 2.1, context: context) == [.dismissControls])
    }

    @Test("holding uses an absolute rate and restores the original rate")
    func holdRestoresRate() {
        var state = PlaybackSurfaceGestureState()
        var context = context()
        context.playbackRate = 1.5
        context.holdPlaybackRate = 3
        _ = state.begin(at: 0, width: 600, context: context)
        #expect(state.advance(to: 0.36, context: context) == [.setRate(3)])
        #expect(state.phase == .holding)
        #expect(state.update(horizontal: 500, vertical: 0, at: 0.5, context: context).isEmpty)
        #expect(state.phase == .holding)
        #expect(state.end(at: 0.6, context: context) == [.setRate(1.5)])
    }

    @Test("paused holding has no rate effect and can still become a seek")
    func pausedHoldDoesNotStart() {
        var state = PlaybackSurfaceGestureState()
        var context = context()
        context.isPlaying = false
        _ = state.begin(at: 0, width: 600, context: context)
        #expect(state.advance(to: 0.4, context: context).isEmpty)
        #expect(state.update(horizontal: 300, vertical: 0, at: 0.5, context: context) == [.seekPreviewActive(true)])
        #expect(state.phase == .seeking)
        #expect(state.end(at: 0.6, context: context) == [.seek(targetSeconds: 130, wasPlaying: false), .seekPreviewActive(false)])
    }

    @Test("horizontal threshold wins before holding and fixes the moving playback origin")
    func seekLocksAndFixesOrigin() {
        var state = PlaybackSurfaceGestureState()
        var context = context()
        _ = state.begin(at: 0, width: 600, context: context)
        context.positionSeconds = 103
        #expect(state.update(horizontal: 12, vertical: 0, at: 0.34, context: context) == [.seekPreviewActive(true)])
        #expect(state.phase == .seeking)
        #expect(state.advance(to: 0.5, context: context).isEmpty)
        context.positionSeconds = 140
        _ = state.update(horizontal: 300, vertical: 0, at: 0.6, context: context)
        #expect(state.preview?.originSeconds == 103)
        #expect(state.preview?.offsetSeconds == 30)
        #expect(state.preview?.targetSeconds == 133)
        #expect(state.end(at: 0.7, context: context) == [.seek(targetSeconds: 133, wasPlaying: true), .seekPreviewActive(false)])
    }

    @Test("expired hold locks even if the timer delivery was late")
    func expiredHoldWins() {
        var state = PlaybackSurfaceGestureState()
        let context = context()
        _ = state.begin(at: 0, width: 600, context: context)
        #expect(state.update(horizontal: 300, vertical: 0, at: 0.36, context: context) == [.setRate(2)])
        #expect(state.phase == .holding)
        #expect(state.end(at: 0.4, context: context) == [.setRate(1)])
    }

    @Test("seek returns to zero without committing")
    func returnToZeroDoesNotSeek() {
        var state = PlaybackSurfaceGestureState()
        let context = context()
        _ = state.begin(at: 0, width: 600, context: context)
        _ = state.update(horizontal: 300, vertical: 0, at: 0.1, context: context)
        #expect(state.preview?.targetSeconds == 130)
        _ = state.update(horizontal: 0, vertical: 0, at: 0.5, context: context)
        #expect(state.preview?.offsetSeconds == 0)
        #expect(state.end(at: 0.6, context: context) == [.seekPreviewActive(false)])
    }

    @Test("seek clips both ends and exposes reachable offsets")
    func clipsBoundaries() {
        var state = PlaybackSurfaceGestureState()
        var context = context()
        context.positionSeconds = 3
        context.durationSeconds = 20
        _ = state.begin(at: 0, width: 600, context: context)
        _ = state.update(horizontal: -1_200, vertical: 0, at: 0.1, context: context)
        #expect(state.preview?.targetSeconds == 0)
        #expect(state.preview?.offsetSeconds == -3)
        #expect(state.preview?.lowerReachableOffsetSeconds == -3)
        #expect(state.preview?.upperReachableOffsetSeconds == 17)
        _ = state.update(horizontal: 1_200, vertical: 0, at: 0.2, context: context)
        #expect(state.preview?.targetSeconds == 20)
        #expect(state.end(at: 0.3, context: context) == [.seek(targetSeconds: 20, wasPlaying: true), .seekPreviewActive(false)])
    }

    @Test("fractional media duration stays within the displayed precision")
    func fractionalDurationDoesNotOvershoot() {
        var state = PlaybackSurfaceGestureState()
        var context = context()
        context.positionSeconds = 25.9
        context.durationSeconds = 29.6
        _ = state.begin(at: 0, width: 600, context: context)
        _ = state.update(horizontal: 300, vertical: 0, at: 0.1, context: context)
        #expect(state.preview?.originSeconds == 25)
        #expect(state.preview?.offsetSeconds == 4)
        #expect(state.preview?.targetSeconds == 29)
        #expect(state.end(at: 0.2, context: context) == [.seek(targetSeconds: 29, wasPlaying: true), .seekPreviewActive(false)])
    }

    @Test("seek elastic mapping stays inside thirty seconds")
    func dampsLargeTranslation() {
        var state = PlaybackSurfaceGestureState()
        let context = context()
        _ = state.begin(at: 0, width: 600, context: context)
        _ = state.update(horizontal: 6_000, vertical: 0, at: 0.1, context: context)
        #expect(state.preview?.offsetSeconds == 30)
        #expect(state.end(at: 0.2, context: context) == [.seek(targetSeconds: 130, wasPlaying: true), .seekPreviewActive(false)])
    }

    @Test("cancel restores a hold and discards a seek preview")
    func cancelClearsTransientState() {
        var state = PlaybackSurfaceGestureState()
        let context = context()
        _ = state.begin(at: 0, width: 600, context: context)
        _ = state.advance(to: 0.4, context: context)
        #expect(state.cancel() == [.setRate(1)])
        #expect(state.phase == .idle)
        _ = state.begin(at: 1, width: 600, context: context)
        _ = state.update(horizontal: 300, vertical: 0, at: 1.1, context: context)
        #expect(state.preview?.targetSeconds == 130)
        #expect(state.cancel() == [.seekPreviewActive(false)])
        #expect(state.preview == nil)
        #expect(state.end(at: 1.2, context: context).isEmpty)
    }

    @Test("vertical displacement rejects the contact without becoming a tap")
    func verticalRejectsContact() {
        var state = PlaybackSurfaceGestureState()
        let context = context()
        _ = state.begin(at: 0, width: 600, context: context)
        _ = state.update(horizontal: 1, vertical: 15, at: 0.1, context: context)
        #expect(state.phase == .rejected)
        #expect(state.end(at: 0.2, context: context).isEmpty)
        _ = state.begin(at: 1, width: 600, context: context)
        _ = state.end(at: 1.1, context: context)
        #expect(state.advance(to: 1.5, context: context) == [.toggleControls])
    }

    @Test("slow seek keeps the latest toggle and restored rate")
    func transportKeepsLatestIntent() {
        var intent = PlaybackSurfaceTransportIntent()
        intent.preservePlayback(isPlaying: true)
        let oldRevision = intent.revision
        #expect(intent.toggle(isPlaying: true) == false)
        intent.preservePlayback(isPlaying: true)
        #expect(intent.desiredPlaying == false)
        intent.setRate(2)
        intent.setRate(1.5)
        #expect(intent.desiredRate == 1.5)
        #expect(intent.revision != oldRevision)
        #expect(intent.toggle(isPlaying: true) == true)
        intent.clear()
        #expect(intent.toggle(isPlaying: false) == true)
    }

    @Test("immersive presentations take eight times the window travel")
    func immersiveTravelIsEightTimesTheWindow() {
        #expect(PlaybackSurfaceSeekTravel.width(for: .window) == 1_200)
        #expect(PlaybackSurfaceSeekTravel.width(for: .portal) == 1_200)
        #expect(PlaybackSurfaceSeekTravel.width(for: .docked) == 9_600)
        #expect(PlaybackSurfaceSeekTravel.width(for: .panorama) == 9_600)
    }

    @Test("equal hand travel reaches the same seek offset in every presentation")
    func equalHandTravelReachesSameOffset() {
        let windowOffset = PlaybackSurfaceGesturePreview(
            originSeconds: 100,
            durationSeconds: 1_000,
            translation: 300,
            width: PlaybackSurfaceSeekTravel.width(for: .window)
        )
        let immersiveOffset = PlaybackSurfaceGesturePreview(
            originSeconds: 100,
            durationSeconds: 1_000,
            translation: 2_400,
            width: PlaybackSurfaceSeekTravel.width(for: .docked)
        )
        #expect(windowOffset.offsetSeconds == 21)
        #expect(immersiveOffset.offsetSeconds == 21)

        let windowCeiling = PlaybackSurfaceGesturePreview(
            originSeconds: 100,
            durationSeconds: 1_000,
            translation: 600,
            width: PlaybackSurfaceSeekTravel.width(for: .window)
        )
        let immersiveCeiling = PlaybackSurfaceGesturePreview(
            originSeconds: 100,
            durationSeconds: 1_000,
            translation: 4_800,
            width: PlaybackSurfaceSeekTravel.width(for: .panorama)
        )
        #expect(windowCeiling.offsetSeconds == 30)
        #expect(immersiveCeiling.offsetSeconds == 30)
    }

    private func context() -> PlaybackSurfaceGestureContext {
        PlaybackSurfaceGestureContext(controlsVisible: false, enabled: true, isPlaying: true, positionSeconds: 100, durationSeconds: 1_000, playbackRate: 1, holdPlaybackRate: 2)
    }
}
