import MediaLibrary
import XCTest

nonisolated final class SourceConnectionDraftTests: XCTestCase {
    func testDismissalPreservesNonSecretInput() {
        var draft = SourceConnectionDraft(
            name: "Living Room",
            address: "media.local:5006",
            username: "viewer",
            password: "secret",
            connectsAsGuest: true
        )

        draft.clearAfterDismissal()

        XCTAssertEqual(draft.name, "Living Room")
        XCTAssertEqual(draft.address, "media.local:5006")
        XCTAssertEqual(draft.username, "viewer")
        XCTAssertTrue(draft.password.isEmpty)
        XCTAssertTrue(draft.connectsAsGuest)
    }

    func testSuccessfulConnectionClearsCompletedDraft() {
        var draft = SourceConnectionDraft(
            name: "Living Room",
            address: "media.local:5006",
            username: "viewer",
            password: "secret",
            connectsAsGuest: true
        )

        draft.clearAfterSuccessfulConnection()

        XCTAssertEqual(draft, SourceConnectionDraft())
    }
}
