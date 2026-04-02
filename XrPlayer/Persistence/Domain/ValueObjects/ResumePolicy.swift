import Foundation

extension PersistenceDomain {
    public enum ResumePolicy: Sendable, Hashable {
        case askEveryTime
        case alwaysResume
        case alwaysStartFromBeginning
    }
}
