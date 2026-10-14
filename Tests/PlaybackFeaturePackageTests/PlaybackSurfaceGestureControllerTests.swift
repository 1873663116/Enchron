import Foundation
import PlaybackCore
import Testing
@testable import Playback

@MainActor
struct PlaybackSurfaceGestureControllerTests {
    @Test("surface hosts share one controller and an old host cannot cancel the latest preview")
    func hostsShareControllerAndOwnCancellation() {
        let core = PlaybackCoreController()
        let runtime = PlaybackRuntime(controller: core)
        let session = PlaybackSessionModel()
        let controller = runtime.surfaceGestureController(session: session)
        #expect(runtime.surfaceGestureController(session: session) === controller)
        var diagnostics = PlaybackDiagnostics()
        diagnostics.currentSeconds = 100
        diagnostics.durationSeconds = 1_000
        core.onDiagnosticsChange?(diagnostics)
        let oldOwner = UUID()
        let newOwner = UUID()
        #expect(controller.begin(owner: oldOwner))
        controller.end(owner: oldOwner)
        #expect(controller.phase == .waitingForSecondTap)
        #expect(controller.begin(owner: newOwner))
        controller.update(horizontalTranslation: 300, owner: newOwner)
        #expect(controller.preview?.targetSeconds == 121)
        controller.update(horizontalTranslation: 600, owner: newOwner)
        #expect(controller.phase == .seeking)
        #expect(controller.preview?.targetSeconds == 130)
        controller.cancel(owner: oldOwner)
        controller.end(owner: oldOwner)
        #expect(controller.phase == .seeking)
        #expect(controller.preview?.targetSeconds == 130)
        controller.cancel(owner: newOwner)
        #expect(controller.phase == .idle)
        #expect(controller.preview == nil)
        #expect(session.showControls == false)
    }

    @Test("an old host cannot cancel a new host's hold")
    func oldHostCannotCancelHold() async throws {
        let core = PlaybackCoreController()
        let runtime = PlaybackRuntime(controller: core)
        let session = PlaybackSessionModel()
        let controller = runtime.surfaceGestureController(session: session)
        let oldOwner = UUID()
        let newOwner = UUID()
        #expect(controller.begin(owner: oldOwner))
        controller.end(owner: oldOwner)
        core.onStatusChange?(.playing)
        #expect(controller.begin(owner: newOwner))
        try await waitUntil { controller.phase == .holding }
        #expect(controller.originalPlaybackRate == 1)
        controller.cancel(owner: oldOwner)
        #expect(controller.phase == .holding)
        controller.cancel(owner: newOwner)
        #expect(controller.phase == .idle)
    }

    @Test("an old host cannot cancel a new host's pending tap")
    func oldHostCannotCancelPendingTap() async throws {
        let runtime = PlaybackRuntime(controller: PlaybackCoreController())
        let session = PlaybackSessionModel()
        let controller = runtime.surfaceGestureController(session: session)
        let oldOwner = UUID()
        let newOwner = UUID()
        #expect(controller.begin(owner: oldOwner))
        controller.end(owner: oldOwner)
        #expect(controller.begin(owner: newOwner))
        controller.end(owner: newOwner)
        controller.cancel(owner: oldOwner)
        #expect(controller.phase == .waitingForSecondTap)
        try await waitUntil { session.showControls }
        #expect(session.showControls)
        #expect(controller.phase == .idle)
    }

    @Test("auto hidden controls stay hidden when a visible contact ends")
    func visibleContactCannotReopenControls() {
        let runtime = PlaybackRuntime(controller: PlaybackCoreController())
        let session = PlaybackSessionModel()
        session.showControls = true
        let controller = runtime.surfaceGestureController(session: session)
        let owner = UUID()
        #expect(controller.begin(owner: owner))
        session.showControls = false
        controller.end(owner: owner)
        #expect(session.showControls == false)
        #expect(controller.phase == .waitingForSecondTap)
        controller.cancel()
    }

    @Test("controls appearing during a preview discard the gesture")
    func visibleControlsCancelPreview() {
        let core = PlaybackCoreController()
        let runtime = PlaybackRuntime(controller: core)
        let session = PlaybackSessionModel()
        let controller = runtime.surfaceGestureController(session: session)
        var diagnostics = PlaybackDiagnostics()
        diagnostics.currentSeconds = 100
        diagnostics.durationSeconds = 1_000
        core.onDiagnosticsChange?(diagnostics)
        let owner = UUID()
        #expect(controller.begin(owner: owner))
        controller.update(horizontalTranslation: 600, owner: owner)
        #expect(controller.preview?.targetSeconds == 130)
        session.showControls = true
        controller.synchronize()
        #expect(controller.preview == nil)
        #expect(controller.phase == .idle)
        controller.end(owner: owner)
        #expect(session.showControls)
    }

    @Test("accessibility activation uses immediate control visibility")
    func accessibilityActivationDoesNotJoinTapSequence() {
        let runtime = PlaybackRuntime(controller: PlaybackCoreController())
        let session = PlaybackSessionModel()
        let controller = runtime.surfaceGestureController(session: session)
        let owner = UUID()
        #expect(controller.begin(owner: owner))
        controller.end(owner: owner)
        #expect(controller.phase == .waitingForSecondTap)
        controller.tap()
        #expect(session.showControls)
        #expect(controller.phase == .idle)
    }

