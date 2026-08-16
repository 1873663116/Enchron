import Foundation

public struct ResolvedMediaSource: @unchecked Sendable {
    public let url: URL
    public let accessLease: MediaAccessLease?
    public let byteStreamHandle: MediaByteStreamHandle?

    public init(
        url: URL,
        accessLease: MediaAccessLease? = nil,
        byteStreamHandle: MediaByteStreamHandle? = nil
    ) {
        self.url = url
        self.accessLease = accessLease
        self.byteStreamHandle = byteStreamHandle
    }

    public init(byteStreamHandle: MediaByteStreamHandle) {
        url = byteStreamHandle.url
        accessLease = nil
        self.byteStreamHandle = byteStreamHandle
    }
}
