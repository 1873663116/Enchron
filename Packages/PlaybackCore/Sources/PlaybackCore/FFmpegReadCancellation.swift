import PlaybackFFmpegBridge

final class FFmpegReadCancellation: @unchecked Sendable {
    let handle: OpaquePointer?

    init() {
        handle = PBFFmpegReadCancellationCreate()
    }

    deinit {
        PBFFmpegReadCancellationDestroy(handle)
    }

    func cancel() {
        PBFFmpegReadCancellationCancel(handle)
    }
}
