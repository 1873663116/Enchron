import BluRayDisc
import Foundation

public enum PlaybackContentSelection: Sendable, Equatable {
    case file
    case bluRayPlaylist(BluRayPlaylistID, source: BluRayDiscSource)

    var bluRayPlaylistID: UInt32? {
        switch self {
        case .file: nil
        case .bluRayPlaylist(let playlist, _): playlist.rawValue
        }
    }
}
