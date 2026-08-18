import Foundation

public struct MediaByteStreamHandle: @unchecked Sendable {
    public enum Issuance: Sendable, Equatable {
        case localFile
        case loopbackRoute
    }

    public let url: URL
    public let accessLease: MediaAccessLease?
    public let issuance: Issuance

    public static func localFile(
        url: URL,
        accessLease: MediaAccessLease? = nil
    ) -> MediaByteStreamHandle {
        precondition(url.isFileURL, "Local media byte-stream handles require a file URL.")
        return MediaByteStreamHandle(
            url: url,
            accessLease: accessLease,
            issuance: .localFile
        )
    }
}
