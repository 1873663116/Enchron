import Foundation

public enum PlaybackUserVisibleIssueCategory: String, CaseIterable, Sendable, Equatable {
    case mediaOpeningFailed
    case mediaRequestFailed
    case unsupportedVideoCodec
    case sourceAccessUnavailable
    case playbackFailed
    case serverCertificateChanged = "server-certificate-changed"
    case connectionInterrupted = "connection-interrupted"
    case connectionFailed = "connection-failed"
    case sourceFileMissing = "source-file-missing"
    case sourceAccessDenied = "source-access-denied"
    case mediaDataCorrupt = "media-data-corrupt"
    case rendererRequiresFlush = "renderer-requires-flush"
    case mediaServicesReset = "media-services-reset"
    case rendererFailed = "renderer-failed"
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
    case mpeg4Part2
    case other

    public init(codecName: String) {
        switch codecName.lowercased().filter({ $0.isLetter || $0.isNumber }) {
        case "vc", "vc1": self = .vc1
        case "mpegvideo", "mpeg2video": self = .mpeg2Video
        case "mpeg4", "mpeg4video": self = .mpeg4Part2
        default: self = .other
        }
    }

    fileprivate var productName: String? {
        switch self {
        case .vc1: "VC-1 video"
        case .mpeg2Video: "MPEG-2 video"
        case .mpeg4Part2: "MPEG-4 Part 2 video"
        case .other: nil
        }
    }
}

public enum PlaybackBlockingCapability: String, CaseIterable, Sendable, Equatable {
    case videoDecoderUnavailable
}

public struct PlaybackActiveFailure: Sendable, Equatable {
    public enum Cause: String, CaseIterable, Sendable, Equatable {
        case connectionInterrupted = "connection-interrupted"
        case sourceFileMissing = "source-file-missing"
        case sourceAccessDenied = "source-access-denied"
        case mediaDataCorrupt = "media-data-corrupt"
        case rendererRequiresFlush = "renderer-requires-flush"
        case mediaServicesReset = "media-services-reset"
        case rendererFailed = "renderer-failed"
    }

    public let cause: Cause
    public let causalPosition: PlaybackModel.PlaybackPosition
    public let runtimeGeneration: UInt64
    public let requestID: URL
    public let mediaSessionID: String

    public init(
        cause: Cause,
        causalPosition: PlaybackModel.PlaybackPosition,
        runtimeGeneration: UInt64,
        requestID: URL,
        mediaSessionID: String
    ) {
        self.cause = cause
        self.causalPosition = causalPosition
        self.runtimeGeneration = runtimeGeneration
        self.requestID = requestID
        self.mediaSessionID = mediaSessionID
    }
}

public enum PlaybackUserVisibleIssue: Sendable, Equatable {
    case mediaOpeningFailed
    case mediaRequestFailed
    case connectionFailed
    case unsupportedVideoCodec(PlaybackUnsupportedVideoCodec)
    case sourceAccessUnavailable
    case playbackFailed
    case serverCertificateChanged
    case activePlaybackFailure(PlaybackActiveFailure)
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
        case .connectionFailed: .connectionFailed
        case .unsupportedVideoCodec: .unsupportedVideoCodec
        case .sourceAccessUnavailable: .sourceAccessUnavailable
        case .playbackFailed: .playbackFailed
        case .serverCertificateChanged: .serverCertificateChanged
        case .activePlaybackFailure(let failure):
            switch failure.cause {
            case .connectionInterrupted: .connectionInterrupted
            case .sourceFileMissing: .sourceFileMissing
            case .sourceAccessDenied: .sourceAccessDenied
            case .mediaDataCorrupt: .mediaDataCorrupt
            case .rendererRequiresFlush: .rendererRequiresFlush
            case .mediaServicesReset: .mediaServicesReset
            case .rendererFailed: .rendererFailed
            }
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
        case .connectionFailed:
            "Could not connect to the media source. Check the network and try again."
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
        case .serverCertificateChanged:
            "The server certificate changed. Close playback before reconnecting."
        case .activePlaybackFailure(let failure):
            switch failure.cause {
            case .connectionInterrupted:
                "The connection to this media source was interrupted."
            case .sourceFileMissing:
                "The source file is no longer available."
            case .sourceAccessDenied:
                "Enchron no longer has permission to read the source file."
            case .mediaDataCorrupt:
                "Playback encountered unreadable media data."
            case .rendererRequiresFlush:
                "The video decoder needs to restart before playback can continue."
            case .mediaServicesReset:
                "The system media service restarted during playback."
            case .rendererFailed:
                "The video renderer could not continue."
            }
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

