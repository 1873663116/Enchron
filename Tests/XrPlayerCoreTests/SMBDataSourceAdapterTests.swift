import Foundation
import Testing
@testable import XrPlayerCore

struct SMBDataSourceAdapterTests {
    @Test("SMB playback cache identity is stable and changes with remote content")
    func playbackCacheIdentity() {
        let file = FileBrowsingDomain.MediaFile(
            name: "feature.mkv",
            sizeInBytes: 42_000,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: "mkv",
            url: URL(string: "smb://placeholder/Movies/feature.mkv")!
        )
        let connection = FileBrowsingDomain.ConnectionInfo(
            sourceType: .smb,
            scheme: "smb",
            host: "192.168.1.20",
            port: 445,
            rootPath: "/Movies"
        )

        let first = SMBDataSourceAdapter.playbackCacheFileName(for: file, connectionInfo: connection)
        let same = SMBDataSourceAdapter.playbackCacheFileName(for: file, connectionInfo: connection)
        let changed = SMBDataSourceAdapter.playbackCacheFileName(
            for: FileBrowsingDomain.MediaFile(
                name: file.name,
                sizeInBytes: file.sizeInBytes + 1,
                modifiedAt: file.modifiedAt,
                fileExtension: file.fileExtension,
                url: file.url
            ),
            connectionInfo: connection
        )

        #expect(first == same)
        #expect(first != changed)
        #expect(first.hasSuffix(".mkv"))
    }
}
