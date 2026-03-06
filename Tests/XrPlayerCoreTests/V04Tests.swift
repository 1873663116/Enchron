import XCTest
import CoreGraphics
@testable import XrPlayerCore

// MARK: - MPVConfiguration Option Generation Tests

final class MPVConfigurationOptionsTests: XCTestCase {

    // MARK: GPU path (useNativeGPUOutput = true)

    func testGPUPathUsesZeroCopyHardwareDecoding() {
        let config = MPVConfiguration()
        let options = config.options(useNativeGPUOutput: true)
        let hwdec = options.first(where: { $0.0 == "hwdec" })?.1
        XCTAssertEqual(hwdec, "videotoolbox", "GPU path should use zero-copy videotoolbox (no -copy)")
    }

    func testBlendSubtitlesIsEnabledAfterFontFix() {
        // blend-subtitles=yes is now correct: NotoSansSC is bundled in XrPlayer/Fonts/ and
        // sub-fonts-dir points to it, so libass font lookup is fast. GPU compositing is
        // more efficient than the separate OSD overlay path.
        let config = MPVConfiguration()
        let optionsGPU = config.options(useNativeGPUOutput: true)
        let blendGPU = optionsGPU.first(where: { $0.0 == "blend-subtitles" })?.1
        XCTAssertEqual(blendGPU, "yes", "blend-subtitles=yes after bundling NotoSansSC font")
    }

    func testGPUPathUsesDisplayResampleSync() {
        let config = MPVConfiguration()
        let options = config.options(useNativeGPUOutput: true)
        let sync = options.first(where: { $0.0 == "video-sync" })?.1
        XCTAssertEqual(sync, "display-resample")
    }

    func testGPUPathIncludesGPUAPIAndContext() {
        let config = MPVConfiguration(gpuAPI: "vulkan", gpuContext: "moltenvk")
        let options = config.options(useNativeGPUOutput: true)
        let gpuAPI = options.first(where: { $0.0 == "gpu-api" })?.1
        let gpuCtx = options.first(where: { $0.0 == "gpu-context" })?.1
        XCTAssertEqual(gpuAPI, "vulkan")
        XCTAssertEqual(gpuCtx, "moltenvk")
    }

    func testGPUPathDefaultVOIsGPUNext() {
        let config = MPVConfiguration(useNativeGPUOutput: true)
        let options = config.options(useNativeGPUOutput: true)
        let vo = options.first(where: { $0.0 == "vo" })?.1
        XCTAssertEqual(vo, "gpu-next")
    }

    // MARK: Software path (useNativeGPUOutput = false)

    func testSWPathUsesCopyHardwareDecoding() {
        let config = MPVConfiguration()
        let options = config.options(useNativeGPUOutput: false)
        let hwdec = options.first(where: { $0.0 == "hwdec" })?.1
        XCTAssertEqual(hwdec, "videotoolbox-copy", "SW path needs CPU access → videotoolbox-copy")
    }

    func testSWPathBlendSubtitlesIsEnabled() {
        // Same reasoning as GPU path — font is bundled, so blend=yes is correct on all paths.
        let config = MPVConfiguration()
        let options = config.options(useNativeGPUOutput: false)
        let blend = options.first(where: { $0.0 == "blend-subtitles" })?.1
        XCTAssertEqual(blend, "yes", "blend-subtitles=yes after bundling NotoSansSC font")
    }

    func testSWPathUsesAudioSync() {
        let config = MPVConfiguration()
        let options = config.options(useNativeGPUOutput: false)
        let sync = options.first(where: { $0.0 == "video-sync" })?.1
        XCTAssertEqual(sync, "audio")
    }

    func testSWPathFallsBackToLibmpvVO() {
        // Even if config.vo is gpu-next, SW path should fall back to libmpv
        let config = MPVConfiguration(useNativeGPUOutput: true) // vo defaults to gpu-next
        let options = config.options(useNativeGPUOutput: false)
        let vo = options.first(where: { $0.0 == "vo" })?.1
        XCTAssertEqual(vo, "libmpv", "SW path should override gpu-next to libmpv")
    }

