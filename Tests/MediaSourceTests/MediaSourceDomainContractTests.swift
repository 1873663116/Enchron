import CoreGraphics
import Foundation
import MediaSource
import Testing

struct MediaSourceDomainContractTests {
    #if DEBUG
    @Test("artwork debug identity is the exact encoded file identity")
    func artworkDebugIdentityMatchesStoredBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ArtworkStore(debugRootURL: root)
        let key = ArtworkKey(
            mediaIdentity: .localPathFallback(canonicalPath: "/regression/artwork.mkv")
        )
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: 4,
                height: 4,
                bitsPerComponent: 8,
                bytesPerRow: 16,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())

        let current = try store.debugEncodedIdentity(image, for: key)
        try store.store(image, for: key)
        let stored = try #require(store.debugStoredIdentity(for: key))

        #expect(current == stored)
        #expect(current.artworkKey == key.debugStorageKey)
        #expect(current.width == 4)
        #expect(current.height == 4)
        #expect(current.bytes > 0)

        let populated = store.debugSnapshot()
        #expect(populated.schema == ArtworkStoreDebugSnapshot.schemaValue)
        #expect(populated.entryCount == 1)
        #expect(populated.entries == [
            ArtworkStoreDebugEntry(
                artworkKey: key.debugStorageKey,
                digest: stored.digest,
                bytes: Int64(stored.bytes),
                hasValidStorageName: true
            )
        ])
        #expect(populated.totalBytes == Int64(stored.bytes))
        #expect(populated.invalidFileCount == 0)

        await store.clear()
        let empty = store.debugSnapshot()
        #expect(empty.storeIdentity == populated.storeIdentity)
        #expect(empty.entryCount == 0)
        #expect(empty.entries.isEmpty)
        #expect(empty.totalBytes == 0)
        #expect(empty.digest != populated.digest)
    }

    @Test("container index debug snapshot binds exact revision files")
    func containerIndexDebugSnapshotBindsExactRevisionFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ContainerIndexCache(debugRootURL: root)
        let revisionKey = String(repeating: "a", count: 64)
        let revisionRoot = root.appending(
            path: revisionKey,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: revisionRoot,
            withIntermediateDirectories: true
        )
        try Data("abc".utf8).write(
            to: revisionRoot.appending(path: "0-3.bin")
        )
        try Data("3".utf8).write(
            to: revisionRoot.appending(path: "length.txt")
        )

        let populated = cache.debugSnapshot()
        #expect(populated.schema == ContainerIndexDebugSnapshot.schemaValue)
        #expect(populated.entryCount == 1)
        #expect(populated.entries.count == 1)
        #expect(populated.entries[0].contentRevision == "sha256:\(revisionKey)")
        #expect(populated.entries[0].bytes == 4)
        #expect(populated.entries[0].contentLength == 3)
        #expect(populated.entries[0].ranges == [
            ContainerIndexDebugRange(
                lowerBound: 0,
                upperBoundExclusive: 3,
                bytes: 3
            )
        ])
        #expect(populated.entries[0].invalidFileCount == 0)
        #expect(populated.entries[0].digest.hasPrefix("sha256:"))
        #expect(populated.digest.hasPrefix("sha256:"))

        await cache.clear()
        let empty = cache.debugSnapshot()
        #expect(empty.cacheIdentity == populated.cacheIdentity)
        #expect(empty.entryCount == 0)
        #expect(empty.entries.isEmpty)
        #expect(empty.totalBytes == 0)
        #expect(empty.digest != populated.digest)
    }
    #endif

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

    #if DEBUG
    @Test("artwork file URL changes when the stored frame is rewritten")
    func artworkFileURLCarriesTheModificationTime() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ArtworkStore(debugRootURL: root)
        let key = ArtworkKey(
            mediaIdentity: .localPathFallback(canonicalPath: "/regression/rewritten.mkv")
        )
        #expect(store.fileURL(for: key) == nil)

        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: 4,
                height: 4,
                bitsPerComponent: 8,
                bytesPerRow: 16,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())
        try store.store(image, for: key)

        let first = try #require(store.fileURL(for: key))
        #expect(first.isFileURL)
        #expect(FileManager.default.fileExists(atPath: first.path))
        let firstStamp = try #require(first.fragment.flatMap(Int.init))

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: first.path
        )
        let second = try #require(store.fileURL(for: key))
        #expect(second.path == first.path)
        #expect(second.fragment == "1700000000000")
        #expect(second.fragment.flatMap(Int.init) != firstStamp)
    }
    #endif

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
