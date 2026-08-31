import CryptoKit
import Foundation
import MediaLibrary
import XCTest
@testable import Enchron

nonisolated final class LibraryEvidenceSnapshotTests: XCTestCase {
    @MainActor
    func testProductStateResetReceiptFindsOnlyManagedDefaultsAndCanonicalizesLists() throws {
        let suiteName = "ProductStateResetReceiptTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("progress", forKey: "enchron.playback.progress")
        defaults.set("fingerprint", forKey: "server-certificate-fingerprint.example")
        defaults.set("preserve", forKey: "unrelated.preference")

        XCTAssertEqual(
            ProductStateResetReceipt.managedDefaultKeys(in: defaults),
            [
                "enchron.playback.progress",
                "server-certificate-fingerprint.example"
            ]
        )

        let receipt = ProductStateResetReceipt(
            removedReferenceCount: 2,
            removedFolderCount: 1,
            removedManagedDefaultKeys: ["z", "a"],
            remainingReferenceCount: 0,
            remainingFolderCount: 2,
            remainingManagedDefaultKeys: ["y", "b"],
            createdFolderNames: ["Second", "First"]
        )
        XCTAssertEqual(receipt.schema, ProductStateResetReceipt.schemaValue)
        XCTAssertEqual(receipt.removedManagedDefaultKeys, ["a", "z"])
        XCTAssertEqual(receipt.remainingManagedDefaultKeys, ["b", "y"])
        XCTAssertEqual(receipt.createdFolderNames, ["First", "Second"])
    }

    @MainActor
    func testSnapshotBindsReferenceFolderIdentityAndSourceBytes() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let inbox = root.appending(path: "TestMediaInbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: inbox,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appending(path: "source.mp4")
        let sourceBytes = Data("source-bytes".utf8)
        try sourceBytes.write(to: source)
        let staged = inbox.appending(path: "fixture.mp4")
        let stagedBytes = Data("staged-bytes".utf8)
        try stagedBytes.write(to: staged)

        var library = FileBrowsingDomain.MediaLibrary()
        let folder = try library.createFolder(named: "Destination")
        let referenceID = UUID()
        try library.add(
            .init(
                id: referenceID,
                name: source.lastPathComponent,
                locator: .file(
                    bookmark: try source.bookmarkData(options: .minimalBookmark),
                    relativePath: ""
                ),
                sizeInBytes: Int64(sourceBytes.count)
            ),
            to: folder.id
        )

        let snapshot = LibraryEvidenceSnapshot(
            library: library,
            folders: [folder],
            inboxURL: inbox,
            fileManager: .default
        )

        XCTAssertEqual(
            snapshot.folders,
            [
                .init(
                    id: folder.id.uuidString.lowercased(),
                    parentID: nil,
                    name: "Destination"
                )
            ]
        )
        let reference = try XCTUnwrap(snapshot.references.first)
        XCTAssertEqual(reference.id, referenceID.uuidString.lowercased())
        XCTAssertEqual(reference.folderID, folder.id.uuidString.lowercased())
        XCTAssertEqual(reference.locatorKind, "file")
        XCTAssertEqual(reference.sourcePath, source.path)
        XCTAssertEqual(reference.sourceExists, true)
        XCTAssertEqual(reference.sourceDigest, digest(sourceBytes))
        XCTAssertEqual(snapshot.stagedFiles, [
            .init(
                name: "fixture.mp4",
                sizeInBytes: Int64(stagedBytes.count),
                digest: digest(stagedBytes)
            )
        ])
    }

    @MainActor
    func testSourceItemIdentityIsStableWithoutInventingLocalIntegrity() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        var library = FileBrowsingDomain.MediaLibrary()
        let dataSourceID = UUID()
        let referenceID = UUID()
        try library.add(.init(
            id: referenceID,
            name: "remote.mkv",
            locator: .sourceItem(
                dataSourceID: dataSourceID,
                path: "/library/remote.mkv"
            )
        ))

        let snapshot = LibraryEvidenceSnapshot(
            library: library,
            folders: [],
            inboxURL: root,
            fileManager: .default
        )
        let reference = try XCTUnwrap(snapshot.references.first)
        XCTAssertEqual(reference.id, referenceID.uuidString.lowercased())
        XCTAssertEqual(reference.locatorKind, "sourceItem")
        XCTAssertEqual(reference.sourcePath, "/library/remote.mkv")
        XCTAssertNil(reference.sourceExists)
        XCTAssertNil(reference.sourceDigest)
        XCTAssertTrue(reference.sourceIdentity.hasPrefix("sha256:"))
        XCTAssertEqual(reference.sourceIdentity.count, 71)
    }

    @MainActor
    func testDirectoryMediaImportMaterializesRegisteredMembersAndProvesLocatorTopology() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let inbox = root.appending(path: "TestMediaInbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let mediaName = "Aggregate.mkv"
        let subtitleNames = ["Aggregate.zh-CN.srt", "Aggregate.styled.ass"]
        let members = [mediaName] + subtitleNames
        for (index, name) in members.enumerated() {
            try Data(repeating: UInt8(index + 1), count: index + 1).write(
                to: inbox.appending(path: name)
            )
        }

        let source = try TestMediaDirectorySource(
            directoryName: "Aggregate Source",
            mediaFileName: mediaName,
            memberFileNames: members
        )
        let directory = try source.materialize(in: inbox, fileManager: .default)

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(),
            members.sorted()
        )
        XCTAssertTrue(members.allSatisfy {
            FileManager.default.fileExists(atPath: inbox.appending(path: $0).path)
        })

        let referenceID = UUID()
        let reference = FileBrowsingDomain.MediaReference(
            id: referenceID,
            name: mediaName,
            locator: .file(
                bookmark: try directory.bookmarkData(options: .minimalBookmark),
                relativePath: mediaName
            )
        )
        let receipt = try DirectoryMediaImportReceipt(
            source: source,
            reference: reference,
            fileManager: .default
        )

        XCTAssertEqual(receipt.schema, DirectoryMediaImportReceipt.schemaValue)
        XCTAssertEqual(receipt.referenceID, referenceID.uuidString.lowercased())
        XCTAssertEqual(receipt.bookmarkRootPath, directory.standardizedFileURL.path)
        XCTAssertTrue(receipt.bookmarkRootIsDirectory)
        XCTAssertEqual(receipt.mediaRelativePath, mediaName)
        XCTAssertEqual(
            receipt.mediaSourcePath,
            directory.appending(path: mediaName).standardizedFileURL.path
        )
        XCTAssertEqual(receipt.memberFileNames, members.sorted())
    }

    nonisolated private func digest(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
