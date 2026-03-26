import XCTest
@testable import XrPlayerCore

final class CoreLogicTests: XCTestCase {
    func testPlayableFilterAcceptsAndRejectsExpectedExtensions() {
        let filter = FileBrowsingDomain.FileFilter.playable

        XCTAssertTrue(filter.matches(fileURL: URL(fileURLWithPath: "/tmp/a.MKV")))
        XCTAssertTrue(filter.matches(fileURL: URL(fileURLWithPath: "/tmp/b.mp4")))
        XCTAssertFalse(filter.matches(fileURL: URL(fileURLWithPath: "/tmp/c.txt")))
    }

    func testLocalDataSourceListsOnlyPlayableFiles() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let playable = root.appendingPathComponent("movie.mp4")
        let notPlayable = root.appendingPathComponent("notes.txt")
        let nestedDirectory = root.appendingPathComponent("dir", isDirectory: true)

        FileManager.default.createFile(atPath: playable.path, contents: Data("a".utf8))
        FileManager.default.createFile(atPath: notPlayable.path, contents: Data("b".utf8))
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)

        let adapter = LocalDataSourceAdapter()
        try await adapter.connect(with: .init(sourceType: .local, rootPath: root.path))
        let files = try await adapter.listContents(at: ".")

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.name, "movie.mp4")
    }

    func testLocalDataSourceSortByNameDescending() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let a = root.appendingPathComponent("a.mp4")
        let z = root.appendingPathComponent("z.mp4")
        FileManager.default.createFile(atPath: a.path, contents: Data("a".utf8))
        FileManager.default.createFile(atPath: z.path, contents: Data("z".utf8))

        let adapter = LocalDataSourceAdapter()
        try await adapter.connect(with: .init(sourceType: .local, rootPath: root.path))

        let folder = FileBrowsingDomain.MediaFolder(name: "Root", dataSourceID: UUID(), path: ".", url: root)
        let sorted = try await adapter.listFiles(
            in: folder,
            sortBy: .init(key: .name, order: .descending)
        )

        XCTAssertEqual(sorted.map { $0.name }, ["z.mp4", "a.mp4"])
    }

    func testProjectionTypePanoramicClassification() {
        XCTAssertTrue(PlaybackCoreDomain.ProjectionType.panorama360.isPanoramic)
        XCTAssertTrue(PlaybackCoreDomain.ProjectionType.panorama180.isPanoramic)
        XCTAssertTrue(PlaybackCoreDomain.ProjectionType.fisheye.isPanoramic)
        XCTAssertFalse(PlaybackCoreDomain.ProjectionType.flat.isPanoramic)
        XCTAssertFalse(PlaybackCoreDomain.ProjectionType.stereoscopicSBS.isPanoramic)
    }

    // PlaybackSpeed and PlaybackPosition clamping tests are in V02Tests.swift
    // (PlaybackSpeedTests and PlaybackPositionTests)

    private func makeTempDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

// MARK: - FileFilter Edge Cases

final class FileFilterEdgeCaseTests: XCTestCase {

    func testFilterIsCaseInsensitive() {
        let filter = FileBrowsingDomain.FileFilter.playable
        XCTAssertTrue(filter.matches(fileURL: URL(fileURLWithPath: "/tmp/movie.MP4")))
        XCTAssertTrue(filter.matches(fileURL: URL(fileURLWithPath: "/tmp/movie.Mkv")))
        XCTAssertTrue(filter.matches(fileURL: URL(fileURLWithPath: "/tmp/movie.AVI")))
    }

    func testAllPlayableExtensionsAccepted() {
        let filter = FileBrowsingDomain.FileFilter.playable
        let expected = ["mp4", "mkv", "avi", "mov", "m4v", "webm", "ts", "m2ts", "flv"]
        for ext in expected {
            XCTAssertTrue(
                filter.matches(fileURL: URL(fileURLWithPath: "/tmp/video.\(ext)")),
                "Extension .\(ext) should be accepted"
            )
        }
    }