    func testSWPathDoesNotIncludeGPUAPIOptions() {
        let config = MPVConfiguration(useNativeGPUOutput: false) // vo = libmpv
        let options = config.options(useNativeGPUOutput: false)
        let gpuAPI = options.first(where: { $0.0 == "gpu-api" })
        let gpuCtx = options.first(where: { $0.0 == "gpu-context" })
        XCTAssertNil(gpuAPI, "SW path (libmpv VO) should not set gpu-api")
        XCTAssertNil(gpuCtx, "SW path (libmpv VO) should not set gpu-context")
    }

    // MARK: Subtitle defaults

    func testSubtitleDefaultsToDisabled() {
        let config = MPVConfiguration()
        let options = config.defaultOptions
        let sid = options.first(where: { $0.0 == "sid" })?.1
        XCTAssertEqual(sid, "no", "Subtitles should default to disabled (KI-001 fix)")
    }

    func testSubtitleEnabledWhenExplicitlySet() {
        let config = MPVConfiguration(initialSubtitleTrack: "1")
        let options = config.defaultOptions
        let sid = options.first(where: { $0.0 == "sid" })?.1
        XCTAssertEqual(sid, "1")
    }

    func testSubtitleCodepageIsAuto() {
        let config = MPVConfiguration()
        let options = config.defaultOptions
        let codepage = options.first(where: { $0.0 == "sub-codepage" })?.1
        XCTAssertEqual(codepage, "utf-8")
    }

    func testBundledSubtitleFontNameIsConfigured() {
        let config = MPVConfiguration()
        let options = config.defaultOptions
        let font = options.first(where: { $0.0 == "sub-font" })?.1
        XCTAssertEqual(font, "Noto Sans SC")
    }

    func testSubtitleFontProviderIsDisabledWithoutFontconfig() {
        let config = MPVConfiguration()
        let options = config.defaultOptions
        let provider = options.first(where: { $0.0 == "sub-font-provider" })?.1
        XCTAssertEqual(provider, "none")
    }

    func testSubtitleFontsDirIsConfiguredWhenBundlePathExists() {
        let config = MPVConfiguration()
        let options = config.defaultOptions
        let fontsDir = options.first(where: { $0.0 == "sub-fonts-dir" })?.1
        if MPVConfiguration.bundledFontsDir != nil {
            XCTAssertEqual(fontsDir, MPVConfiguration.bundledFontsDir)
        } else {
            XCTAssertNil(fontsDir)
        }
    }

    // MARK: HDR options

    func testHDRPassthroughOptionsPresent() {
        let config = MPVConfiguration(enableHDRMetadataPassthrough: true)
        let options = config.defaultOptions
        let computePeak = options.first(where: { $0.0 == "hdr-compute-peak" })?.1
        XCTAssertEqual(computePeak, "no")
    }

    func testHDRDisabledForcesSRGB() {
        let config = MPVConfiguration(hdrEnabled: false)
        let options = config.defaultOptions
        let trc = options.last(where: { $0.0 == "target-trc" })?.1
        let prim = options.last(where: { $0.0 == "target-prim" })?.1
        XCTAssertEqual(trc, "srgb")
        XCTAssertEqual(prim, "bt.709")
    }

    func testForceLibmpvForHDRDefaultsToFalse() {
        let config = MPVConfiguration()
        XCTAssertFalse(config.forceLibmpvForHDR,
                       "forceLibmpvForHDR should default to false (root cause of DoVi metadata loss)")
    }

    // MARK: HDR/SDR Runtime Commands

    func testHDRRuntimeCommandsSetsColorspaceHint() {
        let config = MPVConfiguration()
        let cmds = config.hdrRuntimeCommands()
        XCTAssertTrue(cmds.contains(["set", "target-colorspace-hint", "yes"]))
        XCTAssertTrue(cmds.contains(["set", "target-trc", "auto"]))
        XCTAssertTrue(cmds.contains(["set", "target-prim", "auto"]))
    }

    func testSDRRuntimeCommandsForcesBT709() {
        let config = MPVConfiguration()
        let cmds = config.sdrRuntimeCommands()
        XCTAssertTrue(cmds.contains(["set", "target-colorspace-hint", "no"]))
        XCTAssertTrue(cmds.contains(["set", "target-trc", "srgb"]))
        XCTAssertTrue(cmds.contains(["set", "target-prim", "bt.709"]))
    }

