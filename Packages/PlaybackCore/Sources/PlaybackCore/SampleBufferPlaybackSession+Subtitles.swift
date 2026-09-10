@preconcurrency import AVFoundation
import Foundation
import OSLog

extension SampleBufferPlaybackSession {
    public var availableSubtitleTracks: [PlaybackSubtitleTrack] {
        subtitleStateLock.withLock { subtitleState.availableTracks }
    }

    public var selectedSubtitleTrackID: PlaybackSubtitleTrack.ID? {
        subtitleStateLock.withLock { subtitleState.selectedTrackID }
    }

    public var activeSubtitleCues: [PlaybackSubtitleCue] {
        activeSubtitleCues(at: synchronizer.currentTime())
    }

    public var activeSubtitleFrame: PlaybackSubtitleFrame? {
        subtitleStateLock.withLock { subtitleState.activeFrame }
    }

    func activeSubtitleCues(at time: CMTime) -> [PlaybackSubtitleCue] {
        return subtitleStateLock.withLock {
            Self.activeSubtitleCues(in: subtitleState, at: time)
        }
    }

    func addExternalSubtitleSource(
        _ source: PlaybackExternalSubtitleSource
    ) async throws -> [PlaybackSubtitleTrack] {
        let discoveredTracks = try await subtitleProvider.tracks(in: source.url, asset: nil)
        guard discoveredTracks.isEmpty == false else {
            throw PlaybackControlError.externalSubtitleHasNoSupportedTracks(source.displayName)
        }
        try Task.checkCancellation()
        let externalTracks = discoveredTracks.map { track in
            PlaybackSubtitleTrack(
                id: "external.subtitle.\(source.id).\(track.streamIndex)",
                streamIndex: track.streamIndex,
                codecName: track.codecName,
                language: track.language,
                title: track.title ?? source.displayName
            )
        }
        let clearedSelectedTrack = try subtitleStateLock.withLock { () -> Bool in
            guard !subtitleState.isClosed else {
                throw PlaybackControlError.mediaSessionClosed
            }
            let replacedTrackIDs = Set(
                subtitleState.externalSourceIDByTrackID.compactMap { trackID, sourceID in
                    sourceID == source.id ? trackID : nil
                }
            )
            let selectedTrackWasReplaced = subtitleState.selectedTrackID.map(
                replacedTrackIDs.contains
            ) == true
            subtitleState.availableTracks.removeAll { replacedTrackIDs.contains($0.id) }
            for trackID in replacedTrackIDs {
                subtitleState.sourceURLByTrackID.removeValue(forKey: trackID)
                subtitleState.externalSourceIDByTrackID.removeValue(forKey: trackID)
            }
            subtitleState.availableTracks.append(contentsOf: externalTracks)
            for track in externalTracks {
                subtitleState.sourceURLByTrackID[track.id] = source.url
                subtitleState.externalSourceIDByTrackID[track.id] = source.id
            }
            subtitleState.selectionGeneration &+= 1
            if selectedTrackWasReplaced {
                subtitleState.streamEpoch &+= 1
                subtitleState.selectedTrackID = nil
                subtitleState.cues = []
                subtitleState.frameRenderer = nil
                subtitleState.activeFrame = nil
                subtitleState.suppressesActiveCues = false
            }
            return selectedTrackWasReplaced
        }
        recordSubtitleState(at: synchronizer.currentTime())
        if clearedSelectedTrack {
            publishSubtitleCues(at: synchronizer.currentTime())
        }
        debugStore.emit(
            mediaSessionID: traceID,
            kind: "subtitle.externalSource.added",
            outcome: .succeeded,
            details: [
                "sourceID": source.id,
                "trackCount": String(externalTracks.count)
            ]
        )
        return externalTracks
    }

