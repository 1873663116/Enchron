import Foundation
import MediaSource
import PlaybackCore
import Testing

@testable import Playback

@MainActor
@Suite("Playback residency", .serialized)
struct PlaybackResidencyTests {
    @Test("remote playback exits and reopens through a fresh stream while old requests remain retained")
    func remotePlaybackReopensAfterExit() async throws {
        let fixture = try Self.audioFixture(named: "residency-remote-reopen")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = ReopenByteSource(payload: try Data(contentsOf: fixture))
        let runtime = PlaybackRuntime(
            controller: PlaybackCoreController(),
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(session: SettledAudioSession())
        )
        let firstHandle = try await MediaByteStreamServer().register(source: source, filename: "first.wav")
        let first = PlaybackLaunchRequest(source: PlaybackAddress(byteStreamHandle: firstHandle), displayName: "first")
        try await runtime.open(first)
        let firstSession = runtime.activeSessionID
        #expect(firstSession != nil)
        await runtime.leavePlaybackAndWait(reason: .backButton)
        #expect(runtime.residency == .browsing)

        let nextHandle = try await MediaByteStreamServer().register(source: source, filename: "next.wav")
        let next = PlaybackLaunchRequest(source: PlaybackAddress(byteStreamHandle: nextHandle), displayName: "next")
        firstHandle.release()
        try await runtime.open(next)
        #expect(runtime.residency == .playing(host: .window))
        #expect(runtime.activeSessionID != nil)
        #expect(runtime.activeSessionID != firstSession)
        #expect(runtime.userVisibleIssue == nil)
        await runtime.leavePlaybackAndWait(reason: .backButton)
        withExtendedLifetime(first) {}
    }

    @Test("leaving playback lands in browsing with no session behind it")
    func leavingPlaybackReachesBrowsingWithNoSession() async throws {
        let fixture = try Self.audioFixture(named: "residency-leave")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let audioSession = SettledAudioSession()
        let runtime = PlaybackRuntime(
            controller: PlaybackCoreController(),
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(session: audioSession)
        )

        try await runtime.open(try Self.request(for: fixture))
        #expect(runtime.residency == .playing(host: .window))

        await runtime.leavePlaybackAndWait(reason: .backButton)

        #expect(runtime.residency == .browsing)
        #expect(runtime.liveTechnicalSessionCount == 0)
        #expect(runtime.retiringTechnicalSessionCount == 0)
        #expect(runtime.activeSessionID == nil)

        try await runtime.open(try Self.request(for: fixture))

        #expect(runtime.residency == .playing(host: .window))
        #expect(runtime.activeSessionID != nil)
        await runtime.leavePlaybackAndWait(reason: .backButton)
    }

    @Test("a close that cannot finish overruns its budget and releases the next open")
    func aCloseThatCannotFinishOverrunsAndReleasesTheNextOpen() async throws {
        let fixture = try Self.audioFixture(named: "residency-overrun")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let audioSession = StalledDeactivationAudioSession()
        defer { audioSession.finishDeactivation() }
        let runtime = PlaybackRuntime(
            controller: PlaybackCoreController(),
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(session: audioSession)
        )
        try await runtime.open(try Self.request(for: fixture))
        #expect(runtime.residency == .playing(host: .window))
        let trace = TraceRecorder()
        trace.install()
        defer { trace.uninstall() }

        let leftAt = ContinuousClock.now
        runtime.leavePlayback(reason: .backButton)
        let reachedBrowsing = await Self.wait(until: { runtime.residency == .browsing })
        let elapsed = ContinuousClock.now - leftAt

        #expect(reachedBrowsing)
        #expect(elapsed >= PlaybackCloseBudget.deadline)
        #expect(elapsed <= .milliseconds(1_500))
        #expect(trace.events.contains { $0.contains("runtime.close.overran") })

        let nextOpenProgress = OpenProgress()
        let nextOpen = Task { @MainActor in
            try? await runtime.open(try Self.request(for: fixture))
            nextOpenProgress.finish()
        }
        let nextOpenFinished = await Self.wait(
            until: { nextOpenProgress.isFinished },
            within: .seconds(5)
        )

        #expect(nextOpenFinished)
        #expect(runtime.activeSessionID != nil)
        #expect(runtime.residency == .playing(host: .window))
        audioSession.finishDeactivation()
        _ = await nextOpen.value
        await runtime.leavePlaybackAndWait(reason: .backButton)
    }

