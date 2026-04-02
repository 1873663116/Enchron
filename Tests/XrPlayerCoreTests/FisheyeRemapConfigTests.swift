import XCTest
@testable import XrPlayerCore

final class FisheyeRemapConfigTests: XCTestCase {
    typealias Config = SpatialSceneDomain.FisheyeRemapConfiguration

    func testFisheyeDefaultFOVIsHalfPi() {
        let config = Config()
        let halfPi = Float.pi / 2
        // Stub default FOV = 0 → FAIL (expected π/2)
        XCTAssertEqual(config.fovRadiusRadians, halfPi, accuracy: 0.001,
                       "Default FOV must be π/2 radians (180° fisheye)")
    }

    func testFisheyeCenterPixelMapsToCenter() {
        let config = Config(fovRadiusRadians: Float.pi / 2)
        // Stub always returns nil → FAIL
        let result = config.sampleCoordinate(outputU: 0.5, outputV: 0.5)
        XCTAssertNotNil(result, "Center pixel must map to a valid coordinate")
        if let r = result {
            XCTAssertEqual(r.u, 0.5, accuracy: 0.01)
            XCTAssertEqual(r.v, 0.5, accuracy: 0.01)
        }
    }

    func testFisheyeOutOfFOVReturnsNil() {
        let config = Config(fovRadiusRadians: Float.pi / 4)
        // Point far from center, outside FOV
        // Stub always returns nil → this specific assertion PASSES
        // But we also test that center DOES map → stub returns nil for center too → FAIL
        let edge = config.sampleCoordinate(outputU: 0.0, outputV: 0.0)
        XCTAssertNil(edge, "Point outside FOV should return nil")
        // Also verify center works (stub fails here)
        let center = config.sampleCoordinate(outputU: 0.5, outputV: 0.5)
        XCTAssertNotNil(center, "Center point must be within FOV")
    }
}
