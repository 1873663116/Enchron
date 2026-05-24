import Foundation

public nonisolated protocol PlaybackEventListening: AnyObject {
    func playbackDidStart()
    func playbackDidPause()
    func playbackDidResume()
    func playbackDidEnd()
    func playbackDidUpdatePosition(_ position: PlaybackCoreDomain.PlaybackPosition)
    func playbackDidChangeSpeed(_ speed: PlaybackCoreDomain.PlaybackSpeed)
    func playbackDidSwitchTrack()
    func playbackDidEncounterError(_ error: PlaybackError)
}
