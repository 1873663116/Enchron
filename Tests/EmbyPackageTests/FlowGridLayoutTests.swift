import CoreGraphics
import DesignSystem
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

    @Test("a full row is justified: the remainder widens the gaps and the last card ends at the width")
    func fullRowsAreJustified() {
        let card = CGSize(width: 100, height: 50)
        let arrangement = FlowGridLayout.arrange(sizes: Array(repeating: card, count: 5), width: 370, spacing: 10)
        #expect(arrangement.origins[2].x == 270)
        #expect(arrangement.origins[3] == CGPoint(x: 0, y: 60))
        #expect(arrangement.origins[4].x == 135)
    }

    @Test("gaps never shrink below the base spacing and a single column stays at the leading edge")
    func gapsKeepTheBaseSpacing() {
        let card = CGSize(width: 100, height: 50)
        #expect(FlowGridLayout.arrange(sizes: Array(repeating: card, count: 2), width: 210, spacing: 10).origins[1].x == 110)
        #expect(FlowGridLayout.arrange(sizes: Array(repeating: card, count: 2), width: 150, spacing: 10).origins[1] == CGPoint(x: 0, y: 60))
    }
}