    @Test("a driver close that cannot finish is abandoned when the budget overruns")
    func aDriverCloseThatCannotFinishIsAbandoned() async throws {
        let fixture = try Self.audioFixture(named: "residency-driver-overrun")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let driver = StalledCloseMediaSessionDriver()
        defer { driver.releaseClose() }
        let runtime = PlaybackRuntime(
            openingDriver: driver,
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(
                session: SettledAudioSession()
            )
        )
        try await runtime.open(try Self.request(for: fixture))
        #expect(runtime.residency == .playing(host: .window))
        let trace = TraceRecorder()
        trace.install()
        defer { trace.uninstall() }

        runtime.leavePlayback(reason: .backButton)
        let reachedBrowsing = await Self.wait(until: { runtime.residency == .browsing })

        #expect(reachedBrowsing)
        #expect(driver.abandonCount == 1)
        #expect(driver.closeIsStalled)
        #expect(trace.events.contains { $0.contains("abandonedDrivers=1") })
        #expect(trace.events.contains { $0.contains("controller.close.abandoned") })

        driver.releaseClose()
        try await runtime.open(try Self.request(for: fixture))

        #expect(runtime.residency == .playing(host: .window))
        #expect(runtime.activeSessionID != nil)
        await runtime.leavePlaybackAndWait(reason: .backButton)
    }

