import Foundation
import Testing
@testable import XrPlayerCore

struct PlaybackSourceAccessTests {
    @Test("source access releases its security scope exactly once")
    func releaseIsIdempotent() {
        let counter = ReleaseCounter()
        let access = PlaybackSourceAccess {
            counter.increment()
        }

        access.release()
        access.release()

        #expect(counter.value == 1)
    }

    @Test("released security scope can be acquired again for retry")
    func releasedAccessCanBeReacquired() throws {
        let acquireCounter = ReleaseCounter()
        let releaseCounter = ReleaseCounter()
        let candidate = PlaybackSourceAccess(
            acquire: {
                acquireCounter.increment()
                return true
            },
            release: { releaseCounter.increment() }
        )
        let access = try #require(candidate)

        #expect(acquireCounter.value == 1)
        access.release()
        #expect(releaseCounter.value == 1)

        #expect(access.ensureActive())
        #expect(acquireCounter.value == 2)
        access.release()
        #expect(releaseCounter.value == 2)
    }

    @Test("file playback lease releases exactly once under concurrent teardown")
    func filePlaybackLeaseConcurrentRelease() {
        let counter = ReleaseCounter()
        let lease = FilePlaybackSourceLease {
            counter.increment()
        }

        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            lease.release()
        }

        #expect(counter.value == 1)
    }

    @Test("file playback source owns its lease until the final source is released")
    func filePlaybackSourceOwnsLease() {
        let counter = ReleaseCounter()
        var lease: FilePlaybackSourceLease? = FilePlaybackSourceLease {
            counter.increment()
        }
        var source: FilePlaybackSource? = FilePlaybackSource(
            url: URL(string: "http://127.0.0.1/media")!,
            lease: lease
        )

        lease = nil
        #expect(source?.lease != nil)
        #expect(counter.value == 0)

        source = nil
        #expect(counter.value == 1)
    }

    @Test("resolved playback access releases the transferred file lease")
    func resolvedSourceTransfersLeaseRelease() throws {
        let counter = ReleaseCounter()
        var source: FilePlaybackSource? = FilePlaybackSource(
            url: URL(string: "http://127.0.0.1/media")!,
            lease: FilePlaybackSourceLease {
                counter.increment()
            }
        )
        let resolved = ResolvedPlaybackSource(try #require(source))
        source = nil

        #expect(counter.value == 0)
        let access = try #require(resolved.sourceAccess)
        access.release()
        access.release()

        #expect(counter.value == 1)
    }

    @Test("released file lease cannot report itself active again")
    func transferredFileLeaseIsOneShot() throws {
        let source = FilePlaybackSource(
            url: URL(string: "http://127.0.0.1/media")!,
            lease: FilePlaybackSourceLease {}
        )
        let access = try #require(ResolvedPlaybackSource(source).sourceAccess)

        access.release()
        let didReacquire = access.ensureActive()

        #expect(!didReacquire)
    }
}

private final class ReleaseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
