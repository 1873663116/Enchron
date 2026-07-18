import CoreGraphics
import Testing
@testable import XrPlayerCore

@Suite("Window playback page geometry")
struct WindowPlaybackPageGeometryTests {
    @Test("the deck overlays the canvas without changing the video frame")
    func standardWindowGeometry() {
        let geometry = WindowPlaybackPageGeometry.resolve(
            in: CGSize(width: 1_280, height: 800),
            deckSize: CGSize(width: 728, height: 184),
            spacing: 16
        )

        #expect(geometry.canvasFrame == CGRect(x: 0, y: 0, width: 1_280, height: 800))
        #expect(geometry.deckFrame == CGRect(x: 276, y: 600, width: 728, height: 184))
        #expect(geometry.canvasFrame.intersects(geometry.deckFrame!))
    }

    @Test("hiding controls returns the whole page to the canvas")
    func controlsHiddenGeometry() {
        let geometry = WindowPlaybackPageGeometry.resolve(
            in: CGSize(width: 1_280, height: 800),
            deckSize: nil,
            spacing: 16
        )

        #expect(geometry.canvasFrame == CGRect(x: 0, y: 0, width: 1_280, height: 800))
        #expect(geometry.deckFrame == nil)
    }
}