    @Test("a late driver close cannot deactivate the next session's audio")
    func lateCloseCannotDeactivateNextSession() async throws {
        let fixture = try Self.audioFixture(named: "residency-late-close")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let driver = StalledCloseMediaSessionDriver()
        defer { driver.releaseClose() }
        let audio = SettledAudioSession()
        let runtime = PlaybackRuntime(
            openingDriver: driver,
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(session: audio)
        )
        let trace = TraceRecorder()
        trace.install()
        defer { trace.uninstall() }
        try await runtime.open(try Self.request(for: fixture))
        runtime.leavePlayback(reason: .backButton)
        #expect(await Self.wait(until: { runtime.residency == .browsing }))
        try await runtime.open(try Self.request(for: fixture))
        let nextSessionID = runtime.activeSessionID
        let deactivations = audio.deactivationCount
        driver.releaseClose()
        #expect(await Self.wait(until: {
            trace.events.contains { $0.contains("runtime.close.lateSettled") }
        }))
        #expect(audio.deactivationCount == deactivations)
        #expect(runtime.activeSessionID == nextSessionID)
        await runtime.leavePlaybackAndWait(reason: .backButton)
    }

    @Test("a request replacement keeps the player page across the next open")
    func aRequestReplacementKeepsThePlayerPage() async throws {
        let first = try Self.audioFixture(named: "residency-replace-first")
        defer { try? FileManager.default.removeItem(at: first) }
        let second = try Self.audioFixture(named: "residency-replace-second")
        defer { try? FileManager.default.removeItem(at: second) }
        let runtime = PlaybackRuntime(
            controller: PlaybackCoreController(),
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(
                session: SettledAudioSession()
            )
        )
        try await runtime.open(try Self.request(for: first))
        #expect(runtime.residency == .playing(host: .window))

        runtime.stopForNextRequest(releasingSourceAccess: true)

        #expect(runtime.residency == .playing(host: .window))

        let replacement = try Self.request(for: second)
        runtime.prepareForPlayback(replacement)

        #expect(runtime.residency == .playing(host: .window))

        try await runtime.open(replacement)

        #expect(runtime.residency == .playing(host: .window))
        #expect(runtime.activeSessionID != nil)
        await runtime.leavePlaybackAndWait(reason: .backButton)

        #expect(runtime.residency == .browsing)
    }

    @Test("an open that fails keeps the player page and the request behind the retry")
    func aFailedOpenKeepsThePlayerPage() async throws {
        let fixture = try Self.corruptFixture(named: "residency-failed-open")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let runtime = PlaybackRuntime(
            controller: PlaybackCoreController(),
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(
                session: SettledAudioSession()
            )
        )

        await #expect(throws: Error.self) {
            try await runtime.open(try Self.request(for: fixture))
        }

        #expect(runtime.residency == .playing(host: .window))
        #expect(runtime.hasActivePlaybackRequest)
        #expect(runtime.activeSessionID == nil)
        #expect(runtime.userVisibleIssue != nil)

        await runtime.leavePlaybackAndWait(reason: .failure)

        #expect(runtime.residency == .browsing)
        #expect(runtime.hasActivePlaybackRequest == false)
    }

    @Test("the player window is absent while the immersive space hosts playback")
    func playerWindowIsAbsentWhileImmersiveHostsPlayback() async throws {
        let fixture = try Self.audioFixture(named: "residency-immersive")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let audioSession = SettledAudioSession()
        let runtime = PlaybackRuntime(
            controller: PlaybackCoreController(),
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(session: audioSession)
        )
        try await runtime.open(try Self.request(for: fixture))
        runtime.recordPlaybackHost(.immersiveSpace)
        #expect(runtime.residency == .playing(host: .immersiveSpace))

        #expect(
            SpatialPlatformPlaybackWindowPolicy.pushedWindow(
                for: runtime.residency
            ) == .immersiveSpace
        )
        #expect(
            SpatialPlatformPlayerWindowClosurePolicy
                .awaitsUserDismissalConfirmation(
                    hasActivePlaybackRequest: runtime.hasActivePlaybackRequest,
                    playerWindowStateBeforeDisconnect: .closing
                ) == false
        )
        #expect(runtime.residency == .playing(host: .immersiveSpace))
        await runtime.leavePlaybackAndWait(reason: .backButton)
    }

    @Test(
        "every leave reason lands in browsing",
        arguments: [
            PlaybackLeaveReason.backButton,
            .windowClosedByWearer,
            .failure
        ]
    )
    func leavingFromEveryReasonLandsInBrowsing(
        reason: PlaybackLeaveReason
    ) async throws {
        let fixture = try Self.audioFixture(named: "residency-reason-\(reason.rawValue)")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let audioSession = SettledAudioSession()
        let runtime = PlaybackRuntime(
            controller: PlaybackCoreController(),
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(session: audioSession)
        )
        try await runtime.open(try Self.request(for: fixture))
        #expect(runtime.residency == .playing(host: .window))

        await runtime.leavePlaybackAndWait(reason: reason)

        #expect(runtime.residency == .browsing)
        #expect(runtime.hasActivePlaybackRequest == false)
    }

    private static func wait(
        until condition: @MainActor () -> Bool,
        within timeout: Duration = .seconds(10)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private static func request(for url: URL) throws -> PlaybackLaunchRequest {
        PlaybackLaunchRequest(
            source: try PlaybackAddress(localFileURL: url),
            displayName: url.lastPathComponent
        )
    }

    private static func corruptFixture(named name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try Data(repeating: 0x41, count: 4_096).write(to: url, options: .atomic)
        return url
    }

    private static func audioFixture(named name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try pcmWaveData().write(to: url, options: .atomic)
        return url
    }

    private static func pcmWaveData() -> Data {
        let sampleRate: UInt32 = 8_000
        let sampleCount: UInt32 = 8_000
        let audioByteCount = sampleCount * 2
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(36 + audioByteCount, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate * 2, to: &data)
        appendLittleEndian(UInt16(2), to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(audioByteCount, to: &data)
        data.append(Data(count: Int(audioByteCount)))
        return data
    }

    private static func appendLittleEndian<Value: FixedWidthInteger>(
        _ value: Value,
        to data: inout Data
    ) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) {
            data.append(contentsOf: $0)
        }
    }
}

@MainActor
private final class OpenProgress {
    private(set) var isFinished = false

    func finish() {
        isFinished = true
    }
}

@MainActor
private final class StalledCloseMediaSessionDriver: PlaybackMediaSessionDriver {
    private(set) var abandonCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    var closeIsStalled: Bool { continuation != nil }