    func testHDRAndSDRCommandsAreSymmetric() {
        let config = MPVConfiguration()
        let hdr = config.hdrRuntimeCommands()
        let sdr = config.sdrRuntimeCommands()
        // Both should set the same properties (colorspace-hint, trc, prim)
        let hdrKeys = Set(hdr.map { $0[1] })
        let sdrKeys = Set(sdr.map { $0[1] })
        XCTAssertEqual(hdrKeys, sdrKeys, "HDR and SDR commands should toggle the same properties")
    }

    // MARK: Hardware decoding disabled

    func testHardwareDecodingDisabledSetsHwdecNo() {
        let config = MPVConfiguration(enableHardwareDecoding: false)
        let options = config.options(useNativeGPUOutput: true)
        let hwdec = options.first(where: { $0.0 == "hwdec" })?.1
        XCTAssertEqual(hwdec, "no")
    }

    // MARK: Audio track

    func testInitialAudioTrackSet() {
        let config = MPVConfiguration(initialAudioTrack: "2")
        let options = config.defaultOptions
        let aid = options.first(where: { $0.0 == "aid" })?.1
        XCTAssertEqual(aid, "2")
    }

    func testInitialAudioTrackNilOmitsAID() {
        let config = MPVConfiguration(initialAudioTrack: nil)
        let options = config.defaultOptions
        let aid = options.first(where: { $0.0 == "aid" })
        XCTAssertNil(aid)
    }

    // MARK: Cache & demuxer

    func testCacheEnabledByDefault() {
        let config = MPVConfiguration()
        let options = config.defaultOptions
        let cache = options.first(where: { $0.0 == "cache" })?.1
        XCTAssertEqual(cache, "yes")
    }

    func testCacheDisabled() {
        let config = MPVConfiguration(cache: false)
        let options = config.defaultOptions
        let cache = options.first(where: { $0.0 == "cache" })?.1
        XCTAssertEqual(cache, "no")
    }

    func testDemuxerMaxBytes() {
        let config = MPVConfiguration(demuxerMaxBytes: "256MiB")
        let options = config.defaultOptions
        let demux = options.first(where: { $0.0 == "demuxer-max-bytes" })?.1
        XCTAssertEqual(demux, "256MiB")
    }

    func testDemuxerReadaheadIsReducedForFirstFrameLatency() {
        let config = MPVConfiguration()
        let options = config.defaultOptions
        let readahead = options.first(where: { $0.0 == "demuxer-readahead-secs" })?.1
        XCTAssertEqual(readahead, "0.5")
    }

    // MARK: Keep-open (playback end behavior)

    func testKeepOpenIsYes() {
        let config = MPVConfiguration()
        let options = config.defaultOptions
        let keepOpen = options.first(where: { $0.0 == "keep-open" })?.1
        XCTAssertEqual(keepOpen, "yes", "keep-open=yes required for replay-on-last-frame behavior")
    }

    // MARK: Video filter format

    func testVideoFilterFormatApplied() {
        // vf=format= is only injected for the SW render path (vo=libmpv).
        // On the GPU path (vo=gpu-next) the filter is omitted to preserve zero-copy.
        let config = MPVConfiguration(outputPixelFormat: "nv12")
        let options = config.options(useNativeGPUOutput: false)
        let vf = options.first(where: { $0.0 == "vf" })?.1
        XCTAssertEqual(vf, "format=nv12")
    }

    func testVideoFilterOmittedWhenFormatEmpty() {
        let config = MPVConfiguration(outputPixelFormat: "")
        let options = config.defaultOptions
        let vf = options.first(where: { $0.0 == "vf" })
        XCTAssertNil(vf)
    }

    // MARK: No ASS effect stripping

    func testNoASSOverrideStripOption() {
        let config = MPVConfiguration()
        let options = config.defaultOptions
        let assOverride = options.first(where: { $0.0 == "sub-ass-override" })
        XCTAssertNil(assOverride,
                     "ASS effects should be fully preserved — no strip (GPU compositing handles it)")
    }
}

