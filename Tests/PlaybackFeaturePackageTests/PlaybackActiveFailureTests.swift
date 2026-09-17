import Foundation
import MediaSource
@testable @_spi(Testing) import Playback
import PlaybackCore
import Testing

@MainActor
struct PlaybackActiveFailureTests {
    @Test("Undiagnosed terminal lifecycle publishes a generic playback failure")
    func undiagnosedTerminalLifecyclePublishesPlaybackFailure() async throws {
        let controller = PlaybackCoreController()
        let runtime = PlaybackRuntime(controller: controller)
        let request = PlaybackLaunchRequest(
            source: try PlaybackAddress(
                localFileURL: URL(fileURLWithPath: "/tests/undiagnosed-failure.mkv")
            ),
            displayName: "undiagnosed-failure.mkv"
        )
        runtime.prepareForPlayback(request)

        controller.onStatusChange?(.failed("No structured failure context"))

        #expect(runtime.productLifecycle == .failed)
        #expect(runtime.userVisibleIssue == .playbackFailed)
        await runtime.leavePlaybackAndWait(reason: .backButton)
    }

    @Test("A repeated terminal failure retains a specific active diagnosis")
    func repeatedTerminalFailureRetainsSpecificDiagnosis() async throws {
        let controller = PlaybackCoreController()
        let runtime = PlaybackRuntime(controller: controller)
        let request = PlaybackLaunchRequest(
            source: try PlaybackAddress(
                localFileURL: URL(fileURLWithPath: "/tests/specific-failure.mkv")
            ),
            displayName: "specific-failure.mkv"
        )
        runtime.prepareForPlayback(request)
        let failure = PlaybackActiveFailure(
            cause: .connectionInterrupted,
            causalPosition: .init(seconds: 19, duration: 120),
            runtimeGeneration: runtime.observationGeneration,
            requestID: request.id,
            mediaSessionID: "specific-session"
        )
        runtime.setUserVisibleIssue(.activePlaybackFailure(failure))

        controller.onStatusChange?(.failed("Duplicate terminal callback"))

        #expect(runtime.userVisibleIssue == .activePlaybackFailure(failure))
        await runtime.leavePlaybackAndWait(reason: .backButton)
    }

