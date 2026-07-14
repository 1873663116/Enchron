public enum PlaybackStatus: Equatable, Sendable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case ended
    case failed(String)

    public var label: String {
        switch self {
        case .idle: "No video"
        case .loading: "Loading"
        case .ready: "Ready"
        case .playing: "Playing"
        case .paused: "Paused"
        case .ended: "Ended"
        case .failed(let message): "Failed: \(message)"
        }
    }
}