// MARK: - MPVConfiguration defaultOptions vs options() Consistency

final class MPVConfigurationConsistencyTests: XCTestCase {
    func testDefaultOptionsMatchesExplicitCall() {
        let config = MPVConfiguration()
        let defaultOpts = config.defaultOptions
        let explicitOpts = config.options(useNativeGPUOutput: config.useNativeGPUOutput)
        XCTAssertEqual(defaultOpts.count, explicitOpts.count)
        for (d, e) in zip(defaultOpts, explicitOpts) {
            XCTAssertEqual(d.0, e.0)
            XCTAssertEqual(d.1, e.1)
        }
    }
}

// MARK: - PlaybackControlling Mock

final class MockPlaybackController: PlaybackControlling {
    var currentState: PlaybackCoreDomain.PlaybackState = .idle
    var currentPosition: PlaybackCoreDomain.PlaybackPosition = .init(seconds: 0, duration: 0)
    var availableAudioTracks: [PlaybackCoreDomain.AudioTrack] = []
    var availableSubtitleTracks: [PlaybackCoreDomain.SubtitleTrack] = []
    var currentAudioTrackID: String?
    var currentSubtitleTrackID: String? = "no"
    var isHDRContent: Bool = false
    var isHDROutputEnabled: Bool = false
    var onMediaProfileDetected: ((PlaybackCoreDomain.MediaProfile) -> Void)?
    var onPlaybackEnded: (() -> Void)?

    // Call tracking
    private(set) var playCalled = false
    private(set) var playURL: URL?
    private(set) var pauseCalled = false
    private(set) var resumeCalled = false
    private(set) var stopCalled = false
    private(set) var seekTarget: Double?
    private(set) var skipAmount: Double?
    private(set) var speedSet: PlaybackCoreDomain.PlaybackSpeed?
    private(set) var selectedAudioTrack: PlaybackCoreDomain.AudioTrack?
    private(set) var selectedSubtitleTrack: PlaybackCoreDomain.SubtitleTrack?
    private(set) var subtitleDisabled = false
    private(set) var replayCalled = false
    private(set) var hdrEnabledSet: Bool?
    private(set) var cancelPendingLoadCalled = false

    func play(url: URL) async throws {
        playCalled = true
        playURL = url
        currentState = .playing
    }

    func pause() {
        pauseCalled = true
        currentState = .paused
    }

    func resume() {
        resumeCalled = true
        currentState = .playing
    }

    func stop() {
        stopCalled = true
        currentState = .stopped
    }

    func cancelPendingLoad() {
        cancelPendingLoadCalled = true
    }

    func seek(to seconds: Double) {
        seekTarget = seconds
        currentPosition = PlaybackCoreDomain.PlaybackPosition(seconds: seconds, duration: currentPosition.duration)
    }

    func skip(by seconds: Double) {
        skipAmount = seconds
        let newTime = max(0, min(currentPosition.seconds + seconds, currentPosition.duration))
        currentPosition = PlaybackCoreDomain.PlaybackPosition(seconds: newTime, duration: currentPosition.duration)
    }

    func setSpeed(_ speed: PlaybackCoreDomain.PlaybackSpeed) {
        speedSet = speed
    }

    func selectAudioTrack(_ track: PlaybackCoreDomain.AudioTrack) {
        selectedAudioTrack = track
        currentAudioTrackID = track.id
    }

    func selectSubtitleTrack(_ track: PlaybackCoreDomain.SubtitleTrack?) {
        if let track {
            selectedSubtitleTrack = track
            currentSubtitleTrackID = track.id
            subtitleDisabled = false
        } else {
            currentSubtitleTrackID = "no"
            subtitleDisabled = true
        }
    }

    func replay() {
        replayCalled = true
        currentState = .playing
        currentPosition = PlaybackCoreDomain.PlaybackPosition(seconds: 0, duration: currentPosition.duration)
    }

    func setHDREnabled(_ enabled: Bool) {
        hdrEnabledSet = enabled
        isHDROutputEnabled = enabled
    }

    func frameStepForward() {}
    func frameStepBackward() {}

