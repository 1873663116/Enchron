import Foundation
import MediaSource
import PlaybackFeature
import Synchronization

public enum EmbyPlaybackStartAction: Sendable, Equatable {
    case resume
    case fromBeginning
}

public struct EmbyPlaybackSelection: Sendable, Equatable {
    public let item: EmbyLibraryItem
    public let mediaSourceID: EmbyMediaSourceID?
    public let startAction: EmbyPlaybackStartAction
    public let seasonEpisodes: [EmbyEpisode]?

    public init(
        item: EmbyLibraryItem,
        mediaSourceID: EmbyMediaSourceID? = nil,
        startAction: EmbyPlaybackStartAction
    ) {
        self.item = item
        self.mediaSourceID = mediaSourceID
        self.startAction = startAction
        seasonEpisodes = nil
    }

    public init(
        episode: EmbyEpisode,
        mediaSourceID: EmbyMediaSourceID? = nil,
        startAction: EmbyPlaybackStartAction,
        seasonEpisodes: [EmbyEpisode]
    ) {
        item = .episode(episode)
        self.mediaSourceID = mediaSourceID
        self.startAction = startAction
        self.seasonEpisodes = seasonEpisodes
    }
}

public final class EmbyPlaybackSessionReporter: PlaybackSessionReporting, @unchecked Sendable {
    public typealias UnauthorizedHandler = @Sendable () async -> Void

    private enum Event: Sendable {
        case started
        case progress
        case stopped
    }

    private let client: any EmbyClientProtocol
    private let server: EmbyAuthenticatedServer
    private let itemID: EmbyItemID
    private let mediaSourceID: EmbyMediaSourceID
    private let playSessionID: EmbyPlaySessionID
    private let externalSubtitleStreamIndexBySourceID: [String: Int]
    private let onUnauthorized: UnauthorizedHandler?
    private let pendingTask = Mutex<Task<Void, Never>?>(nil)

    public init(
        client: any EmbyClientProtocol,
        server: EmbyAuthenticatedServer,
        itemID: EmbyItemID,
        mediaSourceID: EmbyMediaSourceID,
        playSessionID: EmbyPlaySessionID,
        externalSubtitleStreamIndexBySourceID: [String: Int] = [:],
        onUnauthorized: UnauthorizedHandler? = nil
    ) {
        self.client = client
        self.server = server
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.playSessionID = playSessionID
        self.externalSubtitleStreamIndexBySourceID = externalSubtitleStreamIndexBySourceID
        self.onUnauthorized = onUnauthorized
    }

    public func playbackStarted(_ report: PlaybackSessionReport) {
        enqueue(.started, report: report)
    }

    public func playbackProgressed(_ report: PlaybackSessionReport) {
        enqueue(.progress, report: report)
    }

    public func playbackStopped(_ report: PlaybackSessionReport) {
        enqueue(.stopped, report: report)
    }

    func waitForPendingReports() async {
        let task = pendingTask.withLock { $0 }
        await task?.value
    }

    private func enqueue(_ event: Event, report: PlaybackSessionReport) {
        let embyReport = EmbyPlaybackReport(
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID,
            positionTicks: Self.ticks(from: report.positionSeconds),
            audioStreamIndex: report.selectedAudioTrackID.flatMap(Int.init),
            subtitleStreamIndex: subtitleStreamIndex(for: report.selectedSubtitleTrackID),
            isPaused: report.isPaused
        )
        pendingTask.withLock { pendingTask in
            let precedingTask = pendingTask
            pendingTask = Task { [client, server, onUnauthorized] in
                await precedingTask?.value
                do {
                    switch event {
                    case .started:
                        try await client.sendPlayingStarted(embyReport, on: server)
                    case .progress:
                        try await client.sendProgress(embyReport, on: server)
                    case .stopped:
                        try await client.sendStopped(embyReport, on: server)
                    }
                } catch EmbyError.httpStatus(401) {
                    await onUnauthorized?()
                } catch {}
            }
        }
    }

    private func subtitleStreamIndex(for trackID: String?) -> Int? {
        guard let trackID else { return nil }
        if let index = Int(trackID) { return index }
        if trackID.hasPrefix("ffmpeg.subtitle.") {
            return trackID.split(separator: ".").last.flatMap { Int($0) }
        }
        for (sourceID, index) in externalSubtitleStreamIndexBySourceID
        where trackID == sourceID || trackID.contains(".\(sourceID).") {
            return index
        }
        return nil
    }

    private static func ticks(from seconds: Double) -> Int64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let ticks = seconds * 10_000_000
        return ticks >= Double(Int64.max) ? Int64.max : Int64(ticks.rounded())
    }
}

