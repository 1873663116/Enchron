import XCTest
@testable import EnchronMacOS

nonisolated final class EnvironmentCarouselLayoutTests: XCTestCase {
    @MainActor
    func testRenderSlotIdentityRemainsContinuousAcrossMultipleCycles() {
        var previous = EnvironmentCarouselLayout.renderSlots(
            environmentCount: 3,
            scrollPosition: -6,
            maximumDistance: 2.18
        )

        for step in -599...600 {
            let current = EnvironmentCarouselLayout.renderSlots(
                environmentCount: 3,
                scrollPosition: CGFloat(step) / 100,
                maximumDistance: 2.18
            )
            let positionsBefore = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.visualPosition) })
            let positionsAfter = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.visualPosition) })

            for id in positionsBefore.keys where positionsAfter[id] != nil {
                XCTAssertEqual(
                    positionsAfter[id]!,
                    positionsBefore[id]! - 0.01,
                    accuracy: 0.0001,
                    "A stable render slot must follow the drag continuously instead of crossing the stage"
                )
            }
            previous = current
        }
    }
}