    @Test("connection interruption maps from URL HTTP and POSIX boundaries")
    func connectionInterruptionMapsFromExternalBoundaries() {
        #expect(
            MediaSourceReadFailure(classifying: URLError(.networkConnectionLost))
                == .transportInterrupted
        )
        #expect(MediaSourceReadFailure(httpStatusCode: 503) == .transportInterrupted)
        #expect(
            MediaSourceReadFailure(classifying: POSIXError(.ECONNRESET))
                == .transportInterrupted
        )
    }

    @Test("source missing maps from URL HTTP Cocoa and nested POSIX boundaries")
    func sourceMissingMapsFromExternalBoundaries() {
        #expect(
            MediaSourceReadFailure(classifying: URLError(.fileDoesNotExist))
                == .resourceMissing
        )
        #expect(MediaSourceReadFailure(httpStatusCode: 404) == .resourceMissing)
        #expect(
            MediaSourceReadFailure(classifying: CocoaError(.fileReadNoSuchFile))
                == .resourceMissing
        )
        #expect(
            MediaSourceReadFailure(
                classifying: NSError(
                    domain: "test.wrapper",
                    code: 1,
                    userInfo: [NSUnderlyingErrorKey: POSIXError(.ENOENT)]
                )
            ) == .resourceMissing
        )
    }

    @Test("source access denied maps from URL HTTP Cocoa and POSIX boundaries")
    func sourceAccessDeniedMapsFromExternalBoundaries() {
        #expect(
            MediaSourceReadFailure(classifying: URLError(.noPermissionsToReadFile))
                == .accessDenied
        )
        #expect(MediaSourceReadFailure(httpStatusCode: 403) == .accessDenied)
        #expect(
            MediaSourceReadFailure(classifying: CocoaError(.fileReadNoPermission))
                == .accessDenied
        )
        #expect(
            MediaSourceReadFailure(classifying: POSIXError(.EACCES))
                == .accessDenied
        )
    }

    @Test("corrupt media maps from URL HTTP Cocoa and POSIX boundaries")
    func corruptMediaMapsFromExternalBoundaries() {
        #expect(
            MediaSourceReadFailure(classifying: URLError(.cannotDecodeContentData))
                == .invalidData
        )
        #expect(MediaSourceReadFailure(httpStatusCode: 416) == .invalidData)
        #expect(
            MediaSourceReadFailure(classifying: CocoaError(.fileReadCorruptFile))
                == .invalidData
        )
        #expect(
            MediaSourceReadFailure(classifying: POSIXError(.EBADMSG))
                == .invalidData
        )
    }

    @Test("unclassified failures do not become a public active category")
    func unclassifiedFailuresRemainDiagnosticOnly() {
        #expect(MediaSourceReadFailure(classifying: URLError(.cancelled)) == nil)
        #expect(MediaSourceReadFailure(httpStatusCode: 500) == nil)
        #expect(MediaSourceReadFailure(classifying: POSIXError(.EIO)) == nil)
    }

    @Test("Runtime maps only causal source and Core failure facts")
    func runtimeMapsOnlyCausalSourceAndCoreFacts() {
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: .transportInterrupted,
                coreContext: .sourceRead(nil)
            ) == .connectionInterrupted
        )
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: .resourceMissing,
                coreContext: .sourceRead(nil)
            ) == .sourceFileMissing
        )
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: .accessDenied,
                coreContext: .sourceRead(nil)
            ) == .sourceAccessDenied
        )
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: .invalidData,
                coreContext: .sourceRead(nil)
            ) == .mediaDataCorrupt
        )
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: nil,
                coreContext: .sourceRead(.connectionInterrupted)
            ) == .connectionInterrupted
        )
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: nil,
                coreContext: .sourceRead(.sourceFileMissing)
            ) == .sourceFileMissing
        )
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: nil,
                coreContext: .sourceRead(.sourceAccessDenied)
            ) == .sourceAccessDenied
        )
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: nil,
                coreContext: .decoder(.mediaDataCorrupt)
            ) == .mediaDataCorrupt
        )
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: nil,
                coreContext: .decoder(.rendererRequiresFlush)
            ) == .rendererRequiresFlush
        )
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: nil,
                coreContext: .decoder(.mediaServicesReset)
            ) == .mediaServicesReset
        )
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: nil,
                coreContext: .decoder(.rendererFailed)
            ) == .rendererFailed
        )
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: nil,
                coreContext: nil
            ) == nil
        )
        #expect(
            PlaybackRuntime.activeFailureCause(
                sourceFailure: .transportInterrupted,
                coreContext: nil
            ) == nil
        )
    }

    @Test("Retry uses the causal position and current playback choices")
    func retryUsesCausalPositionAndCurrentPlaybackChoices() async throws {
        let suiteName = "app.enchron.tests.active-failure-retry.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let runtime = ActiveFailureRuntime()
        let coordinator = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: ActiveFailurePreferences()
        )
        var enteredModes: [PersistedPlaybackMode] = []
        coordinator.onPlaybackModeEntryStarted = { mode, _ in
            enteredModes.append(mode)
            return mode
        }
        let request = Self.request(named: "movie-a")

        coordinator.beginPlayback(request)
        try await runtime.waitUntilOpenCount(1)
        let format = MediaFormat(
            projection: .equirectangular180,
            stereoLayout: .sideBySide
        )
        try await coordinator.applyFormat(
            projection: .equirectangular180,
            stereo: .sideBySide
        )
        coordinator.savePlaybackMode(.panorama)
        try await coordinator.selectAudioTrack(runtime.availableAudioTracks[1])
        try await coordinator.selectSubtitleTrack(runtime.availableSubtitleTracks[1])
        let failure = runtime.emitActiveFailure(
            cause: .connectionInterrupted,
            positionSeconds: 137.25
        )
        runtime.suspendOpen(number: 2)

        coordinator.retryPlayback()
        try await runtime.waitUntilOpenIsSuspended()
        #expect(runtime.userVisibleIssue == .activePlaybackFailure(failure))
        #expect(coordinator.pendingResumeDecision == nil)

        runtime.resumeSuspendedOpen()
        try await runtime.waitUntilOpenCount(2, issueIsCleared: true)

        let retry = try #require(runtime.openCalls.last)
        #expect(retry.request == request)
        #expect(retry.startTimeSeconds == 137.25)
        #expect(retry.initialFormat == format)
        #expect(enteredModes.last == .panorama)
        #expect(runtime.currentAudioTrackID == runtime.availableAudioTracks[1].id)
        #expect(runtime.currentSubtitleTrackID == runtime.availableSubtitleTracks[1].id)
        #expect(coordinator.resumePromptPresentationCount == 0)
    }

    @Test("Failed replacement retains the original active failure")
    func failedReplacementRetainsOriginalFailure() async throws {
        let suiteName = "app.enchron.tests.active-failure-replacement.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let runtime = ActiveFailureRuntime()
        let coordinator = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: ActiveFailurePreferences()
        )
        coordinator.beginPlayback(Self.request(named: "movie-a"))
        try await runtime.waitUntilOpenCount(1)
        let failure = runtime.emitActiveFailure(
            cause: .sourceFileMissing,
            positionSeconds: 61
        )
        runtime.failOpen(number: 2)

        coordinator.retryPlayback()
        try await runtime.waitUntilFailedOpenCount(1)

        #expect(runtime.userVisibleIssue == .activePlaybackFailure(failure))
        runtime.allowOpen(number: 2)
        coordinator.retryPlayback()
        try await runtime.waitUntilOpenCount(3, issueIsCleared: true)
        #expect(runtime.openCalls.last?.startTimeSeconds == 61)
    }

    @Test("Retry clears the failure only after the replacement becomes usable")
    func retryClearsFailureOnlyAfterReplacementBecomesUsable() async throws {
        let suiteName = "app.enchron.tests.active-failure-usable.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let runtime = ActiveFailureRuntime()
        let coordinator = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: ActiveFailurePreferences()
        )
        coordinator.beginPlayback(Self.request(named: "movie-a"))
        try await runtime.waitUntilOpenCount(1)
        let failure = runtime.emitActiveFailure(
            cause: .connectionInterrupted,
            positionSeconds: 73
        )
        runtime.keepOpenLoading(number: 2)

        coordinator.retryPlayback()
        try await runtime.waitUntilOpenReturnCount(2)
        #expect(runtime.userVisibleIssue == .activePlaybackFailure(failure))

        runtime.makeCurrentSessionReady()
        try await runtime.waitUntilIssueIsCleared()
        #expect(runtime.currentLaunchRequest?.displayName == "movie-a.mkv")
    }

    @Test("Stale failure and stale retry completion cannot replace a newer launch")
    func staleFailureAndRetryCompletionCannotReplaceNewerLaunch() async throws {
        let suiteName = "app.enchron.tests.active-failure-stale.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let runtime = ActiveFailureRuntime()
        let coordinator = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: ActiveFailurePreferences()
        )
        let first = Self.request(named: "movie-a")
        let second = Self.request(named: "movie-b")
        coordinator.beginPlayback(first)
        try await runtime.waitUntilOpenCount(1)
        runtime.emitActiveFailure(
            cause: .mediaDataCorrupt,
            positionSeconds: 88
        )
        runtime.suspendOpen(number: 2)
        coordinator.retryPlayback()
        try await runtime.waitUntilOpenIsSuspended()

        coordinator.beginPlayback(second)
        try await runtime.waitUntilOpenCount(3, issueIsCleared: true)
        runtime.resumeSuspendedOpen()
        try await runtime.waitUntilSuspendedOpenFinished()

        #expect(runtime.currentLaunchRequest == second)
        #expect(runtime.userVisibleIssue == nil)
        let openCount = runtime.openCalls.count
        let staleFailure = PlaybackActiveFailure(
            cause: .sourceAccessDenied,
            causalPosition: .init(seconds: 12, duration: 600),
            runtimeGeneration: 1,
            requestID: first.id,
            mediaSessionID: "session-1"
        )
        runtime.userVisibleIssue = .activePlaybackFailure(staleFailure)
        runtime.emit(staleFailure, observationGeneration: 1)
        coordinator.retryPlayback()
        await Task.yield()
        #expect(runtime.openCalls.count == openCount)
        #expect(runtime.currentLaunchRequest == second)
    }

    @Test("Close clears active recovery and stops playback")
    func closeClearsActiveRecoveryAndStopsPlayback() async throws {
        let suiteName = "app.enchron.tests.active-failure-close.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let runtime = ActiveFailureRuntime()
        let coordinator = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: ActiveFailurePreferences()
        )
        coordinator.beginPlayback(Self.request(named: "movie-a"))
        try await runtime.waitUntilOpenCount(1)
        runtime.emitActiveFailure(
            cause: .sourceAccessDenied,
            positionSeconds: 24
        )

        coordinator.stopPlayback(reason: .backButton)
        coordinator.retryPlayback()
        await Task.yield()

        #expect(runtime.userVisibleIssue == nil)
        #expect(runtime.currentLaunchRequest == nil)
        #expect(runtime.stopCount == 2)
        #expect(runtime.openCalls.count == 1)
    }

    @Test("Network request resolution failure publishes a retryable connection issue")
    func networkRequestResolutionFailurePublishesRetryableIssue() async throws {
        let suiteName = "app.enchron.tests.request-retry.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let runtime = ActiveFailureRuntime()
        let coordinator = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: ActiveFailurePreferences()
        )

        coordinator.requestPlayback {
            throw URLError(.cannotConnectToHost)
        }
        try await runtime.waitUntilIssue(.connectionFailed)

        #expect(runtime.userVisibleIssue?.allowedActions == [.retry, .close])
        #expect(runtime.openCalls.isEmpty)
    }

    @Test("Retry after request resolution failure reruns the resolution")
    func retryAfterRequestResolutionFailureRerunsResolution() async throws {
        let suiteName = "app.enchron.tests.request-retry-loop.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let runtime = ActiveFailureRuntime()
        let coordinator = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: ActiveFailurePreferences()
        )
        let request = Self.request(named: "movie-a")
        var attempts = 0

        coordinator.requestPlayback {
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return request
        }
        try await runtime.waitUntilIssue(.connectionFailed)

        coordinator.retryPlayback()
        try await runtime.waitUntilOpenCount(1, issueIsCleared: true)

        #expect(attempts == 2)
        #expect(runtime.openCalls.last?.request == request)
    }

    @Test("Close after request resolution failure discards the pending resolution")
    func closeAfterRequestResolutionFailureDiscardsResolution() async throws {
        let suiteName = "app.enchron.tests.request-retry-close.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let runtime = ActiveFailureRuntime()
        let coordinator = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: ActiveFailurePreferences()
        )
        var attempts = 0
        coordinator.requestPlayback {
            attempts += 1
            throw URLError(.timedOut)
        }
        try await runtime.waitUntilIssue(.connectionFailed)

        coordinator.stopPlayback(reason: .backButton)
        coordinator.retryPlayback()
        await Task.yield()

        #expect(attempts == 1)
        #expect(runtime.userVisibleIssue == nil)
        #expect(runtime.openCalls.isEmpty)
    }

    @Test("A hung request resolution times out into a retryable connection issue")
    func hungRequestResolutionTimesOutIntoRetryableIssue() async throws {
        let suiteName = "app.enchron.tests.request-timeout.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let runtime = ActiveFailureRuntime()
        let coordinator = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: ActiveFailurePreferences(),
            requestResolutionTimeout: .milliseconds(200)
        )

        coordinator.requestPlayback {
            try await Task.sleep(for: .seconds(60))
            return Self.request(named: "movie-a")
        }
        #expect(coordinator.isResolvingPlaybackRequest)

        try await runtime.waitUntilIssue(.connectionFailed)
        try await waitUntilResolutionFlagClears(on: coordinator)
        #expect(runtime.openCalls.isEmpty)
    }

    @Test("Retry after a resolution timeout reruns the resolution")
    func retryAfterResolutionTimeoutRerunsResolution() async throws {
        let suiteName = "app.enchron.tests.request-timeout-retry.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let runtime = ActiveFailureRuntime()
        let coordinator = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: ActiveFailurePreferences(),
            requestResolutionTimeout: .milliseconds(200)
        )
        let request = Self.request(named: "movie-a")
        var attempts = 0

        coordinator.requestPlayback {
            attempts += 1
            if attempts == 1 {
                try await Task.sleep(for: .seconds(60))
            }
            return request
        }
        try await runtime.waitUntilIssue(.connectionFailed)

        coordinator.retryPlayback()
        try await runtime.waitUntilOpenCount(1, issueIsCleared: true)

        #expect(attempts == 2)
        #expect(runtime.openCalls.last?.request == request)
    }

    private func waitUntilResolutionFlagClears(
        on coordinator: PlaybackLaunchCoordinator
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while coordinator.isResolvingPlaybackRequest,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.isResolvingPlaybackRequest == false)
    }

    @Test("Request resolution errors classify network failures separately")
    func requestResolutionClassification() {
        #expect(
            PlaybackLaunchCoordinator.requestResolutionIssue(
                for: URLError(.networkConnectionLost)
            ) == .connectionFailed
        )
        #expect(
            PlaybackLaunchCoordinator.requestResolutionIssue(
                for: NSError(domain: NSURLErrorDomain, code: -1009)
            ) == .connectionFailed
        )
        #expect(
            PlaybackLaunchCoordinator.requestResolutionIssue(
                for: CocoaError(.coderInvalidValue)
            ) == .mediaRequestFailed
        )
    }

    private static func request(named name: String) -> PlaybackLaunchRequest {
        PlaybackLaunchRequest(
            url: URL(fileURLWithPath: "/tests/\(name).mkv"),
            displayName: "\(name).mkv"
        )
    }
}

