import AVFoundation
import Foundation

public struct StreamRenderBinding: @unchecked Sendable {
    public let sessionID: SessionID
    public let version: Int
    public let videoRenderer: AVSampleBufferVideoRenderer

    public init(sessionID: SessionID, version: Int, videoRenderer: AVSampleBufferVideoRenderer) {
        self.sessionID = sessionID
        self.version = version
        self.videoRenderer = videoRenderer
    }
}
