import Foundation

public enum PlaybackUserVisibleIssueCategory: String, CaseIterable, Sendable, Equatable {
    case mediaOpeningFailed
    case mediaRequestFailed
    case unsupportedVideoCodec
    case sourceAccessUnavailable
    case playbackFailed
    case playbackControlFailed
    case mediaFormatChangeFailed
    case audioTrackSelectionFailed
    case subtitleTrackSelectionFailed
    case externalSubtitleFailed
    case presentationTransitionFailed
    case presentationConversionFailed
    case surfaceAttachmentFailed
    case environmentLoadingFailed
    case capabilityUnavailable
}

public enum PlaybackUserVisibleIssueMessageStrategy: Sendable, Equatable {
    case fixedProductCopy
    case unsupportedVideoCodecFact
    case blockingCapabilityFact
}

public enum PlaybackUserVisibleIssueAction: String, CaseIterable, Sendable, Equatable, Hashable {
    case retry
    case close
    case confirm

    public var title: String {
        switch self {
        case .retry: "Retry"
        case .close: "Close"
        case .confirm: "OK"
        }
    }
}

public enum PlaybackIssuePresentationLocation:
    String, CaseIterable, Sendable, Equatable, Hashable {
    case mainWindow
    case playerDeck
    case immersiveSpace
    case mediaLibrary
}

public struct PlaybackUserVisibleIssuePolicy: Sendable, Equatable {
    public let title: String
    public let messageStrategy: PlaybackUserVisibleIssueMessageStrategy
    public let allowedActions: [PlaybackUserVisibleIssueAction]
    public let presentationLocations: [PlaybackIssuePresentationLocation]
    public let interruptsPlayback: Bool

    public init(
        title: String,
        messageStrategy: PlaybackUserVisibleIssueMessageStrategy,
        allowedActions: [PlaybackUserVisibleIssueAction],
        presentationLocations: [PlaybackIssuePresentationLocation],
        interruptsPlayback: Bool
    ) {
        self.title = title
        self.messageStrategy = messageStrategy
        self.allowedActions = allowedActions
        self.presentationLocations = presentationLocations
        self.interruptsPlayback = interruptsPlayback
    }
}

public enum PlaybackUnsupportedVideoCodec: String, Sendable, Equatable {
    case vc1
    case mpeg2Video
    case other

    public init(codecName: String) {
        switch codecName.lowercased().filter(\.isLetter) {
        case "vc": self = .vc1
        case "mpegvideo": self = .mpeg2Video
        default: self = .other
        }
    }

    fileprivate var productName: String? {
        switch self {
        case .vc1: "VC-1 video"
        case .mpeg2Video: "MPEG-2 video"
        case .other: nil
        }
    }
}

public enum PlaybackBlockingCapability: String, CaseIterable, Sendable, Equatable {
    case videoDecoderUnavailable
}

/// A product decision about a playback problem, not the technical error that caused it.
///
/// Associated values are bounded product facts. An `Error` or arbitrary diagnostic string
/// cannot enter this type, so presentation code never needs to decide whether text is safe.
public enum PlaybackUserVisibleIssue: Sendable, Equatable {
    case mediaOpeningFailed
    case mediaRequestFailed
    case unsupportedVideoCodec(PlaybackUnsupportedVideoCodec)
    case sourceAccessUnavailable
    case playbackFailed
    case playbackControlFailed
    case mediaFormatChangeFailed
    case audioTrackSelectionFailed
    case subtitleTrackSelectionFailed
    case externalSubtitleFailed
    case presentationTransitionFailed
    case presentationConversionFailed
    case surfaceAttachmentFailed
    case environmentLoadingFailed
    case capabilityUnavailable(PlaybackBlockingCapability)

    public var category: PlaybackUserVisibleIssueCategory {
        switch self {
        case .mediaOpeningFailed: .mediaOpeningFailed
        case .mediaRequestFailed: .mediaRequestFailed
        case .unsupportedVideoCodec: .unsupportedVideoCodec
        case .sourceAccessUnavailable: .sourceAccessUnavailable
        case .playbackFailed: .playbackFailed
        case .playbackControlFailed: .playbackControlFailed
        case .mediaFormatChangeFailed: .mediaFormatChangeFailed
        case .audioTrackSelectionFailed: .audioTrackSelectionFailed
        case .subtitleTrackSelectionFailed: .subtitleTrackSelectionFailed
        case .externalSubtitleFailed: .externalSubtitleFailed
        case .presentationTransitionFailed: .presentationTransitionFailed
        case .presentationConversionFailed: .presentationConversionFailed
        case .surfaceAttachmentFailed: .surfaceAttachmentFailed
        case .environmentLoadingFailed: .environmentLoadingFailed
        case .capabilityUnavailable: .capabilityUnavailable
        }
    }

    public var title: String { category.policy.title }

