import Foundation
import MediaLibrary
import SwiftUI
import XCTest
@testable import Enchron

#if DEBUG
nonisolated final class FileBrowserAlertFieldRequestTests: XCTestCase {
    @MainActor
    func testRequestWritesThroughThePresentedAlertBindingOnce() {
        var value = "Original"
        var writes = 0
        let binding = Binding(
            get: { value },
            set: {
                value = $0
                writes += 1
            }
        )
        let request = FileBrowserAlertFieldRequest(
            field: .newFolderName,
            value: "Round 13"
        )

        request.handle(
            field: .newFolderName,
            isPresented: true,
            binding: binding
        )
        request.handle(
            field: .newFolderName,
            isPresented: true,
            binding: binding
        )

        XCTAssertEqual(value, "Round 13")
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(request.wasHandled)
    }

    @MainActor
    func testRequestRejectsTheWrongOrHiddenAlert() {
        var value = "Original"
        let binding = Binding(
            get: { value },
            set: { value = $0 }
        )
        let request = FileBrowserAlertFieldRequest(
            field: .renameFolderName,
            value: "Round 13"
        )

        request.handle(
            field: .newFolderName,
            isPresented: true,
            binding: binding
        )
        request.handle(
            field: .renameFolderName,
            isPresented: false,
            binding: binding
        )

        XCTAssertEqual(value, "Original")
        XCTAssertFalse(request.wasHandled)
    }

    @MainActor
    func testRequestOnlyMarksTheTypedFeatureDeliveryHandledWhenAccepted() {
        let request = FileBrowserAlertFieldRequest(
            field: .renameFolderName,
            value: "Round 13"
        )
        var attempts = 0

        request.handle { _, _ in
            attempts += 1
            return false
        }
        request.handle { field, value in
            attempts += 1
            return field == .renameFolderName && value == "Round 13"
        }
        request.handle { _, _ in
            attempts += 1
            return true
        }

        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(request.wasHandled)
    }

    @MainActor
    func testFileImporterCoordinatorDeliversTheTypedRequestExactlyOnce() {
        let coordinator = FilesScreenFileImportCoordinator()
        let selectedURL = URL(fileURLWithPath: "/tmp/selected.mkv")
        var deliveries: [[URL]] = []

        coordinator.present(kind: .folder) { result in
            if case .success(let urls) = result {
                deliveries.append(urls)
            }
        }

        XCTAssertEqual(coordinator.kind, .folder)
        XCTAssertTrue(coordinator.isPresented)

        coordinator.deliver(.success([selectedURL]))
        coordinator.deliver(.success([]))

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertEqual(deliveries, [[selectedURL]])
    }

    @MainActor
    func testFileImporterCoordinatorRecordsOnlyItsActualSystemCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "enchron-files-provider-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let selectedURL = root.appending(path: "Provider Clip.mov")
        let bytes = Data([0xAA, 0xBB, 0xCC])
        try bytes.write(to: selectedURL)
        let coordinator = FilesScreenFileImportCoordinator()

        coordinator.present(kind: .mediaFiles) { _ in }
        coordinator.deliver(.success([selectedURL]))
        let referenceID = UUID()
        SystemImportDeliveryDiagnostics.recordPersistentLibraryDelivery(
            deliveredURLs: [selectedURL],
            newReferences: [
                .init(
                    id: referenceID,
                    name: selectedURL.lastPathComponent,
                    locator: .file(bookmark: Data([0x01]), relativePath: ""),
                    sizeInBytes: Int64(bytes.count)
                )
            ],
            errorDescription: nil
        )

        let snapshot = try XCTUnwrap(SystemImportDeliveryDiagnostics.latestSnapshot)
        XCTAssertEqual(snapshot.deliveryDomain, .filesProviderSecurityScope)
        XCTAssertEqual(snapshot.items.first?.returnedIdentityKind, .filesProviderURL)
        XCTAssertEqual(snapshot.items.first?.returnedIdentity, selectedURL.standardizedFileURL.path)
        XCTAssertEqual(snapshot.items.first?.deliveredName, "Provider Clip.mov")
        XCTAssertEqual(snapshot.items.first?.byteCount, Int64(bytes.count))
        XCTAssertEqual(
            snapshot.items.first?.sha256,
            "sha256:fa22dfe1da9013b3c1145040acae9089e0c08bc1c1a0719614f4b73add6f6ef5"
        )
        XCTAssertEqual(snapshot.persistentLibraryDelivery.outcome, .persisted)
        XCTAssertEqual(snapshot.persistentLibraryDelivery.references.map(\.id), [
            referenceID.uuidString.lowercased()
        ])

        let encoded = try JSONEncoder().encode(snapshot)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(
            object["schema"] as? String,
            "enchron.regression.system-import-delivery@1"
        )
        XCTAssertNotNil(object["persistentLibraryDelivery"])
    }

    @MainActor
    func testFolderImportsNeverRecordASystemImportSnapshot() throws {
        let folderURL = URL(fileURLWithPath: "/tmp/enchron-folder-import")
        let coordinator = FilesScreenFileImportCoordinator()
        coordinator.present(kind: .folder) { _ in }
        coordinator.deliver(.success([folderURL]))
        let snapshotBefore = SystemImportDeliveryDiagnostics.latestSnapshot

        SystemImportDeliveryDiagnostics.recordPersistentLibraryDelivery(
            deliveredURLs: [folderURL],
            newReferences: [
                .init(
                    id: UUID(),
                    name: folderURL.lastPathComponent,
                    locator: .file(bookmark: Data([0x01]), relativePath: ""),
                    sizeInBytes: 1
                )
            ],
            errorDescription: nil
        )

        XCTAssertEqual(
            SystemImportDeliveryDiagnostics.latestSnapshot,
            snapshotBefore
        )
    }
}
#endif
