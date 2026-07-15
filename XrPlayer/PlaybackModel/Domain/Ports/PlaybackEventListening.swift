import Foundation

public nonisolated protocol PlaybackEventListening: AnyObject {
    func playbackDidStart()
    func playbackDidPause()
    func playbackDidResume()
    func playbackDidEnd()
    func playbackDidUpdatePosition(_ position: PlaybackModel.PlaybackPosition)
    func playbackDidChangeSpeed(_ speed: PlaybackModel.PlaybackSpeed)
    func playbackDidSwitchTrack()
    func playbackDidEncounterError(_ error: PlaybackError)
}
