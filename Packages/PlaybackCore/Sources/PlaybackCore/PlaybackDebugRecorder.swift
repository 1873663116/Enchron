import Foundation

final class PlaybackDebugRecorder: @unchecked Sendable {
    let directoryURL: URL
    let eventsURL: URL
    let snapshotURL: URL

    private weak var session: SampleBufferPlaybackSession?
    private var observerID: UUID?
    private let queue = DispatchQueue(
        label: "PlaybackCore.PlaybackDebugRecorder",
        qos: .utility
    )
    private var eventsHandle: FileHandle?
    private var pendingSnapshotWorkItem: DispatchWorkItem?
    private var snapshotGeneration = 0
    private var diagnosticEvents: [PlaybackDebugEvent] = []
    private var lastSnapshotWriteTime: UInt64 = 0
    private var isStopped = false

    private static let snapshotIntervalNanoseconds: UInt64 = 1_000_000_000

    init(session: SampleBufferPlaybackSession, platform: String) {
        self.session = session
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("playbackcore-live-debug", isDirectory: true)
        directoryURL = root.appendingPathComponent(session.traceID, isDirectory: true)
        eventsURL = directoryURL.appendingPathComponent("events.jsonl")
        snapshotURL = directoryURL.appendingPathComponent("snapshot.json")

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try Data().write(to: eventsURL, options: .atomic)
            eventsHandle = try FileHandle(forWritingTo: eventsURL)
            try writeCurrentManifest(root: root, platform: platform, session: session)
            try writeSnapshot()
            PlaybackTrace.event(
                "debug.recorder.started id=\(session.traceID) events=\(eventsURL.path) snapshot=\(snapshotURL.path)"
            )
        } catch {
            PlaybackTrace.event(
                "debug.recorder.failed id=\(session.traceID) error=\(error.localizedDescription)"
            )
        }

        observerID = session.debugStore.addEventObserver { [weak self] event in
            self?.record(event)
        }
    }

    func writeSnapshot() throws {
        try queue.sync {
            guard !isStopped, let session else { return }
            cancelPendingSnapshotLocked()
            try writeSnapshotLocked(session: session)
        }
    }

    private func writeSnapshotLocked(session: SampleBufferPlaybackSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session.debugSnapshot())
        try data.write(to: snapshotURL, options: .atomic)
        lastSnapshotWriteTime = DispatchTime.now().uptimeNanoseconds
    }

    func stop() {
        if let observerID, let session {
            session.debugStore.removeEventObserver(observerID)
        }
        observerID = nil
        queue.sync {
            guard !isStopped else { return }
            cancelPendingSnapshotLocked()
            if let session {
                try? writeSnapshotLocked(session: session)
            }
            try? eventsHandle?.close()
            eventsHandle = nil
            isStopped = true
        }
    }

    func writeSnapshotIgnoringErrors() {
        try? writeSnapshot()
    }

    func diagnosticEvidenceJSON() -> String? {
        queue.sync {
            guard let session else { return nil }
            struct Evidence: Codable {
                let snapshot: PlaybackDebugSnapshotV1
                let events: [PlaybackDebugEvent]
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return try? String(
                decoding: encoder.encode(Evidence(
                    snapshot: session.debugSnapshot(),
                    events: diagnosticEvents
                )),
                as: UTF8.self
            )
        }
    }

    private func record(_ event: PlaybackDebugEvent) {
        queue.sync {
            guard !isStopped else { return }
            appendLocked(event)
            if Self.requiresImmediateSnapshot(event.kind) {
                cancelPendingSnapshotLocked()
                if let session {
                    try? writeSnapshotLocked(session: session)
                }
            } else {
                refreshSnapshotLocked()
            }
        }
    }

    private static func requiresImmediateSnapshot(_ kind: String) -> Bool {
        kind == "audioRenderer.firstEnqueue"
            || kind == "renderer.firstEnqueue"
            || kind == "audioRenderer.prerollCompleted"
            || kind == "audioRenderer.rateActivated"
            || kind == "audioRenderer.statusChanged"
            || kind == "playbackActivation.observation"
            || kind.contains("flushed")
            || kind.contains("outputConfiguration")
    }

    private func appendLocked(_ event: PlaybackDebugEvent) {
        if Self.isDiagnosticEvent(event.kind) {
            diagnosticEvents.append(event)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var data = try? encoder.encode(event) else { return }
        data.append(0x0A)

        do {
            try eventsHandle?.write(contentsOf: data)
        } catch {
            PlaybackTrace.event(
                "debug.recorder.appendFailed error=\(error.localizedDescription)"
            )
        }
    }

    private static func isDiagnosticEvent(_ kind: String) -> Bool {
        kind == "audioRenderer.firstEnqueue"
            || kind == "audioRenderer.prerollCompleted"
            || kind == "audioRenderer.rateActivated"
            || kind == "audioRenderer.statusChanged"
            || kind.hasPrefix("playbackActivation.")
            || kind.hasPrefix("playbackDelivery.stage.")
            || kind.contains("flush")
            || kind.contains("outputConfiguration")
            || kind.contains("warning")
    }

    private func refreshSnapshotLocked() {
        let now = DispatchTime.now().uptimeNanoseconds
        let deadline = lastSnapshotWriteTime + Self.snapshotIntervalNanoseconds
        if now >= deadline {
            cancelPendingSnapshotLocked()
            if let session {
                try? writeSnapshotLocked(session: session)
            }
            return
        }

        guard pendingSnapshotWorkItem == nil else { return }
        snapshotGeneration += 1
        let generation = snapshotGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.isStopped,
                  self.snapshotGeneration == generation,
                  let session = self.session else { return }
            self.pendingSnapshotWorkItem = nil
            try? self.writeSnapshotLocked(session: session)
        }
        pendingSnapshotWorkItem = workItem
        queue.asyncAfter(
            deadline: DispatchTime(uptimeNanoseconds: deadline),
            execute: workItem
        )
    }

    private func cancelPendingSnapshotLocked() {
        snapshotGeneration += 1
        pendingSnapshotWorkItem?.cancel()
        pendingSnapshotWorkItem = nil
    }

    private func writeCurrentManifest(
        root: URL,
        platform: String,
        session: SampleBufferPlaybackSession
    ) throws {
        let manifest: [String: String] = [
            "mediaSessionID": session.traceID,
            "platform": platform,
            "events": eventsURL.path,
            "snapshot": snapshotURL.path,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: root.appendingPathComponent("current.json"), options: .atomic)
    }
}