    @Test("slow seek ignores old completion and applies the latest double tap intent")
    func slowSeekPreservesLatestIntent() async throws {
        let runtime = PlaybackRuntime(controller: PlaybackCoreController())
        let request = PlaybackLaunchRequest(source: try PlaybackAddress(localFileURL: audioFixture()), displayName: "gesture-seek")
        runtime.prepareForPlayback(request)
        try await runtime.open(request, startTimeSeconds: 0, initialSpeed: .default, initialFormat: nil)
        let gate = GestureSeekGate()
        defer {
            gate.releaseAll()
            Task { await runtime.leavePlaybackAndWait(reason: .backButton) }
        }
        runtime.resume()
        try await waitUntil { runtime.productLifecycle == .playing }
        runtime.debugSetSeekGate { await gate.wait() }
        var completedTargets: [Double] = []
        runtime.onPlaybackObservation = { observation in
            if case .seekCompleted(let target) = observation.event { completedTargets.append(target) }
        }
        runtime.seekFromSurfaceGesture(to: 0.1, wasPlaying: true)
        try await waitUntil { gate.count == 1 }
        runtime.togglePlaybackFromSurfaceGesture()
        runtime.seekFromSurfaceGesture(to: 0.2, wasPlaying: true)
        try await waitUntil { gate.count == 2 }
        gate.release(at: 0)
        try await Task.sleep(for: .milliseconds(30))
        #expect(runtime.seekIsInProgress)
        #expect(runtime.playbackPosition.seconds == 0.2)
        #expect(completedTargets.isEmpty)
        gate.release(at: 1)
        try await waitUntil { !runtime.seekIsInProgress && runtime.productLifecycle == .paused }
        #expect(completedTargets == [0.2])
        #expect(runtime.userVisibleIssue == nil)
        runtime.togglePlaybackFromSurfaceGesture()
        try await waitUntil { runtime.productLifecycle == .playing }
        #expect(runtime.productLifecycle == .playing)
    }

    @Test("cancelled preview delivers the natural end action once")
    func cancellingPreviewRestoresNaturalEnd() async throws {
        let runtime = try await nearEndRuntime()
        defer { Task { await runtime.leavePlaybackAndWait(reason: .backButton) } }
        let session = PlaybackSessionModel()
        let controller = runtime.surfaceGestureController(session: session)
        var endedActions = 0
        runtime.onPlaybackEnded = { endedActions += 1 }
        let owner = UUID()
        #expect(controller.begin(owner: owner))
        controller.update(horizontalTranslation: -100, owner: owner)
        #expect(controller.phase == .seeking)
        try await waitUntil { runtime.productLifecycle == .ended }
        #expect(endedActions == 0)
        controller.cancel(owner: owner)
        #expect(endedActions == 1)
        controller.cancel(owner: owner)
        #expect(endedActions == 1)
    }

    @Test("leaving during a preview discards the old natural end action")
    func leavingDiscardsDeferredNaturalEnd() async throws {
        let runtime = try await nearEndRuntime()
        let session = PlaybackSessionModel()
        let controller = runtime.surfaceGestureController(session: session)
        var endedActions = 0
        runtime.onPlaybackEnded = { endedActions += 1 }
        let owner = UUID()
        #expect(controller.begin(owner: owner))
        controller.update(horizontalTranslation: -100, owner: owner)
        #expect(controller.phase == .seeking)
        try await waitUntil { runtime.productLifecycle == .ended }
        #expect(endedActions == 0)
        await runtime.leavePlaybackAndWait(reason: .backButton)
        #expect(endedActions == 0)
        #expect(controller.phase == .idle)
    }

    private func nearEndRuntime() async throws -> PlaybackRuntime {
        let runtime = PlaybackRuntime(controller: PlaybackCoreController())
        let request = PlaybackLaunchRequest(source: try PlaybackAddress(localFileURL: audioFixture()), displayName: "gesture-end")
        runtime.prepareForPlayback(request)
        try await runtime.open(request, startTimeSeconds: 0, initialSpeed: .default, initialFormat: nil)
        try await waitUntil { runtime.playbackPosition.duration > 1 }
        runtime.seek(to: runtime.playbackPosition.duration - 1)
        try await waitUntil { !runtime.seekIsInProgress }
        runtime.resume()
        try await waitUntil { runtime.productLifecycle == .playing }
        return runtime
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(condition())
    }

    private func audioFixture() throws -> URL {
        var workspace = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if workspace.lastPathComponent == ".worktrees" { workspace.deleteLastPathComponent() }
        let url = workspace.appending(path: "TestMedia/TestVectors/Enchron/CodecContainer/Audio/he-aac-v1-apple-audio-toolbox.m4a")
        try #require(FileManager.default.fileExists(atPath: url.path))
        return url
    }
}

@MainActor
private final class GestureSeekGate {
    private var continuations: [CheckedContinuation<Void, Never>?] = []
    var count: Int { continuations.count }

    func wait() async {
        await withCheckedContinuation { continuations.append($0) }
    }

    func release(at index: Int) {
        continuations[index]?.resume()
        continuations[index] = nil
    }

    func releaseAll() {
        for index in continuations.indices { release(at: index) }
    }
}