    public var message: String {
        switch self {
        case .mediaOpeningFailed:
            "Unable to open this file."
        case .mediaRequestFailed:
            "This item could not be prepared for playback."
        case .unsupportedVideoCodec(let codec):
            if let productName = codec.productName {
                "This video uses \(productName), which Enchron does not support."
            } else {
                "This video uses a codec that Enchron does not support."
            }
        case .sourceAccessUnavailable:
            "The original media source is no longer available. Choose it again to restore access."
        case .playbackFailed:
            "Playback could not continue."
        case .playbackControlFailed:
            "The playback command could not be completed."
        case .mediaFormatChangeFailed:
            "The video format could not be changed."
        case .audioTrackSelectionFailed:
            "The audio track could not be changed."
        case .subtitleTrackSelectionFailed:
            "The subtitle track could not be changed."
        case .externalSubtitleFailed:
            "Some external subtitle files could not be loaded."
        case .presentationTransitionFailed:
            "The playback display could not be changed."
        case .presentationConversionFailed:
            "The playback display could not be changed. Enchron returned to the Media Library."
        case .surfaceAttachmentFailed:
            "The video surface could not be attached."
        case .environmentLoadingFailed:
            "The selected environment could not be loaded."
        case .capabilityUnavailable(.videoDecoderUnavailable):
            "This device has no ProRes decoder, so this file cannot play."
        }
    }

    public var messageStrategy: PlaybackUserVisibleIssueMessageStrategy {
        category.policy.messageStrategy
    }

    public var allowedActions: [PlaybackUserVisibleIssueAction] {
        category.policy.allowedActions
    }

    public var presentationLocations: [PlaybackIssuePresentationLocation] {
        category.policy.presentationLocations
    }

    public var interruptsPlayback: Bool { category.policy.interruptsPlayback }

    public func canPresent(at location: PlaybackIssuePresentationLocation) -> Bool {
        presentationLocations.contains(location)
    }
}

public extension PlaybackUserVisibleIssueCategory {
    var policy: PlaybackUserVisibleIssuePolicy {
        switch self {
        case .mediaOpeningFailed:
            .init(
                title: "Failed to Load",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.retry, .close],
                presentationLocations: [.mainWindow, .immersiveSpace],
                interruptsPlayback: true
            )
        case .mediaRequestFailed:
            .init(
                title: "Unable to Play",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.mediaLibrary],
                interruptsPlayback: true
            )
        case .unsupportedVideoCodec:
            .init(
                title: "Unable to Play",
                messageStrategy: .unsupportedVideoCodecFact,
                allowedActions: [.confirm],
                presentationLocations: [.mediaLibrary],
                interruptsPlayback: true
            )
        case .sourceAccessUnavailable:
            .init(
                title: "Playback Error",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.retry, .close],
                presentationLocations: [.mainWindow, .immersiveSpace],
                interruptsPlayback: true
            )
        case .playbackFailed:
            .init(
                title: "Playback Error",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.retry, .close],
                presentationLocations: [.mainWindow, .immersiveSpace],
                interruptsPlayback: true
            )
        case .playbackControlFailed:
            .init(
                title: "Playback Error",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.mainWindow, .immersiveSpace],
                interruptsPlayback: false
            )
        case .mediaFormatChangeFailed:
            .init(
                title: "Unable to Change Format",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.playerDeck],
                interruptsPlayback: false
            )
        case .audioTrackSelectionFailed:
            .init(
                title: "Audio Error",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.playerDeck],
                interruptsPlayback: false
            )
        case .subtitleTrackSelectionFailed:
            .init(
                title: "Subtitle Error",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.playerDeck],
                interruptsPlayback: false
            )
        case .externalSubtitleFailed:
            .init(
                title: "Subtitle Error",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.playerDeck],
                interruptsPlayback: false
            )
        case .presentationTransitionFailed:
            .init(
                title: "Unable to Change Display",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.playerDeck],
                interruptsPlayback: false
            )
        case .presentationConversionFailed:
            .init(
                title: "Conversion Failed",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.mediaLibrary],
                interruptsPlayback: true
            )
        case .surfaceAttachmentFailed:
            .init(
                title: "Playback Error",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.retry, .close],
                presentationLocations: [.mainWindow, .immersiveSpace],
                interruptsPlayback: true
            )
        case .environmentLoadingFailed:
            .init(
                title: "Playback Error",
                messageStrategy: .fixedProductCopy,
                allowedActions: [.retry, .close],
                presentationLocations: [.immersiveSpace],
                interruptsPlayback: true
            )
        case .capabilityUnavailable:
            .init(
                title: "Unable to Play",
                messageStrategy: .blockingCapabilityFact,
                allowedActions: [.confirm],
                presentationLocations: [.playerDeck],
                interruptsPlayback: true
            )
        }
    }
}
