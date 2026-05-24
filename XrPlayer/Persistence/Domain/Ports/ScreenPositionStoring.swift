import Foundation

public nonisolated protocol ScreenPositionStoring: Sendable {
    func savePosition(
        for environmentID: String,
        distanceMeters: Double,
        verticalOffsetMeters: Double,
        angleDegrees: Double
    ) async

    func loadPosition(for environmentID: String) async -> PersistenceDomain.SavedScreenPosition?
}