private struct ActiveFailurePreferences: PlaybackPreferencesProviding {
    func loadPlaybackPreferences() -> PlaybackPreferences {
        PlaybackPreferences(resumePolicy: .askEveryTime)
    }
}

@MainActor
private final class ActiveFailureRuntime: PlaybackRuntimeControlling {
    struct OpenCall: Equatable {
        let request: PlaybackLaunchRequest
        let startTimeSeconds: Double
        let initialFormat: MediaFormat?
    }

    enum TestError: Error {
        case replacementFailed
    }

    var productLifecycle: ProductPlaybackLifecycle = .idle
    var playbackPosition = PlaybackModel.PlaybackPosition(seconds: 0, duration: 600)
    var currentLaunchRequest: PlaybackLaunchRequest?
    var prefetchedMetadata: PlaybackMediaMetadata?
    var displayMediaProfile: PlaybackModel.MediaProfile?
    var displayFileSizeInBytes: Int64?
    var effectiveMediaFormatInterpretation: EffectiveMediaFormatInterpretation {
        MediaFormatInterpretationResolver.resolve(
            source: SourceMediaFormatFact(
                contentKind: .rectilinear,
                projection: .flat,
                stereoLayout: .mono
            ),
            override: selectedFormat
        )
    }
    var mediaKind: PlaybackMediaKind = .video
    var activeSessionID: String?
    var actualPlaybackSeconds: Double = 0
    var didEndNaturally = false
    let availableAudioTracks = [
        PlaybackModel.AudioTrack(
            id: "audio-default",
            languageCode: "en",
            displayName: "English",
            isDefault: true
        ),
        PlaybackModel.AudioTrack(
            id: "audio-selected",
            languageCode: "ja",
            displayName: "Japanese"
        )
    ]
    var currentAudioTrackID: String?
    let availableSubtitleTracks = [
        PlaybackModel.SubtitleTrack(
            id: "subtitle-default",
            languageCode: "en",
            displayName: "English",
            isDefault: true
        ),
        PlaybackModel.SubtitleTrack(
            id: "subtitle-selected",
            languageCode: "ja",
            displayName: "Japanese"
        )
    ]
    var currentSubtitleTrackID: String?
    var userVisibleIssue: PlaybackUserVisibleIssue?
    private(set) var observationGeneration: UInt64 = 0
    var onMediaProfileResolved: ((PlaybackLaunchRequest, PlaybackModel.MediaProfile) -> Void)?
    var onPlaybackObservation: ((PlaybackRuntimeObservation) -> Void)?
    private(set) var openCalls: [OpenCall] = []
    private(set) var stopCount = 0
    private(set) var failedOpenCount = 0
    private(set) var openReturnCount = 0
    private var selectedFormat: MediaFormat?
    private var suspendedOpenNumber: Int?
    private var suspendedOpenContinuation: CheckedContinuation<Void, Never>?
    private var suspendedOpenFinishedCount = 0
    private var failedOpenNumbers: Set<Int> = []
    private var loadingOpenNumbers: Set<Int> = []

