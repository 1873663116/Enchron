import Foundation
import MediaSource
import Playback
import Synchronization

public enum MediaServerPlaybackStartAction: String, Codable, Sendable, Equatable {
    case resume
    case fromBeginning
}

public struct MediaServerPlaybackSelection: Sendable, Equatable {
    public let item: MediaServerLibraryItem
    public let mediaSourceID: MediaServerMediaSourceID?
    public let startAction: MediaServerPlaybackStartAction
    public let seasonEpisodes: [MediaServerEpisode]?

    public init(
        item: MediaServerLibraryItem,
        mediaSourceID: MediaServerMediaSourceID? = nil,
        startAction: MediaServerPlaybackStartAction
    ) {
        self.item = item
        self.mediaSourceID = mediaSourceID
        self.startAction = startAction
        seasonEpisodes = nil
    }

    public init(
        episode: MediaServerEpisode,
        mediaSourceID: MediaServerMediaSourceID? = nil,
        startAction: MediaServerPlaybackStartAction,
        seasonEpisodes: [MediaServerEpisode]
    ) {
        item = .episode(episode)
        self.mediaSourceID = mediaSourceID
        self.startAction = startAction
        self.seasonEpisodes = seasonEpisodes
    }

    private init(
        item: MediaServerLibraryItem,
        mediaSourceID: MediaServerMediaSourceID?,
        startAction: MediaServerPlaybackStartAction,
        seasonEpisodes: [MediaServerEpisode]?
    ) {
        self.item = item
        self.mediaSourceID = mediaSourceID
        self.startAction = startAction
        self.seasonEpisodes = seasonEpisodes
    }

    public var resumeCandidateSeconds: Double {
        guard startAction == .resume,
              let ticks = item.metadata.userData?.playbackPositionTicks,
              ticks > 0 else { return 0 }
        return Double(ticks) / 10_000_000
    }

    public func replacingStartAction(_ startAction: MediaServerPlaybackStartAction) -> MediaServerPlaybackSelection {
        MediaServerPlaybackSelection(
            item: item,
            mediaSourceID: mediaSourceID,
            startAction: startAction,
            seasonEpisodes: seasonEpisodes
        )
    }
}

public struct MediaServerPreparedPlaybackEvidence: Equatable, Sendable {
    public let serverID: MediaServerServerID
    public let userID: MediaServerUserID
    public let itemID: MediaServerItemID
    public let mediaSourceID: MediaServerMediaSourceID
    public let playSessionID: MediaServerPlaySessionID
    public let requestedAction: MediaServerPlaybackStartAction
    public let freshServerProgressTicks: Int64?
    public let appliedStartTicks: Int64

    public init(
        serverID: MediaServerServerID,
        userID: MediaServerUserID,
        itemID: MediaServerItemID,
        mediaSourceID: MediaServerMediaSourceID,
        playSessionID: MediaServerPlaySessionID,
        requestedAction: MediaServerPlaybackStartAction,
        freshServerProgressTicks: Int64?,
        appliedStartTicks: Int64
    ) {
        self.serverID = serverID
        self.userID = userID
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.playSessionID = playSessionID
        self.requestedAction = requestedAction
        self.freshServerProgressTicks = freshServerProgressTicks
        self.appliedStartTicks = appliedStartTicks
    }
}

public struct MediaServerAcceptedPlaybackReport: Equatable, Sendable {
    public enum Event: String, Codable, Equatable, Sendable {
        case started
        case progress
        case stopped
    }

    public let event: Event
    public let serverID: MediaServerServerID
    public let userID: MediaServerUserID
    public let itemID: MediaServerItemID
    public let mediaSourceID: MediaServerMediaSourceID
    public let playSessionID: MediaServerPlaySessionID
    public let positionTicks: Int64
}

public final class MediaServerPlaybackSessionReporter: PlaybackSessionReporting, @unchecked Sendable {
    public typealias UnauthorizedHandler = @Sendable () async -> Void
    public typealias AcceptedReportHandler = @Sendable (
        MediaServerAcceptedPlaybackReport
    ) async -> Void

    private enum Event: Sendable {
        case started
        case progress(MediaServerPlaybackReport.ProgressEvent)
        case stopped
    }

    private let client: any MediaServerClientProtocol
    private let server: MediaServerAuthenticatedServer
    private let itemID: MediaServerItemID
    private let mediaSourceID: MediaServerMediaSourceID
    private let playSessionID: MediaServerPlaySessionID
    private let externalSubtitleStreamIndexBySourceID: [String: Int]
    private let serverIndexByPlaybackIndex: [Int: Int]
    private let durationTicks: Int64?
    private let onUnauthorized: UnauthorizedHandler?
    private let onAcceptedReport: AcceptedReportHandler?
    private let pendingTask = Mutex<Task<Void, Never>?>(nil)

