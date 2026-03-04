import Foundation

public protocol ScreenPositionStoring {
    func savePosition(
        for environmentID: String,
        distanceMeters: Double,
        verticalOffsetMeters: Double,
        angleDegrees: Double
    ) async

    func loadPosition(for environmentID: String) async -> PersistenceDomain.SavedScreenPosition?
}