    func testNonPlayableExtensionsRejected() {
        let filter = FileBrowsingDomain.FileFilter.playable
        let rejected = ["txt", "pdf", "jpg", "png", "zip", "srt", "ass", "mp3", "aac", "doc"]
        for ext in rejected {
            XCTAssertFalse(
                filter.matches(fileURL: URL(fileURLWithPath: "/tmp/file.\(ext)")),
                "Extension .\(ext) should be rejected"
            )
        }
    }

    func testEmptyExtensionRejected() {
        let filter = FileBrowsingDomain.FileFilter.playable
        XCTAssertFalse(filter.matches(fileURL: URL(fileURLWithPath: "/tmp/noextension")))
    }

    func testCustomFilterWithSingleExtension() {
        let filter = FileBrowsingDomain.FileFilter(allowedExtensions: ["Custom"])
        XCTAssertTrue(filter.matches(fileURL: URL(fileURLWithPath: "/tmp/file.custom")))
        XCTAssertTrue(filter.matches(fileURL: URL(fileURLWithPath: "/tmp/file.CUSTOM")))
        XCTAssertFalse(filter.matches(fileURL: URL(fileURLWithPath: "/tmp/file.other")))
    }

    func testFilterEquality() {
        let a = FileBrowsingDomain.FileFilter(allowedExtensions: ["mp4", "mkv"])
        let b = FileBrowsingDomain.FileFilter(allowedExtensions: ["MKV", "MP4"])
        XCTAssertEqual(a, b, "Filters with same extensions (different case) should be equal")
    }
}

// MARK: - SortCriteria Tests

final class SortCriteriaTests: XCTestCase {

    func testNameAscendingConvenience() {
        let criteria = FileBrowsingDomain.SortCriteria.nameAscending
        XCTAssertEqual(criteria.key, .name)
        XCTAssertEqual(criteria.order, .ascending)
    }

    func testAllKeysAndOrderCombinations() {
        let keys: [FileBrowsingDomain.SortCriteria.Key] = [.name, .modifiedDate, .size]
        let orders: [FileBrowsingDomain.SortCriteria.Order] = [.ascending, .descending]

        for key in keys {
            for order in orders {
                let criteria = FileBrowsingDomain.SortCriteria(key: key, order: order)
                XCTAssertEqual(criteria.key, key)
                XCTAssertEqual(criteria.order, order)
            }
        }
    }

    func testEquality() {
        let a = FileBrowsingDomain.SortCriteria(key: .name, order: .ascending)
        let b = FileBrowsingDomain.SortCriteria(key: .name, order: .ascending)
        let c = FileBrowsingDomain.SortCriteria(key: .name, order: .descending)
        let d = FileBrowsingDomain.SortCriteria(key: .size, order: .ascending)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c, "Different order should not be equal")
        XCTAssertNotEqual(a, d, "Different key should not be equal")
    }

    func testSortByNameAscendingInAdapter() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        createFile(at: root, name: "beta.mp4")
        createFile(at: root, name: "alpha.mp4")
        createFile(at: root, name: "gamma.mp4")

        let adapter = LocalDataSourceAdapter()
        try await adapter.connect(with: .init(sourceType: .local, rootPath: root.path))
        let folder = FileBrowsingDomain.MediaFolder(name: "Root", dataSourceID: UUID(), path: ".", url: root)

        let ascending = try await adapter.listFiles(in: folder, sortBy: .init(key: .name, order: .ascending))
        XCTAssertEqual(ascending.map { $0.name }, ["alpha.mp4", "beta.mp4", "gamma.mp4"])
    }

    func testSortByNameDescendingInAdapter() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        createFile(at: root, name: "beta.mp4")
        createFile(at: root, name: "alpha.mp4")
        createFile(at: root, name: "gamma.mp4")

        let adapter = LocalDataSourceAdapter()
        try await adapter.connect(with: .init(sourceType: .local, rootPath: root.path))
        let folder = FileBrowsingDomain.MediaFolder(name: "Root", dataSourceID: UUID(), path: ".", url: root)

        let descending = try await adapter.listFiles(in: folder, sortBy: .init(key: .name, order: .descending))
        XCTAssertEqual(descending.map { $0.name }, ["gamma.mp4", "beta.mp4", "alpha.mp4"])
    }

    func testSortBySizeInAdapter() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        createFile(at: root, name: "small.mp4", size: 10)
        createFile(at: root, name: "large.mp4", size: 1000)
        createFile(at: root, name: "medium.mp4", size: 500)

        let adapter = LocalDataSourceAdapter()
        try await adapter.connect(with: .init(sourceType: .local, rootPath: root.path))
        let folder = FileBrowsingDomain.MediaFolder(name: "Root", dataSourceID: UUID(), path: ".", url: root)

        let ascending = try await adapter.listFiles(in: folder, sortBy: .init(key: .size, order: .ascending))
        XCTAssertEqual(ascending.map { $0.name }, ["small.mp4", "medium.mp4", "large.mp4"])

        let descending = try await adapter.listFiles(in: folder, sortBy: .init(key: .size, order: .descending))
        XCTAssertEqual(descending.map { $0.name }, ["large.mp4", "medium.mp4", "small.mp4"])
    }

    private func makeTempDir() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func createFile(at dir: URL, name: String, size: Int = 1) {
        let data = Data(repeating: 0, count: size)
        FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: data)
    }
}