    func removeExternalSubtitleSource(id sourceID: String) throws {
        let removal = try subtitleStateLock.withLock { () -> (Int, Bool) in
            guard !subtitleState.isClosed else {
                throw PlaybackControlError.mediaSessionClosed
            }
            let removedTrackIDs = Set(
                subtitleState.externalSourceIDByTrackID.compactMap { trackID, storedSourceID in
                    storedSourceID == sourceID ? trackID : nil
                }
            )
            guard !removedTrackIDs.isEmpty else { return (0, false) }
            let selectedTrackWasRemoved = subtitleState.selectedTrackID.map(
                removedTrackIDs.contains
            ) == true
            subtitleState.availableTracks.removeAll { removedTrackIDs.contains($0.id) }
            for trackID in removedTrackIDs {
                subtitleState.sourceURLByTrackID.removeValue(forKey: trackID)
                subtitleState.externalSourceIDByTrackID.removeValue(forKey: trackID)
            }
            subtitleState.selectionGeneration &+= 1
            if selectedTrackWasRemoved {
                subtitleState.streamEpoch &+= 1
                subtitleState.selectedTrackID = nil
                subtitleState.cues = []
                subtitleState.frameRenderer = nil
                subtitleState.activeFrame = nil
                subtitleState.suppressesActiveCues = false
            }
            return (removedTrackIDs.count, selectedTrackWasRemoved)
        }
        guard removal.0 > 0 else { return }
        recordSubtitleState(at: synchronizer.currentTime())
        if removal.1 {
            publishSubtitleCues(at: synchronizer.currentTime())
        }
        debugStore.emit(
            mediaSessionID: traceID,
            kind: "subtitle.externalSource.removed",
            outcome: .succeeded,
            details: [
                "sourceID": sourceID,
                "trackCount": String(removal.0)
            ]
        )
    }

    func selectSubtitleTrack(id: PlaybackSubtitleTrack.ID?) async throws {
        guard let sourceURL else { throw PlaybackControlError.noActiveMediaSession }
        if id == nil {
            let state = try subtitleStateLock.withLock { () -> (UInt64, UInt64) in
                guard !subtitleState.isClosed else {
                    throw PlaybackControlError.mediaSessionClosed
                }
                subtitleState.selectionGeneration &+= 1
                subtitleState.streamEpoch &+= 1
                subtitleState.selectedTrackID = nil
                subtitleState.cues = []
                subtitleState.frameRenderer = nil
                subtitleState.suppressesActiveCues = false
                subtitleState.outcome = .notSelected
                return (subtitleState.selectionGeneration, subtitleState.streamEpoch)
            }
            recordSubtitleState(at: synchronizer.currentTime())
            publishSubtitleCues(at: synchronizer.currentTime())
            debugStore.emit(
                mediaSessionID: traceID,
                kind: "subtitle.selection.off",
                outcome: .succeeded,
                details: [
                    "generation": String(state.0),
                    "subtitleEpoch": String(state.1)
                ]
            )
            return
        }
        guard let trackID = id else { return }
        let selection = try subtitleStateLock.withLock {
            guard !subtitleState.isClosed else {
                throw PlaybackControlError.mediaSessionClosed
            }
            guard let track = subtitleState.availableTracks.first(where: { $0.id == trackID }) else {
                throw PlaybackControlError.invalidSubtitleTrack(trackID)
            }
            subtitleState.selectionGeneration &+= 1
            subtitleState.streamEpoch &+= 1
            subtitleState.selectedTrackID = nil
            subtitleState.cues = []
            subtitleState.frameRenderer = nil
            subtitleState.suppressesActiveCues = true
            subtitleState.outcome = .notSelected
            return (
                track,
                subtitleState.sourceURLByTrackID[track.id] ?? sourceURL,
                subtitleState.selectionGeneration,
                subtitleState.streamEpoch
            )
        }
        recordSubtitleState(at: synchronizer.currentTime())
        publishSubtitleCues(at: synchronizer.currentTime())
        debugStore.emit(
            mediaSessionID: traceID,
            kind: "subtitle.selection.started",
            outcome: .succeeded,
            details: [
                "trackID": selection.0.id,
                "generation": String(selection.2),
                "subtitleEpoch": String(selection.3)
            ]
        )
        do {
            let cues = try await subtitleProvider.cues(
                in: selection.1,
                asset: selection.1 == sourceURL ? sourceAsset : nil,
                track: selection.0
            )
            let frameRenderer = try await subtitleProvider.frameRenderer(
                in: selection.1,
                asset: selection.1 == sourceURL ? sourceAsset : nil,
                track: selection.0
            )
            try Task.checkCancellation()
            let committed = subtitleStateLock.withLock {
                guard !subtitleState.isClosed,
                      subtitleState.selectionGeneration == selection.2,
                      subtitleState.streamEpoch == selection.3 else { return false }
                subtitleState.selectedTrackID = selection.0.id
                subtitleState.cues = cues.sorted {
                    CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0
                }
                subtitleState.frameRenderer = frameRenderer
                subtitleState.activeFrame = nil
                subtitleState.suppressesActiveCues = false
                subtitleState.outcome = cues.isEmpty && frameRenderer == nil
                    ? .unsupported
                    : .selected
                return true
            }
            guard committed else { throw CancellationError() }
            recordSubtitleState(at: synchronizer.currentTime())
            publishSubtitleCues(at: synchronizer.currentTime())
            debugStore.emit(
                mediaSessionID: traceID,
                kind: "subtitle.selection.completed",
                outcome: .succeeded,
                details: [
                    "trackID": selection.0.id,
                    "cueCount": String(cues.count),
                    "generation": String(selection.2),
                    "subtitleEpoch": String(selection.3)
                ]
            )
        } catch {
            subtitleStateLock.withLock {
                guard subtitleState.selectionGeneration == selection.2 else { return }
                subtitleState.selectedTrackID = nil
                subtitleState.cues = []
                subtitleState.frameRenderer = nil
                subtitleState.activeFrame = nil
                subtitleState.suppressesActiveCues = false
                subtitleState.outcome = .notSelected
            }
            recordSubtitleState(at: synchronizer.currentTime())
            publishSubtitleCues(at: synchronizer.currentTime())
            throw error
        }
    }