    init() {
        currentAudioTrackID = availableAudioTracks[0].id
        currentSubtitleTrackID = availableSubtitleTracks[0].id
    }

    func prepareForPlayback(_ request: PlaybackLaunchRequest) {
        if currentLaunchRequest == nil || currentLaunchRequest != request {
            observationGeneration &+= 1
        }
        currentLaunchRequest = request
        productLifecycle = .loading
    }

    func applyPrefetchedMetadata(_ metadata: PlaybackMediaMetadata) {
        prefetchedMetadata = metadata
    }

    func open(
        _ request: PlaybackLaunchRequest,
        startTimeSeconds: Double,
        initialSpeed: PlaybackModel.PlaybackSpeed,
        initialFormat: MediaFormat?
    ) async throws {
        let openNumber = openCalls.count + 1
        openCalls.append(
            OpenCall(
                request: request,
                startTimeSeconds: startTimeSeconds,
                initialFormat: initialFormat
            )
        )
        if suspendedOpenNumber == openNumber {
            await withCheckedContinuation { continuation in
                suspendedOpenContinuation = continuation
            }
            suspendedOpenFinishedCount += 1
            try Task.checkCancellation()
        }
        if failedOpenNumbers.contains(openNumber) {
            failedOpenCount += 1
            throw TestError.replacementFailed
        }
        currentLaunchRequest = request
        activeSessionID = "session-\(openNumber)"
        productLifecycle = loadingOpenNumbers.contains(openNumber) ? .loading : .ready
        selectedFormat = initialFormat
        currentAudioTrackID = availableAudioTracks[0].id
        currentSubtitleTrackID = availableSubtitleTracks[0].id
        openReturnCount += 1
    }

