import Foundation
import MediaLibrary
import MediaSource
import Testing
@testable import Enchron

struct PlaybackSourceAccessTests {
    @Test("source access releases its security scope exactly once")
    func releaseIsIdempotent() {
        let counter = ReleaseCounter()
        let access = MediaAccessLease {
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
        let candidate = MediaAccessLease(
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
        let lease = MediaAccessLease {
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
        var lease: MediaAccessLease? = MediaAccessLease {
            counter.increment()
        }
        var source: ResolvedMediaSource? = ResolvedMediaSource(
            url: URL(string: "http://127.0.0.1/media")!,
            accessLease: lease
        )

        lease = nil
        #expect(source?.accessLease != nil)
        #expect(counter.value == 0)

        source = nil
        #expect(counter.value == 1)
    }

    @Test("resolved media source owns and releases its access lease")
    func resolvedSourceOwnsAccessLease() throws {
        let counter = ReleaseCounter()
        var source: ResolvedMediaSource? = ResolvedMediaSource(
            url: URL(string: "http://127.0.0.1/media")!,
            accessLease: MediaAccessLease {
                counter.increment()
            }
        )
        let access = try #require(source?.accessLease)
        access.release()
        access.release()
        source = nil

        #expect(counter.value == 1)
    }

    @Test("released file lease cannot report itself active again")
    func transferredFileLeaseIsOneShot() throws {
        let source = ResolvedMediaSource(
            url: URL(string: "http://127.0.0.1/media")!,
            accessLease: MediaAccessLease {}
        )
        let access = try #require(source.accessLease)

        access.release()
        let didReacquire = access.ensureActive()

        #expect(!didReacquire)
    }
}

nonisolated private final class ReleaseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
