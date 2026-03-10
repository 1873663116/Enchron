import SwiftUI
import Observation

@MainActor
@Observable
public final class AppModel {
    // MARK: - Navigation & Space State
    public let immersiveSpaceID = "ImmersiveSpace"
    
    public enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    public var immersiveSpaceState: ImmersiveSpaceState = .closed
    
    // MARK: - Playback State
    public var playbackState: PlaybackCoreDomain.PlaybackState = .idle
    public var playbackPosition: PlaybackCoreDomain.PlaybackPosition = .init(seconds: 0, duration: 0)
    public var playbackSpeed: PlaybackCoreDomain.PlaybackSpeed = .default
    public var mediaProfile: PlaybackCoreDomain.MediaProfile?
    public var playbackMode: PlaybackMode = .window
    public var isPlaying: Bool = false
    public var currentPlaybackURL: URL?
    public var showControls: Bool = true
    public var smokePanelRequest: String?
    public var isControlsFocused: Bool = false
    public var lastControlsInteractionAt: Date = .distantPast
    
    // MARK: - Current Media
    public var currentMedia: PlaybackCoreDomain.MediaFile?
    
    public init() {}
    
    // MARK: - Actions
    public func updatePlaybackState(_ state: PlaybackCoreDomain.PlaybackState) {
        playbackState = state
    }
    
    public func updatePlaybackPosition(_ position: PlaybackCoreDomain.PlaybackPosition) {
        playbackPosition = position
    }
    
    public func updatePlaybackSpeed(_ speed: PlaybackCoreDomain.PlaybackSpeed) {
        playbackSpeed = speed
    }
    
    public func updateMediaProfile(_ profile: PlaybackCoreDomain.MediaProfile) {
        mediaProfile = profile
    }
    
    public func updatePlaybackMode(_ mode: PlaybackMode) {
        playbackMode = mode
    }

    public func startPlayback(url: URL) {
        currentPlaybackURL = url
        isPlaying = true
        playbackState = .loading
        playbackPosition = .init(seconds: 0, duration: 0)
        mediaProfile = nil
        showControls = true
        registerControlsInteraction()
    }

    public func stopPlayback() {
        isPlaying = false
        playbackState = .stopped
        playbackPosition = .init(seconds: 0, duration: 0)
        mediaProfile = nil
        currentPlaybackURL = nil
        isControlsFocused = false
    }

    public func registerControlsInteraction(at date: Date = Date()) {
        lastControlsInteractionAt = date
    }

    public func setControlsFocused(_ focused: Bool, at date: Date = Date()) {
        isControlsFocused = focused
        if focused {
            registerControlsInteraction(at: date)
        }
    }

    public var canAutoHideControls: Bool {
        showControls && isControlsFocused == false
    }
}