public actor EmbyPlaybackBridge {
    private struct QueuedEpisode: Sendable {
        let id: UUID
        let episode: EmbyEpisode
    }

    private let client: any EmbyClientProtocol
    private var server: EmbyAuthenticatedServer?
    private var onUnauthorized: EmbyPlaybackSessionReporter.UnauthorizedHandler?
    private var queue: [QueuedEpisode] = []
    private var currentQueueID: UUID?

    public init(
        client: any EmbyClientProtocol,
        server: EmbyAuthenticatedServer?,
        onUnauthorized: EmbyPlaybackSessionReporter.UnauthorizedHandler? = nil
    ) {
        self.client = client
        self.server = server
        self.onUnauthorized = onUnauthorized
    }

    public init(client: any EmbyClientProtocol) {
        self.client = client
        server = nil
        onUnauthorized = nil
    }

    public func configure(
        server: EmbyAuthenticatedServer?,
        onUnauthorized: EmbyPlaybackSessionReporter.UnauthorizedHandler? = nil
    ) {
        if self.server != server {
            queue = []
            currentQueueID = nil
        }
        self.server = server
        self.onUnauthorized = onUnauthorized
    }

    public func request(for selection: EmbyPlaybackSelection) async throws -> PlaybackLaunchRequest {
        let request = try await makeRequest(
            for: selection.item,
            mediaSourceID: selection.mediaSourceID,
            startAction: selection.startAction,
            collectionOrigin: selection.seasonEpisodes == nil ? .standalone : .mediaServer
        )
        if let seasonEpisodes = selection.seasonEpisodes {
            try installQueue(seasonEpisodes, currentItemID: selection.item.metadata.id)
        } else {
            queue = []
            currentQueueID = nil
        }
        return request
    }

    public var queueSnapshot: PlaybackQueueSnapshot {
        PlaybackQueueSnapshot(entries: queue.map { queued in
            PlaybackQueueEntry(
                id: queued.id,
                displayName: queued.episode.metadata.name,
                isCurrent: queued.id == currentQueueID
            )
        })
    }

    public func nextRequest() async -> PlaybackLaunchRequest? {
        guard let currentQueueID,
              let currentIndex = queue.firstIndex(where: { $0.id == currentQueueID }),
              queue.indices.contains(currentIndex + 1) else { return nil }
        return await request(for: queue[currentIndex + 1])
    }

    public func request(for queueID: UUID) async -> PlaybackLaunchRequest? {
        guard let queued = queue.first(where: { $0.id == queueID }) else { return nil }
        return await request(for: queued)
    }

    private func request(for queued: QueuedEpisode) async -> PlaybackLaunchRequest? {
        do {
            let request = try await makeRequest(
                for: .episode(queued.episode),
                mediaSourceID: nil,
                startAction: .resume,
                collectionOrigin: .mediaServer
            )
            currentQueueID = queued.id
            return request
        } catch EmbyError.httpStatus(401) {
            await onUnauthorized?()
            return nil
        } catch {
            return nil
        }
    }

    private func makeRequest(
        for item: EmbyLibraryItem,
        mediaSourceID: EmbyMediaSourceID?,
        startAction: EmbyPlaybackStartAction,
        collectionOrigin: PlaybackCollectionOrigin
    ) async throws -> PlaybackLaunchRequest {
        guard let server else { throw EmbyError.notAuthenticated }
        let freshItem = try await client.item(withID: item.metadata.id, on: server)
        let playback = try await client.playbackInfo(for: freshItem, on: server)
        let source: EmbyMediaSource
        if let mediaSourceID {
            guard let selectedSource = playback.mediaSources.first(where: { $0.id == mediaSourceID }) else {
                throw EmbyError.mediaSourceUnavailable(freshItem.metadata.id, mediaSourceID)
            }
            source = selectedSource
        } else {
            guard let firstSource = playback.mediaSources.first else {
                throw EmbyError.directPlayUnavailable(freshItem.metadata.id)
            }
            source = firstSource
        }
        let subtitles = try source.mediaStreams.compactMap { stream -> ResolvedExternalSubtitleSource? in
            guard stream.kind == .subtitle, stream.isExternal else { return nil }
            let sourceID = Self.externalSubtitleSourceID(for: stream.index)
            return ResolvedExternalSubtitleSource(
                id: sourceID,
                url: try client.externalSubtitleURL(for: stream, on: server),
                displayName: stream.displayTitle ?? stream.language ?? "Subtitle \(stream.index)"
            )
        }
        let externalIndexes: [String: Int] = Dictionary(
            uniqueKeysWithValues: source.mediaStreams.compactMap { stream -> (String, Int)? in
            guard stream.kind == .subtitle, stream.isExternal else { return nil }
            return (Self.externalSubtitleSourceID(for: stream.index), stream.index)
            }
        )
        let reporter = EmbyPlaybackSessionReporter(
            client: client,
            server: server,
            itemID: freshItem.metadata.id,
            mediaSourceID: source.id,
            playSessionID: playback.id,
            externalSubtitleStreamIndexBySourceID: externalIndexes,
            onUnauthorized: onUnauthorized
        )
        let startPosition: Double = switch startAction {
        case .resume:
            Double(freshItem.metadata.userData?.playbackPositionTicks ?? 0) / 10_000_000
        case .fromBeginning:
            0
        }
        return PlaybackLaunchRequest(
            url: source.directPlayURL,
            displayName: freshItem.metadata.name,
            initialMetadata: PlaybackMediaMetadata(
                fileSizeInBytes: source.sizeInBytes ?? freshItem.metadata.sizeInBytes
            ),
            collectionOrigin: collectionOrigin,
            versionedIdentity: source.versionedIdentity,
            externalSubtitleSources: subtitles,
            viewingStateAuthority: .mediaServer,
            startPositionSeconds: startPosition,
            sessionReporter: reporter
        )
    }

    private func installQueue(_ episodes: [EmbyEpisode], currentItemID: EmbyItemID) throws {
        guard let currentEpisode = episodes.first(where: { $0.metadata.id == currentItemID }),
              let seasonID = currentEpisode.seasonID,
              episodes.allSatisfy({ $0.seasonID == seasonID }) else {
            throw EmbyError.childrenUnavailable(currentItemID)
        }
        queue = episodes.map { QueuedEpisode(id: UUID(), episode: $0) }
        currentQueueID = queue.first { $0.episode.metadata.id == currentItemID }?.id
    }

    private static func externalSubtitleSourceID(for streamIndex: Int) -> String {
        "emby.subtitle.\(streamIndex)"
    }
}
