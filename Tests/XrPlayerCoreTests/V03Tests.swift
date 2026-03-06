import XCTest
@testable import XrPlayerCore

// MARK: - DataSource Codable Tests

final class DataSourceCodableTests: XCTestCase {
    func testConnectionInfoCodableRoundtrip() throws {
        let info = FileBrowsingDomain.ConnectionInfo(
            sourceType: .webDAV,
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

// MARK: - Credential Key Tests

final class CredentialStorageKeyTests: XCTestCase {
    func testWebDAVCredentialStorageKeyUsesNormalizedHostAndDefaultPort() {
        let info = FileBrowsingDomain.ConnectionInfo(
            sourceType: .webDAV,
            host: " NAS.LOCAL ",
            port: nil,
            username: "alice",
            rootPath: "videos"
        )
        XCTAssertEqual(info.credentialStorageKey, "webDAV:nas.local:443:/videos")
    }

    func testSMBCredentialStorageKeyUsesExplicitPortAndRootPath() {
        let info = FileBrowsingDomain.ConnectionInfo(
            sourceType: .smb,
            host: "192.168.1.9",
            port: 1445,
            username: "bob",
            rootPath: "/share"
        )
        XCTAssertEqual(info.credentialStorageKey, "smb:192.168.1.9:1445:/share")
    }

    func testLocalSourceDoesNotHaveCredentialStorageKey() {
        let info = FileBrowsingDomain.ConnectionInfo(
            sourceType: .local,
            host: "localhost",
            rootPath: "/tmp"
        )
        XCTAssertNil(info.credentialStorageKey)
    }

    func testDataSourceCredentialStorageKeyPassThrough() {
        let ds = FileBrowsingDomain.DataSource(
            name: "NAS",
            sourceType: .webDAV,
            connectionInfo: .init(sourceType: .webDAV, host: "nas", port: nil, username: "u", rootPath: "/")
        )
        XCTAssertEqual(ds.credentialStorageKey, "webDAV:nas:443:/")
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

    func testResolvePlayableURLReturnsFileURL() async throws {
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

// MARK: - FileIdentifier Normalization Tests

final class FileIdentifierNormalizationTests: XCTestCase {
    func testRemoteIdentifierIgnoresHostForSamePathAndSize() {
        let first = PersistenceDomain.FileIdentifier.make(
            url: URL(string: "https://nas.local/media/movie.mp4")!,
            sizeInBytes: 1_024
        )
        let second = PersistenceDomain.FileIdentifier.make(
            url: URL(string: "https://192.168.1.8/media/movie.mp4")!,
            sizeInBytes: 1_024
        )
        XCTAssertEqual(first, second)
    }

    func testCustomServerFingerprintOverridesDefaultFingerprint() {
        let first = PersistenceDomain.FileIdentifier.make(
            url: URL(string: "smb://nas.local/share/movie.mkv")!,
            sizeInBytes: 42,
            serverFingerprint: "server-a"
        )
        let second = PersistenceDomain.FileIdentifier.make(
            url: URL(string: "webdav://alias/share/movie.mkv")!,
            sizeInBytes: 42,
            serverFingerprint: "SERVER-A"
        )
        XCTAssertEqual(first, second)
    }

    func testLocalIdentifierUsesStandardizedPath() {
        let url = URL(fileURLWithPath: "/tmp/a/../movie.mp4")
        let id = PersistenceDomain.FileIdentifier.make(url: url, sizeInBytes: 10)
        XCTAssertTrue(id.rawValue.hasPrefix("/tmp/movie.mp4|10|local"))
    }
}

// MARK: - SwiftDataStore Tests

final class SwiftDataStoreTests: XCTestCase {
    func testProgressRoundtripPersistsAcrossStoreRecreation() async {
        let (storeURL, cleanup) = makeTempStoreURL()
        defer { cleanup() }

        let fileID = PersistenceDomain.FileIdentifier(rawValue: "file-1")
        let progress = PersistenceDomain.PlaybackProgress(
            fileID: fileID,
            position: .init(seconds: 123.4),
            updatedAt: Date()
        )

        let firstStore = SwiftDataStore(storageURL: storeURL)
        await firstStore.saveProgress(progress)

        let secondStore = SwiftDataStore(storageURL: storeURL)
        let loaded = await secondStore.loadProgress(for: fileID)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.position.seconds, 123.4)
    }

    func testCleanExpiredProgressRemovesOnlyExpiredEntries() async {
        let (storeURL, cleanup) = makeTempStoreURL()
        defer { cleanup() }

        let store = SwiftDataStore(storageURL: storeURL)
        let oldID = PersistenceDomain.FileIdentifier(rawValue: "old")
        let freshID = PersistenceDomain.FileIdentifier(rawValue: "fresh")
        let oldProgress = PersistenceDomain.PlaybackProgress(
            fileID: oldID,
            position: .init(seconds: 1),
            updatedAt: Date().addingTimeInterval(-8 * 86_400)
        )
        let freshProgress = PersistenceDomain.PlaybackProgress(
            fileID: freshID,
            position: .init(seconds: 2),
            updatedAt: Date()
        )

        await store.saveProgress(oldProgress)
        await store.saveProgress(freshProgress)
        await store.cleanExpiredProgress(olderThan: 5)

        let oldLoaded = await store.loadProgress(for: oldID)
        let freshLoaded = await store.loadProgress(for: freshID)
        XCTAssertNil(oldLoaded)
        XCTAssertNotNil(freshLoaded)
    }

    func testScreenPositionRoundtrip() async {
        let (storeURL, cleanup) = makeTempStoreURL()
        defer { cleanup() }

        let store = SwiftDataStore(storageURL: storeURL)
        await store.savePosition(
            for: "living-room",
            distanceMeters: 2.0,
            verticalOffsetMeters: 0.3,
            angleDegrees: 12
        )

        let loaded = await store.loadPosition(for: "living-room")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.distanceMeters, 2.0)
        XCTAssertEqual(loaded?.verticalOffsetMeters, 0.3)
        XCTAssertEqual(loaded?.viewAngleDegrees, 12)
    }

    private func makeTempStoreURL() -> (URL, () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("xrplayer-tests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("store.json", isDirectory: false)
        let cleanup: () -> Void = {
            _ = try? FileManager.default.removeItem(at: directory)
        }
        return (url, cleanup)
    }
}
