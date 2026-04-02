import Foundation

extension SpatialSceneDomain {
    public enum CinemaEnvironment: String, Sendable, CaseIterable, Codable {
        case darkTheatre
        case starryNight
        case sunsetNature

        /// Human-readable name for UI display.
        /// Stub: returns empty string → display name tests FAIL.
        public var displayName: String { "" }

        /// Skybox asset name. nil = no external asset needed (pure dark environment).
        /// Stub: always nil → starryNight/sunsetNature tests FAIL.
        public var skyboxAssetName: String? { nil }
    }
}