    override func close(clearSource: Bool) async {
        if isReleased == false {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        await super.close(clearSource: clearSource)
    }

    override func abandon() {
        abandonCount += 1
        super.abandon()
    }

    func releaseClose() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class SettledAudioSession: PlaybackAudioSessionManaging {
    private(set) var deactivationCount = 0

    func activateForMoviePlayback() async throws {}

    func deactivate() async throws {
        deactivationCount += 1
    }
}

@MainActor
private final class StalledDeactivationAudioSession: PlaybackAudioSessionManaging {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isFinished = false

    func activateForMoviePlayback() async throws {}

    func deactivate() async throws {
        guard isFinished == false else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finishDeactivation() {
        isFinished = true
        continuation?.resume()
        continuation = nil
    }
}

private final class TraceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var events: [String] {
        lock.withLock { recorded }
    }

    func install() {
        PlaybackTrace.installSink { [weak self] event in
            guard let self else { return }
            lock.withLock { recorded.append(event) }
        }
    }

    func uninstall() {
        PlaybackTrace.installSink(nil)
    }
}

private final class ReopenByteSource: MediaByteRangeSource {
    let payload: Data
    init(payload: Data) { self.payload = payload }
    var byteStreamAttributes: MediaByteStreamAttributes {
        .init(contentLength: Int64(payload.count), supportsSeeking: true, isLive: false)
    }
    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        let lower = min(max(0, range.lowerBound), Int64(payload.count))
        let upper = min(max(lower, range.upperBound), Int64(payload.count))
        return .init(
            data: Data(payload[Int(lower)..<Int(upper)]),
            contentLength: Int64(payload.count),
            supportsSeeking: true
        )
    }
}

extension PlaybackResidencyTests {
    @Test("video or audio opens before delayed subtitle discovery and restores a ready default")
    func playbackStartsBeforeDelayedSubtitleDiscovery() async throws {
        let audio = try Self.audioFixture(named: "subtitle-background-open")
        let subtitle = audio.deletingPathExtension().appendingPathExtension("srt")
        try Data("1\n00:00:00,000 --> 00:00:10,000\nReady subtitle\n".utf8).write(to: subtitle)
        defer {
            try? FileManager.default.removeItem(at: audio)
            try? FileManager.default.removeItem(at: subtitle)
        }
        let gate = SubtitleDiscoveryGate()
        let runtime = PlaybackRuntime(
            controller: PlaybackCoreController(),
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(session: SettledAudioSession())
        )
        var observations: [PlaybackRuntimeObservation.Event] = []
        runtime.onPlaybackObservation = { observations.append($0.event) }
        let request = PlaybackLaunchRequest(
            source: try PlaybackAddress(localFileURL: audio), displayName: "Movie",
            externalSubtitleDiscovery: ExternalSubtitleDiscovery {
                await gate.wait()
                return [ResolvedExternalSubtitleSource(id: "delayed", url: subtitle, displayName: "Movie.srt")]
            },
            initialTrackSelection: TrackSelectionPreference(subtitleTrack: .externalSource(id: "delayed"))
        )
        try await runtime.open(request)
        let startedBeforeSubtitles = await Self.wait(until: { runtime.productLifecycle == .playing })
        #expect(startedBeforeSubtitles)
        #expect(runtime.productLifecycle == .playing)
        #expect(runtime.currentSubtitleTrackID == nil)
        let discoveryWaiting = await Self.wait(until: { gate.waiting })
        #expect(discoveryWaiting)
        #expect(runtime.availableSubtitleTracks.isEmpty)
        gate.release()
        let selected = await Self.wait(until: {
            runtime.currentSubtitleTrackID == "external.subtitle.delayed.0"
                && observations.contains(.subtitleSelectionChanged)
        })
        #expect(selected)
        #expect(runtime.availableSubtitleTracks.map(\.id) == ["external.subtitle.delayed.0"])
        #expect(runtime.userVisibleIssue == nil)
        #expect(observations.contains(.subtitleSelectionChanged))
        await runtime.leavePlaybackAndWait(reason: .backButton)
    }