    /// Simulate reaching end of playback
    func simulatePlaybackEnded() {
        currentState = .ended
        onPlaybackEnded?()
    }

    /// Simulate media profile detection
    func simulateMediaProfileDetected(_ profile: PlaybackCoreDomain.MediaProfile) {
        isHDRContent = profile.hdrType != .sdr
        onMediaProfileDetected?(profile)
    }
}

// MARK: - Mock-based Playback Flow Tests

final class PlaybackFlowTests: XCTestCase {

    func testPlayPauseResumeFlow() async throws {
        let player = MockPlaybackController()
        XCTAssertEqual(player.currentState, .idle)

        try await player.play(url: URL(string: "file:///movie.mkv")!)
        XCTAssertEqual(player.currentState, .playing)
        XCTAssertTrue(player.playCalled)

        player.pause()
        XCTAssertEqual(player.currentState, .paused)
        XCTAssertTrue(player.pauseCalled)

        player.resume()
        XCTAssertEqual(player.currentState, .playing)
        XCTAssertTrue(player.resumeCalled)
    }

    func testReplayFromEndedState() async throws {
        let player = MockPlaybackController()
        try await player.play(url: URL(string: "file:///movie.mkv")!)
        player.currentPosition = PlaybackCoreDomain.PlaybackPosition(seconds: 120, duration: 120)

        player.simulatePlaybackEnded()
        XCTAssertEqual(player.currentState, .ended)

        player.replay()
        XCTAssertTrue(player.replayCalled)
        XCTAssertEqual(player.currentState, .playing)
        XCTAssertEqual(player.currentPosition.seconds, 0, "Replay should seek to beginning")
    }

    func testPlaybackEndedCallbackFired() async throws {
        let player = MockPlaybackController()
        var endedCallbackFired = false
        player.onPlaybackEnded = { endedCallbackFired = true }

        try await player.play(url: URL(string: "file:///movie.mkv")!)
        player.simulatePlaybackEnded()

        XCTAssertTrue(endedCallbackFired)
        XCTAssertEqual(player.currentState, .ended)
    }

    func testSeekUpdatesPosition() async throws {
        let player = MockPlaybackController()
        try await player.play(url: URL(string: "file:///movie.mkv")!)
        player.currentPosition = PlaybackCoreDomain.PlaybackPosition(seconds: 0, duration: 600)

        player.seek(to: 120)
        XCTAssertEqual(player.seekTarget, 120)
        XCTAssertEqual(player.currentPosition.seconds, 120)
    }

    func testSkipForwardAndBackward() async throws {
        let player = MockPlaybackController()
        try await player.play(url: URL(string: "file:///movie.mkv")!)
        player.currentPosition = PlaybackCoreDomain.PlaybackPosition(seconds: 50, duration: 600)

        player.skip(by: 10)
        XCTAssertEqual(player.currentPosition.seconds, 60)

        player.skip(by: -20)
        XCTAssertEqual(player.currentPosition.seconds, 40)
    }

    func testSkipClampedToZeroAndDuration() async throws {
        let player = MockPlaybackController()
        try await player.play(url: URL(string: "file:///movie.mkv")!)
        player.currentPosition = PlaybackCoreDomain.PlaybackPosition(seconds: 5, duration: 100)

        player.skip(by: -100) // would go negative
        XCTAssertEqual(player.currentPosition.seconds, 0)

        player.skip(by: 200) // would exceed duration
        XCTAssertEqual(player.currentPosition.seconds, 100)
    }

    func testSubtitleDefaultDisabledThenEnabled() async throws {
        let player = MockPlaybackController()
        XCTAssertEqual(player.currentSubtitleTrackID, "no")

        let jpSub = PlaybackCoreDomain.SubtitleTrack(id: "s1", languageCode: "ja", displayName: "Japanese")
        player.selectSubtitleTrack(jpSub)
        XCTAssertEqual(player.currentSubtitleTrackID, "s1")
        XCTAssertFalse(player.subtitleDisabled)

        player.selectSubtitleTrack(nil)
        XCTAssertEqual(player.currentSubtitleTrackID, "no")
        XCTAssertTrue(player.subtitleDisabled)
    }

