import Foundation
@testable import MediaSource
import Testing

@MainActor
struct MediaSourcePreparationTests {
    @Test("background suspension rejects preparation without executing it")
    func suspensionRejectsWork() async throws {
        let preparation = MediaSourcePreparation()
        var didRun = false
        preparation.suspend()
        do {
            _ = try await preparation.resolve { didRun = true; return "unexpected" }
            Issue.record("Suspended preparation was accepted")
        } catch { #expect(error is CancellationError) }
        #expect(!didRun)
        preparation.resume()
        #expect(try await preparation.resolve { "ready" } == "ready")
    }

    @Test("exit rejects a late preparation result while a new attempt succeeds")
    func rejectsLateResult() async throws {
        let preparation = MediaSourcePreparation()
        let gate = PreparationGate()
        let old = Task {
            try await preparation.resolve {
                await gate.wait()
                return "old"
            }
        }
        while !gate.waiting { await Task.yield() }
        preparation.cancel()
        let next = try await preparation.resolve { "new" }
        #expect(next == "new")
        gate.release()
        do {
            _ = try await old.value
            Issue.record("The cancelled preparation returned a launchable result")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test("an old preparation error cannot replace the next attempt's result")
    func rejectsLateFailure() async throws {
        let preparation = MediaSourcePreparation()
        let gate = PreparationGate()
        let old = Task {
            try await preparation.resolve { () -> String in
                await gate.wait()
                throw URLError(.cannotConnectToHost)
            }
        }
        while !gate.waiting { await Task.yield() }
        let next = try await preparation.resolve { "new" }
        gate.release()
        #expect(next == "new")
        do {
            _ = try await old.value
            Issue.record("The cancelled preparation completed")
        } catch {
            #expect(error is CancellationError)
        }
    }
}

@MainActor
private final class PreparationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
struct ExternalSubtitleDiscoveryTests {
    @Test("a successful discovery returns the source and keeps its access active")
    func successfulDiscoveryTransfersAccess() async throws {
        let counter = SubtitleDiscoveryReleaseCounter()
        let lease = MediaAccessLease(release: { counter.increment() })
        let discovery = ExternalSubtitleDiscovery {
            [ResolvedExternalSubtitleSource(
                id: "ready", url: URL(fileURLWithPath: "/Movie.srt"),
                displayName: "Movie.srt", accessLease: lease
            )]
        }
        let sources = try await discovery.resolve()
        #expect(sources.map(\.id) == ["ready"])
        #expect(counter.value == 0)
        sources.first?.accessLease?.release()
        #expect(counter.value == 1)
    }

    @Test("a discovery deadline returns before unresponsive work and releases its late access")
    func deadlineDiscardsLateResources() async throws {
        let gate = PreparationGate()
        let counter = SubtitleDiscoveryReleaseCounter()
        let lease = MediaAccessLease(release: { counter.increment() })
        let discovery = ExternalSubtitleDiscovery {
            await gate.wait()
            return [ResolvedExternalSubtitleSource(
                id: "late", url: URL(fileURLWithPath: "/Movie.srt"),
                displayName: "Movie.srt", accessLease: lease
            )]
        }
        let resolving = Task { try await discovery.resolve(deadline: .milliseconds(30)) }
        while !gate.waiting { await Task.yield() }
        do {
            _ = try await resolving.value
            Issue.record("Timed out subtitle discovery returned a source")
        } catch {
            #expect(error as? ExternalSubtitleDiscovery.DiscoveryError == .deadlineExceeded)
        }
        #expect(counter.value == 0)
        gate.release()
        let deadline = ContinuousClock.now + .seconds(1)
        while counter.value == 0, ContinuousClock.now < deadline { await Task.yield() }
        #expect(counter.value == 1)
    }

    @Test("cancelling discovery returns before unresponsive work and releases its late access")
    func cancellationDiscardsLateResources() async throws {
        let gate = PreparationGate()
        let counter = SubtitleDiscoveryReleaseCounter()
        let lease = MediaAccessLease(release: { counter.increment() })
        let discovery = ExternalSubtitleDiscovery {
            await gate.wait()
            return [ResolvedExternalSubtitleSource(
                id: "cancelled", url: URL(fileURLWithPath: "/Movie.srt"),
                displayName: "Movie.srt", accessLease: lease
            )]
        }
        let resolving = Task { try await discovery.resolve() }
        while !gate.waiting { await Task.yield() }
        resolving.cancel()
        do {
            _ = try await resolving.value
            Issue.record("Cancelled subtitle discovery returned a source")
        } catch { #expect(error is CancellationError) }
        gate.release()
        let deadline = ContinuousClock.now + .seconds(1)
        while counter.value == 0, ContinuousClock.now < deadline { await Task.yield() }
        #expect(counter.value == 1)
    }
}

private final class SubtitleDiscoveryReleaseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
