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
                    "subtitleEpoch": String(state.1),
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
            return (
                track,
                subtitleState.selectionGeneration,
                subtitleState.streamEpoch
            )
        }
        recordSubtitleState(at: synchronizer.currentTime())
        publishSubtitleCues(at: synchronizer.currentTime())
        do {
            let cues = try await subtitleProvider.cues(
                in: sourceURL,
                asset: sourceAsset,
                track: selection.0
            )
            let frameRenderer = try await subtitleProvider.frameRenderer(
                in: sourceURL,
                asset: sourceAsset,
                track: selection.0
            )
            try Task.checkCancellation()
            let committed = subtitleStateLock.withLock {
                guard !subtitleState.isClosed,
                      subtitleState.selectionGeneration == selection.1,
                      subtitleState.streamEpoch == selection.2 else { return false }
                subtitleState.selectedTrackID = selection.0.id
                subtitleState.cues = cues.sorted {
                    CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0
                }
                subtitleState.frameRenderer = frameRenderer
                subtitleState.activeFrame = nil
                subtitleState.suppressesActiveCues = false
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
                    "generation": String(selection.1),
                    "subtitleEpoch": String(selection.2),
                ]
            )
        } catch {
            subtitleStateLock.withLock {
                guard subtitleState.selectionGeneration == selection.1 else { return }
                subtitleState.selectedTrackID = nil
                subtitleState.cues = []
                subtitleState.frameRenderer = nil
                subtitleState.activeFrame = nil
                subtitleState.suppressesActiveCues = false
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
                "subtitleEpoch": String(state.1),
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
                suppressesActiveCues: subtitleState.suppressesActiveCues
            )
        }
        debugStore.recordSubtitleState(record)
    }

    func publishSubtitleCues(at time: CMTime) {
        let cues = subtitleStateLock.withLock { () -> [PlaybackSubtitleCue]? in
            let activeCues = Self.activeSubtitleCues(in: subtitleState, at: time)
            let cueIDs = activeCues.map(\.id)
            guard cueIDs != subtitleState.lastPublishedCueIDs else { return nil }
            subtitleState.lastPublishedCueIDs = cueIDs
            return activeCues
        }
        if let cues {
            onSubtitleCuesChange?(cues)
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
            )
        } catch {
            debugStore.emit(
                mediaSessionID: traceID,
                kind: "subtitle.frame.failed",
                outcome: .failed,
                details: ["error": error.localizedDescription]
            )
            frame = nil
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
