import Foundation

extension PersistenceDomain {
    public enum PlaybackEndBehavior: Sendable, Hashable {
        case stop
        case repeatOne
        case playNext
    }
}
