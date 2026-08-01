import OSLog

#if os(visionOS)
import AVFAudio
#endif

public struct PlaybackAudioSessionObservation: Codable, Equatable, Sendable {
    public var category: String
    public var mode: String
    public var outputPortTypes: [String]
    public var outputVolume: Float

    public init(
        category: String = "unknown",
        mode: String = "unknown",
        outputPortTypes: [String] = [],
        outputVolume: Float = 0
    ) {
        self.category = category
        self.mode = mode
        self.outputPortTypes = outputPortTypes
        self.outputVolume = outputVolume
    }
}

@MainActor
public protocol PlaybackAudioSessionManaging: AnyObject {
    var observation: PlaybackAudioSessionObservation { get }
    func activateForMoviePlayback() throws
    func deactivate() throws
}

public extension PlaybackAudioSessionManaging {
    var observation: PlaybackAudioSessionObservation { .init() }
}

@MainActor
final class SystemPlaybackAudioSession: PlaybackAudioSessionManaging {
#if os(visionOS)
    private let session = AVAudioSession.sharedInstance()

    var observation: PlaybackAudioSessionObservation {
        PlaybackAudioSessionObservation(
            category: session.category.rawValue,
            mode: session.mode.rawValue,
            outputPortTypes: session.currentRoute.outputs
                .map { $0.portType.rawValue }
                .sorted(),
            outputVolume: session.outputVolume
        )
    }

    func activateForMoviePlayback() throws {
        try session.setCategory(.playback, mode: .moviePlayback)
        try session.setActive(true)
    }

    func deactivate() throws {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }
#else
    var observation: PlaybackAudioSessionObservation { .init() }
    func activateForMoviePlayback() throws {}
    func deactivate() throws {}
#endif
}

@MainActor
public final class PlaybackAudioSessionLifecycle {
    public private(set) var isActive = false
    public var observation: PlaybackAudioSessionObservation { session.observation }

    private let session: any PlaybackAudioSessionManaging
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackAudioSession")

    public init() {
        session = SystemPlaybackAudioSession()
    }

    public init(session: any PlaybackAudioSessionManaging) {
        self.session = session
    }

    public func activateIfNeeded(hasAudio: Bool) throws {
        guard hasAudio else {
            deactivate()
            return
        }
        guard !isActive else { return }
        do {
            try session.activateForMoviePlayback()
            isActive = true
            logger.info("audio session activated category=playback mode=moviePlayback")
        } catch {
            logger.error("audio session activation failed error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func deactivate() {
        guard isActive else { return }
        do {
            try session.deactivate()
            isActive = false
            logger.info("audio session deactivated")
        } catch {
            logger.error("audio session deactivation failed error=\(error.localizedDescription, privacy: .public)")
        }
    }
}