    public init(
        client: any MediaServerClientProtocol,
        server: MediaServerAuthenticatedServer,
        itemID: MediaServerItemID,
        mediaSourceID: MediaServerMediaSourceID,
        playSessionID: MediaServerPlaySessionID,
        externalSubtitleStreamIndexBySourceID: [String: Int] = [:],
        serverIndexByPlaybackIndex: [Int: Int] = [:],
        durationTicks: Int64? = nil,
        onUnauthorized: UnauthorizedHandler? = nil,
        onAcceptedReport: AcceptedReportHandler? = nil
    ) {
        self.client = client
        self.server = server
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.playSessionID = playSessionID
        self.externalSubtitleStreamIndexBySourceID = externalSubtitleStreamIndexBySourceID
        self.serverIndexByPlaybackIndex = serverIndexByPlaybackIndex
        self.durationTicks = durationTicks
        self.onUnauthorized = onUnauthorized
        self.onAcceptedReport = onAcceptedReport
    }

    public func playbackStarted(_ report: PlaybackSessionReport) {
        enqueue(.started, report: report)
    }

    public func playbackProgressed(_ report: PlaybackSessionReport, reason: PlaybackProgressReason) {
        let event: MediaServerPlaybackReport.ProgressEvent = switch reason {
        case .timeUpdate: .timeUpdate
        case .pause: .pause
        case .unpause: .unpause
        case .audioTrackChange: .audioTrackChange
        case .subtitleTrackChange: .subtitleTrackChange
        }
        enqueue(.progress(event), report: report)
    }

    public func playbackStopped(_ report: PlaybackSessionReport) {
        enqueue(.stopped, report: report)
    }

    func waitForPendingReports() async {
        let task = pendingTask.withLock { $0 }
        await task?.value
    }

