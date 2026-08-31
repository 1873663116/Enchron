import Foundation
import XCTest
@testable import Enchron

#if DEBUG
nonisolated final class EmbyRuntimeIdentityCleanupTests: XCTestCase {
    private enum OperationFailure: Error, Equatable {
        case invalidArguments
        case missingIdentity
        case downstreamPreparation
    }

    func testInvalidArgumentFailureRemovesRuntimeIdentity() async throws {
        let identityURL = try makeIdentityFile()
        let cleanup = EmbyRuntimeIdentityCleanup(
            fileURL: identityURL,
            fileManager: .default
        )

        await assertOperationFailure(.invalidArguments) {
            try await cleanup.perform {
                throw OperationFailure.invalidArguments
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: identityURL.path))
    }

    func testSuccessRemovesRuntimeIdentity() async throws {
        let identityURL = try makeIdentityFile()
        let cleanup = EmbyRuntimeIdentityCleanup(
            fileURL: identityURL,
            fileManager: .default
        )

        let receipt = try await cleanup.perform { "prepared" }

        XCTAssertEqual(receipt, "prepared")
        XCTAssertFalse(FileManager.default.fileExists(atPath: identityURL.path))
    }

    func testDownstreamPreparationFailureRemovesRuntimeIdentity() async throws {
        let identityURL = try makeIdentityFile()
        let cleanup = EmbyRuntimeIdentityCleanup(
            fileURL: identityURL,
            fileManager: .default
        )

        await assertOperationFailure(.downstreamPreparation) {
            try await cleanup.perform {
                throw OperationFailure.downstreamPreparation
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: identityURL.path))
    }

    func testMissingRuntimeIdentityPreservesCommandFailure() async {
        let identityURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .notDirectory)
        let cleanup = EmbyRuntimeIdentityCleanup(
            fileURL: identityURL,
            fileManager: .default
        )

        await assertOperationFailure(.missingIdentity) {
            try await cleanup.perform {
                throw OperationFailure.missingIdentity
            }
        }
    }

    func testRemovalFailureIsObservableAndOverridesSuccess() async {
        let identityURL = URL(
            filePath: "/Documents/Regression/emby-runtime-identity.json"
        )
        var removedURL: URL?
        let cleanup = EmbyRuntimeIdentityCleanup(
            fileURL: identityURL,
            removeFile: { url in
                removedURL = url
                throw CocoaError(.fileWriteNoPermission)
            }
        )

        do {
            _ = try await cleanup.perform { "prepared" }
            XCTFail("Expected cleanup failure.")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "The staged Emby runtime identity could not be removed."
            )
        }
        XCTAssertEqual(removedURL, identityURL)
    }

    private func makeIdentityFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let identityURL = directory.appending(
            path: "emby-runtime-identity.json",
            directoryHint: .notDirectory
        )
        try Data([0x65, 0x6D, 0x62, 0x79]).write(to: identityURL)
        return identityURL
    }

    private func assertOperationFailure(
        _ expected: OperationFailure,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected).")
        } catch let failure as OperationFailure {
            XCTAssertEqual(failure, expected)
        } catch {
            XCTFail("Unexpected failure: \(type(of: error)).")
        }
    }
}
#endif
