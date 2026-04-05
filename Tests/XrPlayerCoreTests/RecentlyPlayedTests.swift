import XCTest
@testable import XrPlayerCore

/// Verifies the loadRecentlyPlayed contract for ProgressStoring.
///
/// SwiftDataStore uses UserDefaults internally. These tests use a dedicated
/// UserDefaults suite to avoid pollution and validate the full storage round-trip.
final class RecentlyPlayedTests: XCTestCase {

    private var store: SwiftDataStore!
    private var defaults: UserDefaults!
    private let suiteName = "RecentlyPlayedTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        // Clean slate
        defaults.removePersistentDomain(forName: suiteName)
        store = SwiftDataStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeProgress(
        path: String = "/video.mp4",
        size: Int64 = 1000,
        fingerprint: String? = nil,
        seconds: Double = 120,
        updatedAt: Date = Date()
    ) -> PersistenceDomain.PlaybackProgress {
        PersistenceDomain.PlaybackProgress(
            fileID: PersistenceDomain.FileIdentifier.make(
                path: path, sizeInBytes: size, serverFingerprint: fingerprint
            ),
            position: PersistenceDomain.ProgressPosition(seconds: seconds),
            updatedAt: updatedAt
        )
    }

    // MARK: - Normal Path

    func testLoadRecentlyPlayedReturnsSortedByTimestampDescending() async {
        let older = makeProgress(path: "/a.mp4", seconds: 10, updatedAt: Date(timeIntervalSince1970: 1000))
        let newer = makeProgress(path: "/b.mp4", seconds: 20, updatedAt: Date(timeIntervalSince1970: 2000))
        let newest = makeProgress(path: "/c.mp4", seconds: 30, updatedAt: Date(timeIntervalSince1970: 3000))

        await store.saveProgress(older)
        await store.saveProgress(newer)
        await store.saveProgress(newest)

        let result = await store.loadRecentlyPlayed(limit: 50)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].fileID, newest.fileID, "Most recent should be first")
        XCTAssertEqual(result[1].fileID, newer.fileID)
        XCTAssertEqual(result[2].fileID, older.fileID)
    }

    func testLoadRecentlyPlayedDeduplicatesKeepingMostRecent() async {
        let fileID = PersistenceDomain.FileIdentifier.make(
            path: "/same.mp4", sizeInBytes: 500, serverFingerprint: nil
        )
        // Save twice with same fileID — only the last write survives in UserDefaults
        // (same key overwrite), but the contract specifies dedup behavior.
        let first = PersistenceDomain.PlaybackProgress(
            fileID: fileID,
            position: PersistenceDomain.ProgressPosition(seconds: 10),
            updatedAt: Date(timeIntervalSince1970: 1000)
        )
        await store.saveProgress(first)

        // Overwrite with newer timestamp
        let second = PersistenceDomain.PlaybackProgress(
            fileID: fileID,
            position: PersistenceDomain.ProgressPosition(seconds: 60),
            updatedAt: Date(timeIntervalSince1970: 2000)
        )
        await store.saveProgress(second)

        let result = await store.loadRecentlyPlayed(limit: 50)

        XCTAssertEqual(result.count, 1, "Duplicate FileIdentifier should be deduplicated")
        XCTAssertEqual(result[0].position.seconds, 60, "Should keep the most recent entry")
    }

    func testLoadRecentlyPlayedRespectsLimit() async {
        for i in 0..<10 {
            let progress = makeProgress(
                path: "/video\(i).mp4",
                seconds: Double(i * 10),
                updatedAt: Date(timeIntervalSince1970: Double(i) * 1000)
            )
            await store.saveProgress(progress)
        }

        let result = await store.loadRecentlyPlayed(limit: 3)

        XCTAssertEqual(result.count, 3, "Should return at most `limit` items")
        // Verify they're the 3 most recent
        XCTAssertEqual(result[0].position.seconds, 90)
        XCTAssertEqual(result[1].position.seconds, 80)
        XCTAssertEqual(result[2].position.seconds, 70)
    }

    // MARK: - Edge Cases

    func testLoadRecentlyPlayedEmptyStoreReturnsEmptyArray() async {
        let result = await store.loadRecentlyPlayed(limit: 50)
        XCTAssertTrue(result.isEmpty, "Empty store should return empty array")
    }

    func testLoadRecentlyPlayedWithZeroLimitReturnsEmpty() async {
        await store.saveProgress(makeProgress())
        let result = await store.loadRecentlyPlayed(limit: 0)
        XCTAssertTrue(result.isEmpty, "Limit of 0 should return empty array")
    }

    // MARK: - Protocol Default

    func testProtocolDefaultReturnsEmptyArray() async {
        struct MinimalStore: ProgressStoring {
            func saveProgress(_ progress: PersistenceDomain.PlaybackProgress) async {}
            func loadProgress(for fileID: PersistenceDomain.FileIdentifier) async -> PersistenceDomain.PlaybackProgress? { nil }
            func cleanExpiredProgress(olderThan days: Int) async {}
        }

        let minimalStore = MinimalStore()
        let result = await minimalStore.loadRecentlyPlayed(limit: 10)
        XCTAssertTrue(result.isEmpty, "Protocol default should return empty array")
    }
}