    func beginSubtitleTimelineDiscontinuity() -> UInt64 {
        let state = subtitleStateLock.withLock { () -> (UInt64, UInt64) in
            subtitleState.selectionGeneration &+= 1
            subtitleState.streamEpoch &+= 1
            subtitleState.suppressesActiveCues = true
            return (subtitleState.selectionGeneration, subtitleState.streamEpoch)
        }
        recordSubtitleState(at: synchronizer.currentTime())
        publishSubtitleCues(at: synchronizer.currentTime())
        debugStore.emit(
            mediaSessionID: traceID,
            kind: "subtitle.cues.clearedForSeek",
            outcome: .succeeded,
            details: [
                "generation": String(state.0),
                "subtitleEpoch": String(state.1)
            ]
        )
        return state.1
    }

    func completeSubtitleTimelineDiscontinuity(epoch: UInt64) {
        subtitleStateLock.withLock {
            guard !subtitleState.isClosed,
                  subtitleState.streamEpoch == epoch else { return }
            subtitleState.suppressesActiveCues = false
        }
        recordSubtitleState(at: synchronizer.currentTime())
        publishSubtitleCues(at: synchronizer.currentTime())
    }

    func recordSubtitleState(at time: CMTime) {
        let record = subtitleStateLock.withLock {
            return SubtitleStateRecord(
                availableTracks: subtitleState.availableTracks,
                selectedTrackID: subtitleState.selectedTrackID,
                activeCueIDs: Self.activeSubtitleCues(
                    in: subtitleState,
                    at: time
                ).map(\.id),
                streamEpoch: subtitleState.streamEpoch,
                selectionGeneration: subtitleState.selectionGeneration,
                suppressesActiveCues: subtitleState.suppressesActiveCues,
                outcome: subtitleState.outcome
            )
        }
        debugStore.recordSubtitleState(record)
    }

    func ingestPendingSubtitleCues() {
        let snapshot = subtitleStateLock.withLock {
            () -> (SubtitleFrameRendering, PlaybackSubtitleTrack, UInt64)? in
            guard !subtitleState.isClosed,
                  let trackID = subtitleState.selectedTrackID,
                  let renderer = subtitleState.frameRenderer,
                  let track = subtitleState.availableTracks.first(where: { $0.id == trackID })
            else { return nil }
            return (renderer, track, subtitleState.selectionGeneration)
        }
        guard let (renderer, track, generation) = snapshot else { return }
        let arrived: [PlaybackSubtitleCue]
        do {
            arrived = try renderer.ingestPendingCues(for: track)
        } catch {
            debugStore.emit(
                mediaSessionID: traceID,
                kind: "subtitle.cues.ingestFailed",
                outcome: .failed,
                details: ["trackID": track.id, "error": error.localizedDescription]
            )
            return
        }
        guard !arrived.isEmpty else { return }
        let total = subtitleStateLock.withLock { () -> Int? in
            guard subtitleState.selectionGeneration == generation,
                  subtitleState.selectedTrackID == track.id else { return nil }
            subtitleState.cues.append(contentsOf: arrived)
            subtitleState.cues.sort {
                CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0
            }
            return subtitleState.cues.count
        }
        guard let total else { return }
        debugStore.emit(
            mediaSessionID: traceID,
            kind: "subtitle.cues.ingested",
            outcome: .succeeded,
            details: [
                "trackID": track.id,
                "arrived": String(arrived.count),
                "total": String(total)
            ]
        )
    }