    func setFormat(
        projection: PlaybackModel.ProjectionType,
        horizontalFieldOfViewDegrees: Int?,
        stereo: PlaybackModel.StereoLayout,
        usesDolbyVisionFallback: Bool
    ) async throws {
        selectedFormat = MediaFormat(
            projection: Self.projection(from: projection),
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            stereoLayout: Self.stereo(from: stereo),
            usesDolbyVisionFallback: usesDolbyVisionFallback
        )
    }

    func useSourceFormat() async throws {
        selectedFormat = nil
    }

    func selectAudioTrack(_ track: PlaybackModel.AudioTrack) async throws {
        currentAudioTrackID = track.id
    }

    func selectSubtitleTrack(_ track: PlaybackModel.SubtitleTrack?) async throws {
        currentSubtitleTrackID = track?.id
    }

    func replay() {}

    func leavePlayback(reason: PlaybackLeaveReason) {
        stopCount += 1
        currentLaunchRequest = nil
        activeSessionID = nil
        productLifecycle = .idle
    }

    func leavePlaybackAndWait(reason: PlaybackLeaveReason) async {
        leavePlayback(reason: reason)
    }

    func stopForNextRequest(releasingSourceAccess: Bool) {
        stopCount += 1
        currentLaunchRequest = nil
        activeSessionID = nil
        productLifecycle = .idle
    }