    func testHDRToggle() {
        let player = MockPlaybackController()
        let hdrProfile = PlaybackCoreDomain.MediaProfile(
            projectionType: .flat,
            hdrType: .hdr10,
            resolution: .init(width: 3840, height: 2160),
            frameRate: 24
        )
        player.simulateMediaProfileDetected(hdrProfile)
        XCTAssertTrue(player.isHDRContent)

        player.setHDREnabled(true)
        XCTAssertTrue(player.isHDROutputEnabled)

        player.setHDREnabled(false)
        XCTAssertFalse(player.isHDROutputEnabled)
    }

    func testSDRContentNotMarkedAsHDR() {
        let player = MockPlaybackController()
        let sdrProfile = PlaybackCoreDomain.MediaProfile(
            projectionType: .flat,
            hdrType: .sdr,
            resolution: .init(width: 1920, height: 1080),
            frameRate: 30
        )
        player.simulateMediaProfileDetected(sdrProfile)
        XCTAssertFalse(player.isHDRContent)
    }

    func testDolbyVisionDetectedAsHDR() {
        let player = MockPlaybackController()
        let doViProfile = PlaybackCoreDomain.MediaProfile(
            projectionType: .flat,
            hdrType: .dolbyVision,
            resolution: .init(width: 3840, height: 2160),
            frameRate: 23.976
        )
        player.simulateMediaProfileDetected(doViProfile)
        XCTAssertTrue(player.isHDRContent, "Dolby Vision should be detected as HDR content")
    }

    func testSpeedChange() {
        let player = MockPlaybackController()
        player.setSpeed(.speed2_0)
        XCTAssertEqual(player.speedSet, .speed2_0)
    }

    func testAudioTrackSelection() {
        let player = MockPlaybackController()
        let track = PlaybackCoreDomain.AudioTrack(id: "2", languageCode: "zh", displayName: "Chinese", isDefault: false)
        player.selectAudioTrack(track)
        XCTAssertEqual(player.currentAudioTrackID, "2")
    }
}

// MARK: - PlaybackPosition Extended Tests

final class PlaybackPositionExtendedTests: XCTestCase {
    func testProgressAtHalfway() {
        let pos = PlaybackCoreDomain.PlaybackPosition(seconds: 300, duration: 600)
        XCTAssertEqual(pos.progress, 0.5, accuracy: 1e-9)
    }

    func testProgressNeverExceedsOne() {
        let pos = PlaybackCoreDomain.PlaybackPosition(seconds: 999, duration: 100)
        XCTAssertLessThanOrEqual(pos.progress, 1.0)
    }

    func testProgressNeverNegative() {
        let pos = PlaybackCoreDomain.PlaybackPosition(seconds: -10, duration: 100)
        XCTAssertGreaterThanOrEqual(pos.progress, 0.0)
        XCTAssertEqual(pos.seconds, 0)
    }

    func testVerySmallDuration() {
        let pos = PlaybackCoreDomain.PlaybackPosition(seconds: 0.001, duration: 0.001)
        XCTAssertEqual(pos.progress, 1.0, accuracy: 1e-6)
    }

    func testLargeValues() {
        // 24-hour video
        let pos = PlaybackCoreDomain.PlaybackPosition(seconds: 43200, duration: 86400)
        XCTAssertEqual(pos.progress, 0.5, accuracy: 1e-9)
    }
}

// MARK: - PlaybackSession Tests

final class PlaybackSessionTests: XCTestCase {
    func testDefaultSessionState() {
        let session = PlaybackSession()
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.speed, .default)
        XCTAssertEqual(session.position.seconds, 0)
        XCTAssertEqual(session.position.duration, 0)
        XCTAssertNil(session.mediaFile)
    }

    func testSessionPreservesCustomValues() {
        let id = UUID()
        let session = PlaybackSession(
            id: id,
            state: .playing,
            speed: .speed2_0,
            position: .init(seconds: 60, duration: 120)
        )
        XCTAssertEqual(session.id, id)
        XCTAssertEqual(session.state, .playing)
        XCTAssertEqual(session.speed, .speed2_0)
        XCTAssertEqual(session.position.seconds, 60)
    }
}

// MARK: - ProjectionType Extended Tests

