import XCTest
@testable import XrPlayerCore

final class HemisphereMeshConfigTests: XCTestCase {
    typealias Config = SpatialSceneDomain.HemisphereMeshConfiguration

    func testHemisphereUVRangeForFrontHalf() {
        let config = Config()
        // Stub returns 0...0 → FAIL (expected 0.25...0.75)
        XCTAssertEqual(config.uRange.lowerBound, 0.25, accuracy: 0.001)
        XCTAssertEqual(config.uRange.upperBound, 0.75, accuracy: 0.001)
    }

    func testHemisphereLongitudeRange() {
        let config = Config()
        let halfPi = Float.pi / 2
        // Stub returns 0...0 → FAIL (expected -π/2...π/2)
        XCTAssertEqual(config.longitudeRange.lowerBound, -halfPi, accuracy: 0.001)
        XCTAssertEqual(config.longitudeRange.upperBound, halfPi, accuracy: 0.001)
    }

    func testHemisphereVertexCount() {
        let config = Config(stacks: 64, slices: 64)
        // Stub returns 0 → FAIL (expected (64+1)*(64+1) = 4225)
        XCTAssertEqual(config.vertexCount, 4225)
    }

    func testHemisphereFullLatitudeRange() {
        let config = Config()
        // Stub returns 0...0 → FAIL (expected 0.0...1.0)
        XCTAssertEqual(config.vRange.lowerBound, 0.0, accuracy: 0.001)
        XCTAssertEqual(config.vRange.upperBound, 1.0, accuracy: 0.001)
    }
}
