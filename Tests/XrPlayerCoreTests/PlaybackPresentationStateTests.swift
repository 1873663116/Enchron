import Testing
@testable import XrPlayerCore

@Suite("Playback presentation")
struct PlaybackPresentationStateTests {
    @Test("direct dock uses the active environment")
    func directDockUsesActiveEnvironment() throws {
        var state = PlaybackPresentationState(
            environment: .active(.starryNight)
        )

        let transition = try state.begin(.docked)
        try state.commit(transition.id)

        #expect(state.presented == .docked)
        #expect(state.environment == .active(.starryNight))
    }

    @Test("direct dock opens the default environment when none is active")
    func directDockUsesDefaultEnvironment() throws {
        var state = PlaybackPresentationState()

        let transition = try state.begin(
            .docked,
            defaultEnvironment: .sunsetNature
        )
        try state.commit(transition.id)

        #expect(state.presented == .docked)
        #expect(state.environment == .active(.sunsetNature))
    }

    @Test("dock menu selection replaces the environment")
    func dockMenuSelectionReplacesEnvironment() throws {
        var state = PlaybackPresentationState(
            environment: .active(.darkTheatre)
        )

        let transition = try state.begin(
            .docked,
            environment: .starryNight
        )
        try state.commit(transition.id)

        #expect(state.environment == .active(.starryNight))
    }

    @Test("undock returns to window without closing the environment")
    func undockKeepsEnvironment() throws {
        var state = PlaybackPresentationState(
            presented: .docked,
            environment: .active(.darkTheatre)
        )

        let transition = try state.begin(.window)
        try state.commit(transition.id)

        #expect(state.presented == .window)
        #expect(state.environment == .active(.darkTheatre))
    }

    @Test("panorama rollback restores window and its environment context")
    func panoramaRollbackRestoresPreviousState() throws {
        var state = PlaybackPresentationState(
            environment: .active(.sunsetNature)
        )

        let transition = try state.begin(.panorama)
        state.rollback(transition.id)

        #expect(state.presented == .window)
        #expect(state.environment == .active(.sunsetNature))
        #expect(state.transition == nil)
    }

    @Test("a transition rejects a second product command")
    func transitionRejectsSecondCommand() throws {
        var state = PlaybackPresentationState()
        _ = try state.begin(.panorama)

        #expect(throws: PlaybackPresentationTransitionError.transitionInFlight) {
            try state.begin(.docked)
        }
    }

    @Test("docked and panorama cannot transition directly")
    func spatialPresentationsReturnThroughWindow() {
        var state = PlaybackPresentationState(
            presented: .docked,
            environment: .active(.darkTheatre)
        )

        #expect(throws: PlaybackPresentationTransitionError.directSpatialTransitionNotSupported) {
            try state.begin(.panorama)
        }
    }
}
