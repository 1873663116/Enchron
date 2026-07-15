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
