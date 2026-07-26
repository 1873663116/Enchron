import Foundation

public enum NaturalMediaNameOrder {
    public static func lessThan(
        _ leftName: String,
        id leftID: UUID,
        _ rightName: String,
        id rightID: UUID
    ) -> Bool {
        let comparison = leftName.localizedStandardCompare(rightName)
        if comparison == .orderedSame {
            return leftID.uuidString < rightID.uuidString
        }
        return comparison == .orderedAscending
    }
}
