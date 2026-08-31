import Foundation
@testable import Playback
import Testing

private struct PlaybackIssueExpectation {
    let issue: PlaybackUserVisibleIssue
    let category: PlaybackUserVisibleIssueCategory
    let title: String
    let message: String
    let messageStrategy: PlaybackUserVisibleIssueMessageStrategy
    let actions: [PlaybackUserVisibleIssueAction]
    let locations: [PlaybackIssuePresentationLocation]
}

@MainActor
private func activeFailureIssue(
    _ cause: PlaybackActiveFailure.Cause
) -> PlaybackUserVisibleIssue {
    .activePlaybackFailure(
        PlaybackActiveFailure(
            cause: cause,
            causalPosition: .init(seconds: 42, duration: 600),
            runtimeGeneration: 7,
            requestID: URL(fileURLWithPath: "/tests/movie.mkv"),
            mediaSessionID: "session-7"
        )
    )
}

@MainActor
private let playbackIssueExpectations: [PlaybackIssueExpectation] = [
    .init(
        issue: .mediaOpeningFailed,
        category: .mediaOpeningFailed,
        title: "Failed to Load",
        message: "Unable to open this file.",
        messageStrategy: .fixedProductCopy,
        actions: [.retry, .close],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: .mediaRequestFailed,
        category: .mediaRequestFailed,
        title: "Unable to Play",
        message: "This item could not be prepared for playback.",
        messageStrategy: .fixedProductCopy,
        actions: [.close],
        locations: [.mainWindow, .mediaLibrary]
    ),
    .init(
        issue: .unsupportedVideoCodec(.vc1),
        category: .unsupportedVideoCodec,
        title: "Unable to Play",
        message: "This video uses VC-1 video, which Enchron does not support.",
        messageStrategy: .unsupportedVideoCodecFact,
        actions: [.close],
        locations: [.mainWindow, .mediaLibrary]
    ),
    .init(
        issue: .sourceAccessUnavailable,
        category: .sourceAccessUnavailable,
        title: "Playback Error",
        message: "The original media source is no longer available. Choose it again to restore access.",
        messageStrategy: .fixedProductCopy,
        actions: [.retry, .close],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: .playbackFailed,
        category: .playbackFailed,
        title: "Playback Error",
        message: "Playback could not continue.",
        messageStrategy: .fixedProductCopy,
        actions: [.retry, .close],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: .serverCertificateChanged,
        category: .serverCertificateChanged,
        title: "Server Certificate Changed",
        message: "The server certificate changed. Close playback before reconnecting.",
        messageStrategy: .fixedProductCopy,
        actions: [.close],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: activeFailureIssue(.connectionInterrupted),
        category: .connectionInterrupted,
        title: "Playback Error",
        message: "The connection to this media source was interrupted.",
        messageStrategy: .fixedProductCopy,
        actions: [.retry, .close],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: activeFailureIssue(.sourceFileMissing),
        category: .sourceFileMissing,
        title: "Playback Error",
        message: "The source file is no longer available.",
        messageStrategy: .fixedProductCopy,
        actions: [.retry, .close],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: activeFailureIssue(.sourceAccessDenied),
        category: .sourceAccessDenied,
        title: "Playback Error",
        message: "Enchron no longer has permission to read the source file.",
        messageStrategy: .fixedProductCopy,
        actions: [.retry, .close],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: activeFailureIssue(.mediaDataCorrupt),
        category: .mediaDataCorrupt,
        title: "Playback Error",
        message: "Playback encountered unreadable media data.",
        messageStrategy: .fixedProductCopy,
        actions: [.retry, .close],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: activeFailureIssue(.rendererRequiresFlush),
        category: .rendererRequiresFlush,
        title: "Playback Error",
        message: "The video decoder needs to restart before playback can continue.",
        messageStrategy: .fixedProductCopy,
        actions: [.retry, .close],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: activeFailureIssue(.mediaServicesReset),
        category: .mediaServicesReset,
        title: "Playback Error",
        message: "The system media service restarted during playback.",
        messageStrategy: .fixedProductCopy,
        actions: [.retry, .close],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: activeFailureIssue(.rendererFailed),
        category: .rendererFailed,
        title: "Playback Error",
        message: "The video renderer could not continue.",
        messageStrategy: .fixedProductCopy,
        actions: [.retry, .close],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: .playbackControlFailed,
        category: .playbackControlFailed,
        title: "Playback Error",
        message: "The playback command could not be completed.",
        messageStrategy: .fixedProductCopy,
        actions: [.confirm],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: .mediaFormatChangeFailed,
        category: .mediaFormatChangeFailed,
        title: "Unable to Change Format",
        message: "The video format could not be changed.",
        messageStrategy: .fixedProductCopy,
        actions: [.confirm],
        locations: [.playerDeck]
    ),
    .init(
        issue: .audioTrackSelectionFailed,
        category: .audioTrackSelectionFailed,
        title: "Audio Error",
        message: "The audio track could not be changed.",
        messageStrategy: .fixedProductCopy,
        actions: [.confirm],
        locations: [.playerDeck]
    ),
    .init(
        issue: .subtitleTrackSelectionFailed,
        category: .subtitleTrackSelectionFailed,
        title: "Subtitle Error",
        message: "The subtitle track could not be changed.",
        messageStrategy: .fixedProductCopy,
        actions: [.confirm],
        locations: [.playerDeck]
    ),
    .init(
        issue: .externalSubtitleFailed,
        category: .externalSubtitleFailed,
        title: "Subtitle Error",
        message: "Some external subtitle files could not be loaded.",
        messageStrategy: .fixedProductCopy,
        actions: [.confirm],
        locations: [.playerDeck]
    ),
    .init(
        issue: .presentationTransitionFailed,
        category: .presentationTransitionFailed,
        title: "Unable to Change Display",
        message: "The playback display could not be changed.",
        messageStrategy: .fixedProductCopy,
        actions: [.confirm],
        locations: [.playerDeck]
    ),
    .init(
        issue: .presentationConversionFailed,
        category: .presentationConversionFailed,
        title: "Conversion Failed",
        message: "The playback display could not be changed. Enchron returned to the Media Library.",
        messageStrategy: .fixedProductCopy,
        actions: [.confirm],
        locations: [.mediaLibrary]
    ),
    .init(
        issue: .surfaceAttachmentFailed,
        category: .surfaceAttachmentFailed,
        title: "Playback Error",
        message: "The video surface could not be attached.",
        messageStrategy: .fixedProductCopy,
        actions: [.retry, .close],
        locations: [.mainWindow, .immersiveSpace]
    ),
    .init(
        issue: .environmentLoadingFailed,
        category: .environmentLoadingFailed,
        title: "Playback Error",
        message: "The selected environment could not be loaded.",
        messageStrategy: .fixedProductCopy,
        actions: [.retry, .close],
        locations: [.immersiveSpace]
    ),
    .init(
        issue: .capabilityUnavailable(.videoDecoderUnavailable),
        category: .capabilityUnavailable,
        title: "Unable to Play",
        message: "This device has no ProRes decoder, so this file cannot play.",
        messageStrategy: .blockingCapabilityFact,
        actions: [.confirm],
        locations: [.playerDeck]
    )
]