    @Test("turning subtitles off overrides a delayed default while failed sources stay absent")
    func subtitlesOffOverridesLateDefaultAndFailureIsSilent() async throws {
        let audio = try Self.audioFixture(named: "subtitle-background-off")
        let subtitle = audio.deletingPathExtension().appendingPathExtension("srt")
        try Data("1\n00:00:00,000 --> 00:00:10,000\nReady subtitle\n".utf8).write(to: subtitle)
        defer {
            try? FileManager.default.removeItem(at: audio)
            try? FileManager.default.removeItem(at: subtitle)
        }
        let gate = SubtitleDiscoveryGate()
        let counter = SubtitleRuntimeReleaseCounter()
        let failedAccess = MediaAccessLease(release: { counter.increment() })
        let runtime = PlaybackRuntime(
            controller: PlaybackCoreController(),
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(session: SettledAudioSession())
        )
        try await runtime.open(PlaybackLaunchRequest(
            source: try PlaybackAddress(localFileURL: audio), displayName: "Movie",
            externalSubtitleSources: [ResolvedExternalSubtitleSource(
                id: "broken", url: audio.appendingPathExtension("missing.srt"), displayName: "Missing.srt", accessLease: failedAccess
            )],
            externalSubtitleDiscovery: ExternalSubtitleDiscovery {
                await gate.wait()
                return [ResolvedExternalSubtitleSource(id: "delayed", url: subtitle, displayName: "Movie.srt")]
            },
            initialTrackSelection: TrackSelectionPreference(subtitleTrack: .externalSource(id: "delayed"))
        ))
        let discoveryWaiting = await Self.wait(until: { gate.waiting })
        #expect(discoveryWaiting)
        try await runtime.selectSubtitleTrack(nil)
        gate.release()
        let ready = await Self.wait(until: { runtime.availableSubtitleTracks.map(\.id) == ["external.subtitle.delayed.0"] })
        #expect(ready)
        #expect(runtime.currentSubtitleTrackID == nil)
        #expect(runtime.userVisibleIssue == nil)
        #expect(counter.value == 0)
        await runtime.leavePlaybackAndWait(reason: .backButton)
        #expect(counter.value == 1)
    }

    @Test("late discovery from an exited session releases access and cannot change the next menu")
    func lateDiscoveryCannotPolluteTheNextSession() async throws {
        let first = try Self.audioFixture(named: "subtitle-background-old")
        let next = try Self.audioFixture(named: "subtitle-background-next")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: next)
        }
        let gate = SubtitleDiscoveryGate()
        let counter = SubtitleRuntimeReleaseCounter()
        let lease = MediaAccessLease(release: { counter.increment() })
        let runtime = PlaybackRuntime(
            controller: PlaybackCoreController(),
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(session: SettledAudioSession())
        )
        try await runtime.open(PlaybackLaunchRequest(
            source: try PlaybackAddress(localFileURL: first), displayName: "Old",
            externalSubtitleDiscovery: ExternalSubtitleDiscovery {
                await gate.wait()
                return [ResolvedExternalSubtitleSource(
                    id: "late", url: first.appendingPathExtension("srt"), displayName: "Old.srt", accessLease: lease
                )]
            }
        ))
        let discoveryWaiting = await Self.wait(until: { gate.waiting })
        #expect(discoveryWaiting)
        await runtime.leavePlaybackAndWait(reason: .backButton)
        try await runtime.open(try Self.request(for: next))
        let nextSession = runtime.activeSessionID
        gate.release()
        let released = await Self.wait(until: { counter.value == 1 })
        #expect(released)
        #expect(runtime.currentLaunchRequest?.displayName == next.lastPathComponent)
        #expect(runtime.activeSessionID == nextSession)
        #expect(runtime.availableSubtitleTracks.isEmpty)
        #expect(runtime.userVisibleIssue == nil)
        await runtime.leavePlaybackAndWait(reason: .backButton)
    }
}

@MainActor
private final class SubtitleDiscoveryGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var didReturn = false
    var waiting: Bool { continuation != nil }
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
        didReturn = true
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private final class SubtitleRuntimeReleaseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

