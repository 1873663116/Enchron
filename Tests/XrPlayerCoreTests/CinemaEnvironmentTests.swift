import XCTest
@testable import XrPlayerCore

final class CinemaEnvironmentTests: XCTestCase {
    typealias Env = SpatialSceneDomain.CinemaEnvironment

    func testCinemaEnvironmentHasThreeCasesWithValidNames() {
        let all = Env.allCases
        XCTAssertEqual(all.count, 3)
        // Stub returns "" for displayName → FAIL
        XCTAssertFalse(Env.darkTheatre.displayName.isEmpty,
                       "darkTheatre must have a non-empty display name")
    }

    func testCinemaEnvironmentRawValuesAreUniqueAndDescriptive() {
        let rawValues = Env.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count)
        // Stub returns "" for displayName → FAIL
        for env in Env.allCases {
            XCTAssertFalse(env.displayName.isEmpty,
                           "\(env) must have a non-empty display name")
        }
    }

    func testDarkTheatreRequiresNoSkyboxAsset() {
        XCTAssertNil(Env.darkTheatre.skyboxAssetName)
        // Stub returns "" for displayName → FAIL
        XCTAssertEqual(Env.darkTheatre.displayName, "暗黑影院")
    }

    func testStarryNightHasSkyboxAsset() {
        // Stub returns nil → FAIL
        XCTAssertNotNil(Env.starryNight.skyboxAssetName,
                        "starryNight must reference a skybox asset")
    }

    func testSunsetNatureHasSkyboxAsset() {
        // Stub returns nil → FAIL
        XCTAssertNotNil(Env.sunsetNature.skyboxAssetName,
                        "sunsetNature must reference a skybox asset")
    }

    func testCinemaEnvironmentCodableRoundTrip() throws {
        for env in Env.allCases {
            let data = try JSONEncoder().encode(env)
            let decoded = try JSONDecoder().decode(Env.self, from: data)
            XCTAssertEqual(env, decoded)
            // Stub returns "" for displayName → FAIL
            XCTAssertFalse(decoded.displayName.isEmpty,
                           "decoded \(env) must have a non-empty display name")
        }
    }
}