    private func enqueue(_ event: Event, report: PlaybackSessionReport) {
        let progressEvent: MediaServerPlaybackReport.ProgressEvent? = if case .progress(let reason) = event {
            reason
        } else {
            nil
        }
        let embyReport = MediaServerPlaybackReport(
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID,
            positionTicks: Self.ticks(from: report.positionSeconds),
            durationTicks: durationTicks,
            audioStreamIndex: report.selectedAudioTrackID.flatMap(Int.init).map { serverIndexByPlaybackIndex[$0] ?? $0 },
            subtitleStreamIndex: subtitleStreamIndex(for: report.selectedSubtitleTrackID),
            isPaused: report.isPaused,
            progressEvent: progressEvent
        )
        pendingTask.withLock { pendingTask in
            let precedingTask = pendingTask
            pendingTask = Task { [
                client,
                server,
                onUnauthorized,
                onAcceptedReport,
                itemID,
                mediaSourceID,
                playSessionID,
            ] in
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
                    let acceptedEvent: MediaServerAcceptedPlaybackReport.Event = switch event {
                    case .started: .started
                    case .progress: .progress
                    case .stopped: .stopped
                    }
                    await onAcceptedReport?(MediaServerAcceptedPlaybackReport(
                        event: acceptedEvent,
                        serverID: server.id,
                        userID: server.userID,
                        itemID: itemID,
                        mediaSourceID: mediaSourceID,
                        playSessionID: playSessionID,
                        positionTicks: embyReport.positionTicks
                    ))
                } catch MediaServerError.httpStatus(401) {
                    await onUnauthorized?()
                } catch {}
            }
        }
    }

    private func subtitleStreamIndex(for trackID: String?) -> Int? {
        guard let trackID else { return -1 }
        if let index = Int(trackID) { return serverIndexByPlaybackIndex[index] ?? index }
        if trackID.hasPrefix("ffmpeg.subtitle.") {
            return trackID.split(separator: ".").last.flatMap { Int($0) }.map { serverIndexByPlaybackIndex[$0] ?? $0 }
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

public actor MediaServerPlaybackBridge {
    private struct QueuedEpisode: Sendable {
        let id: UUID
        let episode: MediaServerEpisode
    }

    private let client: any MediaServerClientProtocol
    private var server: MediaServerAuthenticatedServer?
    private var onUnauthorized: MediaServerPlaybackSessionReporter.UnauthorizedHandler?
    private var onAcceptedReport: MediaServerPlaybackSessionReporter.AcceptedReportHandler?
    private var onPreparedPlayback: (@Sendable (MediaServerPreparedPlaybackEvidence) async -> Void)?
    private var queue: [QueuedEpisode] = []
    private var currentQueueID: UUID?

    public init(
        client: any MediaServerClientProtocol,
        server: MediaServerAuthenticatedServer?,
        onUnauthorized: MediaServerPlaybackSessionReporter.UnauthorizedHandler? = nil,
        onAcceptedReport: MediaServerPlaybackSessionReporter.AcceptedReportHandler? = nil,
        onPreparedPlayback: (@Sendable (MediaServerPreparedPlaybackEvidence) async -> Void)? = nil
    ) {
        self.client = client
        self.server = server
        self.onUnauthorized = onUnauthorized
        self.onAcceptedReport = onAcceptedReport
        self.onPreparedPlayback = onPreparedPlayback
    }

    public init(client: any MediaServerClientProtocol) {
        self.client = client
        server = nil
        onUnauthorized = nil
        onAcceptedReport = nil
        onPreparedPlayback = nil
    }

    public func configure(
        server: MediaServerAuthenticatedServer?,
        onUnauthorized: MediaServerPlaybackSessionReporter.UnauthorizedHandler? = nil,
        onAcceptedReport: MediaServerPlaybackSessionReporter.AcceptedReportHandler? = nil,
        onPreparedPlayback: (@Sendable (MediaServerPreparedPlaybackEvidence) async -> Void)? = nil
    ) {
        if self.server != server {
            queue = []
            currentQueueID = nil
        }
        self.server = server
        self.onUnauthorized = onUnauthorized
        self.onAcceptedReport = onAcceptedReport
        self.onPreparedPlayback = onPreparedPlayback
    }

    public func request(for selection: MediaServerPlaybackSelection) async throws -> PlaybackLaunchRequest {
        let request = try await makeRequest(
            for: selection.item,
            mediaSourceID: selection.mediaSourceID,
            startAction: selection.startAction,
            collectionOrigin: selection.seasonEpisodes == nil ? .standalone : .mediaServer
        )
        try Task.checkCancellation()
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
            try Task.checkCancellation()
            currentQueueID = queued.id
            return request
        } catch MediaServerError.httpStatus(401) {
            await onUnauthorized?()
            return nil
        } catch {
            return nil
        }
    }

    private func makeRequest(
        for item: MediaServerLibraryItem,
        mediaSourceID: MediaServerMediaSourceID?,
        startAction: MediaServerPlaybackStartAction,
        collectionOrigin: PlaybackCollectionOrigin
    ) async throws -> PlaybackLaunchRequest {
        guard let server else { throw MediaServerError.notAuthenticated }
        let freshItem = try await client.item(withID: item.metadata.id, on: server)
        let playback = try await client.playbackInfo(for: freshItem, on: server)
        let source: MediaServerMediaSource
        if let mediaSourceID {
            guard let selectedSource = playback.mediaSources.first(where: { $0.id == mediaSourceID }) else {
                throw MediaServerError.mediaSourceUnavailable(freshItem.metadata.id, mediaSourceID)
            }
            source = selectedSource
        } else {
            guard let firstSource = playback.mediaSources.first else {
                throw MediaServerError.directPlayUnavailable(freshItem.metadata.id)
            }
            source = firstSource
        }
        try Task.checkCancellation()
        let byteStreamServer = MediaByteStreamServer()
        var subtitles: [ResolvedExternalSubtitleSource] = []
        for stream in source.mediaStreams where stream.kind == .subtitle && stream.isExternal {
            let sourceID = Self.externalSubtitleSourceID(for: stream.index)
            let subtitleURL: URL
            do {
                subtitleURL = try client.externalSubtitleURL(for: stream, on: server)
            } catch MediaServerError.externalSubtitleUnavailable {
                continue
            }
            let subtitleHandle = try await byteStreamServer.register(
                source: MediaServerByteRangeSource(url: subtitleURL, reportedContentLength: nil),
                filename: stream.displayTitle ?? "Subtitle \(stream.index)"
            )
            subtitles.append(ResolvedExternalSubtitleSource(
                id: sourceID,
                url: subtitleHandle.url,
                displayName: stream.displayTitle ?? stream.language ?? "Subtitle \(stream.index)",
                byteStreamHandle: subtitleHandle
            ))
        }
        let externalIndexes: [String: Int] = Dictionary(
            uniqueKeysWithValues: source.mediaStreams.compactMap { stream -> (String, Int)? in
            guard stream.kind == .subtitle, stream.isExternal else { return nil }
            return (Self.externalSubtitleSourceID(for: stream.index), stream.index)
            }
        )
        let reporter = MediaServerPlaybackSessionReporter(
            client: client,
            server: server,
            itemID: freshItem.metadata.id,
            mediaSourceID: source.id,
            playSessionID: playback.id,
            externalSubtitleStreamIndexBySourceID: externalIndexes,
            serverIndexByPlaybackIndex: Dictionary(uniqueKeysWithValues: source.mediaStreams.compactMap { stream in
                stream.playbackIndex.map { ($0, stream.index) }
            }),
            durationTicks: freshItem.metadata.runTimeTicks,
            onUnauthorized: onUnauthorized,
            onAcceptedReport: onAcceptedReport
        )
        let freshServerProgressTicks = freshItem.metadata.userData?.playbackPositionTicks
        let appliedStartTicks: Int64 = switch startAction {
        case .resume:
            freshServerProgressTicks ?? 0
        case .fromBeginning:
            0
        }
        let startPosition = Double(appliedStartTicks) / 10_000_000
        let byteSource = MediaServerByteSource(
            streamURL: source.directPlayURL,
            accessToken: server.accessToken,
            kind: server.kind,
            contentLength: source.sizeInBytes ?? freshItem.metadata.sizeInBytes
        )
        let byteStreamHandle = try await byteStreamServer.register(
            source: byteSource,
            filename: source.displayName,
            preferredBufferDepth: .automatic
        )
        await onPreparedPlayback?(MediaServerPreparedPlaybackEvidence(
            serverID: server.id,
            userID: server.userID,
            itemID: freshItem.metadata.id,
            mediaSourceID: source.id,
            playSessionID: playback.id,
            requestedAction: startAction,
            freshServerProgressTicks: freshServerProgressTicks,
            appliedStartTicks: appliedStartTicks
        ))
        return PlaybackLaunchRequest(
            source: PlaybackAddress(byteStreamHandle: byteStreamHandle),
            displayName: freshItem.metadata.name,
            initialMetadata: PlaybackMediaMetadata(
                fileSizeInBytes: source.sizeInBytes ?? freshItem.metadata.sizeInBytes,
                overview: freshItem.metadata.overview
            ),
            collectionOrigin: collectionOrigin,
            versionedIdentity: source.versionedIdentity,
            externalSubtitleSources: subtitles,
            viewingStateAuthority: .mediaServer,
            startPositionSeconds: startPosition,
            initialTrackSelection: TrackSelectionPreference(
                audioTrackID: source.defaultStreamIndexes.audio.map { index in
                    String(source.mediaStreams.first { $0.index == index }?.playbackIndex ?? index)
                },
                subtitleTrack: Self.subtitleSelection(for: source)
            ),
            sessionReporter: reporter
        )
    }

    private static func subtitleSelection(for source: MediaServerMediaSource) -> SubtitleTrackSelectionPreference {
        guard let index = source.defaultStreamIndexes.subtitle, index >= 0 else { return .off }
        if source.mediaStreams.contains(where: { $0.index == index && $0.isExternal }) {
            return .externalSource(id: externalSubtitleSourceID(for: index))
        }
        let fileIndex = source.mediaStreams.first(where: { $0.index == index })?.playbackIndex ?? index
        return .track(id: "ffmpeg.subtitle.\(fileIndex)")
    }

    private func installQueue(_ episodes: [MediaServerEpisode], currentItemID: MediaServerItemID) throws {
        guard let currentEpisode = episodes.first(where: { $0.metadata.id == currentItemID }),
              let seasonID = currentEpisode.seasonID,
              episodes.allSatisfy({ $0.seasonID == seasonID }) else {
            throw MediaServerError.childrenUnavailable(currentItemID)
        }
        queue = episodes.map { QueuedEpisode(id: UUID(), episode: $0) }
        currentQueueID = queue.first { $0.episode.metadata.id == currentItemID }?.id
    }

    static func externalSubtitleSourceID(for streamIndex: Int) -> String {
        "emby.subtitle.\(streamIndex)"
    }
}

private final class MediaServerByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes: MediaByteStreamAttributes
    private let url: URL
    private let session: URLSession

    init(url: URL, reportedContentLength: Int64?, session: URLSession = MediaSourceNetwork.shared.session) {
        self.url = url
        self.session = session
        byteStreamAttributes = MediaByteStreamAttributes(
            contentLength: reportedContentLength,
            supportsSeeking: true,
            isLive: false
        )
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if let failure = MediaSourceReadFailure(classifying: error) {
                throw failure
            }
            throw error
        }
        guard let response = response as? HTTPURLResponse else {
            throw MediaSourceReadFailure.invalidData
        }
        if response.statusCode == 200 {
            return MediaByteRangeRead(
                data: data,
                contentLength: response.expectedContentLength >= 0
                    ? response.expectedContentLength
                    : nil,
                supportsSeeking: false
            )
        }
        guard response.statusCode == 206 else {
            if let failure = MediaSourceReadFailure(
                httpStatusCode: response.statusCode
            ) {
                throw failure
            }
            throw MediaServerError.httpStatus(response.statusCode)
        }
        guard let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
              contentRange.lowercased().hasPrefix("bytes \(range.lowerBound)-") else {
            throw MediaSourceReadFailure.invalidData
        }
        let total = contentRange.lastIndex(of: "/").flatMap {
            Int64(contentRange[contentRange.index(after: $0)...])
        }
        return MediaByteRangeRead(data: data, contentLength: total, supportsSeeking: true)
    }
}
