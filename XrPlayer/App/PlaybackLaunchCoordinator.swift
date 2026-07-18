import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class PlaybackLaunchCoordinator: PlaybackLaunching {
    public struct ResumeDecision: Equatable {
        public let request: PlaybackLaunchRequest
        public let seconds: Double
    }

    private let playbackRuntime: PlaybackRuntime
    private let progressStore: ProgressStoring
    private let preferencesStore: PreferencesStoring
    private let metadataService: PlaybackMediaMetadataService
    private let networkMonitor: NetworkMonitor
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackLaunch")

    public var nextFileProvider: (@MainActor @Sendable () async -> PlaybackLaunchRequest?)?
    public private(set) var pendingResumeDecision: ResumeDecision?

    private var launchTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var generation = 0

    public init(
        playbackRuntime: PlaybackRuntime,
        progressStore: ProgressStoring = SwiftDataStore(),
        preferencesStore: PreferencesStoring = UserDefaultsStore(),
        metadataService: PlaybackMediaMetadataService = PlaybackMediaMetadataService(),
        prefetchService: MediaProfilePrefetchService? = nil,
        networkMonitor: NetworkMonitor = NetworkMonitor()
    ) {
        self.playbackRuntime = playbackRuntime
        self.progressStore = progressStore
        self.preferencesStore = preferencesStore
        self.metadataService = metadataService
        self.networkMonitor = networkMonitor

        playbackRuntime.onMediaProfileResolved = { [weak self] request, profile in
            guard let self else { return }
            Task {
                let metadata = await self.metadataService.recordDetectedProfile(profile, for: request)
                guard self.playbackRuntime.currentLaunchRequest == request else { return }
                self.playbackRuntime.applyPrefetchedMetadata(metadata)
            }
        }
    }

    public func beginPlayback(for url: URL) {
        beginPlayback(.init(url: url, displayName: url.lastPathComponent))
    }

    public func requestPlayback(_ request: PlaybackLaunchRequest) {
        generation += 1
        let requestGeneration = generation
        pendingResumeDecision = nil
        Task { [weak self] in
            guard let self else { return }
            let progress: PersistenceDomain.PlaybackProgress? = if let fileID = request.fileIdentifier {
                await progressStore.loadProgress(for: fileID)
            } else {
                nil
            }
            guard generation == requestGeneration else { return }
            let seconds = progress?.position.seconds ?? 0
            switch preferencesStore.loadPreferences().resumePolicy {
            case .askEveryTime where seconds > 0:
                pendingResumeDecision = ResumeDecision(request: request, seconds: seconds)
            case .alwaysResume where seconds > 0:
                beginPlayback(request, resumeAt: seconds)
            default:
                beginPlayback(request)
            }
        }
    }

    public func resumePendingPlayback() {
        guard let decision = pendingResumeDecision else { return }
        pendingResumeDecision = nil
        beginPlayback(decision.request, resumeAt: decision.seconds)
    }

    public func startPendingPlaybackFromBeginning() {
        guard let decision = pendingResumeDecision else { return }
        pendingResumeDecision = nil
        beginPlayback(decision.request)
    }

    public func cancelPendingResume() {
        generation += 1
        pendingResumeDecision = nil
    }

    public func beginPlayback(_ request: PlaybackLaunchRequest) {
        beginPlayback(request, resumeAt: nil)
    }

    private func beginPlayback(_ request: PlaybackLaunchRequest, resumeAt seconds: Double?) {
        generation += 1
        let launchGeneration = generation
        persistCurrentSession()
        launchTask?.cancel()
        metadataTask?.cancel()
        let reusesSourceAccess = request.sourceAccess != nil
            && playbackRuntime.currentLaunchRequest?.sourceAccess === request.sourceAccess
        playbackRuntime.stop(releasingSourceAccess: reusesSourceAccess == false)

        let preparedRequest = request.updating(metadata: request.initialMetadata)
        playbackRuntime.prepareForPlayback(preparedRequest)
        logger.info("launch requested source=\(preparedRequest.displayName, privacy: .public)")

        metadataTask = Task { [weak self] in
            guard let self else { return }
            let metadata = await metadataService.prepareMetadata(for: preparedRequest)
            guard !Task.isCancelled, generation == launchGeneration else { return }
            if let metadata {
                playbackRuntime.applyPrefetchedMetadata(metadata)
            }
        }

        launchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await playbackRuntime.open(
                    preparedRequest,
                    startTimeSeconds: seconds ?? 0
                )
                guard generation == launchGeneration else { return }
                let defaultSpeed = preferencesStore.loadPreferences().defaultPlaybackSpeed
                if defaultSpeed != 1 {
                    let speed = PlaybackModel.PlaybackSpeed(defaultSpeed)
                    playbackRuntime.setSpeed(speed)
                }
            } catch {
                guard generation == launchGeneration else { return }
                if Self.isNetworkURL(preparedRequest.url),
                   await retry(
                    preparedRequest,
                    resumeAt: seconds,
                    generation: launchGeneration
                   ) {
                    return
                }
            }
        }
    }

    public func stopPlayback() {
        cancelPlaybackLaunchAndPersistProgress()
        playbackRuntime.stop()
    }

    public func stopPlaybackAndWait() async {
        cancelPlaybackLaunchAndPersistProgress()
        await playbackRuntime.stopAndWait()
    }

    private func cancelPlaybackLaunchAndPersistProgress() {
        generation += 1
        launchTask?.cancel()
        metadataTask?.cancel()
        launchTask = nil
        metadataTask = nil
        pendingResumeDecision = nil
        persistCurrentSession()
    }

    public func handlePlaybackEnded(onFallbackShowControls: (@MainActor () -> Void)? = nil) -> Bool {
        switch preferencesStore.loadPreferences().playbackEndBehavior {
        case .stop:
            return true
        case .repeatOne:
            playbackRuntime.replay()
            return false
        case .playNext:
            Task { [weak self] in
                guard let self else { return }
                if let next = await nextFileProvider?() {
                    beginPlayback(next)
                } else {
                    onFallbackShowControls?()
                }
            }
            return false
        }
    }

    public func loadProgress(
        for fileID: PersistenceDomain.FileIdentifier
    ) async -> PersistenceDomain.PlaybackProgress? {
        await progressStore.loadProgress(for: fileID)
    }

    private func persistCurrentSession() {
        guard let request = playbackRuntime.currentLaunchRequest else { return }
        let position = playbackRuntime.playbackPosition
        let metadata = playbackRuntime.prefetchedMetadata?.merging(
            with: playbackRuntime.displayMediaProfile.map {
                PlaybackMediaMetadata(
                    mediaProfile: $0,
                    fileSizeInBytes: playbackRuntime.displayFileSizeInBytes
                )
            }
        )
        Task.detached(priority: .utility) { [progressStore, metadataService] in
            if let fileID = request.fileIdentifier, position.seconds > 0 {
                await progressStore.saveProgress(
                    .init(fileID: fileID, position: .init(seconds: position.seconds))
                )
            }
            if let metadata {
                await metadataService.persist(metadata, for: request)
            }
        }
    }

    private func retry(
        _ request: PlaybackLaunchRequest,
        resumeAt seconds: Double?,
        generation: Int
    ) async -> Bool {
        for attempt in 1...3 {
            guard self.generation == generation, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .seconds(1 << attempt))
            guard await networkMonitor.waitForConnection(timeout: .seconds(10)) else { continue }
            do {
                try await playbackRuntime.open(
                    request,
                    startTimeSeconds: seconds ?? 0
                )
                logger.info("network retry succeeded attempt=\(attempt)")
                return true
            } catch {
                logger.error("network retry failed attempt=\(attempt) error=\(error.localizedDescription, privacy: .public)")
            }
        }
        return false
    }

    private static func isNetworkURL(_ url: URL) -> Bool {
        ["smb", "http", "https", "ftp"].contains(url.scheme?.lowercased() ?? "")
    }
}