extension PlaybackResidencyTests {
    @Test("failed request subtitles keep their loopback handles available for video recovery")
    func failedRequestSubtitleDoesNotBreakLoopbackRefresh() async throws {
        let audioPayload = Self.pcmWaveData()
        let subtitlePayload = Data("broken subtitle without any cues".utf8)
        let audioHandle = try await MediaByteStreamServer().register(
            source: ReopenByteSource(payload: audioPayload), filename: "Movie.wav"
        )
        let subtitleHandle = try await MediaByteStreamServer().register(
            source: ReopenByteSource(payload: subtitlePayload), filename: "Broken.srt"
        )
        let driver = SubtitleCompletionDriver()
        let runtime = PlaybackRuntime(
            openingDriver: driver,
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(session: SettledAudioSession())
        )
        let request = PlaybackLaunchRequest(
            source: PlaybackAddress(byteStreamHandle: audioHandle), displayName: "Movie",
            externalSubtitleSources: [ResolvedExternalSubtitleSource(
                id: "broken", url: subtitleHandle.url, displayName: "Broken.srt", byteStreamHandle: subtitleHandle
            )]
        )
        try await runtime.open(request)
        let failed = await Self.wait(until: { driver.failedSourceIDs.contains("broken") })
        #expect(failed)
        #expect(runtime.userVisibleIssue == nil)
        #expect(runtime.availableSubtitleTracks.isEmpty)
        let refreshed = try #require(await request.refreshedLoopbackEndpoints())
        let (audioBytes, _) = try await URLSession.shared.data(from: refreshed.url)
        let (subtitleBytes, _) = try await URLSession.shared.data(from: #require(refreshed.externalSubtitleSources.first).url)
        #expect(audioBytes == audioPayload)
        #expect(subtitleBytes == subtitlePayload)
        #expect(refreshed.externalSubtitleSources.map(\.id) == ["broken"])
        await runtime.leavePlaybackAndWait(reason: .backButton)
        refreshed.source.byteStreamHandle?.release()
        refreshed.externalSubtitleSources.forEach { $0.byteStreamHandle?.release() }
    }
}

@MainActor
private final class SubtitleCompletionDriver: PlaybackMediaSessionDriver {
    private(set) var failedSourceIDs: Set<String> = []
    override func addExternalSubtitleSource(
        _ source: PlaybackExternalSubtitleSource
    ) async throws -> [PlaybackSubtitleTrack] {
        do {
            return try await super.addExternalSubtitleSource(source)
        } catch {
            failedSourceIDs.insert(source.id)
            throw error
        }
    }
}

extension PlaybackResidencyTests {
    @Test("a cancelled discovery cannot release subtitle access reused by the next session")
    func cancelledDiscoveryKeepsReusedSubtitleAccessActive() async throws {
        let first = try Self.audioFixture(named: "subtitle-shared-old")
        let next = try Self.audioFixture(named: "subtitle-shared-next")
        let subtitle = next.deletingPathExtension().appendingPathExtension("srt")
        try Data("1\n00:00:00,000 --> 00:00:10,000\nShared subtitle\n".utf8).write(to: subtitle)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: next)
            try? FileManager.default.removeItem(at: subtitle)
        }
        let gate = SubtitleDiscoveryGate()
        let counter = SubtitleRuntimeReleaseCounter()
        let lease = MediaAccessLease(release: { counter.increment() })
        let source = ResolvedExternalSubtitleSource(
            id: "shared", url: subtitle, displayName: "Shared.srt", accessLease: lease
        )
        let runtime = PlaybackRuntime(
            controller: PlaybackCoreController(),
            audioSessionLifecycle: PlaybackAudioSessionLifecycle(session: SettledAudioSession())
        )
        try await runtime.open(PlaybackLaunchRequest(
            source: try PlaybackAddress(localFileURL: first), displayName: "Old",
            externalSubtitleDiscovery: ExternalSubtitleDiscovery {
                await gate.wait()
                return [source]
            }
        ))
        let discoveryWaiting = await Self.wait(until: { gate.waiting })
        #expect(discoveryWaiting)
        await runtime.leavePlaybackAndWait(reason: .backButton)
        try await runtime.open(PlaybackLaunchRequest(
            source: try PlaybackAddress(localFileURL: next), displayName: "Next",
            externalSubtitleSources: [source]
        ))
        let ready = await Self.wait(until: { runtime.availableSubtitleTracks.map(\.id) == ["external.subtitle.shared.0"] })
        #expect(ready)
        gate.release()
        let lateReturned = await Self.wait(until: { gate.didReturn })
        #expect(lateReturned)
        await Task.yield()
        #expect(counter.value == 0)
        #expect(runtime.availableSubtitleTracks.map(\.id) == ["external.subtitle.shared.0"])
        #expect(runtime.currentLaunchRequest?.displayName == "Next")
        await runtime.leavePlaybackAndWait(reason: .backButton)
        #expect(counter.value == 1)
    }
}
