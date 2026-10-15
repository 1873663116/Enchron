import simd

nonisolated enum TidalScenePlacement {
    static let rootHeight: Float = 0.8
    static let debrisOffsets: [(String, SIMD3<Float>)] = [
        ("BrokenRoad01", [0, 0, -2]),
        ("BuildingFragment02", [0, 10, 0])
    ]

    static func isFragment(_ name: String) -> Bool {
        name.hasPrefix("RockFragment") && !name.hasSuffix("Mesh")
            || name == "BrokenRoad01" || name == "BuildingFragment02"
    }
}
