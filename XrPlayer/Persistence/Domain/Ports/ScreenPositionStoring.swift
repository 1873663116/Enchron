import Foundation

public nonisolated protocol ScreenPositionStoring: Sendable {
    func savePosition(
        for environmentID: String,
        depthOffsetMeters: Double,
        verticalOffsetMeters: Double,
        angleDegrees: Double,
        screenScale: Double
    ) async

    func loadPosition(for environmentID: String) async -> PersistenceDomain.SavedScreenPosition?
}
