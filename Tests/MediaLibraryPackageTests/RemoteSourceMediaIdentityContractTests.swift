import Foundation
import MediaSource
import Testing
@testable import MediaLibrary

struct RemoteSourceMediaIdentityContractTests {
    @Test("equivalent remote source entries must share media identity")
    func equivalentRemoteSourceEntriesShareMediaIdentity() throws {
        let firstRemoteSource = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .smb,
            address: "192.0.2.10"
        )
        let recreatedRemoteSource = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .smb,
            address: "192.0.2.10"
        )

        #expect(
            MediaIdentity.remote(
                sourceKey: firstRemoteSource.mediaIdentitySourceKey,
                canonicalPath: "/Share/Episode 01.mkv"
            ) == MediaIdentity.remote(
                sourceKey: recreatedRemoteSource.mediaIdentitySourceKey,
                canonicalPath: "/Share/Episode 01.mkv"
            ),
            "equivalent remote source entries must share media identity"
        )
    }

    @Test("different remote account namespaces must not share media identity")
    func differentRemoteAccountNamespacesDoNotShareMediaIdentity() throws {
        let tenantOne = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .webDAV,
            address: "https://media.example.test/library",
            username: "tenant-one"
        )
        let tenantTwo = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .webDAV,
            address: "https://media.example.test/library",
            username: "tenant-two"
        )

        #expect(
            MediaIdentity.remote(
                sourceKey: tenantOne.mediaIdentitySourceKey,
                canonicalPath: "/video.mkv"
            ) != MediaIdentity.remote(
                sourceKey: tenantTwo.mediaIdentitySourceKey,
                canonicalPath: "/video.mkv"
            ),
            "different remote account namespaces must not share media identity"
        )
    }
}
