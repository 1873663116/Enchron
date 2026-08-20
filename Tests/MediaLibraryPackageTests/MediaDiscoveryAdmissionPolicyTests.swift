import MediaLibrary
import XCTest

nonisolated final class MediaDiscoveryAdmissionPolicyTests: XCTestCase {
    func testMediaFileAdmissionHasTheDeclaredDiscoveryScope() {
        let expected = Set([
            "mp4", "mkv", "avi", "mov", "m4v", "webm", "ts", "m2ts", "flv", "iso",
            "m4a", "mp3", "flac", "wav", "ogg", "opus", "aiff"
        ])

        XCTAssertEqual(
            FileBrowsingDomain.MediaDiscoveryAdmissionPolicy.mediaFiles.allowedExtensions,
            expected
        )
        XCTAssertEqual(expected.count, 17)
    }

    func testAdmissionExtensionsAreNormalizedToLowercase() {
        let policy = FileBrowsingDomain.MediaDiscoveryAdmissionPolicy(
            allowedExtensions: ["MP4", "MkV", "ISO"]
        )

        XCTAssertEqual(policy.allowedExtensions, ["mp4", "mkv", "iso"])
    }

    func testPlayableFilterIsDerivedFromTheDiscoveryPolicy() {
        XCTAssertEqual(
            FileBrowsingDomain.FileFilter.playable.allowedExtensions,
            FileBrowsingDomain.MediaDiscoveryAdmissionPolicy.mediaFiles.allowedExtensions
        )
    }
}
