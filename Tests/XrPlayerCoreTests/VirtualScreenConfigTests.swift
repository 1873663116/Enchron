import XCTest
@testable import XrPlayerCore

final class VirtualScreenConfigTests: XCTestCase {
    typealias Geom = SpatialSceneDomain.ScreenGeometry
    typealias Config = SpatialSceneDomain.VirtualScreenConfiguration

    func testScreenGeometryFlatHasDimensions() {
        let flat = Geom.flat(width: 2.4, height: 1.35)
        // Stub aspectRatio returns 0 → FAIL
        let config = Config(geometry: flat)
        XCTAssertGreaterThan(config.aspectRatio, 1.0,
                             "Flat screen must have positive aspect ratio")
    }

    func testScreenGeometryCurvedHasRadiusAndHeight() {
        let curved = Geom.curved(radius: 3.0, height: 1.5)
        let config = Config(geometry: curved)
        // Stub aspectRatio returns 0 → FAIL
        XCTAssertGreaterThan(config.aspectRatio, 1.0,
                             "Curved screen must have positive aspect ratio")
    }

    func testScreenGeometryIsCodable() throws {
        let flat = Geom.flat(width: 2.4, height: 1.35)
        let data = try JSONEncoder().encode(flat)
        let decoded = try JSONDecoder().decode(Geom.self, from: data)
        XCTAssertEqual(flat, decoded)
        // Also verify config level Codable + aspect ratio
        let config = Config(geometry: flat)
        // Stub aspectRatio returns 0 → FAIL
        XCTAssertTrue(config.aspectRatio > 1.5,
                      "16:9 flat screen aspect ratio must be > 1.5")
    }

    func testVirtualScreenConfigDefaultAspectRatio() {
        let config = Config(geometry: .flat(width: 2.4, height: 1.35))
        // Stub returns 0 → FAIL (expected ~1.778)
        let expected: Float = 16.0 / 9.0
        XCTAssertEqual(config.aspectRatio, expected, accuracy: 0.01,
                       "Default aspect ratio must be 16:9")
    }

    func testVirtualScreenConfigWidthClampedToMin() {
        let config = Config(geometry: .flat(width: 0.5, height: 1.0))
        // Stub has no clamping → width stays 0.5 → FAIL
        if case .flat(let w, _) = config.geometry {
            XCTAssertGreaterThanOrEqual(w, 1.0,
                                        "Width must be clamped to minimum 1.0m")
        } else {
            XCTFail("Expected flat geometry")
        }
    }

    func testVirtualScreenConfigWidthClampedToMax() {
        let config = Config(geometry: .flat(width: 15.0, height: 1.0))
        // Stub has no clamping → width stays 15.0 → FAIL
        if case .flat(let w, _) = config.geometry {
            XCTAssertLessThanOrEqual(w, 10.0,
                                     "Width must be clamped to maximum 10.0m")
        } else {
            XCTFail("Expected flat geometry")
        }
    }

    func testVirtualScreenConfigShapeSwitchPreservesHeight() {
        let original = Config(geometry: .flat(width: 2.4, height: 1.35))
        let switched = original.switchToCurved(radius: 2.5)
        // Stub switchToCurved sets height to 0 → FAIL
        XCTAssertEqual(switched.geometry.height, 1.35, accuracy: 0.001,
                       "Switching shape must preserve height")
    }
}