    func setUserVisibleIssue(_ issue: PlaybackUserVisibleIssue?) {
        userVisibleIssue = issue
    }

    func suspendOpen(number: Int) {
        suspendedOpenNumber = number
    }

    func resumeSuspendedOpen() {
        suspendedOpenContinuation?.resume()
        suspendedOpenContinuation = nil
        suspendedOpenNumber = nil
    }

    func failOpen(number: Int) {
        failedOpenNumbers.insert(number)
    }

    func allowOpen(number: Int) {
        failedOpenNumbers.remove(number)
    }

    func keepOpenLoading(number: Int) {
        loadingOpenNumbers.insert(number)
    }

    func makeCurrentSessionReady() {
        productLifecycle = .ready
        onPlaybackObservation?(
            PlaybackRuntimeObservation(
                generation: observationGeneration,
                event: .lifecycle(.ready)
            )
        )
    }

    @discardableResult
    func emitActiveFailure(
        cause: PlaybackActiveFailure.Cause,
        positionSeconds: Double
    ) -> PlaybackActiveFailure {
        playbackPosition = .init(seconds: positionSeconds, duration: playbackPosition.duration)
        productLifecycle = .failed
        let failure = PlaybackActiveFailure(
            cause: cause,
            causalPosition: playbackPosition,
            runtimeGeneration: observationGeneration,
            requestID: currentLaunchRequest?.id ?? URL(fileURLWithPath: "/missing"),
            mediaSessionID: activeSessionID ?? "missing"
        )
        userVisibleIssue = .activePlaybackFailure(failure)
        emit(failure, observationGeneration: observationGeneration)
        return failure
    }