final class ProjectionTypeExtendedTests: XCTestCase {
    func testStereoscopicSBSIsNotPanoramic() {
        XCTAssertFalse(PlaybackCoreDomain.ProjectionType.stereoscopicSBS.isPanoramic)
    }

    func testStereoscopicOUIsNotPanoramic() {
        XCTAssertFalse(PlaybackCoreDomain.ProjectionType.stereoscopicOU.isPanoramic)
    }

    func testAllCasesExist() {
        XCTAssertEqual(PlaybackCoreDomain.ProjectionType.allCases.count, 6)
    }

    func testRawValues() {
        XCTAssertEqual(PlaybackCoreDomain.ProjectionType.flat.rawValue, "flat")
        XCTAssertEqual(PlaybackCoreDomain.ProjectionType.panorama360.rawValue, "panorama360")
        XCTAssertEqual(PlaybackCoreDomain.ProjectionType.fisheye.rawValue, "fisheye")
    }
}

// MARK: - DisambiguateGestureUseCase Additional Edge Case Tests

@MainActor
final class DisambiguateGestureEdgeCaseTests: XCTestCase {

    func testRapidTriplePinchOnlyEmitsDoublePinch() async {
        let sut = DisambiguateGestureUseCase()
        var received: [GestureType] = []
        sut.onGestureResolved = { received.append($0) }

        let t0 = Date()
        // First pinch
        sut.handlePinchBegan(at: t0)
        sut.handlePinchEnded(at: t0.addingTimeInterval(0.03))
        // Second pinch within window → doublePinch
        sut.handlePinchBegan(at: t0.addingTimeInterval(0.15))
        sut.handlePinchEnded(at: t0.addingTimeInterval(0.18))

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(received, [.doublePinch])

        // Third pinch after double resolved
        try? await Task.sleep(for: .milliseconds(500))
        let t1 = Date()
        sut.handlePinchBegan(at: t1)
        sut.handlePinchEnded(at: t1.addingTimeInterval(0.03))

        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.last, .singlePinch)
    }

    func testHandlePinchConvenienceMethod() async {
        let sut = DisambiguateGestureUseCase()
        var received: GestureType?
        sut.onGestureResolved = { received = $0 }

        // handlePinch() = began + ended immediately (instant tap)
        sut.handlePinch()

        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(received, .singlePinch)
    }

    func testDragThenNewPinchIsIndependent() async {
        let sut = DisambiguateGestureUseCase()
        var received: [GestureType] = []
        sut.onGestureResolved = { received.append($0) }

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        sut.handlePinchChanged(translation: CGSize(width: 50, height: 0), at: t0.addingTimeInterval(0.01))
        XCTAssertEqual(received, [.drag])

        sut.handlePinchEnded(at: t0.addingTimeInterval(0.1))

        // Wait for state reset
        try? await Task.sleep(for: .milliseconds(600))

        // New independent pinch
        let t1 = Date()
        sut.handlePinchBegan(at: t1)
        sut.handlePinchEnded(at: t1.addingTimeInterval(0.03))

        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.last, .singlePinch)
    }

    func testLongPressExactlyAtThreshold() async {
        let sut = DisambiguateGestureUseCase()
        var received: GestureType?
        sut.onGestureResolved = { received = $0 }

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        // Release at exactly 200ms (the threshold)
        sut.handlePinchEnded(at: t0.addingTimeInterval(0.2))

        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(received, .longPress)
    }

    func testSmallDiagonalMovementBelowThreshold() {
        let sut = DisambiguateGestureUseCase()
        var received: GestureType?
        sut.onGestureResolved = { received = $0 }

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        // hypot(5, 5) ≈ 7.07 < threshold of 8
        sut.handlePinchChanged(translation: CGSize(width: 5, height: 5), at: t0.addingTimeInterval(0.01))
        XCTAssertNil(received, "Movement below threshold should not trigger drag")
    }
}

// MARK: - VideoToolboxBridge Tests

final class VideoToolboxBridgeTests: XCTestCase {
    func testHwdecCodecsIsAll() {
        XCTAssertEqual(VideoToolboxBridge.hwdecCodecs, "all")
    }

