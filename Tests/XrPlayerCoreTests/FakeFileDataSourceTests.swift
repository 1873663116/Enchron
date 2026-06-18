import Foundation
import Testing
@testable import XrPlayerCore

/// Verifies the in-memory `FakeFileDataSource` that backs the FakeApp's file
/// browsing — the deterministic catalog, empty directories, path normalization,
/// URL resolution, and the injectable failure mode (UC-FILE-23 / UC-FILE-28).
struct FakeFileDataSourceTests {

    @Test("demo catalog root lists the nine demo films")
    func rootListsNineFilms() async throws {
        let source = FakeFileDataSource()
        let files = try await source.listContents(at: "/")
        #expect(files.count == 9)
        #expect(files.contains { $0.name == "Interstellar.mkv" })
        #expect(files.contains { $0.name == "Dune Part Two.mkv" })
    }

    @Test("demo catalog root lists the two seeded folders")
    func rootListsTwoFolders() async throws {
        let source = FakeFileDataSource()
        let folders = try await source.listFolders(at: "/")
        #expect(folders.map(\.name).sorted() == ["Documentaries", "Empty"])
    }

    @Test("a subfolder lists its own films")
    func subfolderListsItsFilms() async throws {
        let source = FakeFileDataSource()
        let files = try await source.listContents(at: "/Documentaries")
        #expect(files.map(\.name).sorted() == ["Cosmos.mkv", "Planet Earth.mkv"])
    }

    @Test("an empty folder lists no files and no folders (UC-FILE-23)")
    func emptyFolderIsEmpty() async throws {
        let source = FakeFileDataSource()
        let files = try await source.listContents(at: "/Empty")
        let folders = try await source.listFolders(at: "/Empty")
        #expect(files.isEmpty)
        #expect(folders.isEmpty)
    }

    @Test("\".\" and empty path normalize to the catalog root")
    func dotPathNormalizesToRoot() async throws {
        let source = FakeFileDataSource()
        let dotFiles = try await source.listContents(at: ".")
        let emptyFiles = try await source.listContents(at: "")
        #expect(dotFiles.count == 9)
        #expect(emptyFiles.count == 9)
    }

    @Test("resolvePlayableURL returns the file's own URL")
    func resolvePlayableURLReturnsFileURL() async throws {
        let source = FakeFileDataSource()
        let file = try await source.listContents(at: "/").first { $0.name == "Arrival.mkv" }
        let resolved = try await source.resolvePlayableURL(for: try #require(file))
        #expect(resolved == file?.url)
        #expect(resolved.scheme == "fake")
    }

    @Test("listing fails when the failure mode is armed (UC-FILE-28)")
    func failureModeThrows() async throws {
        let source = FakeFileDataSource(failureMode: .listingFails(message: "connection dropped"))
        await #expect(throws: (any Error).self) {
            _ = try await source.listContents(at: "/")
        }
    }
}
