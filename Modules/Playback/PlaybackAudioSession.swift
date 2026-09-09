import AVFAudio
import OSLog

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
    func activateForMoviePlayback() async throws
    func deactivate() async throws
}

public extension PlaybackAudioSessionManaging {
    var observation: PlaybackAudioSessionObservation { .init() }
}

@MainActor
final class SystemPlaybackAudioSession: PlaybackAudioSessionManaging {
    private enum SessionError: LocalizedError {
        case activationRejected
        case deactivationRejected

        var errorDescription: String? {
            switch self {
            case .activationRejected:
                "The system rejected audio-session activation."
            case .deactivationRejected:
                "The system rejected audio-session deactivation."
            }
        }
    }

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

    func activateForMoviePlayback() async throws {
        try session.setCategory(.playback, mode: .moviePlayback)
        let activated: Bool = try await withCheckedThrowingContinuation { continuation in
            session.activate(options: []) { activated, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: activated)
                }
            }
        }
        guard activated else { throw SessionError.activationRejected }
    }

    func deactivate() async throws {
        let deactivated: Bool = try await withCheckedThrowingContinuation { continuation in
            session.deactivate(options: [.notifyOthersOnDeactivation]) { deactivated, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: deactivated)
                }
            }
        }
        guard deactivated else { throw SessionError.deactivationRejected }
    }
}

@MainActor
public final class PlaybackAudioSessionLifecycle {
    public var isActive: Bool {
        switch state {
        case .active, .deactivating:
            true
        case .inactive, .activating:
            false
        }
    }
    public var observation: PlaybackAudioSessionObservation { session.observation }

    private enum State {
        case inactive
        case activating(id: UInt64, task: Task<Void, any Error>)
        case active
        case deactivating(id: UInt64, task: Task<Bool, Never>)
    }

    private let session: any PlaybackAudioSessionManaging
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackAudioSession")
    private var state = State.inactive
    private var operationID: UInt64 = 0

    public init() {
        session = SystemPlaybackAudioSession()
    }

    public init(session: any PlaybackAudioSessionManaging) {
        self.session = session
    }

    public func activateIfNeeded(hasAudio: Bool) async throws {
        guard hasAudio else {
            await deactivate()
            return
        }

        while true {
            switch state {
            case .active:
                return
            case .inactive:
                operationID &+= 1
                let id = operationID
                let session = session
                let task = Task { @MainActor in
                    try await session.activateForMoviePlayback()
                }
                state = .activating(id: id, task: task)
                do {
                    try await task.value
                    if case .activating(let currentID, _) = state,
                       currentID == id {
                        state = .active
                        logger.info("audio session activated category=playback mode=moviePlayback")
                    }
                    return
                } catch {
                    if case .activating(let currentID, _) = state,
                       currentID == id {
                        state = .inactive
                    }
                    logger.error("audio session activation failed error=\(error.localizedDescription, privacy: .public)")
                    throw error
                }
            case .activating(let id, let task):
                do {
                    try await task.value
                    if case .activating(let currentID, _) = state,
                       currentID == id {
                        state = .active
                        logger.info("audio session activated category=playback mode=moviePlayback")
                    }
                    return
                } catch {
                    if case .activating(let currentID, _) = state,
                       currentID == id {
                        state = .inactive
                    }
                    throw error
                }
            case .deactivating(let id, let task):
                let deactivated = await task.value
                settleDeactivation(id: id, succeeded: deactivated)
            }
        }
    }

    public func deactivate() async {
        while true {
            switch state {
            case .inactive:
                return
            case .active:
                operationID &+= 1
                let id = operationID
                let session = session
                let logger = logger
                let task = Task { @MainActor in
                    do {
                        try await session.deactivate()
                        return true
                    } catch {
                        logger.error("audio session deactivation failed error=\(error.localizedDescription, privacy: .public)")
                        return false
                    }
                }
                state = .deactivating(id: id, task: task)
                let deactivated = await task.value
                settleDeactivation(id: id, succeeded: deactivated)
                return
            case .activating(let id, let task):
                do {
                    try await task.value
                    if case .activating(let currentID, _) = state,
                       currentID == id {
                        state = .active
                    }
                } catch {
                    if case .activating(let currentID, _) = state,
                       currentID == id {
                        state = .inactive
                    }
                    return
                }
            case .deactivating(let id, let task):
                let deactivated = await task.value
                settleDeactivation(id: id, succeeded: deactivated)
                return
            }
        }
    }

    public func abandonDeactivation() {
        guard case .deactivating(let id, let task) = state else { return }
        guard id == operationID else { return }
        task.cancel()
        operationID &+= 1
        state = .inactive
        logger.notice("audio session deactivation abandoned")
    }

    private func settleDeactivation(id: UInt64, succeeded: Bool) {
        guard case .deactivating(let currentID, _) = state,
              currentID == id else { return }
        if succeeded {
            state = .inactive
            logger.info("audio session deactivated")
        } else {
            state = .active
        }
    }
}
