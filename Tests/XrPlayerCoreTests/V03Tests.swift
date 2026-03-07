import XCTest
@testable import XrPlayerCore

// MARK: - DataSource Codable Tests

final class DataSourceCodableTests: XCTestCase {
    func testConnectionInfoCodableRoundtrip() throws {
        let info = FileBrowsingDomain.ConnectionInfo(
            sourceType: .webDAV,
            address: "http://nas.local:8080/videos",
            scheme: "http",
            host: "nas.local",
            port: 8080,
            username: "alice",
            rootPath: "/videos"
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(FileBrowsingDomain.ConnectionInfo.self, from: data)
        XCTAssertEqual(decoded, info)
    }

    func testConnectionInfoCodableWithNilFields() throws {
        let info = FileBrowsingDomain.ConnectionInfo(
            sourceType: .local,
            rootPath: "/docs"
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(FileBrowsingDomain.ConnectionInfo.self, from: data)
        XCTAssertEqual(decoded, info)
        XCTAssertNil(decoded.host)
        XCTAssertNil(decoded.port)
        XCTAssertNil(decoded.username)
    }

    func testRemoteWebDAVAddressParsingWithoutSchemeDefaultsToHTTP() throws {
        let info = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .webDAV,
            address: "192.168.1.8:5244/dav",
            username: "alice"
        )

        XCTAssertEqual(info.scheme, "http")
        XCTAssertEqual(info.host, "192.168.1.8")
        XCTAssertEqual(info.port, 5244)
        XCTAssertEqual(info.rootPath, "/dav")
        XCTAssertEqual(info.username, "alice")
    }

    func testRemoteSMBAddressParsingRequiresShareName() {
        XCTAssertThrowsError(
            try FileBrowsingDomain.ConnectionInfo.remote(
                sourceType: .smb,
                address: "smb://192.168.1.9"
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "SMB address must include a share name, for example smb://192.168.1.20/share."
            )
        }
    }

    func testDataSourceCodableRoundtrip() throws {
        let id = UUID()
        let ds = FileBrowsingDomain.DataSource(
            id: id,
            name: "My NAS",
            sourceType: .webDAV,
            connectionInfo: .init(
                sourceType: .webDAV,
                host: "192.168.1.10",
                port: 443,
                username: "bob",
                rootPath: "/media"
            )
        )
        let data = try JSONEncoder().encode(ds)
        let decoded = try JSONDecoder().decode(FileBrowsingDomain.DataSource.self, from: data)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "My NAS")
        XCTAssertEqual(decoded.sourceType, .webDAV)
        XCTAssertEqual(decoded.connectionInfo.host, "192.168.1.10")
        XCTAssertEqual(decoded.connectionInfo.port, 443)
    }

    func testDataSourceArrayCodableRoundtrip() throws {
        let sources = [
            FileBrowsingDomain.DataSource(
                name: "WebDAV Server",
                sourceType: .webDAV,
                connectionInfo: .init(sourceType: .webDAV, host: "host1", port: 80, rootPath: "/")
            ),
            FileBrowsingDomain.DataSource(
                name: "SMB Share",
                sourceType: .smb,
                connectionInfo: .init(sourceType: .smb, host: "host2", port: 445, rootPath: "/share")
            )
        ]
        let data = try JSONEncoder().encode(sources)
        let decoded = try JSONDecoder().decode([FileBrowsingDomain.DataSource].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "WebDAV Server")
        XCTAssertEqual(decoded[1].sourceType, .smb)
    }

    func testSourceTypeCodableRoundtrip() throws {
        let types: [FileBrowsingDomain.SourceType] = [.local, .webDAV, .smb]
        for type_ in types {
            let data = try JSONEncoder().encode(type_)
            let decoded = try JSONDecoder().decode(FileBrowsingDomain.SourceType.self, from: data)
            XCTAssertEqual(decoded, type_)
        }
    }
}

// MARK: - SMBDataSourceAdapter Tests

