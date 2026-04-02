import Foundation

/// Observable state published by `PlaybackLaunchCoordinator` during
/// the prepare-then-confirm flow.
///
/// The detail page observes `currentPreparation` and reacts to transitions:
/// - `.preparing` — show loading indicator, partial metadata if available
/// - `.ready` — show track picker, confirm button
/// - `.failed` — show error, offer retry
public enum PreparationState: Sendable {
    case preparing(request: PlaybackLaunchRequest, metadata: PlaybackMediaMetadata?)
    case ready(PreparedPlayback)
    case failed(Error)
}

/// A snapshot of everything the detail page needs to render its UI
/// before the user confirms playback.
///
/// Created by `PlaybackLaunchCoordinator.preparePlayback` after mpv
/// has loaded the file with `pause=yes` and enumerated tracks.
public struct PreparedPlayback: Sendable {
    public let request: PlaybackLaunchRequest
    public let metadata: PlaybackMediaMetadata?
    public let audioTracks: [PlaybackCoreDomain.AudioTrack]
    public let subtitleTracks: [PlaybackCoreDomain.SubtitleTrack]
    /// Monotonic generation counter — `confirmPlayback` validates this
    /// matches the coordinator's current generation to reject stale confirmations.
    public let generation: Int

    public init(
        request: PlaybackLaunchRequest,
        metadata: PlaybackMediaMetadata?,
        audioTracks: [PlaybackCoreDomain.AudioTrack],
        subtitleTracks: [PlaybackCoreDomain.SubtitleTrack],
        generation: Int
    ) {
        self.request = request
        self.metadata = metadata
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.generation = generation
    }
}

// MARK: - Equatable (needed for SwiftUI observation diffing)

extension PreparationState: Equatable {
    public static func == (lhs: PreparationState, rhs: PreparationState) -> Bool {
        switch (lhs, rhs) {
        case let (.preparing(lReq, lMeta), .preparing(rReq, rMeta)):
            return lReq == rReq && lMeta == rMeta
        case let (.ready(lPrep), .ready(rPrep)):
            return lPrep == rPrep
        case (.failed, .failed):
            // Error is not Equatable; treat any two failures as equal for diffing.
            // The detail view should read the associated error, not rely on equality.
            return true
        default:
            return false
        }
    }
}

extension PreparedPlayback: Equatable {
    public static func == (lhs: PreparedPlayback, rhs: PreparedPlayback) -> Bool {
        lhs.request == rhs.request
            && lhs.metadata == rhs.metadata
            && lhs.audioTracks == rhs.audioTracks
            && lhs.subtitleTracks == rhs.subtitleTracks
            && lhs.generation == rhs.generation
    }
}
