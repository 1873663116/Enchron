import Foundation
import PlaybackFFmpegBridge

public struct PlaybackSourceReadObservation: Codable, Equatable, Sendable {
    public let totalBytesRead: UInt64
    public let bytesPerSecond: UInt64
    public let pendingReadSeconds: Double

    public init(
        totalBytesRead: UInt64,
        bytesPerSecond: UInt64,
        pendingReadSeconds: Double = 0
    ) {
        self.totalBytesRead = totalBytesRead
        self.bytesPerSecond = bytesPerSecond
        self.pendingReadSeconds = pendingReadSeconds
    }
}

struct PlaybackSourceReadRateSampler: Sendable {
    static let refreshInterval: TimeInterval = 1

    private var sampleStartedAt: TimeInterval
    private var sampledBytesRead: UInt64 = 0
    private var publishedBytesPerSecond: UInt64 = 0

    init(startedAt: TimeInterval) {
        sampleStartedAt = startedAt
    }

    mutating func observe(
        totalBytesRead: UInt64,
        at uptime: TimeInterval
    ) -> UInt64 {
        let elapsed = uptime - sampleStartedAt
        guard elapsed >= Self.refreshInterval else {
            if elapsed < 0 {
                sampleStartedAt = uptime
                sampledBytesRead = totalBytesRead
                publishedBytesPerSecond = 0
            }
            return publishedBytesPerSecond
        }

        let byteDelta = totalBytesRead >= sampledBytesRead
            ? totalBytesRead - sampledBytesRead
            : 0
        sampleStartedAt = uptime
        sampledBytesRead = totalBytesRead
        publishedBytesPerSecond = UInt64(Double(byteDelta) / elapsed)
        return publishedBytesPerSecond
    }
}

final class PlaybackSourceReadMeter: @unchecked Sendable {
    private let monitor: OpaquePointer?

    init() {
        monitor = PBFFmpegSourceReadMonitorCreate()
    }

    deinit {
        if let monitor {
            PBFFmpegSourceReadMonitorDestroy(monitor)
        }
    }

    var bridgeMonitor: OpaquePointer? { monitor }

    func interruptReads() {
        PBFFmpegSourceReadMonitorInterrupt(monitor)
    }

    var totalBytesRead: UInt64 {
        PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor)
    }

    var pendingReadCount: Int {
        Int(PBFFmpegSourceReadMonitorGetPendingReadCount(monitor))
    }

    var pendingReadUptimeMilliseconds: UInt64 {
        PBFFmpegSourceReadMonitorGetPendingReadUptimeMilliseconds(monitor)
    }

    var hasPendingSourceRead: Bool {
        pendingReadCount > 0
    }
}
