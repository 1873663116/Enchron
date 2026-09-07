import CoreGraphics
import DesignSystem
import SwiftUI
import Testing

struct FlowGridLayoutTests {
    @Test("cards wrap to the next row only when the next card no longer fits")
    func cardsWrapAtTheWidth() {
        let card = CGSize(width: 100, height: 50)
        let arrangement = FlowGridLayout.arrange(
            sizes: Array(repeating: card, count: 5),
            width: 320,
            spacing: 10
        )
        #expect(arrangement.origins == [
            CGPoint(x: 0, y: 0), CGPoint(x: 110, y: 0), CGPoint(x: 220, y: 0),
            CGPoint(x: 0, y: 60), CGPoint(x: 110, y: 60)
        ])
        #expect(arrangement.totalHeight == 110)
    }

    @Test("a narrower width moves cards without changing their order")
    func narrowerWidthKeepsOrder() {
        let card = CGSize(width: 100, height: 50)
        let wide = FlowGridLayout.arrange(sizes: Array(repeating: card, count: 4), width: 450, spacing: 10)
        let narrow = FlowGridLayout.arrange(sizes: Array(repeating: card, count: 4), width: 230, spacing: 10)
        #expect(wide.origins.count == narrow.origins.count)
        #expect(wide.totalHeight == 50)
        #expect(narrow.totalHeight == 110)
        #expect(narrow.origins[2] == CGPoint(x: 0, y: 60))
    }

    @Test("columns stretch so the rows fill the width exactly and never shrink below the minimum")
    func columnsFillTheWidth() {
        #expect(CardGrid<EmptyView>.columnWidth(filling: 1_024, minimumCardWidth: 224, spacing: 16) == 244)
        #expect(abs(CardGrid<EmptyView>.columnWidth(filling: 744, minimumCardWidth: 180, spacing: 16) - 712 / 3) < 0.001)
        #expect(CardGrid<EmptyView>.columnWidth(filling: 100, minimumCardWidth: 224, spacing: 16) == 224)
    }
}
