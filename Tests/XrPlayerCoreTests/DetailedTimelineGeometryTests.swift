import XCTest
import CoreGraphics
@testable import XrPlayerCore

final class DetailedTimelineGeometryTests: XCTestCase {
    func testMinimumZoomKeepsTimelineAtHalfViewportWidth() {
        let sut = DetailedTimelineGeometry(viewportWidth: 600, duration: 240, zoomLevel: 0)

        XCTAssertEqual(sut.timelineWidth, 300, accuracy: 0.001)
    }

    func testMaximumZoomExpandsTimelineWidth() {
        let sut = DetailedTimelineGeometry(viewportWidth: 600, duration: 240, zoomLevel: 1)

        XCTAssertEqual(sut.timelineWidth, 2400, accuracy: 0.001)
    }

    func testOffsetForStartAlignsCenterAxisToFirstFrame() {
        let sut = DetailedTimelineGeometry(viewportWidth: 600, duration: 240, zoomLevel: 0.35)
        let offset = sut.contentOffset(for: 0)

        XCTAssertEqual(offset, sut.timelineWidth / 2, accuracy: 0.001)
        XCTAssertEqual(sut.timelineBodyLeadingX(for: offset), sut.centerAxisX, accuracy: 0.001)
    }

    func testOffsetForEndAlignsCenterAxisToLastFrame() {
        let sut = DetailedTimelineGeometry(viewportWidth: 600, duration: 240, zoomLevel: 0.35)
        let offset = sut.contentOffset(for: 240)

        XCTAssertEqual(offset, -sut.timelineWidth / 2, accuracy: 0.001)
        XCTAssertEqual(
            sut.timelineBodyLeadingX(for: offset) + sut.timelineWidth,
            sut.centerAxisX,
            accuracy: 0.001
        )
    }

    func testOffsetForMidpointCentersTimelineBody() {
        let sut = DetailedTimelineGeometry(viewportWidth: 600, duration: 240, zoomLevel: 0)
        let offset = sut.contentOffset(for: 120)

        XCTAssertEqual(offset, 0, accuracy: 0.001)
        XCTAssertEqual(sut.timelineBodyLeadingX(for: offset), 150, accuracy: 0.001)
    }

    func testTimeAndOffsetRoundTripStayStableAcrossZoomLevels() {
        let original = DetailedTimelineGeometry(viewportWidth: 640, duration: 360, zoomLevel: 0.15)
        let targetTime = 137.25
        let initialOffset = original.contentOffset(for: targetTime)
        let updated = DetailedTimelineGeometry(viewportWidth: 640, duration: 360, zoomLevel: 0.8)
        let updatedOffset = updated.contentOffset(for: targetTime)

        XCTAssertEqual(original.time(atContentOffset: initialOffset), targetTime, accuracy: 0.001)
        XCTAssertEqual(updated.time(atContentOffset: updatedOffset), targetTime, accuracy: 0.001)
    }

    func testTickIntervalGetsDenserAsTimelineExpands() {
        let zoomedOut = DetailedTimelineGeometry(viewportWidth: 600, duration: 600, zoomLevel: 0.1)
        let zoomedIn = DetailedTimelineGeometry(viewportWidth: 600, duration: 600, zoomLevel: 0.9)

        XCTAssertGreaterThan(zoomedOut.tickIntervals().minor, zoomedIn.tickIntervals().minor)
    }
}

final class DetailedTimelinePreviewSeekPolicyTests: XCTestCase {
    func testBoundaryTargetBypassesIntervalThrottle() {
        let sut = DetailedTimelinePreviewSeekPolicy()

        XCTAssertTrue(
            sut.shouldDispatchSeek(
                elapsed: 0.01,
                targetTime: 0,
                lastSeekTarget: 12,
                duration: 240
            )
        )
        XCTAssertTrue(
            sut.shouldDispatchSeek(
                elapsed: 0.01,
                targetTime: 240,
                lastSeekTarget: 228,
                duration: 240
            )
        )
    }

    func testBoundaryTargetDoesNotRedispatchSameEdge() {
        let sut = DetailedTimelinePreviewSeekPolicy()

        XCTAssertFalse(
            sut.shouldDispatchSeek(
                elapsed: 0.01,
                targetTime: 0,
                lastSeekTarget: 0,
                duration: 240
            )
        )
    }

    func testMidstreamTargetStillRespectsThrottle() {
        let sut = DetailedTimelinePreviewSeekPolicy()

        XCTAssertFalse(
            sut.shouldDispatchSeek(
                elapsed: 0.01,
                targetTime: 120,
                lastSeekTarget: 80,
                duration: 240
            )
        )
        XCTAssertTrue(
            sut.shouldDispatchSeek(
                elapsed: 0.2,
                targetTime: 120,
                lastSeekTarget: 80,
                duration: 240
            )
        )
    }
}
