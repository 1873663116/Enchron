import Foundation

struct PlaybackSourceDescription: Sendable {
    let epoch: UInt64?
    let information: MediaSourceInformation
    let audioTracks: [PlaybackAudioTrack]
    let subtitleTracks: [PlaybackSubtitleTrack]

    var mediaKind: PlaybackMediaKind { information.playbackMediaKind }
    var durationSeconds: Double { information.durationSeconds }
    var streamCount: Int { information.streams.count }
}
