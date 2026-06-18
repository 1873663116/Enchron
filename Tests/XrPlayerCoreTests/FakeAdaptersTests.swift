import Foundation
import Testing
@testable import XrPlayerCore

@Suite("FakePlaybackSource")
struct FakePlaybackSourceTests {
    @Test("play then tick advances position by real time")
    func tickAdvancesPosition() async throws {
        let source = FakePlaybackSource(duration: 100)
        try await source.play(url: URL(fileURLWithPath: "/tmp/fake.mp4"))

        source.tick(realSeconds: 10)

        #expect(source.currentState == .playing)
        #expect(source.currentPosition.seconds == 10)
    }

    @Test("setSpeed doubles the advance rate")
    func speedDoublesAdvance() async throws {
        let source = FakePlaybackSource(duration: 100)
        try await source.play(url: URL(fileURLWithPath: "/tmp/fake.mp4"))
        source.setSpeed(PlaybackCoreDomain.PlaybackSpeed(2.0))

        source.tick(realSeconds: 10)

        #expect(source.currentPosition.seconds == 20)
    }

    @Test("skip never goes below zero")
    func skipClampsToZero() async throws {
        let source = FakePlaybackSource(duration: 100)
        try await source.play(url: URL(fileURLWithPath: "/tmp/fake.mp4"))
        source.seek(to: 5)

        source.skip(by: -30)

        #expect(source.currentPosition.seconds == 0)
    }

    @Test("seek clamps to duration")
    func seekClampsToDuration() async throws {
        let source = FakePlaybackSource(duration: 100)
        try await source.play(url: URL(fileURLWithPath: "/tmp/fake.mp4"))

        source.seek(to: 500)

        #expect(source.currentPosition.seconds == 100)
    }

    @Test("reaching duration ends playback and fires onPlaybackEnded")
    func reachingDurationEnds() async throws {
        let source = FakePlaybackSource(duration: 100)
        var endedFired = false
        source.onPlaybackEnded = { endedFired = true }
        try await source.play(url: URL(fileURLWithPath: "/tmp/fake.mp4"))

        source.tick(realSeconds: 200)

        #expect(source.currentState == .ended)
        #expect(source.currentPosition.seconds == 100)
        #expect(endedFired)
    }

    @Test("loadPaused loads to paused at zero without advancing")
    func loadPausedStaysPaused() async throws {
        let source = FakePlaybackSource(duration: 100)
        try await source.loadPaused(url: URL(fileURLWithPath: "/tmp/fake.mp4"))

        source.tick(realSeconds: 10)

        #expect(source.currentState == .paused)
        #expect(source.currentPosition.seconds == 0)
    }
}

@Suite("FakePreferencesStore")
struct FakePreferencesStoreTests {
    @Test("save then load round-trips preferences")
    func saveLoadRoundTrips() {
        let store = FakePreferencesStore()
        let preferences = PersistenceDomain.UserPreferences(
            resumePolicy: .alwaysResume,
            playbackEndBehavior: .playNext,
            defaultPlaybackSpeed: 1.5,
            defaultEnvironmentID: "cinema",
            isScreenCurved: true
        )

        store.savePreferences(preferences)

        #expect(store.loadPreferences() == preferences)
    }

    @Test("loadPreferences returns the seeded initial value")
    func loadReturnsInitial() {
        let initial = PersistenceDomain.UserPreferences(defaultPlaybackSpeed: 2.0)
        let store = FakePreferencesStore(initial: initial)

        #expect(store.loadPreferences() == initial)
    }
}
