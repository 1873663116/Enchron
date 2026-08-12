import Testing
@testable import Emby

struct EmbyPosterItemTests {
    @Test("progress is clamped to the normalized range and rejects non-finite values")
    func progressNormalization() {
        #expect(item(progress: -0.25).progress == 0)
        #expect(item(progress: 0.4).progress == 0.4)
        #expect(item(progress: 1.25).progress == 1)
        #expect(item(progress: .nan).progress == nil)
        #expect(item(progress: .infinity).progress == nil)
    }

    @Test("unplayed count is present only when positive")
    func unplayedCountNormalization() {
        #expect(item(unplayedCount: -1).unplayedCount == nil)
        #expect(item(unplayedCount: 0).unplayedCount == nil)
        #expect(item(unplayedCount: 3).unplayedCount == 3)
    }

    private func item(
        progress: Double? = nil,
        unplayedCount: Int? = nil
    ) -> EmbyPosterItem {
        EmbyPosterItem(
            id: EmbyItemID(rawValue: "fixture"),
            title: "Fixture",
            progress: progress,
            unplayedCount: unplayedCount
        )
    }
}