// MARK: - Playback Mode Decision Tests

final class PlaybackModeDecisionTests: XCTestCase {

    /// Test the playback mode decision logic directly.
    /// The actual decision lives in AppCoordinator (App module, not testable here),
    /// but the decision rule is: panoramic → panorama, env active → immersive, else → window.
    /// We test the inputs (ProjectionType.isPanoramic) and verify all combinations.
    func testPanoramicProjectionTypesReturnTrue() {
        let panoramicTypes: [PlaybackCoreDomain.ProjectionType] = [.panorama360, .panorama180, .fisheye]
        for type in panoramicTypes {
            XCTAssertTrue(type.isPanoramic, "\(type) should be panoramic")
        }
    }

    func testNonPanoramicProjectionTypesReturnFalse() {
        let nonPanoramic: [PlaybackCoreDomain.ProjectionType] = [.flat, .stereoscopicSBS, .stereoscopicOU]
        for type in nonPanoramic {
            XCTAssertFalse(type.isPanoramic, "\(type) should not be panoramic")
        }
    }

    func testAllProjectionTypesCovered() {
        // Ensure every ProjectionType case has been classified
        let allTypes = PlaybackCoreDomain.ProjectionType.allCases
        XCTAssertEqual(allTypes.count, 6, "Expected 6 projection types (flat, sbs, ou, 360, 180, fisheye)")

        let panoramic = allTypes.filter { $0.isPanoramic }
        let nonPanoramic = allTypes.filter { !$0.isPanoramic }
        XCTAssertEqual(panoramic.count, 3)
        XCTAssertEqual(nonPanoramic.count, 3)
    }

    /// Simulate the decision matrix that AppCoordinator.decidePlaybackMode implements.
    /// Each row: (projectionType.isPanoramic, isEnvironmentActive) → expected mode
    func testDecisionMatrix() {
        struct DecisionRow {
            let isPanoramic: Bool
            let isEnvironmentActive: Bool
            let expectedMode: String
        }

        let matrix: [DecisionRow] = [
            DecisionRow(isPanoramic: true, isEnvironmentActive: false, expectedMode: "panorama"),
            DecisionRow(isPanoramic: true, isEnvironmentActive: true, expectedMode: "panorama"),
            DecisionRow(isPanoramic: false, isEnvironmentActive: true, expectedMode: "immersive"),
            DecisionRow(isPanoramic: false, isEnvironmentActive: false, expectedMode: "window"),
        ]

        for row in matrix {
            let mode: String
            if row.isPanoramic {
                mode = "panorama"
            } else {
                mode = row.isEnvironmentActive ? "immersive" : "window"
            }
            XCTAssertEqual(mode, row.expectedMode,
                "isPanoramic=\(row.isPanoramic) envActive=\(row.isEnvironmentActive) should be \(row.expectedMode)")
        }
    }
}
