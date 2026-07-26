import Testing
@testable import PlaybackCore

@Test func explicitAfterSeekBehaviorSelectsPlayOrPause() {
    #expect(PlaybackAfterSeekBehavior.play.resolvesStartsPaused(for: .paused) == false)
    #expect(PlaybackAfterSeekBehavior.pause.resolvesStartsPaused(for: .playing) == true)
}

@Test func preservingAfterSeekPauseStateKeepsOnlyThePausedLifecyclePaused() {
    #expect(
        PlaybackAfterSeekBehavior.preserveCurrentPauseState.resolvesStartsPaused(for: .paused)
    )
    #expect(
        PlaybackAfterSeekBehavior.preserveCurrentPauseState.resolvesStartsPaused(for: .playing)
            == false
    )
    #expect(
        PlaybackAfterSeekBehavior.preserveCurrentPauseState.resolvesStartsPaused(for: .ended)
            == false
    )
}
