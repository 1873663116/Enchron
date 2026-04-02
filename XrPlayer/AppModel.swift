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

    // MARK: - Debug Controls
    public var showDebugPanel: Bool = false

    // MARK: - Current Media
    public var currentMedia: PlaybackCoreDomain.MediaFile?

    // MARK: - Screen Position State (Immersive Mode)
    public var screenDistance: Double = 8.0
    public var screenVerticalOffset: Double = 0.0
    public var screenViewAngle: Double = 0.0

    // MARK: - Immersive Cinema State
    public var currentCinemaEnvironment: SpatialSceneDomain.CinemaEnvironment = .darkTheatre
    public var screenShape: SpatialSceneDomain.ScreenGeometry = .flat(width: 2.4, height: 1.35)

    private let screenPositionStore: ScreenPositionStoring

    public init(screenPositionStore: ScreenPositionStoring = SwiftDataStore()) {
        self.screenPositionStore = screenPositionStore
    }
    
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

    // MARK: - Screen Position Persistence

    public func loadScreenPosition() async {
        let envID = currentCinemaEnvironment.rawValue
        if let saved = await screenPositionStore.loadPosition(for: envID) {
            screenDistance = saved.distanceMeters
            screenVerticalOffset = saved.verticalOffsetMeters
            screenViewAngle = saved.viewAngleDegrees
        }
    }

    public func saveScreenPosition() {
        let envID = currentCinemaEnvironment.rawValue
        let store = screenPositionStore
        let distance = screenDistance
        let verticalOffset = screenVerticalOffset
        let viewAngle = screenViewAngle
        Task.detached(priority: .utility) {
            await store.savePosition(
                for: envID,
                distanceMeters: distance,
                verticalOffsetMeters: verticalOffset,
                angleDegrees: viewAngle
            )
        }
    }

    public func switchEnvironment(to environment: SpatialSceneDomain.CinemaEnvironment) async {
        guard environment != currentCinemaEnvironment else { return }
        saveScreenPosition()
        currentCinemaEnvironment = environment
        await loadScreenPosition()
    }
}
