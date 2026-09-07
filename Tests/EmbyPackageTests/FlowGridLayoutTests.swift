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

    @Test("the layout reports the widest row, not the proposed width, so a grid can be centred")
    func usedWidthIsTheWidestRow() {
        let card = CGSize(width: 100, height: 50)
        let arrangement = FlowGridLayout.arrange(
            sizes: Array(repeating: card, count: 5),
            width: 370,
            spacing: 10
        )
        #expect(arrangement.usedWidth == 320)
        #expect(FlowGridLayout.arrange(sizes: [], width: 370, spacing: 10).usedWidth == 0)
    }

    @Test("a partial row still reports the full row width so it stays left-aligned inside a centred block")
    func partialRowKeepsTheFullRowWidth() {
        let card = CGSize(width: 100, height: 50)
        let partial = FlowGridLayout.arrange(sizes: Array(repeating: card, count: 2), width: 370, spacing: 10)
        #expect(partial.usedWidth == 320)
        #expect(partial.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 110, y: 0)])
    }
}
