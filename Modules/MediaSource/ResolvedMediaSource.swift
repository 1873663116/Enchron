import Foundation

public struct ResolvedMediaSource: @unchecked Sendable {
    public let url: URL
    public let accessLease: MediaAccessLease?

    public init(url: URL, accessLease: MediaAccessLease? = nil) {
        self.url = url
        self.accessLease = accessLease
    }
}
