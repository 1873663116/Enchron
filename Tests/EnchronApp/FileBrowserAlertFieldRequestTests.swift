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
}
#endif