final class SMBDataSourceAdapterTests: XCTestCase {
    func testConnectThrowsLibraryNotAvailable() async {
        let sut = SMBDataSourceAdapter()
        let info = FileBrowsingDomain.ConnectionInfo(sourceType: .smb, host: "server", port: 445, rootPath: "/share")
        do {
            try await sut.connect(with: info)
            XCTFail("Expected SMBError.libraryNotAvailable")
        } catch SMBError.libraryNotAvailable {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testListContentsThrowsLibraryNotAvailable() async {
        let sut = SMBDataSourceAdapter()
        do {
            _ = try await sut.listContents(at: "/")
            XCTFail("Expected SMBError.libraryNotAvailable")
        } catch SMBError.libraryNotAvailable {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testResolvePlayableURLThrowsLibraryNotAvailable() async {
        let sut = SMBDataSourceAdapter()
        let file = FileBrowsingDomain.MediaFile(
            name: "movie.mkv",
            sizeInBytes: 1024,
            modifiedAt: Date(),
            fileExtension: "mkv",
            url: URL(string: "smb://server/share/movie.mkv")!
        )
        do {
            _ = try await sut.resolvePlayableURL(for: file)
            XCTFail("Expected SMBError.libraryNotAvailable")
        } catch SMBError.libraryNotAvailable {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInitialStatusIsDisconnected() {
        let sut = SMBDataSourceAdapter()
        if case .disconnected = sut.connectionStatus { } else {
            XCTFail("Expected .disconnected, got \(sut.connectionStatus)")
        }
    }

    func testSMBErrorHasLocalizedDescription() {
        let error = SMBError.libraryNotAvailable
        XCTAssertFalse(error.localizedDescription.isEmpty)
        XCTAssertTrue(error.localizedDescription.contains("AMSMB2"))
    }

    func testListFoldersThrowsLibraryNotAvailable() async {
        let sut = SMBDataSourceAdapter()
        do {
            _ = try await sut.listFolders(at: "/")
            XCTFail("Expected SMBError.libraryNotAvailable")
        } catch SMBError.libraryNotAvailable {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAllSMBErrorsHaveDescriptions() {
        let errors: [SMBError] = [
            .libraryNotAvailable,
            .notConnected,
            .invalidConnectionInfo,
            .connectionFailed("test"),
            .authenticationFailed
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty, "SMBError.\(error) has empty description")
        }
    }
}

// MARK: - WebDAVDataSourceAdapter Tests

final class WebDAVDataSourceAdapterTests: XCTestCase {
    func testInitialStatusIsDisconnected() {
        let sut = WebDAVDataSourceAdapter()
        if case .disconnected = sut.connectionStatus { } else {
            XCTFail("Expected .disconnected, got \(sut.connectionStatus)")
        }
    }

    func testListContentsThrowsNotConnectedWhenDisconnected() async {
        let sut = WebDAVDataSourceAdapter()
        do {
            _ = try await sut.listContents(at: "/")
            XCTFail("Expected WebDAVError.notConnected")
        } catch WebDAVError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConnectWithNilHostThrowsInvalidConnectionInfo() async {
        let sut = WebDAVDataSourceAdapter()
        let info = FileBrowsingDomain.ConnectionInfo(sourceType: .webDAV, host: nil, rootPath: "/")
        do {
            try await sut.connect(with: info)
            XCTFail("Expected WebDAVError.invalidConnectionInfo")
        } catch WebDAVError.invalidConnectionInfo {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConnectWithEmptyHostThrowsInvalidConnectionInfo() async {
        let sut = WebDAVDataSourceAdapter()
        let info = FileBrowsingDomain.ConnectionInfo(sourceType: .webDAV, host: "  ", rootPath: "/")
        do {
            try await sut.connect(with: info)
            XCTFail("Expected WebDAVError.invalidConnectionInfo")
        } catch WebDAVError.invalidConnectionInfo {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConnectStatusBecomesFailedOnInvalidHost() async {
        let sut = WebDAVDataSourceAdapter()
        let info = FileBrowsingDomain.ConnectionInfo(sourceType: .webDAV, host: nil, rootPath: "/")
        try? await sut.connect(with: info)
        if case .failed = sut.connectionStatus { } else {
            XCTFail("Expected .failed, got \(sut.connectionStatus)")
        }
    }

    func testDisconnectResetsToDisconnected() async {
        let sut = WebDAVDataSourceAdapter()
        // Try connecting (will fail, but status changes)
        let info = FileBrowsingDomain.ConnectionInfo(sourceType: .webDAV, host: nil, rootPath: "/")
        try? await sut.connect(with: info)
        sut.disconnect()
        if case .disconnected = sut.connectionStatus { } else {
            XCTFail("Expected .disconnected after disconnect(), got \(sut.connectionStatus)")
        }
    }

    func testResolvePlayableURLReturnsFileURLWithoutAuth() async throws {
        // When not connected (no connectionInfo), resolvePlayableURL returns the original URL
        let sut = WebDAVDataSourceAdapter()
        let expectedURL = URL(string: "http://nas.local/videos/movie.mp4")!
        let file = FileBrowsingDomain.MediaFile(
            name: "movie.mp4",
            sizeInBytes: 500_000_000,
            modifiedAt: Date(),
            fileExtension: "mp4",
            url: expectedURL
        )
        let resolved = try await sut.resolvePlayableURL(for: file)
        XCTAssertEqual(resolved, expectedURL)
    }

    func testListFoldersThrowsNotConnectedWhenDisconnected() async {
        let sut = WebDAVDataSourceAdapter()
        do {
            _ = try await sut.listFolders(at: "/")
            XCTFail("Expected WebDAVError.notConnected")
        } catch WebDAVError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWebDAVErrorDescriptionsAreNonEmpty() {
        let errors: [WebDAVError] = [
            .invalidConnectionInfo,
            .notConnected,
            .invalidResponse,
            .requestFailed(404),
            .malformedResponse
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty, "Error \(error) has empty description")
        }
    }

    func testRequestFailedErrorContainsStatusCode() {
        let error = WebDAVError.requestFailed(401)
        XCTAssertTrue(error.localizedDescription.contains("401"))
    }
}

// MARK: - KeychainStore Tests

final class KeychainStoreTests: XCTestCase {
    private let testSourceID = "xrplayer.test.\(UUID().uuidString)"
    private var sut: KeychainStore!

    override func setUp() {
        super.setUp()
        sut = KeychainStore()
        // Clean up any leftover from prior run
        try? sut.deleteCredential(for: testSourceID)
    }

    override func tearDown() {
        try? sut.deleteCredential(for: testSourceID)
        sut = nil
        super.tearDown()
    }

    func testSaveAndLoadCredential() throws {
        let credential = StorageCredential(username: "alice", password: "s3cr3t")
        try sut.saveCredential(for: testSourceID, credential: credential)

        let loaded = try sut.loadCredential(for: testSourceID)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.username, "alice")
        XCTAssertEqual(loaded?.password, "s3cr3t")
    }

    func testLoadReturnsNilForMissingCredential() throws {
        let missing = try sut.loadCredential(for: "xrplayer.test.definitely-not-stored")
        XCTAssertNil(missing)
    }

    func testDeleteCredential() throws {
        let credential = StorageCredential(username: "bob", password: "pass123")
        try sut.saveCredential(for: testSourceID, credential: credential)
        try sut.deleteCredential(for: testSourceID)
        let result = try sut.loadCredential(for: testSourceID)
        XCTAssertNil(result)
    }

    func testDeleteNonExistentCredentialDoesNotThrow() throws {
        XCTAssertNoThrow(try sut.deleteCredential(for: "xrplayer.test.not-stored"))
    }

    func testOverwriteCredential() throws {
        let first = StorageCredential(username: "carol", password: "old")
        try sut.saveCredential(for: testSourceID, credential: first)

        let second = StorageCredential(username: "carol", password: "new")
        try sut.saveCredential(for: testSourceID, credential: second)

        let loaded = try sut.loadCredential(for: testSourceID)
        XCTAssertEqual(loaded?.password, "new")
    }

    func testSaveCredentialWithSpecialCharacters() throws {
        let credential = StorageCredential(username: "用户", password: "p@$$w0rd!🔑")
        try sut.saveCredential(for: testSourceID, credential: credential)
        let loaded = try sut.loadCredential(for: testSourceID)
        XCTAssertEqual(loaded?.username, "用户")
        XCTAssertEqual(loaded?.password, "p@$$w0rd!🔑")
    }

    func testMultipleSourceIDsStoredIndependently() throws {
        let id1 = testSourceID + ".1"
        let id2 = testSourceID + ".2"
        defer {
            try? sut.deleteCredential(for: id1)
            try? sut.deleteCredential(for: id2)
        }

        try sut.saveCredential(for: id1, credential: StorageCredential(username: "u1", password: "p1"))
        try sut.saveCredential(for: id2, credential: StorageCredential(username: "u2", password: "p2"))

        let l1 = try sut.loadCredential(for: id1)
        let l2 = try sut.loadCredential(for: id2)
        XCTAssertEqual(l1?.username, "u1")
        XCTAssertEqual(l2?.username, "u2")
        XCTAssertNotEqual(l1?.password, l2?.password)
    }
}

// MARK: - DataSource credentialSourceID Tests

final class CredentialSourceIDTests: XCTestCase {
    func testCredentialSourceIDFormatWebDAV() {
        let ds = FileBrowsingDomain.DataSource(
            name: "Test",
            sourceType: .webDAV,
            connectionInfo: .init(sourceType: .webDAV, host: "nas.local", port: 443, rootPath: "/videos")
        )
        XCTAssertEqual(ds.credentialSourceID, "webDAV:nas.local:443:/videos")
    }

    func testCredentialSourceIDFormatSMB() {
        let ds = FileBrowsingDomain.DataSource(
            name: "SMB",
            sourceType: .smb,
            connectionInfo: .init(sourceType: .smb, host: "server", port: 445, rootPath: "/share")
        )
        XCTAssertEqual(ds.credentialSourceID, "smb:server:445:/share")
    }

    func testCredentialSourceIDWithNilFields() {
        let ds = FileBrowsingDomain.DataSource(
            name: "Minimal",
            sourceType: .webDAV,
            connectionInfo: .init(sourceType: .webDAV, rootPath: "/")
        )
        XCTAssertEqual(ds.credentialSourceID, "webDAV::0:/")
    }

    func testDifferentDataSourcesProduceDifferentIDs() {
        let ds1 = FileBrowsingDomain.DataSource(
            name: "A",
            sourceType: .webDAV,
            connectionInfo: .init(sourceType: .webDAV, host: "host1", port: 80, rootPath: "/a")
        )
        let ds2 = FileBrowsingDomain.DataSource(
            name: "B",
            sourceType: .webDAV,
            connectionInfo: .init(sourceType: .webDAV, host: "host2", port: 80, rootPath: "/b")
        )
        XCTAssertNotEqual(ds1.credentialSourceID, ds2.credentialSourceID)
    }
}

// MARK: - MediaFolder Tests

final class MediaFolderTests: XCTestCase {
    func testMediaFolderInit() {
        let folder = FileBrowsingDomain.MediaFolder(
            name: "Videos",
            dataSourceID: UUID(),
            path: "/media/videos",
            url: URL(string: "http://nas.local/media/videos")!
        )
        XCTAssertEqual(folder.name, "Videos")
        XCTAssertEqual(folder.path, "/media/videos")
    }

    func testMediaFolderEquality() {
        let id = UUID()
        let dsID = UUID()
        let folder1 = FileBrowsingDomain.MediaFolder(
            id: id, name: "A", dataSourceID: dsID,
            path: "/a", url: URL(string: "http://x/a")!
        )
        let folder2 = FileBrowsingDomain.MediaFolder(
            id: id, name: "A", dataSourceID: dsID,
            path: "/a", url: URL(string: "http://x/a")!
        )
        XCTAssertEqual(folder1, folder2)
    }
}
