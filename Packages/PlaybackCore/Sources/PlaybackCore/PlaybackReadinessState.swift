enum PlaybackReadinessState: String, Sendable {
    case loading
    case playable
    case stalled
    case failed
}
