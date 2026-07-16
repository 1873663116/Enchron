import Foundation

final class PlaybackDebugRecorder: @unchecked Sendable {
    let directoryURL: URL
    let eventsURL: URL
    let snapshotURL: URL

    private weak var session: SampleBufferPlaybackSession?
    private var observerID: UUID?
    private let lock = NSLock()
    private var isStopped = false

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
            guard let self else { return }
            self.append(event)
            try? self.writeSnapshot()
        }
    }

    func writeSnapshot() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isStopped, let session else { return }
        try writeSnapshotLocked(session: session)
    }

    private func writeSnapshotLocked(session: SampleBufferPlaybackSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session.debugSnapshot())
        try data.write(to: snapshotURL, options: .atomic)
    }

    func stop() {
        if let observerID, let session {
            session.debugStore.removeEventObserver(observerID)
        }
        observerID = nil
        lock.lock()
        if !isStopped, let session {
            isStopped = true
            try? writeSnapshotLocked(session: session)
        }
        lock.unlock()
    }

    func writeSnapshotIgnoringErrors() {
        try? writeSnapshot()
    }

    private func append(_ event: PlaybackDebugEvent) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var data = try? encoder.encode(event) else { return }
        data.append(0x0A)

        lock.lock()
        defer { lock.unlock() }
        guard !isStopped else { return }
        do {
            let handle = try FileHandle(forWritingTo: eventsURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            PlaybackTrace.event(
                "debug.recorder.appendFailed error=\(error.localizedDescription)"
            )
        }
    }

    private func writeCurrentManifest(
        root: URL,
        platform: String,
        session: SampleBufferPlaybackSession
    ) throws {
        let manifest: [String: String] = [
            "mediaSessionID": session.traceID,
            "platform": platform,
            "route": session.route.rawValue,
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
