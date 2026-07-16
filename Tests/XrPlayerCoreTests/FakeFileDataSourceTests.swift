import Foundation
import Testing
@testable import XrPlayerCore

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

    @Test("resolvePlayableSource returns the file's own URL")
    func resolvePlayableSourceReturnsFileURL() async throws {
        let source = FakeFileDataSource()
        let file = try await source.listContents(at: "/").first { $0.name == "Arrival.mkv" }
        let resolved = try await source.resolvePlayableSource(for: try #require(file))
        #expect(resolved.url == file?.url)
        #expect(resolved.url.scheme == "fake")
        #expect(resolved.lease == nil)
    }

    @Test("listing fails when the failure mode is armed (UC-FILE-28)")
    func failureModeThrows() async throws {
        let source = FakeFileDataSource(failureMode: .listingFails(message: "connection dropped"))
        await #expect(throws: (any Error).self) {
            _ = try await source.listContents(at: "/")
        }
    }

    // MARK: - Deep catalog (in/out navigation harness)

    @Test("demoDeep root lists the four top-level folders")
    func demoDeepRootFolders() async throws {
        let source = FakeFileDataSource(catalog: .demoDeep)
        let folders = try await source.listFolders(at: "/")
        #expect(folders.map(\.name) == ["Movies", "Documentaries", "Concerts", "Empty"])
    }

    @Test("demoDeep nests four levels deep with a leaf series folder")
    func demoDeepNesting() async throws {
        let source = FakeFileDataSource(catalog: .demoDeep)
        #expect(try await source.listFolders(at: "/Movies").map(\.name) == ["Sci-Fi", "Drama", "Animation"])
        #expect(try await source.listFolders(at: "/Movies/Sci-Fi").map(\.name) == ["Series"])
        let episodes = try await source.listContents(at: "/Movies/Sci-Fi/Series")
        #expect(episodes.count == 3)
        #expect(episodes.allSatisfy { $0.name.hasPrefix("Foundation") })
    }

    @Test("demoDeep exposes empty folders at root and nested depth (UC-FILE-23)")
    func demoDeepEmptyFolders() async throws {
        let source = FakeFileDataSource(catalog: .demoDeep)
        // Root-level empty folder.
        #expect(try await source.listContents(at: "/Empty").isEmpty)
        #expect(try await source.listFolders(at: "/Empty").isEmpty)
        // Nested empty folder, reachable only by descending into /Concerts.
        #expect(try await source.listFolders(at: "/Concerts").map(\.name) == ["Empty Nested"])
        #expect(try await source.listContents(at: "/Concerts/Empty Nested").isEmpty)
        #expect(try await source.listFolders(at: "/Concerts/Empty Nested").isEmpty)
    }

    @Test("demoDeep round-trips the logical root key the browser falls back to")
    func demoDeepRootKeyConsistency() async throws {
        // The browser lists the local root via "." (empty stack) and, after
        // popping back from a subfolder, via "/" — both must surface the same
        // root listing or back/forward navigation lands on an empty page.
        let source = FakeFileDataSource(catalog: .demoDeep)
        let viaDot = try await source.listFolders(at: ".").map(\.name)
        let viaSlash = try await source.listFolders(at: "/").map(\.name)
        #expect(viaDot == viaSlash)
        #expect(!viaSlash.isEmpty)
    }
}