    public var activePlaybackFailure: PlaybackActiveFailure? {
        guard case .activePlaybackFailure(let failure) = self else { return nil }
        return failure
    }

    public func canPresent(at location: PlaybackIssuePresentationLocation) -> Bool {
        presentationLocations.contains(location)
    }
}

public extension PlaybackUserVisibleIssueCategory {
    var policy: PlaybackUserVisibleIssuePolicy {
        switch self {
        case .mediaOpeningFailed:
            .init(
                title: String(localized: "Failed to Load"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.retry, .close],
                presentationLocations: [.mainWindow, .immersiveSpace],
                interruptsPlayback: true
            )
        case .mediaRequestFailed:
            .init(
                title: String(localized: "Unable to Play"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.close],
                presentationLocations: [.mainWindow, .mediaLibrary],
                interruptsPlayback: true
            )
        case .connectionFailed:
            .init(
                title: String(localized: "Connection Failed"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.retry, .close],
                presentationLocations: [.mainWindow, .mediaLibrary, .immersiveSpace],
                interruptsPlayback: true
            )
        case .unsupportedVideoCodec:
            .init(
                title: String(localized: "Unable to Play"),
                messageStrategy: .unsupportedVideoCodecFact,
                allowedActions: [.close],
                presentationLocations: [.mainWindow, .mediaLibrary],
                interruptsPlayback: true
            )
        case .sourceAccessUnavailable:
            .init(
                title: String(localized: "Playback Error"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.retry, .close],
                presentationLocations: [.mainWindow, .immersiveSpace],
                interruptsPlayback: true
            )
        case .serverCertificateChanged:
            .init(
                title: String(localized: "Server Certificate Changed"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.close],
                presentationLocations: [.mainWindow, .immersiveSpace],
                interruptsPlayback: true
            )
        case .playbackFailed, .connectionInterrupted, .sourceFileMissing,
             .sourceAccessDenied, .mediaDataCorrupt, .rendererRequiresFlush,
             .mediaServicesReset, .rendererFailed:
            .init(
                title: String(localized: "Playback Error"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.retry, .close],
                presentationLocations: [.mainWindow, .immersiveSpace],
                interruptsPlayback: true
            )
        case .playbackControlFailed:
            .init(
                title: String(localized: "Playback Error"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.mainWindow, .immersiveSpace],
                interruptsPlayback: false
            )
        case .mediaFormatChangeFailed:
            .init(
                title: String(localized: "Unable to Change Format"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.playerDeck],
                interruptsPlayback: false
            )
        case .audioTrackSelectionFailed:
            .init(
                title: String(localized: "Audio Error"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.playerDeck],
                interruptsPlayback: false
            )
        case .subtitleTrackSelectionFailed:
            .init(
                title: String(localized: "Subtitle Error"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.playerDeck],
                interruptsPlayback: false
            )
        case .externalSubtitleFailed:
            .init(
                title: String(localized: "Subtitle Error"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.playerDeck],
                interruptsPlayback: false
            )
        case .presentationTransitionFailed:
            .init(
                title: String(localized: "Unable to Change Display"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.playerDeck],
                interruptsPlayback: false
            )
        case .presentationConversionFailed:
            .init(
                title: String(localized: "Conversion Failed"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.confirm],
                presentationLocations: [.mediaLibrary],
                interruptsPlayback: true
            )
        case .surfaceAttachmentFailed:
            .init(
                title: String(localized: "Playback Error"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.retry, .close],
                presentationLocations: [.mainWindow, .immersiveSpace],
                interruptsPlayback: true
            )
        case .environmentLoadingFailed:
            .init(
                title: String(localized: "Playback Error"),
                messageStrategy: .fixedProductCopy,
                allowedActions: [.retry, .close],
                presentationLocations: [.immersiveSpace],
                interruptsPlayback: true
            )
        case .capabilityUnavailable:
            .init(
                title: String(localized: "Unable to Play"),
                messageStrategy: .blockingCapabilityFact,
                allowedActions: [.confirm],
                presentationLocations: [.playerDeck],
                interruptsPlayback: true
            )
        }
    }
}
