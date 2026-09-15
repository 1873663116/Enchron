import Foundation
import MediaSource
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
