import BluRayDisc
import Foundation
import Playback
import PlaybackCore
import Testing

struct BluRayPlaybackLaunchTests {
    @Test func playlistsKeepSeparateRequestsAndRetainTheirTransport() {
        let discURL = URL(fileURLWithPath: "/Films/Feature.iso")
        let disc = BluRayDiscSource.url(discURL)
        let source = PlaybackAddress(discSource: disc)
        let first = PlaybackLaunchRequest(
            source: source,
            contentSelection: .bluRayPlaylist(BluRayPlaylistID(rawValue: 42), source: disc),
            displayName: "Playlist 00042",
            sourceAccess: nil
        )
        let other = PlaybackLaunchRequest(
            source: source,
            contentSelection: .bluRayPlaylist(BluRayPlaylistID(rawValue: 43), source: disc),
            displayName: "Playlist 00043",
            sourceAccess: nil
        )
        let updated = first.updating(metadata: PlaybackMediaMetadata(fileSizeInBytes: 1_024))

        #expect(first.id != other.id)
        #expect(first.source.url == discURL)
        #expect(other.source.url == discURL)
        #expect(updated.contentSelection == first.contentSelection)
        #expect(updated.id == first.id)
        #expect(updated.source.url == discURL)
    }
}
