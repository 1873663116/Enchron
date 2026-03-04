import Foundation

extension PersistenceDomain {
    public enum ResumePolicy: Sendable {
        case askEveryTime
        case alwaysResume
        case alwaysStartFromBeginning
    }
}
