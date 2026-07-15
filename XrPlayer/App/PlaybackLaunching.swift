import Foundation

@MainActor
public protocol PlaybackLaunching: AnyObject {
    func beginPlayback(for url: URL)
    func beginPlayback(_ request: PlaybackLaunchRequest)
    func stopPlayback()
}