    func emit(
        _ failure: PlaybackActiveFailure,
        observationGeneration: UInt64
    ) {
        onPlaybackObservation?(
            PlaybackRuntimeObservation(
                generation: observationGeneration,
                event: .activeFailure(failure)
            )
        )
    }

    func waitUntilOpenCount(
        _ count: Int,
        issueIsCleared: Bool = false
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if openCalls.count >= count,
               issueIsCleared == false || userVisibleIssue == nil {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Runtime did not complete \(count) opens")
    }

    func waitUntilOpenIsSuspended() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while suspendedOpenContinuation == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(suspendedOpenContinuation != nil)
    }

    func waitUntilSuspendedOpenFinished() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while suspendedOpenFinishedCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(suspendedOpenFinishedCount == 1)
    }

    func waitUntilFailedOpenCount(_ count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while failedOpenCount < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(failedOpenCount == count)
    }

    func waitUntilOpenReturnCount(_ count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while openReturnCount < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(openReturnCount == count)
    }

    func waitUntilIssue(_ issue: PlaybackUserVisibleIssue) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while userVisibleIssue != issue, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(userVisibleIssue == issue)
    }

    func waitUntilIssueIsCleared() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while userVisibleIssue != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(userVisibleIssue == nil)
    }

    private static func projection(
        from projection: PlaybackModel.ProjectionType
    ) -> MediaProjection {
        switch projection {
        case .flat: .flat
        case .equirectangular180: .equirectangular180
        case .equirectangular360: .equirectangular360
        case .customAngle: .customAngle
        }
    }

    private static func stereo(
        from stereo: PlaybackModel.StereoLayout
    ) -> MediaStereoLayout {
        switch stereo {
        case .mono, .multiview: .mono
        case .sideBySide: .sideBySide
        case .topBottom: .topBottom
        }
    }
}
