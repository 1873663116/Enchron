import Foundation
import MediaSource
@testable @_spi(Testing) import Playback
import Testing

@MainActor
struct KnownDurationTests {
    @Test("a known duration survives without a viewing status and is read back by identity")
    func knownDurationPersistsIndependentlyOfViewingStatus() async throws {
        let suite = "enchron.tests.known-duration.\(UUID().uuidString)"
        let store = MediaStateStore(suiteName: suite)
        let identity = VersionedMediaIdentity(
            mediaIdentity: .remote(sourceKey: "smb:test", canonicalPath: "/clips/short.mkv"),
            contentRevision: .remote(entityTag: "etag-1", sizeInBytes: 1_024)
        )
        await store.recordKnownDuration(30, for: identity)
        await store.applyViewingMutation(.remove, for: identity)
        #expect(await store.viewingProjection(for: identity.mediaIdentity) == nil)
        #expect(await store.knownDurationProjection(for: identity.mediaIdentity) == 30)
        await store.recordKnownDuration(0, for: identity)
        #expect(await store.knownDurationProjection(for: identity.mediaIdentity) == 30)
        await store.recordKnownDuration(31, for: identity)
        #expect(await store.knownDurationProjection(for: identity.mediaIdentity) == 31)
    }
}
