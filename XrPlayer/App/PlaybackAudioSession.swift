import AVFAudio
import OSLog

@MainActor
protocol PlaybackAudioSessionManaging: AnyObject {
    func activateForMoviePlayback() throws
    func deactivate() throws
}

@MainActor
final class SystemPlaybackAudioSession: PlaybackAudioSessionManaging {
    private let session = AVAudioSession.sharedInstance()

    func activateForMoviePlayback() throws {
        try session.setCategory(.playback, mode: .moviePlayback)
        try session.setActive(true)
    }

    func deactivate() throws {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
final class PlaybackAudioSessionLifecycle {
    private(set) var isActive = false

    private let session: any PlaybackAudioSessionManaging
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackAudioSession")

    init(session: any PlaybackAudioSessionManaging = SystemPlaybackAudioSession()) {
        self.session = session
    }

    func activateIfNeeded(hasAudio: Bool) throws {
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

    func deactivate() {
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
