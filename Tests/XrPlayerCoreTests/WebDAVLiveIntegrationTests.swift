import Foundation
import XCTest
@testable import XrPlayerCore

final class WebDAVLiveIntegrationTests: XCTestCase {
    func testAuthenticatedServerListsAndReadsMedia() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["ENCHRON_WEBDAV_TEST_URL"],
              let username = environment["ENCHRON_WEBDAV_TEST_USERNAME"],
              let password = environment["ENCHRON_WEBDAV_TEST_PASSWORD"] else {
            throw XCTSkip("Set the ENCHRON_WEBDAV_TEST_* environment variables to run the live WebDAV test.")
        }

        let info = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .webDAV,
            address: address,
            username: username
        )
        let credentials = TestCredentialStore()
        try credentials.saveCredential(
            for: info.credentialSourceID,
            credential: StorageCredential(username: username, password: password)
        )
        let adapter = WebDAVDataSourceAdapter(credentialStore: credentials)

        try await adapter.connect(with: info)
        let files = try await adapter.listContents(at: "/")
        let media = try XCTUnwrap(files.first)
        let playableURL = try await adapter.resolvePlayableURL(for: media)

        guard case .connected = adapter.connectionStatus else {
            return XCTFail("WebDAV adapter did not remain connected after listing.")
        }
        XCTAssertFalse(media.name.isEmpty)
        XCTAssertEqual(playableURL.user, username)

        var request = URLRequest(url: playableURL)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)

        XCTAssertEqual(httpResponse.statusCode, 206)
        XCTAssertEqual(data.count, 1024)
    }
}

private final class TestCredentialStore: CredentialStoring, @unchecked Sendable {
    private var credentials: [String: StorageCredential] = [:]

    func saveCredential(for sourceID: String, credential: StorageCredential) throws {
        credentials[sourceID] = credential
    }

    func loadCredential(for sourceID: String) throws -> StorageCredential? {
        credentials[sourceID]
    }

    func deleteCredential(for sourceID: String) throws {
        credentials[sourceID] = nil
    }
}