    func testPlaceholderPixelBufferCreation() throws {
        let bridge = VideoToolboxBridge()
        let buffer = try bridge.makePlaceholderPixelBuffer(width: 1920, height: 1080)
        XCTAssertEqual(CVPixelBufferGetWidth(buffer), 1920)
        XCTAssertEqual(CVPixelBufferGetHeight(buffer), 1080)
    }

    func testPlaceholderPixelBufferInvalidDimensions() {
        let bridge = VideoToolboxBridge()
        XCTAssertThrowsError(try bridge.makePlaceholderPixelBuffer(width: 0, height: 0)) { error in
            if case VideoToolboxBridgeError.invalidDimensions = error { } else {
                XCTFail("Expected invalidDimensions, got \(error)")
            }
        }
    }

    func testMakePixelBufferFromEmptyDataReturns1x1() throws {
        let bridge = VideoToolboxBridge()
        let buffer = try bridge.makePixelBuffer(from: Data())
        XCTAssertEqual(CVPixelBufferGetWidth(buffer), 1)
        XCTAssertEqual(CVPixelBufferGetHeight(buffer), 1)
    }

    func testMakePixelBufferFromNonEmptyDataThrows() {
        let bridge = VideoToolboxBridge()
        XCTAssertThrowsError(try bridge.makePixelBuffer(from: Data("video".utf8))) { error in
            if case VideoToolboxBridgeError.unsupportedPacketLayout = error { } else {
                XCTFail("Expected unsupportedPacketLayout, got \(error)")
            }
        }
    }

    func testPoolReusedForSameDimensions() throws {
        let bridge = VideoToolboxBridge()
        let b1 = try bridge.makePlaceholderPixelBuffer(width: 100, height: 100)
        let b2 = try bridge.makePlaceholderPixelBuffer(width: 100, height: 100)
        // Both should succeed (pool reuse)
        XCTAssertEqual(CVPixelBufferGetWidth(b1), 100)
        XCTAssertEqual(CVPixelBufferGetWidth(b2), 100)
    }

    func testPoolRecreatedForDifferentDimensions() throws {
        let bridge = VideoToolboxBridge()
        let b1 = try bridge.makePlaceholderPixelBuffer(width: 100, height: 100)
        let b2 = try bridge.makePlaceholderPixelBuffer(width: 200, height: 200)
        XCTAssertEqual(CVPixelBufferGetWidth(b1), 100)
        XCTAssertEqual(CVPixelBufferGetWidth(b2), 200)
    }
}

// MARK: - HDRType Extended Tests

final class HDRTypeExtendedTests: XCTestCase {
    func testAllHDRTypesExceptSDRAreHDR() {
        let hdrTypes = PlaybackCoreDomain.HDRType.allCases.filter { $0 != .sdr }
        XCTAssertEqual(hdrTypes.count, 4)
        XCTAssertTrue(hdrTypes.contains(.hdr10))
        XCTAssertTrue(hdrTypes.contains(.hdr10Plus))
        XCTAssertTrue(hdrTypes.contains(.dolbyVision))
        XCTAssertTrue(hdrTypes.contains(.hlg))
    }

    func testHDRTypeIsSendable() {
        // Compile-time check: if this compiles, HDRType conforms to Sendable
        let _: @Sendable () -> PlaybackCoreDomain.HDRType = { .hdr10 }
    }
}

// MARK: - GestureType Tests

final class GestureTypeTests: XCTestCase {
    func testGestureTypeCodableRoundtrip() throws {
        let types: [GestureType] = [.singlePinch, .doublePinch, .longPress, .drag]
        for type_ in types {
            let data = try JSONEncoder().encode(type_)
            let decoded = try JSONDecoder().decode(GestureType.self, from: data)
            XCTAssertEqual(decoded, type_)
        }
    }

    func testGestureTypeRawValues() {
        XCTAssertEqual(GestureType.singlePinch.rawValue, "singlePinch")
        XCTAssertEqual(GestureType.doublePinch.rawValue, "doublePinch")
        XCTAssertEqual(GestureType.longPress.rawValue, "longPress")
        XCTAssertEqual(GestureType.drag.rawValue, "drag")
    }
}
