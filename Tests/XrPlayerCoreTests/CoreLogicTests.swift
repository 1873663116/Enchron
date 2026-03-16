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
