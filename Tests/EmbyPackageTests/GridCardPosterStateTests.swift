import Testing
@testable import DesignSystem

struct GridCardPosterStateTests {
    @Test("progress is clamped to the normalized range and rejects non-finite values")
    func progressNormalization() {
        #expect(state(progress: -0.25).watchedProgress == 0)
        #expect(state(progress: 0.4).watchedProgress == 0.4)
        #expect(state(progress: 1.25).watchedProgress == 1)
        #expect(state(progress: .nan).watchedProgress == nil)
        #expect(state(progress: .infinity).watchedProgress == nil)
    }

    @Test("unplayed count is present only when positive")
    func unplayedCountNormalization() {
        #expect(state(unplayedCount: -1).unplayedCount == nil)
        #expect(state(unplayedCount: 0).unplayedCount == nil)
        #expect(state(unplayedCount: 3).unplayedCount == 3)
    }

    private func state(
        progress: Double? = nil,
        unplayedCount: Int? = nil
    ) -> GridCard.PosterState {
        GridCard.PosterState(
            artworkURL: nil,
            watchedProgress: progress,
            unplayedCount: unplayedCount
        )
    }
}
