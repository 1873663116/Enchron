import Foundation
import PlaybackCore
import Testing

@testable import Playback

@MainActor
@Suite("Playback residency", .serialized)
struct PlaybackResidencyTests {
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
            SpatialPlatformPlayerWindowClosurePolicy.stopsPlayback(
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
        within timeout: Duration = .seconds(3)
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