    func publishSubtitleCues(at time: CMTime) {
        ingestPendingSubtitleCues()
        let published = subtitleStateLock.withLock {
            () -> ([PlaybackSubtitleCue], UInt64)? in
            let activeCues = Self.activeSubtitleCues(in: subtitleState, at: time)
            let cueIDs = activeCues.map(\.id)
            guard cueIDs != subtitleState.lastPublishedCueIDs else { return nil }
            subtitleState.lastPublishedCueIDs = cueIDs
            return (activeCues, subtitleState.selectionGeneration)
        }
        if let (cues, generation) = published {
            onSubtitleCuesChange?(cues)
            if !cues.isEmpty {
                noteSubtitleOutcome(.producing, generation: generation)
            }
        }
        publishSubtitleFrame(at: time)
    }

    func publishSubtitleFrame(at time: CMTime) {
        let snapshot = subtitleStateLock.withLock {
            guard time.isNumeric,
                  !subtitleState.isClosed,
                  !subtitleState.suppressesActiveCues,
                  subtitleState.selectedTrackID != nil,
                  let renderer = subtitleState.frameRenderer else {
                return (nil as SubtitleFrameRendering?, subtitleState.selectionGeneration)
            }
            return (renderer, subtitleState.selectionGeneration)
        }
        let frame: PlaybackSubtitleFrame?
        do {
            frame = try snapshot.0?.frame(
                at: time,
                viewportWidth: 1_920,
                viewportHeight: 1_080
            ).map { rendered in
                PlaybackSubtitleFrame(
                    kind: rendered.kind,
                    canvasWidth: rendered.canvasWidth,
                    canvasHeight: rendered.canvasHeight,
                    contentX: rendered.contentX,
                    contentY: rendered.contentY,
                    contentWidth: rendered.contentWidth,
                    contentHeight: rendered.contentHeight,
                    bytesPerRow: rendered.bytesPerRow,
                    premultipliedBGRA: rendered.premultipliedBGRA,
                    changeIdentifier: (snapshot.1 << 32) | (rendered.changeIdentifier & 0xFFFF_FFFF)
                )
            }
        } catch {
            debugStore.emit(
                mediaSessionID: traceID,
                kind: "subtitle.frame.failed",
                outcome: .failed,
                details: ["error": error.localizedDescription]
            )
            frame = nil
        }
        if frame != nil {
            noteSubtitleOutcome(.producing, generation: snapshot.1)
        }
        if frame == nil, let renderer = snapshot.0 {
            let description = renderer.stateDescription
            if renderer.holdsUndecodablePackets {
                noteSubtitleOutcome(.producedNothing, generation: snapshot.1)
                let second = Int(time.seconds.isFinite ? time.seconds : 0)
                if second != lastReportedEmptySubtitleSecond {
                    lastReportedEmptySubtitleSecond = second
                    debugStore.emit(
                        mediaSessionID: traceID,
                        kind: "subtitle.frame.empty",
                        outcome: .succeeded,
                        details: ["atSeconds": String(second), "renderer": description]
                    )
                }
            }
        }
        let shouldPublish = subtitleStateLock.withLock {
            guard subtitleState.selectionGeneration == snapshot.1 else { return false }
            let current = subtitleState.activeFrame
            let changed = current?.changeIdentifier != frame?.changeIdentifier ||
                current?.kind != frame?.kind
            guard changed else { return false }
            subtitleState.activeFrame = frame
            return true
        }
        if shouldPublish {
            onSubtitleFrameChange?(frame)
        }
    }

    func noteSubtitleOutcome(
        _ outcome: SubtitleTrackOutcome,
        generation: UInt64
    ) {
        let changed = subtitleStateLock.withLock { () -> Bool in
            guard subtitleState.selectionGeneration == generation,
                  subtitleState.outcome != outcome,
                  subtitleState.outcome != .producing else { return false }
            subtitleState.outcome = outcome
            return true
        }
        guard changed else { return }
        recordSubtitleState(at: synchronizer.currentTime())
    }

    static func activeSubtitleCues(
        in state: SubtitleState,
        at time: CMTime
    ) -> [PlaybackSubtitleCue] {
        guard time.isNumeric,
              !state.isClosed,
              !state.suppressesActiveCues,
              state.selectedTrackID != nil else { return [] }
        return state.cues.filter { cue in
            CMTimeCompare(time, cue.timeRange.start) >= 0 &&
                CMTimeCompare(time, cue.timeRange.end) < 0
        }
    }

}
