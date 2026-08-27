import Foundation
import MediaSource
import Testing

struct MediaSourceDomainContractTests {
    @Test("playback collection must use natural ascending name order")
    func playbackCollectionUsesNaturalAscendingNameOrder() throws {
        let names = ["Episode 10", "Episode 2", "Episode 01"]
        var collection: [(name: String, id: UUID)] = []
        for (offset, name) in names.enumerated() {
            let identifier = try #require(
                UUID(uuidString: "00000000-0000-0000-0000-00000000000\(offset)")
            )
            collection.append((name, identifier))
        }
        let ordered = collection.sorted {
            NaturalMediaNameOrder.lessThan($0.name, id: $0.id, $1.name, id: $1.id)
        }

        #expect(
            ordered.map(\.name) == ["Episode 01", "Episode 2", "Episode 10"],
            "playback collection must use natural ascending name order"
        )
    }

    @Test("media access lease must release exactly once")
    func mediaAccessLeaseReleasesExactlyOnce() {
        let leaseCounter = MediaSourceContractCounter()
        let lease = MediaAccessLease { leaseCounter.increment() }

        lease.release()
        lease.release()

        #expect(leaseCounter.value == 1, "media access lease must release exactly once")
    }
}

nonisolated private final class MediaSourceContractCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int { lock.withLock { storedValue } }

    func increment() {
        lock.withLock { storedValue += 1 }
    }
}
