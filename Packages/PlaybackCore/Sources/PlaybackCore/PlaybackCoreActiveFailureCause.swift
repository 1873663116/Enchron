public enum PlaybackCoreActiveFailureCause: String, CaseIterable, Sendable, Equatable {
    case connectionInterrupted
    case sourceFileMissing
    case sourceAccessDenied
    case mediaDataCorrupt
    case rendererRequiresFlush
    case mediaServicesReset
    case rendererFailed
}

public enum PlaybackCoreActiveFailureContext: Sendable, Equatable {
    case sourceRead(PlaybackCoreActiveFailureCause?)
    case decoder(PlaybackCoreActiveFailureCause)
}