@Test("every playback issue category has one complete presentation policy")
@MainActor
func everyPlaybackIssueCategoryHasOnePolicy() {
    #expect(playbackIssueExpectations.map(\.category) == PlaybackUserVisibleIssueCategory.allCases)

    for expectation in playbackIssueExpectations {
        let issue = expectation.issue
        #expect(issue.category == expectation.category)
        #expect(issue.title == expectation.title)
        #expect(issue.message == expectation.message)
        #expect(issue.messageStrategy == expectation.messageStrategy)
        #expect(issue.allowedActions == expectation.actions)
        #expect(issue.presentationLocations == expectation.locations)
        #expect(Set(issue.allowedActions).count == issue.allowedActions.count)
        #expect(Set(issue.presentationLocations).count == issue.presentationLocations.count)
    }
}

@Test("active playback failures have one exact recovery policy")
@MainActor
func activePlaybackFailuresHaveOneRecoveryPolicy() {
    #expect(PlaybackActiveFailure.Cause.allCases.count == 7)

    for cause in PlaybackActiveFailure.Cause.allCases {
        let issue = activeFailureIssue(cause)
        #expect(issue.category.rawValue == cause.rawValue)
        #expect(issue.allowedActions == [.retry, .close])
        #expect(issue.presentationLocations == [.mainWindow, .immersiveSpace])
        #expect(issue.interruptsPlayback)
        #expect(issue.activePlaybackFailure?.cause == cause)
    }
}

@Test("server certificate changes are not active playback failure causes")
@MainActor
func serverCertificateChangesRemainOutsideActiveFailureCauses() {
    let issue = PlaybackUserVisibleIssue.serverCertificateChanged

    #expect(issue.category.rawValue == "server-certificate-changed")
    #expect(issue.allowedActions == [.close])
    #expect(issue.presentationLocations == [.mainWindow, .immersiveSpace])
    #expect(issue.interruptsPlayback)
    #expect(issue.activePlaybackFailure == nil)
}

@Test("unsupported codec names are reduced to bounded product facts")
@MainActor
func unsupportedCodecNamesDoNotBecomeProductCopy() {
    let arbitrary = PlaybackUserVisibleIssue.unsupportedVideoCodec(
        PlaybackUnsupportedVideoCodec(codecName: "secret-server-diagnostic")
    )

    #expect(arbitrary.message == "This video uses a codec that Enchron does not support.")
    #expect(arbitrary.message.contains("secret-server-diagnostic") == false)
    #expect(
        PlaybackUserVisibleIssue.unsupportedVideoCodec(
            PlaybackUnsupportedVideoCodec(codecName: "mpeg4")
        ).message
            == "This video uses MPEG-4 Part 2 video, which Enchron does not support."
    )
    #expect(PlaybackUnsupportedVideoCodec(codecName: "mpeg2video") == .mpeg2Video)
    #expect(PlaybackUnsupportedVideoCodec(codecName: "vc1") == .vc1)
}
