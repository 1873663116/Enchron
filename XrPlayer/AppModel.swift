import SwiftUI
import Observation

@MainActor
@Observable
public final class AppModel {
    // MARK: - Navigation State
    public enum NavigationTab: String, CaseIterable {
        case browse, recent, settings
    }
    public var selectedTab: NavigationTab = .browse
    public var showSceneSelector: Bool = false

    // MARK: - Immersive Space State
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
    public var detectedProjectionType: PlaybackCoreDomain.ProjectionType = .flat
    public var projectionOverride: PlaybackCoreDomain.ProjectionType? = nil
    public var detectedStereoLayout: PlaybackCoreDomain.StereoLayout = .mono

    public var effectiveProjectionType: PlaybackCoreDomain.ProjectionType {
        projectionOverride ?? detectedProjectionType
    }

    public var isStereoContent: Bool {
        detectedStereoLayout != .mono
    }

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
    public var isFullImmersion: Bool = true

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

    public func updateDetectedProjection(_ type: PlaybackCoreDomain.ProjectionType) {
        detectedProjectionType = type
        // Clear override when new media detected
        projectionOverride = nil
        // Auto-route playback mode based on detected content type
        autoRoutePlaybackMode()
    }

    private static let modeDecider = DecidePlaybackModeUseCase()

    private func autoRoutePlaybackMode() {
        guard let profile = mediaProfile else { return }
        // Use effectiveProjectionType (respects user override) for routing
        let routingProfile = PlaybackCoreDomain.MediaProfile(
            projectionType: effectiveProjectionType,
            hdrType: profile.hdrType,
            resolution: profile.resolution,
            frameRate: profile.frameRate
        )
        let decidedMode = Self.modeDecider.decideMode(
            for: routingProfile,
            isEnvironmentActive: immersiveSpaceState == .open,
            manualOverride: nil
        )
        if decidedMode != playbackMode {
            playbackMode = decidedMode
        }
    }

    public func setProjectionOverride(_ type: PlaybackCoreDomain.ProjectionType?) {
        projectionOverride = type
        autoRoutePlaybackMode()
    }

    public func startPlayback(url: URL) {
        currentPlaybackURL = url
        isPlaying = true
        playbackState = .loading
        playbackPosition = .init(seconds: 0, duration: 0)
        mediaProfile = nil
        projectionOverride = nil
        withAnimation(.easeInOut(duration: 0.4)) { showControls = true }
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
        } else {
            // Reset to defaults when no saved position exists for this environment
            screenDistance = 8.0
            screenVerticalOffset = 0.0
            screenViewAngle = 0.0
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
