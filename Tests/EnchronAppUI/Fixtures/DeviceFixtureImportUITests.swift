import ImageIO
import Vision
import XCTest

nonisolated final class DeviceFixtureImportUITests: XCTestCase {
    private let baselineFixtureName = "sdr-bframe-multiaudio-avsync-30s.mp4"
    private let baselineFixturePickerLabel = "sdr-bframe-multiaudio-avsync-30s"
    private let externalSubRipFixtureName =
        "sdr-bframe-multiaudio-avsync-30s.zh-CN.srt"
    private let externalASSFixtureName =
        "sdr-bframe-multiaudio-avsync-30s.styled.ass"
    private let multitrackFixtureName =
        "sdr-bframe-multiaudio-subtitles-30s.mkv"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLocalMediaReferenceCanBeRemovedAndReadded() throws {
        let app = launchMediaLibrary()
        let importedCard = app.descendants(matching: .any)[
            "MediaLibrary-grid-video-\(baselineFixtureName)"
        ].firstMatch
        if importedCard.waitForExistence(timeout: 3) {
            guard removeMediaReference(importedCard, in: app) else { return }
        }
        XCTAssertTrue(importedCard.waitForNonExistence(timeout: 10))
        guard addBaselineFile(using: importedCard, in: app) else { return }

        importedCard.tap()
        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        guard let first = waitForState(controlPlane, timeout: 30, where: {
            $0.string("lifecycle")?.lowercased() == "playing"
                && ($0.double("actualRate") ?? 0) > 0.5
                && $0.bool("displayedPixel") == true
                && ($0.uint64("videoSamples") ?? 0) > 0
                && ($0.uint64("rendererInputs") ?? 0) > 0
        }) else {
            attachScreenshot(from: app, name: "04-imported-fixture-playback-failure")
            XCTFail("The imported fixture did not produce sustained wearer-visible playback evidence.")
            return
        }
        guard requireContinuousPlayback(
            after: first,
            in: controlPlane,
            app: app,
            name: "media-reference-01-first-playback"
        ) != nil else { return }
        XCTAssertFalse(app.alerts["Failed to Load"].exists)

        let back = app.buttons["PlayerUI-InfoBar-button-back"].firstMatch
        guard requireHittable(back, named: "Back to Media Library") else { return }
        back.tap()
        XCTAssertTrue(importedCard.waitForExistence(timeout: 20))
        guard removeMediaReference(importedCard, in: app) else { return }
        XCTAssertTrue(
            importedCard.waitForNonExistence(timeout: 10),
            "Removing the Media Reference must remove only its Media Library card."
        )
        attachScreenshot(from: app, name: "media-reference-02-removed")

        guard addBaselineFile(using: importedCard, in: app) else { return }
        attachScreenshot(from: app, name: "media-reference-03-readded")
        importedCard.tap()
        let reopened = try XCTUnwrap(waitForState(controlPlane, timeout: 30) {
            $0.string("lifecycle")?.lowercased() == "playing"
                && $0.bool("displayedPixel") == true
                && $0.string("session") != first.string("session")
        })
        guard requireContinuousPlayback(
            after: reopened,
            in: controlPlane,
            app: app,
            name: "media-reference-04-readded-playback"
        ) != nil else { return }
    }

    @MainActor
    func testOpeningMediaAutomaticallyAssociatesSiblingSubtitles() throws {
        let app = launchMediaLibrary()
        let importedCard = app.descendants(matching: .any)[
            "MediaLibrary-grid-video-\(baselineFixtureName)"
        ].firstMatch
        guard ensureGeneratedFolderImported(for: importedCard, in: app) else { return }
        importedCard.tap()

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        guard let discovered = waitForState(controlPlane, timeout: 30, where: {
            $0.string("lifecycle")?.lowercased() == "playing"
                && $0.bool("displayedPixel") == true
                && ($0.uint64("subtitleTracks") ?? 0) >= 2
                && $0.string("subtitleTrack") == "off"
        }) else {
            attachScreenshot(from: app, name: "02-automatic-subtitle-association-failure")
            XCTFail(
                "The two matching sidecar files were not added as distinct unselected tracks."
            )
            return
        }

        openWindowSubtitleMenu(in: app)
        XCTAssertNotNil(
            waitForHittableElement(
                matchingAnyLabel: [externalSubRipFixtureName],
                in: app,
                timeout: 5
            ),
            "The automatically associated SubRip file is missing from Subtitles."
        )
        let assTrack = waitForHittableElement(
            matchingAnyLabel: [externalASSFixtureName],
            in: app,
            timeout: 5
        )
        XCTAssertNotNil(
            assTrack,
            "The automatically associated ASS file is missing from Subtitles."
        )
        guard requireContinuousPlayback(
            after: discovered,
            in: controlPlane,
            app: app,
            name: "automatic-subtitle-association-remains-playing"
        ) != nil else { return }
        XCTAssertEqual(discovered.string("subtitleTrack"), "off")
        attachScreenshot(from: app, name: "automatic-subtitle-candidates-and-off")
    }

    @MainActor
    func testSelectingAndDisablingSubtitlesPreservesMediaSession() throws {
        let app = launchMediaLibrary()
        let importedCard = app.descendants(matching: .any)[
            "MediaLibrary-grid-video-\(baselineFixtureName)"
        ].firstMatch
        guard ensureGeneratedFolderImported(for: importedCard, in: app) else { return }
        importedCard.tap()

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        guard let discovered = waitForState(controlPlane, timeout: 30, where: {
            $0.string("lifecycle")?.lowercased() == "playing"
                && $0.bool("displayedPixel") == true
                && ($0.uint64("subtitleTracks") ?? 0) >= 2
                && $0.string("subtitleTrack") == "off"
        }) else {
            attachScreenshot(from: app, name: "01-automatic-subrip-discovery-failure")
            XCTFail("The matching external subtitle files were not available for selection.")
            return
        }

        openWindowSubtitleMenu(in: app)
        let subRipTrack = waitForHittableElement(
            matchingAnyLabel: [externalSubRipFixtureName],
            in: app,
            timeout: 5
        )
        XCTAssertNotNil(subRipTrack, "The automatically associated SubRip track is missing.")
        subRipTrack?.tap()

        guard let selected = waitForState(controlPlane, timeout: 10, where: {
            $0.string("session") == discovered.string("session")
                && $0.string("lifecycle")?.lowercased() == "playing"
                && $0.string("subtitleTrack") != "off"
                && ($0.uint64("subtitleCues") ?? 0) > 0
        }) else {
            attachScreenshot(from: app, name: "02-automatic-subrip-selection-failure")
            XCTFail("Selecting the associated SubRip track did not expose an active cue.")
            return
        }
        XCTAssertEqual(selected.string("session"), discovered.string("session"))
        XCTAssertTrue(
            waitForAccessibilityValue(
                app.descendants(matching: .any)["PlayerUI-active-subtitles"].firstMatch,
                containing: "Enchron 字幕验证",
                timeout: 5
            ),
            "The active subtitle surface did not receive the Chinese SubRip cue."
        )
        try assertScreenshot(
            from: app,
            containsText: "字幕验证",
            attachmentName: "subtitle-selection-01-subrip-chinese-rendered"
        )

        openWindowSubtitleMenu(in: app)
        let assTrack = waitForHittableElement(
            matchingAnyLabel: [externalASSFixtureName],
            in: app,
            timeout: 5
        )
        XCTAssertNotNil(assTrack, "The automatically associated ASS track is missing.")
        assTrack?.tap()
        guard let selectedASS = waitForState(controlPlane, timeout: 10, where: {
            $0.string("session") == discovered.string("session")
                && $0.string("lifecycle")?.lowercased() == "playing"
                && $0.string("subtitleTrack") != "off"
                && $0.string("subtitleTrack") != selected.string("subtitleTrack")
                && ($0.uint64("subtitleCues") ?? 0) > 0
        }) else { return }
        XCTAssertTrue(
            waitForAccessibilityValue(
                app.descendants(matching: .any)["PlayerUI-active-subtitles"].firstMatch,
                containing: "Enchron GPU PIXEL PROOF",
                timeout: 5
            )
        )
        attachState(selectedASS, name: "subtitle-selection-02-ass-selected")
        attachScreenshot(from: app, name: "subtitle-selection-02-ass-selected")

        openWindowSubtitleMenu(in: app)
        let off = waitForHittableElement(matchingAnyLabel: ["Off"], in: app, timeout: 5)
        XCTAssertNotNil(off, "Subtitles did not expose Off.")
        off?.tap()
        guard let disabled = waitForState(controlPlane, timeout: 8, where: {
            $0.string("session") == discovered.string("session")
                && $0.string("subtitleTrack") == "off"
                && $0.uint64("subtitleCues") == 0
                && $0.string("lifecycle")?.lowercased() == "playing"
        }) else { return }
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-active-subtitles"].exists)
        XCTAssertFalse(app.alerts["Subtitle Error"].exists)
        attachState(disabled, name: "subtitle-selection-03-off")
        attachScreenshot(from: app, name: "subtitle-selection-03-off")
        attachHumanReviewBoundary(
            "Review the clear frames for Chinese glyph integrity, ASS styling and placement, readable contrast, and complete disappearance after Off.",
            name: "subtitle-selection-human-review-boundary"
        )
    }

    @MainActor
    func testReopeningMediaRestoresTrackSelections() throws {
        let app = launchMediaLibrary()
        let mediaCard = app.descendants(matching: .any)[
            "MediaLibrary-grid-video-\(multitrackFixtureName)"
        ].firstMatch
        guard ensureGeneratedFolderImported(for: mediaCard, in: app) else { return }
        mediaCard.tap()

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let firstSession = try XCTUnwrap(waitForState(controlPlane, timeout: 30) {
            $0.string("lifecycle")?.lowercased() == "playing"
                && $0.bool("displayedPixel") == true
                && $0.uint64("audioTracks") == 2
                && $0.uint64("subtitleTracks") == 3
        })

        openWindowMenu(named: "Audio Track", in: app)
        let secondAudioTrack = waitForHittableElement(
            matchingAnyLabel: ["Track 2"],
            in: app,
            timeout: 5
        )
        XCTAssertNotNil(secondAudioTrack, "The second registered audio track was missing.")
        secondAudioTrack?.tap()
        let selectedAudio = try XCTUnwrap(waitForState(controlPlane, timeout: 10) {
            $0.string("session") == firstSession.string("session")
                && $0.string("audioTrack") == "2"
        })
        guard let selectedAudioContinuous = requireContinuousPlayback(
            after: selectedAudio,
            in: controlPlane,
            app: app,
            name: "track-preferences-second-audio-output"
        ) else { return }
        assertMechanicalAudioOutputAdvanced(
            from: selectedAudio,
            to: selectedAudioContinuous,
            context: "Selected second audio track"
        )

        openWindowSubtitleMenu(in: app)
        let chineseSubRip = waitForHittableElement(
            matchingAnyLabel: ["Enchron acceptance subtitles"],
            in: app,
            timeout: 5
        )
        XCTAssertNotNil(chineseSubRip, "The registered Chinese SubRip track was missing.")
        chineseSubRip?.tap()
        let selectedSubtitle = try XCTUnwrap(waitForState(controlPlane, timeout: 10) {
            $0.string("session") == firstSession.string("session")
                && $0.string("audioTrack") == selectedAudio.string("audioTrack")
                && $0.string("subtitleTrack") == "ffmpeg.subtitle.3"
                && ($0.uint64("subtitleCues") ?? 0) > 0
        })
        try assertScreenshot(
            from: app,
            containsText: "字幕验证",
            attachmentName: "01-track-preferences-selected"
        )

        try closeAndReopen(
            mediaIdentifier: "MediaLibrary-grid-video-\(multitrackFixtureName)",
            controlPlane: controlPlane,
            in: app
        )
        let restored = try XCTUnwrap(waitForState(controlPlane, timeout: 30) {
            $0.string("session") != selectedSubtitle.string("session")
                && $0.string("lifecycle")?.lowercased() == "playing"
                && $0.bool("displayedPixel") == true
                && $0.string("audioTrack") == "2"
                && $0.string("subtitleTrack") == "ffmpeg.subtitle.3"
                && ($0.uint64("subtitleCues") ?? 0) > 0
        })
        try assertScreenshot(
            from: app,
            containsText: "字幕验证",
            attachmentName: "02-track-preferences-restored"
        )

        openWindowSubtitleMenu(in: app)
        let off = waitForHittableElement(matchingAnyLabel: ["Off"], in: app, timeout: 5)
        XCTAssertNotNil(off, "The explicit subtitle Off choice was missing.")
        off?.tap()
        _ = try XCTUnwrap(waitForState(controlPlane, timeout: 10) {
            $0.string("session") == restored.string("session")
                && $0.string("audioTrack") == "2"
                && $0.string("subtitleTrack") == "off"
                && $0.uint64("subtitleCues") == 0
        })

        try closeAndReopen(
            mediaIdentifier: "MediaLibrary-grid-video-\(multitrackFixtureName)",
            controlPlane: controlPlane,
            in: app
        )
        let subtitleOffRestored = try XCTUnwrap(waitForState(controlPlane, timeout: 30) {
            $0.string("session") != restored.string("session")
                && $0.string("lifecycle")?.lowercased() == "playing"
                && $0.bool("displayedPixel") == true
                && $0.bool("componentReady") == true
                && $0.bool("videoVisible") == true
                && $0.uint64("boundVideoComponentRevision")
                    == $0.uint64("videoComponentRevision")
                && $0.uint64("rendererPixelVideoComponentRevision")
                    == $0.uint64("videoComponentRevision")
                && $0.uint64("rendererPixelStreamEpoch")
                    == $0.uint64("streamEpoch")
                && $0.string("audioTrack") == "2"
                && $0.string("subtitleTrack") == "off"
                && $0.uint64("subtitleCues") == 0
        })
        attachState(subtitleOffRestored, name: "03-subtitle-off-restored-state")
        try assertGeneratedColorBarsBecomeVisible(
            in: app,
            timeout: 10,
            attachmentName: "03-subtitle-off-restored"
        )
        attachHumanReviewBoundary(
            "Mechanical state proves that the second audio track remained selected and produced renderer samples. "
                + "Confirm its registered distinct pulse frequency through calibrated acoustic evidence; "
                + "also review restored subtitle pixels and Off disappearance.",
            name: "track-selection-restoration-human-review-boundary"
        )
    }

    @MainActor
    func testH264AutomaticSourcePlaybackOnVisionPro() throws {
        let expectation = AutomaticSourceExpectation(
            filename: "sdr-bframe-multiaudio-avsync-30s.mp4",
            pickerPath: ["TestVectors", "Enchron", "PlaybackBehavior"],
            pickerLabels: ["sdr-bframe-multiaudio-avsync-30s"],
            evidenceSlug: "matrix-h264",
            sourceContentKind: "rectilinear",
            projection: "flat",
            stereoLayout: "mono",
            presentation: "window",
            contentType: "mono",
            formatSignalingProjectionKind: nil,
            actualViewingMode: "mono",
            actualImmersiveMode: nil,
            actualSpatialVideoMode: "screen",
            isMVHEVC: false,
            compressedFormat: .init(
                providerCodecName: "h264",
                providerCodecTag: "avc1",
                sampleMediaSubtype: "avc1"
            )
        )
        let source = try openAutomaticSourcePlayback(expectation)
        let rewound = try performTransportSeek(
            source,
            direction: .rewind,
            evidenceSlug: "matrix-h264-03-rewind"
        )
        let transportVerified = try performTransportSeek(
            rewound,
            direction: .forward,
            evidenceSlug: "matrix-h264-04-forward"
        )
        var audio = try captureAudioSentinel(
            transportVerified.state,
            context: "H264 after progress and transport seeks"
        )
        let overridden180 = try applyWindowPanoramaOverride(
            transportVerified,
            override: .halfEquirectangular,
            sourceContentKind: expectation.sourceContentKind,
            evidenceSlug: "matrix-h264-05-180-override"
        )
        audio = try requireAudioPipelineContinues(
            from: audio,
            through: overridden180.state,
            context: "H264 180 override"
        )
        let flatEscape = try escapePanoramaToFlatMonoWindow(
            overridden180,
            sourceContentKind: expectation.sourceContentKind,
            evidenceSlug: "matrix-h264-06-flat-window-escape"
        )
        audio = try requireAudioSentinelContinues(
            from: audio,
            through: flatEscape.state,
            context: "H264 Flat Mono escape"
        )
        let restored = try restoreAutomaticFormat(
            from: flatEscape,
            expectation: expectation,
            evidenceSlug: "matrix-h264-07-automatic-restored"
        )
        _ = try requireAudioSentinelContinues(
            from: audio,
            through: restored.state,
            context: "H264 Automatic restore"
        )
        _ = try reopenAndVerifyAutomaticSource(
            after: restored,
            expectation: expectation,
            evidenceSlug: "matrix-h264-08-reopened-source"
        )
    }

    @MainActor
    func testHDR10AutomaticSourcePlaybackOnVisionPro() throws {
        _ = try openAutomaticSourcePlayback(
            .init(
                filename: "HDR10.MP4",
                pickerPath: ["Samples", "DynamicRange", "HDR10"],
                pickerLabels: ["HDR10", "HDR10.MP4"],
                evidenceSlug: "matrix-hdr10",
                sourceContentKind: "rectilinear",
                projection: "flat",
                stereoLayout: "mono",
                presentation: "window",
                contentType: "mono",
                formatSignalingProjectionKind: nil,
                actualViewingMode: "mono",
                actualImmersiveMode: nil,
                actualSpatialVideoMode: "screen",
                isMVHEVC: false,
                compressedFormat: .init(
                    providerCodecName: "hevc",
                    providerCodecTag: "hvc1",
                    sampleMediaSubtype: "hvc1",
                    providerTransferToken: "2084",
                    sampleTransferToken: "2084",
                    requiredProviderConfigurationAtoms: ["hvcC"]
                )
            )
        )
    }

    @MainActor
    func testOfficialMVHEVCAutomaticMonoOverrideAndRestoreOnVisionPro() throws {
        let expectation = AutomaticSourceExpectation(
            filename: "spatial_lighthouse_flowers_waves_short.mov",
            pickerPath: ["Samples", "Spatial", "MVHEVC-Apple-Official"],
            pickerLabels: [
                "spatial_lighthouse_flowers_waves_short",
                "spatial_lighthouse_flowers_waves_short.mov"
            ],
            evidenceSlug: "matrix-mvhevc",
            sourceContentKind: "spatialVideo",
            projection: "flat",
            stereoLayout: "multiview",
            presentation: "window",
            contentType: "stereo",
            formatSignalingProjectionKind: nil,
            actualViewingMode: "stereo",
            actualImmersiveMode: nil,
            actualSpatialVideoMode: "spatial",
            isMVHEVC: true,
            compressedFormat: nil
        )
        let source = try openAutomaticSourcePlayback(expectation)
        let overridden = try applyWindowFlatMonoOverride(
            source,
            sourceContentKind: expectation.sourceContentKind,
            evidenceSlug: "matrix-mvhevc-03-mono-override"
        )
        _ = try restoreAutomaticFormat(
            from: overridden,
            expectation: expectation,
            evidenceSlug: "matrix-mvhevc-04-automatic-restored"
        )
    }

    @MainActor
    func testAPMP180AutomaticSourcePlaybackOnVisionPro() throws {
        try exercisePanoramicAutomaticRestore(
            expectation: .init(
                filename: "APMP-180-example.mp4",
                pickerPath: ["Samples", "Spatial", "Stereo180"],
                pickerLabels: ["APMP-180-example", "APMP-180-example.mp4"],
                evidenceSlug: "matrix-apmp-180",
                sourceContentKind: "halfEquirectangular",
                projection: "equirectangular180",
                stereoLayout: "multiview",
                presentation: "panorama",
                contentType: "halfEquirectangular",
                formatSignalingProjectionKind: "HalfEquirectangular",
                actualViewingMode: "stereo",
                actualImmersiveMode: "progressive",
                actualSpatialVideoMode: "screen",
                isMVHEVC: true,
                compressedFormat: nil
            ),
            explicitPanoramaOverride: nil
        )
    }

    @MainActor
    func testAPMP360AutomaticSourcePlaybackOnVisionPro() throws {
        try exercisePanoramicAutomaticRestore(
            expectation: .init(
                filename: "APMP-360-example.mp4",
                pickerPath: ["Samples", "Spatial", "Panorama"],
                pickerLabels: ["APMP-360-example", "APMP-360-example.mp4"],
                evidenceSlug: "matrix-apmp-360",
                sourceContentKind: "equirectangular",
                projection: "equirectangular360",
                stereoLayout: "mono",
                presentation: "panorama",
                contentType: "equirectangular",
                formatSignalingProjectionKind: "Equirectangular",
                actualViewingMode: "mono",
                actualImmersiveMode: "progressive",
                actualSpatialVideoMode: "screen",
                isMVHEVC: false,
                compressedFormat: nil
            ),
            explicitPanoramaOverride: nil
        )
    }

    @MainActor
    func testAPMPWideFOVAutomaticSourcePlaybackOnVisionPro() throws {
        try exercisePanoramicAutomaticRestore(
            expectation: .init(
                filename: "APMP-wide-FOV-example.mp4",
                pickerPath: ["Samples", "Spatial", "Panorama"],
                pickerLabels: ["APMP-wide-FOV-example", "APMP-wide-FOV-example.mp4"],
                evidenceSlug: "matrix-apmp-wide-fov",
                sourceContentKind: "parametricImmersive",
                projection: "flat",
                stereoLayout: "mono",
                presentation: "panorama",
                contentType: "parametricImmersive",
                formatSignalingProjectionKind: "ParametricImmersive",
                actualViewingMode: "mono",
                actualImmersiveMode: "progressive",
                actualSpatialVideoMode: "screen",
                isMVHEVC: false,
                compressedFormat: nil
            ),
            explicitPanoramaOverride: .equirectangular360
        )
    }

    @MainActor
    func testDolbyVisionProfile5AutomaticSourcePlaybackOnVisionPro() throws {
        _ = try openAutomaticSourcePlayback(
            .init(
                filename:
                    "Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4",
                pickerPath: ["Samples", "DynamicRange", "DolbyVision", "HD"],
                pickerLabels: ["Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps"],
                evidenceSlug: "matrix-dolby-vision-p5",
                sourceContentKind: "rectilinear",
                projection: "flat",
                stereoLayout: "mono",
                presentation: "window",
                contentType: "mono",
                formatSignalingProjectionKind: nil,
                actualViewingMode: "mono",
                actualImmersiveMode: nil,
                actualSpatialVideoMode: "screen",
                isMVHEVC: false,
                compressedFormat: .init(
                    providerCodecName: "hevc",
                    providerCodecTag: "dvh1",
                    sampleMediaSubtype: "dvh1",
                    requiredProviderConfigurationAtoms: ["hvcC", "dvcC"],
                    sampleHasDvcC: true
                )
            )
        )
    }

    @MainActor
    func testDolbyVisionProfile10AutomaticSourcePlaybackOnVisionPro() throws {
        _ = try openAutomaticSourcePlayback(
            .init(
                filename: "media-video-dav1-dav1-1.mp4",
                pickerPath: [
                    "Samples", "DynamicRange", "DolbyVision", "Profile10",
                    "OfficialDolby", "P10.0"
                ],
                pickerLabels: ["media-video-dav1-dav1-1"],
                evidenceSlug: "matrix-dolby-vision-p10",
                sourceContentKind: "rectilinear",
                projection: "flat",
                stereoLayout: "mono",
                presentation: "window",
                contentType: "mono",
                formatSignalingProjectionKind: nil,
                actualViewingMode: "mono",
                actualImmersiveMode: nil,
                actualSpatialVideoMode: "screen",
                isMVHEVC: false,
                compressedFormat: .init(
                    providerCodecName: "av1",
                    providerCodecTag: "dav1",
                    sampleMediaSubtype: "av01",
                    requiredProviderConfigurationAtoms: ["dvvC"],
                    sampleHasDvvC: true
                )
            )
        )
    }

    @MainActor
    func testAppleImmersiveVideoIsRejectedBeforePlaybackOnVisionPro() throws {
        let filename = "Immersive-Video-example.f99766.mp4"
        let app = launchMediaLibrary()
        let identifier = "MediaLibrary-grid-video-\(filename)"
        let card = app.buttons.matching(identifier: identifier).firstMatch
        try requireMatrix(
            importExactRealMediaReference(
                card: card,
                identifier: identifier,
                pickerPath: ["Samples", "Spatial", "Apple-Immersive"],
                pickerLabels: ["Immersive-Video-example.f99766", filename],
                filename: filename,
                in: app
            ),
            "Apple Immersive fixture could not be imported from its exact path."
        )

        card.tap()
        resolveResumeDecisionIfNeeded(in: app)
        let alert = app.alerts["Failed to Load"].firstMatch
        try requireMatrix(
            alert.waitForExistence(timeout: 45),
            "Apple Immersive Video did not produce the generic load failure."
        )
        try requireMatrix(
            app.staticTexts["Unable to open this file."].firstMatch
                .waitForExistence(timeout: 5),
            "Apple Immersive Video exposed a non-generic failure message."
        )
        let applicationState = app.descendants(matching: .any)[
            "PlayerUI-application-state"
        ].firstMatch
        let failed = try requireMatrix(
            waitForState(applicationState, timeout: 15) {
                $0.string("lifecycle")?.lowercased().hasPrefix("failed") == true
                    && $0.string("session") == "none"
                    && $0.string("attached") == "none"
            },
            "Rejected Apple Immersive Video did not publish its terminal failure state."
        )
        for field in [
            "videoSamples", "rendererInputs", "audioSamples", "audioRendererSamples"
        ] {
            let count = try requireMatrix(
                failed.uint64(field),
                "Rejected Apple Immersive Video did not expose \(field)."
            )
            try requireMatrix(
                count == 0,
                "Rejected Apple Immersive Video published \(field)=\(count)."
            )
        }
        try requireMatrix(
            failed.bool("componentReady") == false,
            "Rejected Apple Immersive Video prepared a video component."
        )
        try requireMatrix(
            failed.bool("hasAudio") == false,
            "Rejected Apple Immersive Video published an audio output."
        )
        try requireMatrix(
            failed.string("rendererConsumer") == "none"
                && failed.string("rendererConsumerEntity") == "none",
            "Rejected Apple Immersive Video bound a renderer consumer."
        )
        try requireMatrix(
            app.descendants(matching: .any)["PlayerUI-spatial-state"]
                .firstMatch.waitForNonExistence(timeout: 5),
            "Rejected Apple Immersive Video must not enter a spatial presentation."
        )
        attachState(failed, name: "matrix-apple-immersive-rejected-state")
        attachScreenshot(from: app, name: "matrix-apple-immersive-rejected")
    }

    private struct CompressedFormatExpectation {
        let providerCodecName: String
        let providerCodecTag: String
        let sampleMediaSubtype: String
        let providerTransferToken: String?
        let sampleTransferToken: String?
        let requiredProviderConfigurationAtoms: Set<String>
        let sampleHasDvcC: Bool?
        let sampleHasDvvC: Bool?

        init(
            providerCodecName: String,
            providerCodecTag: String,
            sampleMediaSubtype: String,
            providerTransferToken: String? = nil,
            sampleTransferToken: String? = nil,
            requiredProviderConfigurationAtoms: Set<String> = [],
            sampleHasDvcC: Bool? = nil,
            sampleHasDvvC: Bool? = nil
        ) {
            self.providerCodecName = providerCodecName
            self.providerCodecTag = providerCodecTag
            self.sampleMediaSubtype = sampleMediaSubtype
            self.providerTransferToken = providerTransferToken
            self.sampleTransferToken = sampleTransferToken
            self.requiredProviderConfigurationAtoms =
                requiredProviderConfigurationAtoms
            self.sampleHasDvcC = sampleHasDvcC
            self.sampleHasDvvC = sampleHasDvvC
        }
    }

    private struct AutomaticSourceExpectation {
        let filename: String
        let pickerPath: [String]
        let pickerLabels: [String]
        let evidenceSlug: String
        let sourceContentKind: String
        let projection: String
        let stereoLayout: String
        let presentation: String
        let contentType: String
        let formatSignalingProjectionKind: String?
        let actualViewingMode: String?
        let actualImmersiveMode: String?
        let actualSpatialVideoMode: String?
        let isMVHEVC: Bool
        let compressedFormat: CompressedFormatExpectation?
    }

    private struct AutomaticSourcePlayback {
        let app: XCUIApplication
        let stateElement: XCUIElement
        let state: RegressionStateSnapshot
    }

    private struct PanoramaOverrideExpectation {
        let projectionLabel: String
        let sampleProjectionKind: String
        let contentType: String

        static let halfEquirectangular = Self(
            projectionLabel: "180°",
            sampleProjectionKind: "HalfEquirectangular",
            contentType: "halfEquirectangular"
        )
        static let equirectangular360 = Self(
            projectionLabel: "360°",
            sampleProjectionKind: "Equirectangular",
            contentType: "equirectangular"
        )
    }

    private struct AudioSentinel {
        let track: String
        let streamEpoch: UInt64
        let audioRendererEpoch: UInt64
        let samples: UInt64
        let rendererSamples: UInt64
    }

    private struct MatrixRequirementFailure: Error {}

    @MainActor
    private func openAutomaticSourcePlayback(
        _ expectation: AutomaticSourceExpectation
    ) throws -> AutomaticSourcePlayback {
        let app = launchMediaLibrary()
        let identifier = "MediaLibrary-grid-video-\(expectation.filename)"
        let card = app.buttons.matching(identifier: identifier).firstMatch
        try requireMatrix(
            importExactRealMediaReference(
                card: card,
                identifier: identifier,
                pickerPath: expectation.pickerPath,
                pickerLabels: expectation.pickerLabels,
                filename: expectation.filename,
                in: app
            ),
            "\(expectation.filename) could not be imported from its exact path."
        )

        let sourceAttachment = XCTAttachment(
            string: "Desktop/TestMedia/\(expectation.pickerPath.joined(separator: "/"))/\(expectation.filename)"
        )
        sourceAttachment.name = "\(expectation.evidenceSlug)-source-path"
        sourceAttachment.lifetime = .keepAlways
        add(sourceAttachment)

        card.tap()
        resolveResumeDecisionIfNeeded(in: app)
        let firstPresentation = expectation.presentation == "panorama"
            ? "portal"
            : expectation.presentation
        let firstStateElement = app.descendants(matching: .any)[
            firstPresentation == "window" || firstPresentation == "portal"
                ? "PlayerUI-window-control-plane"
                : "PlayerUI-spatial-state"
        ].firstMatch
        var observedFailures: [String] = []
        _ = try requireMatrix(
            waitForRealMediaSurface(
                firstStateElement,
                presentation: firstPresentation,
                timeout: 75,
                app: app,
                evidenceName: "\(expectation.evidenceSlug)-01-source-surface",
                observedFailures: &observedFailures
            ),
            "\(expectation.filename) did not expose its playback surface."
        )
        let stateElement: XCUIElement
        if expectation.presentation == "panorama" {
            let portal = try requireMatrix(
                waitForState(firstStateElement, timeout: 45) {
                    automaticSourceState(
                        $0,
                        matches: expectation,
                        presentation: "portal"
                    )
                },
                "\(expectation.filename) did not settle its Automatic source in Portal."
            )
            attachState(
                portal,
                name: "\(expectation.evidenceSlug)-01-automatic-portal-state"
            )
            let enterPanorama = app.buttons[
                "PlayerUI-TopAction-resumePanorama"
            ].firstMatch
            try requireMatrix(
                requireHittable(enterPanorama, named: "Enter Panorama"),
                "\(expectation.filename) did not expose explicit Panorama entry."
            )
            enterPanorama.tap()
            stateElement = app.descendants(matching: .any)[
                "PlayerUI-spatial-state"
            ].firstMatch
            _ = try requireMatrix(
                waitForRealMediaSurface(
                    stateElement,
                    presentation: "panorama",
                    timeout: 75,
                    app: app,
                    evidenceName: "\(expectation.evidenceSlug)-01-panorama-surface",
                    observedFailures: &observedFailures
                ),
                "\(expectation.filename) did not enter Panorama."
            )
        } else {
            stateElement = firstStateElement
        }
        let automatic = try requireMatrix(
            waitForState(stateElement, timeout: 45, where: {
                automaticSourceState($0, matches: expectation)
            }),
            "\(expectation.filename) did not retain its Automatic source interpretation."
        )
        if automaticSourceState(automatic, matches: expectation) == false {
            attachCurrentState(
                of: stateElement,
                name: "\(expectation.evidenceSlug)-automatic-source-mismatch"
            )
            attachScreenshot(
                from: app,
                name: "\(expectation.evidenceSlug)-automatic-source-mismatch"
            )
            try requireMatrix(
                false,
                "\(expectation.filename) Automatic source facts did not match."
            )
        }
        assertPlaybackIdentityIsReady(
            automatic,
            context: "\(expectation.filename) Automatic source"
        )
        attachState(
            automatic,
            name: "\(expectation.evidenceSlug)-01-automatic-source-state"
        )
        attachScreenshot(
            from: app,
            name: "\(expectation.evidenceSlug)-01-automatic-source"
        )
        let continuous = try requireMatrix(
            ensureRealMediaPlaybackAdvances(
                in: stateElement,
                presentation: expectation.presentation,
                app: app,
                evidenceName: "\(expectation.evidenceSlug)-01-automatic-source",
                observedFailures: &observedFailures
            ),
            "\(expectation.filename) did not continue after Automatic source detection."
        )
        try requireMatrix(
            observedFailures.isEmpty,
            observedFailures.joined(separator: "\n")
        )
        attachHumanReviewBoundary(
            "Review the two retained observations and the full recording for "
                + "continuously moving, correctly projected \(expectation.filename) "
                + "video; state counters and identity are necessary but do not "
                + "replace wearer-visible review.",
            name: "\(expectation.evidenceSlug)-wearer-visible-review"
        )
        return AutomaticSourcePlayback(
            app: app,
            stateElement: stateElement,
            state: continuous
        )
    }

    private func requireMatrix<T>(
        _ value: T?,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> T {
        guard let value else {
            XCTFail(message, file: file, line: line)
            throw MatrixRequirementFailure()
        }
        return value
    }

    private func requireMatrix(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard condition() else {
            XCTFail(message, file: file, line: line)
            throw MatrixRequirementFailure()
        }
    }

    private enum TransportSeekDirection {
        case rewind
        case forward

        var offsetSeconds: Double {
            switch self {
            case .rewind: -15
            case .forward: 15
            }
        }

        var buttonIdentifier: String {
            switch self {
            case .rewind: "PlayerPanel-button-rewind"
            case .forward: "PlayerPanel-button-forward"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .rewind: "Rewind 15 seconds"
            case .forward: "Forward 15 seconds"
            }
        }
    }

    private func requireSeekPosition(
        _ state: RegressionStateSnapshot,
        expectedPosition: (Double) -> Double,
        context: String
    ) throws {
        let position = try requireMatrix(
            state.double("position"),
            "\(context) did not expose position."
        )
        let duration = try requireMatrix(
            state.double("duration"),
            "\(context) did not expose duration."
        )
        try requireMatrix(
            position.isFinite && duration.isFinite && duration > 0,
            "\(context) exposed an unusable position or duration."
        )
        let actualRate = try requireMatrix(
            state.double("actualRate"),
            "\(context) did not expose actualRate."
        )
        try requireMatrix(
            actualRate.isFinite,
            "\(context) exposed an unusable actualRate."
        )
        let target = expectedPosition(duration)
        try requireMatrix(
            target.isFinite,
            "\(context) produced an unusable seek target."
        )

        let allowedDelta = duration * 0.02 + abs(actualRate) * 0.1
        try requireMatrix(
            abs(position - target) <= allowedDelta,
            "\(context) settled at \(position)s; expected \(target)s "
                + "within the derived \(allowedDelta)s bound."
        )
    }

    @MainActor
    private func performTransportSeek(
        _ playback: AutomaticSourcePlayback,
        direction: TransportSeekDirection,
        evidenceSlug: String
    ) throws -> AutomaticSourcePlayback {
        try requireMatrix(
            playback.state.string("presentation") == "window",
            "\(evidenceSlug) did not start in Window presentation."
        )
        try requireMatrix(
            showWindowPlaybackControls(
                windowState: playback.stateElement,
                app: playback.app,
                evidenceName: "\(evidenceSlug)-controls"
            ),
            "\(evidenceSlug) could not expose Window transport controls."
        )
        let button = playback.app.buttons[direction.buttonIdentifier].firstMatch
        try requireMatrix(
            requireHittable(button, named: direction.accessibilityLabel),
            "\(evidenceSlug) did not expose its transport control."
        )
        try requireMatrix(
            button.label == direction.accessibilityLabel,
            "\(evidenceSlug) unexpectedly exposed frame-step mode."
        )

        let baselineRawValue = try requireMatrix(
            playback.stateElement.value as? String,
            "\(evidenceSlug) did not expose current playback state before tap."
        )
        let baseline = RegressionStateSnapshot(rawValue: baselineRawValue)
        try requireMatrix(
            baseline.string("lifecycle")?.lowercased() == "playing",
            "\(evidenceSlug) was not Playing immediately before tap."
        )
        let baselinePosition = try requireMatrix(
            baseline.double("position"),
            "\(evidenceSlug) did not expose its latest baseline position."
        )
        let baselineDuration = try requireMatrix(
            baseline.double("duration"),
            "\(evidenceSlug) did not expose its latest duration."
        )
        try requireMatrix(
            baselinePosition.isFinite
                && baselineDuration.isFinite
                && baselineDuration > 0,
            "\(evidenceSlug) exposed an unusable position or duration before tap."
        )
        let baselineEpoch = try requireMatrix(
            baseline.uint64("streamEpoch"),
            "\(evidenceSlug) did not expose its latest streamEpoch."
        )
        let baselineSession = try requireMatrix(
            baseline.string("session"),
            "\(evidenceSlug) did not expose its media session."
        )
        button.tap()

        let firstAdvancedEpoch = try requireMatrix(
            waitForState(playback.stateElement, timeout: 15) {
                ($0.uint64("streamEpoch") ?? 0) > baselineEpoch
            },
            "\(evidenceSlug) did not complete its transport seek."
        )
        attachState(firstAdvancedEpoch, name: "\(evidenceSlug)-state")
        attachScreenshot(from: playback.app, name: evidenceSlug)
        try requireMatrix(
            firstAdvancedEpoch.string("lifecycle")?.lowercased() == "playing",
            "\(evidenceSlug) was not Playing at its first advanced epoch."
        )
        try requireMatrix(
            firstAdvancedEpoch.string("session") == baselineSession,
            "\(evidenceSlug) replaced its media session during transport seek."
        )
        try requireSeekPosition(
            firstAdvancedEpoch,
            expectedPosition: { _ in
                min(
                    max(baselinePosition + direction.offsetSeconds, 0),
                    baselineDuration
                )
            },
            context: evidenceSlug
        )
        let continuous = try requireContinuousMatrixPlayback(
            app: playback.app,
            stateElement: playback.stateElement,
            presentation: "window",
            evidenceSlug: "\(evidenceSlug)-continuous",
            requiresCurrentPixelEpoch: false
        )
        assertStablePlaybackIdentity(
            from: playback.state,
            to: continuous,
            expectsSameFormatRevision: true,
            requiresCurrentPixelEpoch: false,
            context: evidenceSlug
        )
        return AutomaticSourcePlayback(
            app: playback.app,
            stateElement: playback.stateElement,
            state: continuous
        )
    }

    @MainActor
    private func submitWindowFormat(
        from playback: AutomaticSourcePlayback,
        projectionLabel: String,
        stereoLayoutLabel: String,
        evidenceSlug: String
    ) throws {
        try requireMatrix(
            playback.state.string("presentation") == "window",
            "\(evidenceSlug) did not start in Window presentation."
        )
        try requireMatrix(
            showWindowPlaybackControls(
                windowState: playback.stateElement,
                app: playback.app,
                evidenceName: "\(evidenceSlug)-controls"
            ),
            "\(evidenceSlug) could not expose Window controls."
        )
        let format = playback.app.buttons[
            "PlayerUI-TopAction-videoFormat"
        ].firstMatch
        try requireMatrix(
            requireHittable(format, named: "\(evidenceSlug) Video Format"),
            "\(evidenceSlug) Video Format action was unavailable."
        )
        format.tap()
        let projection = playback.app.descendants(matching: .any)[
            "PlayerUI-VideoFormat-Projection-\(projectionLabel)"
        ].firstMatch
        try requireMatrix(
            requireHittable(projection, named: "\(projectionLabel) projection"),
            "\(evidenceSlug) could not select \(projectionLabel)."
        )
        projection.tap()
        let stereoLayout = playback.app.descendants(matching: .any)[
            "PlayerUI-VideoFormat-Stereo Layout-\(stereoLayoutLabel)"
        ].firstMatch
        try requireMatrix(
            requireHittable(stereoLayout, named: "\(stereoLayoutLabel) layout"),
            "\(evidenceSlug) could not select \(stereoLayoutLabel)."
        )
        stereoLayout.tap()
        let apply = playback.app.buttons["PlayerUI-VideoFormat-apply"].firstMatch
        try requireMatrix(
            requireHittable(apply, named: "Apply \(evidenceSlug) format"),
            "\(evidenceSlug) Apply action was unavailable."
        )
        attachScreenshot(from: playback.app, name: "\(evidenceSlug)-draft")
        apply.tap()
    }

    @MainActor
    private func requireContinuousMatrixPlayback(
        app: XCUIApplication,
        stateElement: XCUIElement,
        presentation: String,
        evidenceSlug: String,
        requiresCurrentPixelEpoch: Bool = true
    ) throws -> RegressionStateSnapshot {
        var observedFailures: [String] = []
        let continuous = try requireMatrix(
            ensureRealMediaPlaybackAdvances(
                in: stateElement,
                presentation: presentation,
                app: app,
                evidenceName: evidenceSlug,
                requiresCurrentPixelEpoch: requiresCurrentPixelEpoch,
                observedFailures: &observedFailures
            ),
            "\(evidenceSlug) did not produce continuous playback."
        )
        try requireMatrix(
            observedFailures.isEmpty,
            observedFailures.joined(separator: "\n")
        )
        return continuous
    }

    @MainActor
    private func applyWindowFlatMonoOverride(
        _ playback: AutomaticSourcePlayback,
        sourceContentKind: String,
        evidenceSlug: String
    ) throws -> AutomaticSourcePlayback {
        let priorFormatRevision = try requireMatrix(
            playback.state.uint64("lastRendererInputFormatRevision"),
            "\(evidenceSlug) did not expose its input format revision."
        )
        try submitWindowFormat(
            from: playback,
            projectionLabel: "Flat",
            stereoLayoutLabel: "Mono",
            evidenceSlug: evidenceSlug
        )
        let overridden = try requireMatrix(
            waitForState(playback.stateElement, timeout: 30) {
                $0.string("presentation") == "window"
                    && $0.string("transition") == "none"
                    && $0.string("attached") == "window"
                    && $0.string("session") == playback.state.string("session")
                    && $0.string("formatProvenance") == "userOverride"
                    && $0.string("sourceContentKind") == sourceContentKind
                    && $0.string("projection") == "flat"
                    && $0.string("stereoLayout") == "mono"
                    && $0.string("windowComponentContentType")?.lowercased() == "mono"
                    && $0.string("actualViewingMode")?.lowercased() == "mono"
                    && $0.string("actualSpatialVideoMode")?.lowercased() == "screen"
                    && ($0.uint64("lastRendererInputFormatRevision") ?? 0)
                        > priorFormatRevision
            },
            "\(evidenceSlug) did not apply Flat and Mono."
        )
        attachState(overridden, name: "\(evidenceSlug)-state")
        attachScreenshot(from: playback.app, name: evidenceSlug)
        let continuous = try requireContinuousMatrixPlayback(
            app: playback.app,
            stateElement: playback.stateElement,
            presentation: "window",
            evidenceSlug: "\(evidenceSlug)-continuous"
        )
        assertStablePlaybackIdentity(
            from: playback.state,
            to: continuous,
            expectsSameFormatRevision: false,
            context: evidenceSlug
        )
        return AutomaticSourcePlayback(
            app: playback.app,
            stateElement: playback.stateElement,
            state: continuous
        )
    }

    @MainActor
    private func applyWindowPanoramaOverride(
        _ playback: AutomaticSourcePlayback,
        override: PanoramaOverrideExpectation,
        sourceContentKind: String,
        evidenceSlug: String
    ) throws -> AutomaticSourcePlayback {
        let priorFormatRevision = try requireMatrix(
            playback.state.uint64("lastRendererInputFormatRevision"),
            "\(evidenceSlug) did not expose its input format revision."
        )
        try submitWindowFormat(
            from: playback,
            projectionLabel: override.projectionLabel,
            stereoLayoutLabel: "Mono",
            evidenceSlug: evidenceSlug
        )
        let windowState = playback.app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let portal = try requireMatrix(
            waitForState(windowState, timeout: 75) {
                $0.string("presentation") == "portal"
                    && $0.string("transition") == "none"
                    && $0.string("pendingSpatialEffect") == "none"
                    && $0.string("attached") == "portal"
                    && $0.string("session") == playback.state.string("session")
                    && $0.string("formatProvenance") == "userOverride"
                    && $0.string("sourceContentKind") == sourceContentKind
                    && $0.string("sampleProjectionKind")?.lowercased()
                        == override.sampleProjectionKind.lowercased()
                    && $0.string("windowComponentContentType")?.lowercased()
                        == override.contentType.lowercased()
                    && $0.string("actualImmersiveMode")?.lowercased() == "portal"
                    && $0.string("actualSpatialVideoMode")?.lowercased() == "screen"
                    && $0.bool("videoVisible") == true
                    && ($0.uint64("lastRendererInputFormatRevision") ?? 0)
                        > priorFormatRevision
            },
            "\(evidenceSlug) did not settle in Portal after format application."
        )
        attachState(portal, name: "\(evidenceSlug)-portal-state")
        let spatialState = playback.app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        try requireMatrix(
            spatialState.exists == false,
            "\(evidenceSlug) opened Panorama before explicit entry."
        )
        let enterPanorama = playback.app.buttons[
            "PlayerUI-TopAction-resumePanorama"
        ].firstMatch
        try requireMatrix(
            requireHittable(enterPanorama, named: "Enter Panorama"),
            "\(evidenceSlug) did not expose explicit Panorama entry."
        )
        enterPanorama.tap()
        let overridden = try requireMatrix(
            waitForState(spatialState, timeout: 75) {
                $0.string("presentation") == "panorama"
                    && $0.string("transition") == "none"
                    && $0.string("attached") == "panorama"
                    && $0.string("session") == playback.state.string("session")
                    && $0.string("formatProvenance") == "userOverride"
                    && $0.string("sourceContentKind") == sourceContentKind
                    && $0.string("sampleProjectionKind")?.lowercased()
                        == override.sampleProjectionKind.lowercased()
                    && $0.string("surfaceContentType")?.lowercased()
                        == override.contentType.lowercased()
                    && $0.string("surfaceActualViewingMode")?.lowercased() == "mono"
                    && $0.string("surfaceActualImmersiveMode")?.lowercased()
                        == "progressive"
                    && $0.string("surfaceActualSpatialVideoMode")?.lowercased()
                        == "screen"
                    && $0.bool("surfaceSettled") == true
                    && ($0.uint64("lastRendererInputFormatRevision") ?? 0)
                        > priorFormatRevision
            },
            "\(evidenceSlug) did not reach its panoramic override."
        )
        attachState(overridden, name: "\(evidenceSlug)-state")
        attachScreenshot(from: playback.app, name: evidenceSlug)
        let continuous = try requireContinuousMatrixPlayback(
            app: playback.app,
            stateElement: spatialState,
            presentation: "panorama",
            evidenceSlug: "\(evidenceSlug)-continuous"
        )
        assertStablePlaybackIdentity(
            from: playback.state,
            to: continuous,
            expectsSameFormatRevision: false,
            context: evidenceSlug
        )
        return AutomaticSourcePlayback(
            app: playback.app,
            stateElement: spatialState,
            state: continuous
        )
    }

    @MainActor
    private func escapePanoramaToFlatMonoWindow(
        _ playback: AutomaticSourcePlayback,
        sourceContentKind: String,
        evidenceSlug: String
    ) throws -> AutomaticSourcePlayback {
        try requireMatrix(
            playback.state.string("presentation") == "panorama",
            "\(evidenceSlug) did not start in Panorama."
        )
        let priorFormatRevision = try requireMatrix(
            playback.state.uint64("lastRendererInputFormatRevision"),
            "\(evidenceSlug) did not expose its input format revision."
        )
        let panoramaContentType = try requireMatrix(
            playback.state.string("surfaceContentType"),
            "\(evidenceSlug) did not expose its Panorama content type."
        )
        let exit = playback.app.buttons[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        try requireMatrix(
            requireHittable(exit, named: "Return Panorama to Portal"),
            "\(evidenceSlug) could not return Panorama to Portal."
        )
        exit.tap()

        let windowState = playback.app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let portal = try requireMatrix(
            waitForState(windowState, timeout: 45) {
                $0.string("presentation") == "portal"
                    && $0.string("transition") == "none"
                    && $0.string("attached") == "portal"
                    && $0.string("session") == playback.state.string("session")
                    && $0.bool("videoVisible") == true
                    && $0.bool("displayedPixel") == true
                    && $0.string("actualImmersiveMode")?.lowercased() == "portal"
                    && $0.string("windowComponentContentType")?.lowercased()
                        == panoramaContentType.lowercased()
                    && $0.uint64("lastRendererInputFormatRevision")
                        == playback.state.uint64("lastRendererInputFormatRevision")
            },
            "\(evidenceSlug) did not reach Portal."
        )
        let continuousPortal = try requireContinuousMatrixPlayback(
            app: playback.app,
            stateElement: windowState,
            presentation: "portal",
            evidenceSlug: "\(evidenceSlug)-portal-continuous"
        )
        assertStablePlaybackIdentity(
            from: playback.state,
            to: continuousPortal,
            expectsSameFormatRevision: true,
            context: "\(evidenceSlug) Portal handoff"
        )
        attachState(portal, name: "\(evidenceSlug)-portal-state")
        attachState(
            continuousPortal,
            name: "\(evidenceSlug)-portal-continuous-state"
        )
        attachScreenshot(from: playback.app, name: "\(evidenceSlug)-portal")

        let settings = playback.app.buttons[
            "PlayerPanel-button-settings"
        ].firstMatch
        try requireMatrix(
            requireHittable(settings, named: "Portal Advanced Settings"),
            "\(evidenceSlug) could not open Portal Advanced Settings."
        )
        settings.tap()
        let flatMono = playback.app.buttons[
            "PlayerPanel-Advanced-ReturnToMonoWindow"
        ].firstMatch
        try requireMatrix(
            requireHittable(flatMono, named: "Return to Mono Window"),
            "\(evidenceSlug) could not apply the Flat Mono escape."
        )
        flatMono.tap()

        let flat = try requireMatrix(
            waitForState(windowState, timeout: 45) {
                $0.string("presentation") == "window"
                    && $0.string("transition") == "none"
                    && $0.string("attached") == "window"
                    && $0.string("session") == playback.state.string("session")
                    && $0.string("formatProvenance") == "userOverride"
                    && $0.string("sourceContentKind") == sourceContentKind
                    && $0.string("projection") == "flat"
                    && $0.string("stereoLayout") == "mono"
                    && $0.string("windowComponentContentType")?.lowercased() == "mono"
                    && $0.string("actualViewingMode")?.lowercased() == "mono"
                    && $0.string("actualSpatialVideoMode")?.lowercased() == "screen"
                    && ($0.uint64("lastRendererInputFormatRevision") ?? 0)
                        > priorFormatRevision
            },
            "\(evidenceSlug) did not apply Flat Mono in Window."
        )
        attachState(flat, name: "\(evidenceSlug)-window-state")
        attachScreenshot(from: playback.app, name: "\(evidenceSlug)-window")
        let continuous = try requireContinuousMatrixPlayback(
            app: playback.app,
            stateElement: windowState,
            presentation: "window",
            evidenceSlug: "\(evidenceSlug)-continuous"
        )
        assertStablePlaybackIdentity(
            from: playback.state,
            to: continuous,
            expectsSameFormatRevision: false,
            context: evidenceSlug
        )
        return AutomaticSourcePlayback(
            app: playback.app,
            stateElement: windowState,
            state: continuous
        )
    }

    @MainActor
    private func restoreAutomaticFormat(
        from playback: AutomaticSourcePlayback,
        expectation: AutomaticSourceExpectation,
        evidenceSlug: String
    ) throws -> AutomaticSourcePlayback {
        try requireMatrix(
            playback.state.string("presentation") == "window",
            "\(evidenceSlug) did not start in Window."
        )
        let priorFormatRevision = try requireMatrix(
            playback.state.uint64("lastRendererInputFormatRevision"),
            "\(evidenceSlug) did not expose its input format revision."
        )
        try requireMatrix(
            showWindowPlaybackControls(
                windowState: playback.stateElement,
                app: playback.app,
                evidenceName: "\(evidenceSlug)-controls"
            ),
            "\(evidenceSlug) could not expose Window controls."
        )
        let format = playback.app.buttons[
            "PlayerUI-TopAction-videoFormat"
        ].firstMatch
        try requireMatrix(
            requireHittable(format, named: "\(evidenceSlug) Video Format"),
            "\(evidenceSlug) Video Format action was unavailable."
        )
        format.tap()
        let automatic = playback.app.buttons[
            "PlayerUI-VideoFormat-automatic"
        ].firstMatch
        try requireMatrix(
            requireHittable(automatic, named: "Restore Automatic Format"),
            "\(evidenceSlug) did not expose an actionable Automatic button."
        )
        automatic.tap()

        let firstPresentation = expectation.presentation == "panorama"
            ? "portal"
            : expectation.presentation
        let firstStateElement = playback.app.descendants(matching: .any)[
            firstPresentation == "window" || firstPresentation == "portal"
                ? "PlayerUI-window-control-plane"
                : "PlayerUI-spatial-state"
        ].firstMatch
        let firstRestored = try requireMatrix(
            waitForState(firstStateElement, timeout: 75) {
                automaticSourceState(
                    $0,
                    matches: expectation,
                    presentation: firstPresentation
                )
                    && $0.string("session") == playback.state.string("session")
                    && ($0.uint64("lastRendererInputFormatRevision") ?? 0)
                        > priorFormatRevision
            },
            "\(evidenceSlug) did not restore the immutable source interpretation."
        )
        let stateElement: XCUIElement
        let restored: RegressionStateSnapshot
        if expectation.presentation == "panorama" {
            attachState(firstRestored, name: "\(evidenceSlug)-portal-state")
            let enterPanorama = playback.app.buttons[
                "PlayerUI-TopAction-resumePanorama"
            ].firstMatch
            try requireMatrix(
                requireHittable(enterPanorama, named: "Enter Panorama"),
                "\(evidenceSlug) did not expose explicit Panorama entry."
            )
            enterPanorama.tap()
            stateElement = playback.app.descendants(matching: .any)[
                "PlayerUI-spatial-state"
            ].firstMatch
            restored = try requireMatrix(
                waitForState(stateElement, timeout: 75) {
                    automaticSourceState($0, matches: expectation)
                        && $0.string("session") == playback.state.string("session")
                        && ($0.uint64("lastRendererInputFormatRevision") ?? 0)
                            > priorFormatRevision
                },
                "\(evidenceSlug) did not enter Panorama after source restoration."
            )
        } else {
            stateElement = firstStateElement
            restored = firstRestored
        }
        try requireMatrix(
            playback.app.descendants(matching: .any)["PlayerUI-VideoFormat"]
                .firstMatch.waitForNonExistence(timeout: 5),
            "\(evidenceSlug) left the Video Format panel open."
        )
        attachState(restored, name: "\(evidenceSlug)-state")
        attachScreenshot(from: playback.app, name: evidenceSlug)
        let continuous = try requireContinuousMatrixPlayback(
            app: playback.app,
            stateElement: stateElement,
            presentation: expectation.presentation,
            evidenceSlug: "\(evidenceSlug)-continuous"
        )
        assertStablePlaybackIdentity(
            from: playback.state,
            to: continuous,
            expectsSameFormatRevision: false,
            context: evidenceSlug
        )
        return AutomaticSourcePlayback(
            app: playback.app,
            stateElement: stateElement,
            state: continuous
        )
    }

    @MainActor
    private func exercisePanoramicAutomaticRestore(
        expectation: AutomaticSourceExpectation,
        explicitPanoramaOverride: PanoramaOverrideExpectation?
    ) throws {
        let source = try openAutomaticSourcePlayback(expectation)
        var flatEscape = try escapePanoramaToFlatMonoWindow(
            source,
            sourceContentKind: expectation.sourceContentKind,
            evidenceSlug: "\(expectation.evidenceSlug)-03-wrong-flat-override"
        )
        if let explicitPanoramaOverride {
            let panoramicOverride = try applyWindowPanoramaOverride(
                flatEscape,
                override: explicitPanoramaOverride,
                sourceContentKind: expectation.sourceContentKind,
                evidenceSlug: "\(expectation.evidenceSlug)-04-explicit-360-override"
            )
            flatEscape = try escapePanoramaToFlatMonoWindow(
                panoramicOverride,
                sourceContentKind: expectation.sourceContentKind,
                evidenceSlug: "\(expectation.evidenceSlug)-05-flat-window-escape"
            )
        }
        let restored = try restoreAutomaticFormat(
            from: flatEscape,
            expectation: expectation,
            evidenceSlug: "\(expectation.evidenceSlug)-06-automatic-restored"
        )
        assertStablePlaybackIdentity(
            from: source.state,
            to: restored.state,
            expectsSameFormatRevision: false,
            context: "\(expectation.filename) complete format closure"
        )
    }

    @MainActor
    private func captureAudioSentinel(
        _ state: RegressionStateSnapshot,
        context: String
    ) throws -> AudioSentinel {
        try requireMatrix(state.bool("hasAudio") == true, "\(context) had no audio.")
        let track = try requireMatrix(
            state.string("audioTrack"),
            "\(context) did not expose the selected audio track."
        )
        try requireMatrix(track != "none", "\(context) had no selected audio track.")
        let streamEpoch = try requireMatrix(
            state.uint64("streamEpoch"),
            "\(context) did not expose streamEpoch."
        )
        let audioRendererEpoch = try requireMatrix(
            state.uint64("audioRendererEpoch"),
            "\(context) did not expose audioRendererEpoch."
        )
        try requireMatrix(
            audioRendererEpoch == streamEpoch,
            "\(context) audio and video epochs diverged."
        )
        try requireMatrix(
            state.string("audioRendererStatus") == "rendering",
            "\(context) audio renderer was not rendering."
        )
        try requireMatrix(
            state.string("audioRendererError") == "none",
            "\(context) audio renderer reported an error."
        )
        return AudioSentinel(
            track: track,
            streamEpoch: streamEpoch,
            audioRendererEpoch: audioRendererEpoch,
            samples: try requireMatrix(
                state.uint64("audioSamples"),
                "\(context) did not expose audio samples."
            ),
            rendererSamples: try requireMatrix(
                state.uint64("audioRendererSamples"),
                "\(context) did not expose renderer audio samples."
            )
        )
    }

    @MainActor
    private func requireAudioSentinelContinues(
        from baseline: AudioSentinel,
        through state: RegressionStateSnapshot,
        context: String
    ) throws -> AudioSentinel {
        let current = try captureAudioSentinel(state, context: context)
        try requireMatrix(
            current.track == baseline.track,
            "\(context) rebuilt or changed the selected audio track."
        )
        try requireMatrix(
            current.streamEpoch == baseline.streamEpoch
                && current.audioRendererEpoch == baseline.audioRendererEpoch,
            "\(context) rebuilt the audio/video stream epoch during a format-only change."
        )
        try requireMatrix(
            current.samples > baseline.samples,
            "\(context) stopped producing audio samples."
        )
        try requireMatrix(
            current.rendererSamples > baseline.rendererSamples,
            "\(context) stopped submitting audio renderer samples."
        )
        return current
    }

    private func requireAudioPipelineContinues(
        from baseline: AudioSentinel,
        through state: RegressionStateSnapshot,
        context: String
    ) throws -> AudioSentinel {
        try requireMatrix(state.bool("hasAudio") == true, "\(context) had no audio.")
        let streamEpoch = try requireMatrix(
            state.uint64("streamEpoch"),
            "\(context) did not expose streamEpoch."
        )
        let audioRendererEpoch = try requireMatrix(
            state.uint64("audioRendererEpoch"),
            "\(context) did not expose audioRendererEpoch."
        )
        let samples = try requireMatrix(
            state.uint64("audioSamples"),
            "\(context) did not expose audio samples."
        )
        let rendererSamples = try requireMatrix(
            state.uint64("audioRendererSamples"),
            "\(context) did not expose renderer audio samples."
        )
        try requireMatrix(
            streamEpoch == baseline.streamEpoch
                && audioRendererEpoch == baseline.audioRendererEpoch,
            "\(context) rebuilt the audio/video stream epoch during a format-only change."
        )
        try requireMatrix(
            state.string("audioRendererStatus") == "rendering"
                && state.string("audioRendererError") == "none",
            "\(context) audio renderer stopped rendering or reported an error."
        )
        try requireMatrix(
            samples > baseline.samples,
            "\(context) stopped producing audio samples."
        )
        try requireMatrix(
            rendererSamples > baseline.rendererSamples,
            "\(context) stopped submitting audio renderer samples."
        )
        return AudioSentinel(
            track: baseline.track,
            streamEpoch: streamEpoch,
            audioRendererEpoch: audioRendererEpoch,
            samples: samples,
            rendererSamples: rendererSamples
        )
    }

    @MainActor
    private func reopenAndVerifyAutomaticSource(
        after playback: AutomaticSourcePlayback,
        expectation: AutomaticSourceExpectation,
        evidenceSlug: String
    ) throws -> AutomaticSourcePlayback {
        let previousSession = try requireMatrix(
            playback.state.string("session"),
            "\(evidenceSlug) did not expose the previous session."
        )
        let back = playback.app.buttons[
            "PlayerUI-InfoBar-button-back"
        ].firstMatch
        try requireMatrix(
            requireHittable(back, named: "Back to Media Library"),
            "\(evidenceSlug) could not exit playback."
        )
        back.tap()
        try requireMatrix(
            playback.stateElement.waitForNonExistence(timeout: 20),
            "\(evidenceSlug) did not close the previous playback surface."
        )
        let identifier = "MediaLibrary-grid-video-\(expectation.filename)"
        let card = try requireMatrix(
            waitForHittableRegisteredMediaCard(
                identifier: identifier,
                in: playback.app,
                timeout: 30
            ),
            "\(evidenceSlug) could not find the existing Media Reference."
        )
        card.tap()
        resolveResumeDecisionIfNeeded(in: playback.app)
        let firstPresentation = expectation.presentation == "panorama"
            ? "portal"
            : expectation.presentation
        let firstStateElement = playback.app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let firstReopened = try requireMatrix(
            waitForState(firstStateElement, timeout: 45) {
                automaticSourceState(
                    $0,
                    matches: expectation,
                    presentation: firstPresentation
                )
                    && $0.string("session") != previousSession
            },
            "\(evidenceSlug) retained an override or reused the previous session."
        )
        let stateElement: XCUIElement
        let reopened: RegressionStateSnapshot
        if expectation.presentation == "panorama" {
            attachState(firstReopened, name: "\(evidenceSlug)-portal-state")
            let enterPanorama = playback.app.buttons[
                "PlayerUI-TopAction-resumePanorama"
            ].firstMatch
            try requireMatrix(
                requireHittable(enterPanorama, named: "Enter Panorama"),
                "\(evidenceSlug) did not expose explicit Panorama entry."
            )
            enterPanorama.tap()
            stateElement = playback.app.descendants(matching: .any)[
                "PlayerUI-spatial-state"
            ].firstMatch
            reopened = try requireMatrix(
                waitForState(stateElement, timeout: 45) {
                    automaticSourceState($0, matches: expectation)
                        && $0.string("session") != previousSession
                },
                "\(evidenceSlug) did not enter Panorama after reopening."
            )
        } else {
            stateElement = firstStateElement
            reopened = firstReopened
        }
        attachState(reopened, name: "\(evidenceSlug)-state")
        attachScreenshot(from: playback.app, name: evidenceSlug)
        let continuous = try requireContinuousMatrixPlayback(
            app: playback.app,
            stateElement: stateElement,
            presentation: "window",
            evidenceSlug: "\(evidenceSlug)-continuous"
        )
        return AutomaticSourcePlayback(
            app: playback.app,
            stateElement: stateElement,
            state: continuous
        )
    }

    private func automaticSourceState(
        _ state: RegressionStateSnapshot,
        matches expectation: AutomaticSourceExpectation,
        presentation: String? = nil
    ) -> Bool {
        let expectedPresentation = presentation ?? expectation.presentation
        guard state.string("presentation") == expectedPresentation,
              state.string("transition") == "none",
              state.string("formatProvenance") == "source",
              state.string("sourceContentKind") == expectation.sourceContentKind,
              state.string("projection")?.lowercased()
                == expectation.projection.lowercased(),
              state.string("stereoLayout")?.lowercased()
                == expectation.stereoLayout.lowercased(),
              state.bool("mvHEVC") == expectation.isMVHEVC else {
            return false
        }

        let usesMainWindow = expectedPresentation == "window"
            || expectedPresentation == "portal"
        if let expected = expectation.formatSignalingProjectionKind {
            guard state.string("providerProjectionKind")?.lowercased()
                    == expected.lowercased(),
                  state.string("sampleProjectionKind")?.lowercased()
                    == expected.lowercased() else {
                return false
            }
        }
        if let compressedFormat = expectation.compressedFormat,
           compressedFormatFactsMatch(state, expectation: compressedFormat) == false {
            return false
        }
        let contentTypeKey = usesMainWindow
            ? "windowComponentContentType"
            : "surfaceContentType"
        guard state.string(contentTypeKey)?.lowercased()
            == expectation.contentType.lowercased() else {
            return false
        }
        if let expected = expectation.actualViewingMode {
            let key = usesMainWindow ? "actualViewingMode" : "surfaceActualViewingMode"
            guard state.string(key)?.lowercased() == expected.lowercased() else {
                return false
            }
        }
        let expectedImmersiveMode = expectedPresentation == "portal"
            ? "portal"
            : expectation.actualImmersiveMode
        if let expected = expectedImmersiveMode {
            let key = usesMainWindow
                ? "actualImmersiveMode"
                : "surfaceActualImmersiveMode"
            guard state.string(key)?.lowercased() == expected.lowercased() else {
                return false
            }
        }
        if let expected = expectation.actualSpatialVideoMode {
            let key = usesMainWindow
                ? "actualSpatialVideoMode"
                : "surfaceActualSpatialVideoMode"
            guard state.string(key)?.lowercased() == expected.lowercased() else {
                return false
            }
        }
        return usesMainWindow
            ? state.bool("videoVisible") == true
                && state.bool("displayedPixel") == true
            : state.bool("surfaceSettled") == true
                && state.bool("surfaceRenderingReady") == true
                && state.bool("displayedPixel") == true
    }

    private func compressedFormatFactsMatch(
        _ state: RegressionStateSnapshot,
        expectation: CompressedFormatExpectation
    ) -> Bool {
        guard state.string("providerCodecName")?.lowercased()
                == expectation.providerCodecName.lowercased(),
              state.string("providerCodecTag")?.lowercased()
                == expectation.providerCodecTag.lowercased(),
              state.string("sampleMediaSubtype")?.lowercased()
                == expectation.sampleMediaSubtype.lowercased() else {
            return false
        }
        if let token = expectation.providerTransferToken,
           state.string("providerTransferFunction")?.lowercased()
                .contains(token.lowercased()) != true {
            return false
        }
        if let token = expectation.sampleTransferToken,
           state.string("sampleTransferFunction")?.lowercased()
                .contains(token.lowercased()) != true {
            return false
        }
        if expectation.requiredProviderConfigurationAtoms.isEmpty == false {
            guard let configuration = state.string("providerCodecConfiguration") else {
                return false
            }
            let actualAtoms = Set(
                configuration.split(separator: ",").map {
                    String($0).lowercased()
                }
            )
            let requiredAtoms = Set(
                expectation.requiredProviderConfigurationAtoms.map {
                    $0.lowercased()
                }
            )
            guard requiredAtoms.isSubset(of: actualAtoms) else { return false }
        }
        if let expected = expectation.sampleHasDvcC,
           state.bool("sampleHasDvcC") != expected {
            return false
        }
        if let expected = expectation.sampleHasDvvC,
           state.bool("sampleHasDvvC") != expected {
            return false
        }
        return true
    }

    private func assertPlaybackIdentityIsReady(
        _ state: RegressionStateSnapshot,
        context: String,
        requiresCurrentPixelEpoch: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let session = state.string("session") else {
            XCTFail("\(context): session was not exposed.", file: file, line: line)
            return
        }
        XCTAssertNotEqual(session, "none", context, file: file, line: line)
        guard let playbackEntity = state.string("playbackEntity") else {
            XCTFail("\(context): playbackEntity was not exposed.", file: file, line: line)
            return
        }
        XCTAssertNotEqual(playbackEntity, "none", context, file: file, line: line)
        let componentRevision = state.uint64("videoComponentRevision")
        XCTAssertNotNil(componentRevision, context, file: file, line: line)
        XCTAssertEqual(
            state.uint64("boundVideoComponentRevision"),
            componentRevision,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            state.uint64("rendererPixelVideoComponentRevision"),
            componentRevision,
            context,
            file: file,
            line: line
        )
        guard let streamEpoch = state.uint64("streamEpoch") else {
            XCTFail("\(context): streamEpoch was not exposed.", file: file, line: line)
            return
        }
        if requiresCurrentPixelEpoch {
            guard let rendererPixelStreamEpoch = state.uint64(
                "rendererPixelStreamEpoch"
            ) else {
                XCTFail(
                    "\(context): rendererPixelStreamEpoch was not exposed.",
                    file: file,
                    line: line
                )
                return
            }
            XCTAssertEqual(
                rendererPixelStreamEpoch,
                streamEpoch,
                context,
                file: file,
                line: line
            )
        }
        XCTAssertNotNil(
            state.uint64("lastRendererInputGraphRevision"),
            context,
            file: file,
            line: line
        )
        XCTAssertNotNil(
            state.uint64("lastRendererInputFormatRevision"),
            context,
            file: file,
            line: line
        )
    }

    private func assertStablePlaybackIdentity(
        from baseline: RegressionStateSnapshot,
        to current: RegressionStateSnapshot,
        expectsSameFormatRevision: Bool,
        requiresCurrentPixelEpoch: Bool = true,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertPlaybackIdentityIsReady(
            current,
            context: context,
            requiresCurrentPixelEpoch: requiresCurrentPixelEpoch,
            file: file,
            line: line
        )
        XCTAssertEqual(
            current.string("session"), baseline.string("session"),
            context, file: file, line: line
        )
        XCTAssertEqual(
            current.string("playbackEntity"), baseline.string("playbackEntity"),
            context, file: file, line: line
        )
        XCTAssertEqual(
            current.uint64("videoComponentRevision"),
            baseline.uint64("videoComponentRevision"),
            context, file: file, line: line
        )
        XCTAssertEqual(
            current.uint64("lastRendererInputGraphRevision"),
            baseline.uint64("lastRendererInputGraphRevision"),
            context, file: file, line: line
        )
        if expectsSameFormatRevision {
            XCTAssertEqual(
                current.uint64("lastRendererInputFormatRevision"),
                baseline.uint64("lastRendererInputFormatRevision"),
                context,
                file: file,
                line: line
            )
        }
    }

    @MainActor
    func testRealHEVCMOVAcrossWindowDockedAndPanoramaRoundTrips() async throws {
        continueAfterFailure = true
        var observedFailures: [String] = []
        defer {
            if observedFailures.isEmpty == false {
                XCTFail(observedFailures.joined(separator: "\n"))
            }
        }
        try await exerciseRealMediaAcrossPresentations(
            filename: "applle.MOV",
            pickerPath: ["Samples", "CameraOriginals", "Apple"],
            pickerLabels: ["applle", "applle.MOV"],
            projectionLabel: "360°",
            stereoLayoutLabel: "Mono",
            evidenceSlug: "real-hevc-mov",
            metadata:
                "MOV; HEVC Main; 2200x2200; yuvj420p; AAC stereo; 20.533 seconds",
            observedFailures: &observedFailures
        )
    }

    @MainActor
    func testRealHEVC180AcrossWindowDockedAndPanoramaRoundTrips() async throws {
        continueAfterFailure = true
        var observedFailures: [String] = []
        defer {
            if observedFailures.isEmpty == false {
                XCTFail(observedFailures.joined(separator: "\n"))
            }
        }
        try await exerciseRealMediaAcrossPresentations(
            filename: "HNVR-158_H_4096p_8K_LR_180_clip.mp4",
            pickerPath: ["Samples", "Spatial", "Stereo180"],
            pickerLabels: [
                "HNVR-158_H_4096p_8K_LR_180_clip",
                "HNVR-158_H_4096p_8K_LR_180_clip.mp4"
            ],
            projectionLabel: "180°",
            stereoLayoutLabel: "Side-by-Side",
            evidenceSlug: "real-hevc-180-side-by-side",
            metadata:
                "MP4; HEVC Main; 8192x4096; AAC stereo; 60.043 seconds; 180 degrees Side-by-Side",
            observedFailures: &observedFailures
        )
    }

    @MainActor
    func testRealAV1360AcrossWindowDockedAndPanoramaRoundTrips() async throws {
        continueAfterFailure = true
        var observedFailures: [String] = []
        defer {
            if observedFailures.isEmpty == false {
                XCTFail(observedFailures.joined(separator: "\n"))
            }
        }
        try await exerciseRealMediaAcrossPresentations(
            filename: "insta360.mp4",
            pickerPath: ["Samples", "Spatial", "Panorama"],
            pickerLabels: ["insta360", "insta360.mp4"],
            projectionLabel: "360°",
            stereoLayoutLabel: "Mono",
            evidenceSlug: "real-av1-360-mono",
            metadata:
                "MP4; AV1 Main; 7680x3840; Opus stereo; 60.026 seconds; 360 degrees Mono",
            observedFailures: &observedFailures
        )
    }

    @MainActor
    func testRealNHVR180ExplicitPanoramaRoundTrip() async throws {
        try await exerciseRealMediaExplicitPanoramaRoundTrip(
            filename: "HNVR-158_H_4096p_8K_LR_180_clip.mp4",
            pickerPath: ["Samples", "Spatial", "Stereo180"],
            pickerLabels: [
                "HNVR-158_H_4096p_8K_LR_180_clip",
                "HNVR-158_H_4096p_8K_LR_180_clip.mp4"
            ],
            projectionLabel: "180°",
            stereoLayoutLabel: "Side-by-Side",
            evidenceSlug: "real-nhvr-explicit-panorama"
        )
    }

    @MainActor
    func testRealInsta360ExplicitPanoramaRoundTrip() async throws {
        try await exerciseRealMediaExplicitPanoramaRoundTrip(
            filename: "insta360.mp4",
            pickerPath: ["Samples", "Spatial", "Panorama"],
            pickerLabels: ["insta360", "insta360.mp4"],
            projectionLabel: "360°",
            stereoLayoutLabel: "Mono",
            evidenceSlug: "real-insta360-explicit-panorama"
        )
    }

    @MainActor
    func testRealNHVR180PersistedFormatColdLaunchStartsInPortal() async throws {
        let filename = "HNVR-158_H_4096p_8K_LR_180_clip.mp4"
        let evidenceSlug = "real-nhvr-persisted-portal-cold-launch"
        var observedFailures: [String] = []
        defer {
            if observedFailures.isEmpty == false {
                XCTFail(observedFailures.joined(separator: "\n"))
            }
        }
        let app = launchMediaLibrary()
        let identifier = "MediaLibrary-grid-video-\(filename)"
        let card = app.buttons.matching(identifier: identifier).firstMatch
        guard ensureRealMediaImported(
            card: card,
            identifier: identifier,
            pickerPath: ["Samples", "Spatial", "Stereo180"],
            pickerLabels: [
                "HNVR-158_H_4096p_8K_LR_180_clip",
                filename
            ],
            filename: filename,
            in: app
        ) else { return }

        let initialPlaybackStartedAt = Date()
        card.tap()
        resolveResumeDecisionIfNeeded(in: app)
        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        guard waitForRealMediaSurface(
            windowState,
            presentation: "window",
            timeout: 45,
            app: app,
            evidenceName: "\(evidenceSlug)-initial-window",
            observedFailures: &observedFailures
        ) != nil,
        showWindowPlaybackControls(
            windowState: windowState,
            app: app,
            evidenceName: "\(evidenceSlug)-initial-controls"
        ) else { return }
        attachElapsedTime(
            since: initialPlaybackStartedAt,
            name: "\(evidenceSlug)-initial-window-startup"
        )

        let format = app.buttons.matching(
            identifier: "PlayerUI-TopAction-videoFormat"
        ).firstMatch
        guard requireHittable(format, named: "Persisted Panorama Video Format") else {
            return
        }
        format.tap()
        let projection = app.descendants(matching: .any)[
            "PlayerUI-VideoFormat-Projection-180°"
        ].firstMatch
        guard requireHittable(projection, named: "Persisted 180° projection") else {
            return
        }
        projection.tap()
        let stereoLayout = app.descendants(matching: .any)[
            "PlayerUI-VideoFormat-Stereo Layout-Side-by-Side"
        ].firstMatch
        guard requireHittable(
            stereoLayout,
            named: "Persisted Side-by-Side layout"
        ) else { return }
        stereoLayout.tap()
        let apply = app.buttons["PlayerUI-VideoFormat-apply"].firstMatch
        guard requireHittable(apply, named: "Apply persisted Panorama format") else {
            return
        }
        apply.tap()

        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        guard waitForRealMediaSurface(
            windowState,
            presentation: "portal",
            timeout: 60,
            app: app,
            evidenceName: "\(evidenceSlug)-portal-before-first-entry",
            observedFailures: &observedFailures
        ) != nil else { return }
        let enterPanorama = app.buttons.matching(
            identifier: "PlayerUI-TopAction-resumePanorama"
        ).firstMatch
        guard requireHittable(enterPanorama, named: "Enter persisted Panorama") else {
            return
        }
        enterPanorama.tap()
        guard let firstPanorama = waitForRealMediaSurface(
            spatialState,
            presentation: "panorama",
            timeout: 60,
            app: app,
            evidenceName: "\(evidenceSlug)-before-relaunch",
            observedFailures: &observedFailures
        ), firstPanorama.hasConfirmedPanoramaAdoption() else { return }
        attachState(firstPanorama, name: "\(evidenceSlug)-persisted-state")

        app.terminate()
        let coldAppLaunchStartedAt = Date()
        app.launch()
        let relaunchedCard = app.buttons.matching(identifier: identifier).firstMatch
        guard requireHittable(
            relaunchedCard,
            named: "NHVR media after cold app relaunch",
            timeout: 30
        ) else { return }
        attachElapsedTime(
            since: coldAppLaunchStartedAt,
            name: "\(evidenceSlug)-cold-app-launch-to-library"
        )
        let coldPlaybackStartedAt = Date()
        relaunchedCard.tap()
        resolveResumeDecisionIfNeeded(in: app)

        guard let restoredPortal = waitForRealMediaSurface(
            windowState,
            presentation: "portal",
            timeout: 75,
            app: app,
            evidenceName: "\(evidenceSlug)-after-relaunch",
            observedFailures: &observedFailures
        ) else { return }
        let applicationState = app.descendants(matching: .any)[
            "PlayerUI-application-state"
        ].firstMatch
        let restoredApplicationState = RegressionStateSnapshot(
            rawValue: String(describing: applicationState.value)
        )
        XCTAssertEqual(
            restoredApplicationState.string("firstTechnicalSessionAttachment"),
            "portal",
            "The cold technical session did not attach to Portal."
        )
        XCTAssertEqual(restoredPortal.string("formatProvenance"), "userOverride")
        XCTAssertEqual(restoredPortal.string("projection"), "equirectangular180")
        XCTAssertEqual(restoredPortal.string("stereoLayout"), "sideBySide")
        guard requireHittable(
            enterPanorama,
            named: "Enter persisted Panorama after cold launch"
        ) else { return }
        enterPanorama.tap()
        guard let restoredPanorama = waitForRealMediaSurface(
            spatialState,
            presentation: "panorama",
            timeout: 75,
            app: app,
            evidenceName: "\(evidenceSlug)-panorama-after-entry",
            observedFailures: &observedFailures
        ) else { return }
        XCTAssertTrue(restoredPanorama.hasConfirmedPanoramaAdoption())
        attachElapsedTime(
            since: coldPlaybackStartedAt,
            name: "\(evidenceSlug)-cold-playback-to-panorama-first-pixel"
        )
        _ = attachRendererFramePerformance(
            in: spatialState,
            presentation: "panorama",
            evidenceName: "\(evidenceSlug)-cold-panorama-frame-performance"
        )
        attachState(restoredPanorama, name: "\(evidenceSlug)-panorama-state")
        attachScreenshot(from: app, name: "\(evidenceSlug)-panorama-frame")

        let exit = app.buttons.matching(
            identifier: "PlayerPanel-button-exit-spatial"
        ).firstMatch
        guard requireHittable(exit, named: "Return persisted Panorama to Portal") else {
            return
        }
        exit.tap()
        guard waitForRealMediaSurface(
            windowState,
            presentation: "portal",
            timeout: 60,
            app: app,
            evidenceName: "\(evidenceSlug)-portal-cleanup",
            observedFailures: &observedFailures
        ) != nil else { return }
        let settings = app.buttons.matching(
            identifier: "PlayerPanel-button-settings"
        ).firstMatch
        guard requireHittable(settings, named: "Portal Advanced Settings cleanup") else {
            return
        }
        settings.tap()
        let returnToWindow = app.buttons.matching(
            identifier: "PlayerPanel-Advanced-ReturnToMonoWindow"
        ).firstMatch
        guard requireHittable(
            returnToWindow,
            named: "Restore Flat Window after persistence acceptance"
        ) else { return }
        returnToWindow.tap()
        _ = waitForRealMediaSurface(
            windowState,
            presentation: "window",
            timeout: 60,
            app: app,
            evidenceName: "\(evidenceSlug)-window-cleanup",
            observedFailures: &observedFailures
        )
        XCTAssertTrue(observedFailures.isEmpty, observedFailures.joined(separator: "\n"))
    }

    @MainActor
    private func exerciseRealMediaExplicitPanoramaRoundTrip(
        filename: String,
        pickerPath: [String],
        pickerLabels: [String],
        projectionLabel: String,
        stereoLayoutLabel: String,
        evidenceSlug: String
    ) async throws {
        continueAfterFailure = true
        var observedFailures: [String] = []
        defer {
            if observedFailures.isEmpty == false {
                XCTFail(observedFailures.joined(separator: "\n"))
            }
        }
        let app = launchMediaLibrary()
        let identifier = "MediaLibrary-grid-video-\(filename)"
        let card = app.buttons.matching(identifier: identifier).firstMatch
        guard ensureRealMediaImported(
            card: card,
            identifier: identifier,
            pickerPath: pickerPath,
            pickerLabels: pickerLabels,
            filename: filename,
            in: app
        ) else { return }

        let initialPlaybackStartedAt = Date()
        card.tap()
        resolveResumeDecisionIfNeeded(in: app)
        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        guard waitForRealMediaSurface(
            windowState,
            presentation: "window",
            timeout: 45,
            app: app,
            evidenceName: "\(evidenceSlug)-window-initial",
            observedFailures: &observedFailures
        ) != nil else { return }
        attachElapsedTime(
            since: initialPlaybackStartedAt,
            name: "\(evidenceSlug)-initial-window-startup"
        )
        _ = try await exercisePanoramaRoundTrip(
            cycle: 1,
            projectionLabel: projectionLabel,
            stereoLayoutLabel: stereoLayoutLabel,
            windowState: windowState,
            app: app,
            evidenceSlug: evidenceSlug,
            observedFailures: &observedFailures
        )
    }

    @MainActor
    private func exerciseRealMediaAcrossPresentations(
        filename: String,
        pickerPath: [String],
        pickerLabels: [String],
        projectionLabel: String,
        stereoLayoutLabel: String,
        evidenceSlug: String,
        metadata: String,
        observedFailures: inout [String]
    ) async throws {
        let app = launchMediaLibrary()
        let identifier = "MediaLibrary-grid-video-\(filename)"
        let card = app.buttons.matching(identifier: identifier).firstMatch
        guard ensureRealMediaImported(
            card: card,
            identifier: identifier,
            pickerPath: pickerPath,
            pickerLabels: pickerLabels,
            filename: filename,
            in: app
        ) else { return }

        let metadataAttachment = XCTAttachment(
            string: "filename=\(filename)\nffprobe=\(metadata)"
        )
        metadataAttachment.name = "\(evidenceSlug)-sample-metadata"
        metadataAttachment.lifetime = .keepAlways
        add(metadataAttachment)

        let initialPlaybackStartedAt = Date()
        card.tap()
        resolveResumeDecisionIfNeeded(in: app, prefersRestart: true)
        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        guard waitForRealMediaSurface(
            windowState,
            presentation: "window",
            timeout: 45,
            app: app,
            evidenceName: "\(evidenceSlug)-window-initial",
            observedFailures: &observedFailures
        ) != nil else { return }
        attachElapsedTime(
            since: initialPlaybackStartedAt,
            name: "\(evidenceSlug)-initial-window-startup"
        )
        guard ensureRealMediaPlaybackAdvances(
            in: windowState,
            presentation: "window",
            app: app,
            evidenceName: "\(evidenceSlug)-window-initial",
            observedFailures: &observedFailures
        ) != nil else { return }
        _ = attachRendererFramePerformance(
            in: windowState,
            presentation: "window",
            evidenceName: "\(evidenceSlug)-window-initial-frame-performance"
        )

        for cycle in 1...2 {
            guard try await exerciseDockedRoundTrip(
                cycle: cycle,
                windowState: windowState,
                app: app,
                evidenceSlug: evidenceSlug,
                observedFailures: &observedFailures
            ) else { return }
        }

        for cycle in 1...2 {
            guard try await exercisePanoramaRoundTrip(
                cycle: cycle,
                projectionLabel: projectionLabel,
                stereoLayoutLabel: stereoLayoutLabel,
                windowState: windowState,
                app: app,
                evidenceSlug: evidenceSlug,
                observedFailures: &observedFailures
            ) else { return }
        }

        attachHumanReviewBoundary(
            "Review the full recording, contact sheet, and clear frames for the real \(filename) sample. Confirm actual moving video in Window, both Docked round trips, both Panorama round trips, and every return to Window; record black frames, frozen imagery, distortion beyond the intentionally selected projection, duplicate surfaces, alerts, or app termination.",
            name: "\(evidenceSlug)-human-review-boundary"
        )
    }

    @MainActor
    private func exerciseDockedRoundTrip(
        cycle: Int,
        windowState: XCUIElement,
        app: XCUIApplication,
        evidenceSlug: String,
        observedFailures: inout [String]
    ) async throws -> Bool {
        guard rewindRealMediaForNextPresentationTransition(
            in: windowState,
            app: app,
            evidenceName: "\(evidenceSlug)-dock-\(cycle)-rewind"
        ) else { return false }
        guard ensureRealMediaPlaybackAdvances(
            in: windowState,
            presentation: "window",
            app: app,
            evidenceName: "\(evidenceSlug)-dock-\(cycle)-window-before",
            requiresCurrentPixelEpoch: false,
            observedFailures: &observedFailures
        ) != nil else { return false }
        guard showWindowPlaybackControls(
            windowState: windowState,
            app: app,
            evidenceName: "\(evidenceSlug)-dock-\(cycle)-controls"
        ) else { return false }

        let dock = app.buttons.matching(
            identifier: "PlayerUI-TopAction-dock"
        ).firstMatch
        guard requireHittable(dock, named: "Dock real media cycle \(cycle)") else {
            return false
        }
        dock.tap()
        let light = app.buttons.matching(
            identifier: "PlayerUI-DockMenu-light"
        ).firstMatch
        guard requireHittable(
            light,
            named: "Dock real media with Light Mode cycle \(cycle)"
        ) else { return false }
        let dockTransitionStartedAt = Date()
        light.tap()

        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        guard waitForRealMediaSurface(
            spatialState,
            presentation: "docked",
            timeout: 45,
            app: app,
            evidenceName: "\(evidenceSlug)-dock-\(cycle)-docked",
            observedFailures: &observedFailures
        ) != nil else { return false }
        attachElapsedTime(
            since: dockTransitionStartedAt,
            name: "\(evidenceSlug)-dock-\(cycle)-transition-to-first-pixel"
        )
        guard ensureRealMediaPlaybackAdvances(
            in: spatialState,
            presentation: "docked",
            app: app,
            evidenceName: "\(evidenceSlug)-dock-\(cycle)-docked",
            observedFailures: &observedFailures
        ) != nil else { return false }
        _ = attachRendererFramePerformance(
            in: spatialState,
            presentation: "docked",
            evidenceName: "\(evidenceSlug)-dock-\(cycle)-frame-performance"
        )
        try await Task.sleep(for: .seconds(1))
        attachScreenshot(
            from: app,
            name: "\(evidenceSlug)-dock-\(cycle)-docked-clear-frame"
        )

        let exit = app.buttons.matching(
            identifier: "PlayerPanel-button-exit-spatial"
        ).firstMatch
        guard requireHittable(
            exit,
            named: "Return real media from Docked cycle \(cycle)"
        ) else { return false }
        let windowReturnStartedAt = Date()
        exit.tap()
        guard waitForRealMediaSurface(
            windowState,
            presentation: "window",
            timeout: 45,
            app: app,
            evidenceName: "\(evidenceSlug)-dock-\(cycle)-window-return",
            observedFailures: &observedFailures
        ) != nil else { return false }
        attachElapsedTime(
            since: windowReturnStartedAt,
            name: "\(evidenceSlug)-dock-\(cycle)-return-to-window-first-pixel"
        )
        guard ensureRealMediaPlaybackAdvances(
            in: windowState,
            presentation: "window",
            app: app,
            evidenceName: "\(evidenceSlug)-dock-\(cycle)-window-return",
            observedFailures: &observedFailures
        ) != nil else { return false }
        attachScreenshot(
            from: app,
            name: "\(evidenceSlug)-dock-\(cycle)-window-return-clear-frame"
        )
        return true
    }

    @MainActor
    private func exercisePanoramaRoundTrip(
        cycle: Int,
        projectionLabel: String,
        stereoLayoutLabel: String,
        windowState: XCUIElement,
        app: XCUIApplication,
        evidenceSlug: String,
        observedFailures: inout [String]
    ) async throws -> Bool {
        guard rewindRealMediaForNextPresentationTransition(
            in: windowState,
            app: app,
            evidenceName: "\(evidenceSlug)-panorama-\(cycle)-rewind"
        ) else { return false }
        guard ensureRealMediaPlaybackAdvances(
            in: windowState,
            presentation: "window",
            app: app,
            evidenceName: "\(evidenceSlug)-panorama-\(cycle)-window-before",
            requiresCurrentPixelEpoch: false,
            observedFailures: &observedFailures
        ) != nil else { return false }
        guard showWindowPlaybackControls(
            windowState: windowState,
            app: app,
            evidenceName: "\(evidenceSlug)-panorama-\(cycle)-controls"
        ) else { return false }

        let format = app.buttons.matching(
            identifier: "PlayerUI-TopAction-videoFormat"
        ).firstMatch
        guard requireHittable(
            format,
            named: "Video Format for real media Panorama cycle \(cycle)"
        ) else { return false }
        format.tap()
        let projection = app.descendants(matching: .any)[
            "PlayerUI-VideoFormat-Projection-\(projectionLabel)"
        ].firstMatch
        guard requireHittable(
            projection,
            named: "\(projectionLabel) projection cycle \(cycle)"
        ) else { return false }
        projection.tap()
        let stereoLayout = app.descendants(matching: .any)[
            "PlayerUI-VideoFormat-Stereo Layout-\(stereoLayoutLabel)"
        ].firstMatch
        guard requireHittable(
            stereoLayout,
            named: "\(stereoLayoutLabel) stereo layout cycle \(cycle)"
        ) else { return false }
        stereoLayout.tap()
        let apply = app.buttons["PlayerUI-VideoFormat-apply"].firstMatch
        guard requireHittable(
            apply,
            named: "Apply real media format cycle \(cycle)"
        ) else { return false }
        apply.tap()

        guard waitForRealMediaSurface(
            windowState,
            presentation: "portal",
            timeout: 60,
            app: app,
            evidenceName: "\(evidenceSlug)-panorama-\(cycle)-portal-after-apply",
            observedFailures: &observedFailures
        ) != nil else { return false }
        let enterPanorama = app.buttons.matching(
            identifier: "PlayerUI-TopAction-resumePanorama"
        ).firstMatch
        guard requireHittable(
            enterPanorama,
            named: "Enter real media Panorama cycle \(cycle)"
        ) else { return false }
        let panoramaTransitionStartedAt = Date()
        enterPanorama.tap()

        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        guard let panorama = waitForRealMediaSurface(
            spatialState,
            presentation: "panorama",
            timeout: 60,
            app: app,
            evidenceName: "\(evidenceSlug)-panorama-\(cycle)-spatial",
            observedFailures: &observedFailures
        ), panorama.hasConfirmedPanoramaAdoption() else {
            attachCurrentState(
                of: spatialState,
                name: "\(evidenceSlug)-panorama-\(cycle)-content-type-failure"
            )
            XCTFail("Real media Panorama did not expose confirmed RealityKit adoption.")
            return false
        }
        attachElapsedTime(
            since: panoramaTransitionStartedAt,
            name: "\(evidenceSlug)-panorama-\(cycle)-transition-to-first-pixel"
        )
        guard ensureRealMediaPlaybackAdvances(
            in: spatialState,
            presentation: "panorama",
            app: app,
            evidenceName: "\(evidenceSlug)-panorama-\(cycle)-spatial",
            observedFailures: &observedFailures
        ) != nil else { return false }
        _ = attachRendererFramePerformance(
            in: spatialState,
            presentation: "panorama",
            evidenceName: "\(evidenceSlug)-panorama-\(cycle)-frame-performance"
        )
        try await Task.sleep(for: .seconds(1))
        attachScreenshot(
            from: app,
            name: "\(evidenceSlug)-panorama-\(cycle)-clear-frame"
        )

        let exit = app.buttons.matching(
            identifier: "PlayerPanel-button-exit-spatial"
        ).firstMatch
        guard requireHittable(
            exit,
            named: "Return real media from Panorama to Portal cycle \(cycle)"
        ) else { return false }
        let portalTransitionStartedAt = Date()
        exit.tap()
        guard waitForRealMediaSurface(
            windowState,
            presentation: "portal",
            timeout: 60,
            app: app,
            evidenceName: "\(evidenceSlug)-panorama-\(cycle)-portal",
            observedFailures: &observedFailures
        ) != nil else { return false }
        attachElapsedTime(
            since: portalTransitionStartedAt,
            name: "\(evidenceSlug)-panorama-\(cycle)-return-to-portal-first-pixel"
        )
        guard ensureRealMediaPlaybackAdvances(
            in: windowState,
            presentation: "portal",
            app: app,
            evidenceName: "\(evidenceSlug)-panorama-\(cycle)-portal",
            observedFailures: &observedFailures
        ) != nil else { return false }
        _ = attachRendererFramePerformance(
            in: windowState,
            presentation: "portal",
            evidenceName: "\(evidenceSlug)-panorama-\(cycle)-portal-frame-performance"
        )

        let settings = app.buttons.matching(
            identifier: "PlayerPanel-button-settings"
        ).firstMatch
        guard requireHittable(
            settings,
            named: "Open Portal Advanced Settings cycle \(cycle)"
        ) else { return false }
        settings.tap()
        let returnToWindow = app.buttons.matching(
            identifier: "PlayerPanel-Advanced-ReturnToMonoWindow"
        ).firstMatch
        guard requireHittable(
            returnToWindow,
            named: "Return Portal to Window cycle \(cycle)"
        ) else { return false }
        let windowTransitionStartedAt = Date()
        returnToWindow.tap()
        guard waitForRealMediaSurface(
            windowState,
            presentation: "window",
            timeout: 60,
            app: app,
            evidenceName: "\(evidenceSlug)-panorama-\(cycle)-window-return",
            observedFailures: &observedFailures
        ) != nil else { return false }
        attachElapsedTime(
            since: windowTransitionStartedAt,
            name: "\(evidenceSlug)-panorama-\(cycle)-portal-to-window-first-pixel"
        )
        guard ensureRealMediaPlaybackAdvances(
            in: windowState,
            presentation: "window",
            app: app,
            evidenceName: "\(evidenceSlug)-panorama-\(cycle)-window-return",
            observedFailures: &observedFailures
        ) != nil else { return false }
        attachScreenshot(
            from: app,
            name: "\(evidenceSlug)-panorama-\(cycle)-window-return-clear-frame"
        )
        return true
    }

    @MainActor
    private func rewindRealMediaForNextPresentationTransition(
        in windowState: XCUIElement,
        app: XCUIApplication,
        evidenceName: String
    ) -> Bool {
        guard showWindowPlaybackControls(
            windowState: windowState,
            app: app,
            evidenceName: "\(evidenceName)-controls"
        ) else { return false }
        let state = RegressionStateSnapshot(
            rawValue: windowState.value as? String ?? ""
        )
        guard let position = state.double("position"),
              position.isFinite,
              position >= 0 else {
            XCTFail("\(evidenceName): playback position was unavailable.")
            return false
        }
        let rewindStepSeconds = 15.0
        guard position >= rewindStepSeconds else { return true }
        let lifecycleAfterSeek = state.string("lifecycle")?.lowercased()
        let playbackShouldResumeAfterSeek = lifecycleAfterSeek == "playing"
        let rewind = app.buttons.matching(
            identifier: "PlayerPanel-button-rewind"
        ).firstMatch
        guard requireHittable(rewind, named: "Rewind real media to beginning") else {
            return false
        }
        guard let baselineEpoch = state.uint64("streamEpoch"),
              let baselinePosition = state.double("position"),
              let baselineVideoSamples = state.uint64("videoSamples") else {
            XCTFail("\(evidenceName): rewind baseline was unavailable.")
            return false
        }
        let targetPosition = max(0, baselinePosition - rewindStepSeconds)
        rewind.tap()
        guard let rewound = waitForState(windowState, timeout: 15, where: {
            $0.string("presentation") == "window"
                && ($0.uint64("streamEpoch") ?? 0) > baselineEpoch
                && $0.string("lifecycle")?.lowercased() == lifecycleAfterSeek
                && (!playbackShouldResumeAfterSeek
                    || ($0.double("actualRate") ?? 0) > 0.5)
                && (!playbackShouldResumeAfterSeek
                    || (($0.double("position") ?? 0) >= targetPosition + 0.25
                        && ($0.uint64("videoSamples") ?? 0) > baselineVideoSamples))
                && $0.bool("seekInProgress") == false
        }) else { return false }
        attachState(rewound, name: "\(evidenceName)-one-step")
        return true
    }

    @MainActor
    private func attachElapsedTime(
        since startedAt: Date,
        name: String
    ) {
        let elapsedSeconds = Date().timeIntervalSince(startedAt)
        let value = String(format: "%.6f", elapsedSeconds)
        let attachment = XCTAttachment(string: "elapsedSeconds=\(value)")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("ENCHRON_TIMING name=\(name) elapsedSeconds=\(value)")
    }

    @MainActor
    private func attachRendererFramePerformance(
        in stateElement: XCUIElement,
        presentation: String,
        evidenceName: String
    ) -> RegressionStateSnapshot? {
        guard let initial = waitForState(stateElement, timeout: 10, where: {
            $0.string("presentation") == presentation
                && ($0.double("sourceFrameRate") ?? 0) > 0
                && ($0.uint64("rendererMetricsObservations") ?? 0) > 0
                && $0.uint64("rendererTotalFrames") != nil
                && $0.uint64("rendererDroppedFrames") != nil
                && $0.uint64("rendererCorruptedFrames") != nil
                && $0.double("rendererAccumulatedFrameDelay") != nil
        }),
        let initialMetricsObservation = initial.uint64("rendererMetricsObservations"),
        let initialPosition = initial.double("position"),
        let sourceFrameRate = initial.double("sourceFrameRate") else {
            XCTFail("\(evidenceName): renderer performance metrics were unavailable.")
            return nil
        }

        let oneSourceSecondFrameCount = UInt64(ceil(sourceFrameRate))
        let oneSourceSecond = Double(oneSourceSecondFrameCount) / sourceFrameRate
        guard let warmup = waitForState(stateElement, timeout: 10, where: {
            $0.string("presentation") == presentation
                && ($0.uint64("rendererMetricsObservations") ?? 0)
                    > initialMetricsObservation
                && ($0.double("position") ?? 0)
                    >= initialPosition + oneSourceSecond
        }),
        let warmupMetricsObservation = warmup.uint64("rendererMetricsObservations"),
        let warmupPosition = warmup.double("position"),
        let baseline = waitForState(stateElement, timeout: 10, where: {
            $0.string("presentation") == presentation
                && ($0.uint64("rendererMetricsObservations") ?? 0)
                    > warmupMetricsObservation
                && ($0.double("position") ?? 0) > warmupPosition
        }),
        let baselinePosition = baseline.double("position"),
        let baselineMetricsObservation = baseline.uint64("rendererMetricsObservations"),
        let baselineTotalFrames = baseline.uint64("rendererTotalFrames"),
        let baselineDroppedFrames = baseline.uint64("rendererDroppedFrames"),
        let baselineCorruptedFrames = baseline.uint64("rendererCorruptedFrames"),
        let baselineDelay = baseline.double("rendererAccumulatedFrameDelay") else {
            XCTFail("\(evidenceName): renderer performance metrics were unavailable.")
            return nil
        }

        guard let observed = waitForState(stateElement, timeout: 15, where: {
            $0.string("presentation") == presentation
                && ($0.uint64("rendererMetricsObservations") ?? 0)
                    > baselineMetricsObservation
                && ($0.double("position") ?? 0)
                    >= baselinePosition + oneSourceSecond
        }),
        let observedPosition = observed.double("position"),
        let observedMetricsObservation = observed.uint64("rendererMetricsObservations"),
        let observedTotalFrames = observed.uint64("rendererTotalFrames"),
        let observedDroppedFrames = observed.uint64("rendererDroppedFrames"),
        let observedCorruptedFrames = observed.uint64("rendererCorruptedFrames"),
        let observedDelay = observed.double("rendererAccumulatedFrameDelay") else {
            XCTFail("\(evidenceName): renderer frame metrics did not advance with playback.")
            return nil
        }

        guard observedTotalFrames >= baselineTotalFrames,
              observedDroppedFrames >= baselineDroppedFrames,
              observedCorruptedFrames >= baselineCorruptedFrames,
              observedMetricsObservation >= baselineMetricsObservation else {
            XCTFail("\(evidenceName): renderer metrics reset during observation.")
            return nil
        }
        let mediaSeconds = observedPosition - baselinePosition
        let processedFrames = observedTotalFrames - baselineTotalFrames
        let droppedFrames = observedDroppedFrames - baselineDroppedFrames
        let corruptedFrames = observedCorruptedFrames - baselineCorruptedFrames
        let metricsObservations = observedMetricsObservation
            - baselineMetricsObservation
        let sourceScheduledFrames = sourceFrameRate * mediaSeconds
        let accumulatedDelay = max(0, observedDelay - baselineDelay)
        guard processedFrames > 0 else {
            XCTFail("\(evidenceName): renderer frame count did not advance with playback.")
            return nil
        }
        let displayedFrames = processedFrames >= droppedFrames
            ? processedFrames - droppedFrames
            : 0
        let report = [
            "presentation=\(presentation)",
            "sourceFrameRate=\(String(format: "%.6f", sourceFrameRate))",
            "mediaSeconds=\(String(format: "%.6f", mediaSeconds))",
            "sourceScheduledFrames=\(String(format: "%.6f", sourceScheduledFrames))",
            "rendererMetricsObservations=\(metricsObservations)",
            "rendererScheduledFrames=\(processedFrames)",
            "rendererDisplayedFrames=\(displayedFrames)",
            "rendererDroppedFrames=\(droppedFrames)",
            "rendererCorruptedFrames=\(corruptedFrames)",
            "lifetimeDroppedFramesAtBaseline=\(baselineDroppedFrames)",
            "lifetimeCorruptedFramesAtBaseline=\(baselineCorruptedFrames)",
            "accumulatedFrameDelaySeconds=\(String(format: "%.6f", accumulatedDelay))",
        ].joined(separator: "\n")
        let attachment = XCTAttachment(string: report)
        attachment.name = evidenceName
        attachment.lifetime = .keepAlways
        add(attachment)
        print("ENCHRON_FRAME_PERFORMANCE name=\(evidenceName) \(report.replacingOccurrences(of: "\n", with: " "))")
        return observed
    }

    @MainActor
    private func waitForRealMediaSurface(
        _ _: XCUIElement,
        presentation: String,
        timeout: TimeInterval,
        app: XCUIApplication,
        evidenceName: String,
        observedFailures: inout [String]
    ) -> RegressionStateSnapshot? {
        let usesMainWindow = presentation == "window" || presentation == "portal"
        let stateIdentifier = usesMainWindow
            ? "PlayerUI-window-control-plane"
            : "PlayerUI-spatial-state"
        let deadline = Date().addingTimeInterval(timeout)
        var state: RegressionStateSnapshot?
        var terminalFailure: RegressionStateSnapshot?
        var lastObservedStates: [String: RegressionStateSnapshot] = [:]
        var hasObservedActivePlayback = false
        while Date() < deadline {
            if usesMainWindow {
                let applicationStateElement = app.descendants(matching: .any)[
                    "PlayerUI-application-state"
                ].firstMatch
                if applicationStateElement.exists,
                   let rawApplicationState = applicationStateElement.value as? String,
                   rawApplicationState.isEmpty == false {
                    let applicationState = RegressionStateSnapshot(
                        rawValue: rawApplicationState
                    )
                    lastObservedStates["PlayerUI-application-state"] = applicationState
                    if applicationState.bool("active") == true
                        || applicationState.string("session") != "none" {
                        hasObservedActivePlayback = true
                    }
                    if applicationState.string("lastExecutionCheckpoint")
                        == "presentation-conversion-failed"
                        || (hasObservedActivePlayback
                            && applicationState.bool("active") == false) {
                        terminalFailure = applicationState
                        break
                    }
                }
            }
            let currentStateElement = app.descendants(matching: .any)[
                stateIdentifier
            ].firstMatch
            guard currentStateElement.exists,
                  let rawValue = currentStateElement.value as? String,
                  rawValue.isEmpty == false else {
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            let current = RegressionStateSnapshot(rawValue: rawValue)
            lastObservedStates[stateIdentifier] = current
            if current.string("presentation") == presentation,
               current.string("transition") == "none",
               current.string("attached") == presentation,
               current.bool("componentReady") == true,
               current.bool("displayedPixel") == true,
               (current.uint64("videoSamples") ?? 0) > 0,
               (current.uint64("rendererInputs") ?? 0) > 0,
               (usesMainWindow || current.bool("surfaceSettled") == true),
               (presentation != "portal"
                   || (current.bool("videoVisible") == true
                       && current.string("actualImmersiveMode")?.lowercased()
                           == "portal")) {
                state = current
            }
            if current.string("lifecycle")?
                .lowercased()
                .hasPrefix("failed") == true {
                terminalFailure = current
            }
            if state != nil || terminalFailure != nil { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        if let terminalFailure {
            attachState(
                terminalFailure,
                name: "\(evidenceName)-terminal-playback-failure"
            )
            attachScreenshot(
                from: app,
                name: "\(evidenceName)-terminal-playback-failure"
            )
            attachObservedRealMediaStates(
                lastObservedStates,
                evidenceName: evidenceName
            )
            let failureDescription = terminalFailure.string("error")
                ?? terminalFailure.string("lifecycle")
                ?? "Unknown playback failure."
            observedFailures.append(
                "\(evidenceName): playback entered a terminal failure while waiting for the \(presentation) surface. \(failureDescription)"
            )
            XCTAssertEqual(app.state, .runningForeground)
            return nil
        }
        guard let state else {
            XCTFail(
                "The real media \(presentation) surface did not reach its required state within \(timeout) seconds."
            )
            attachObservedRealMediaStates(
                lastObservedStates,
                evidenceName: evidenceName
            )
            attachScreenshot(from: app, name: "\(evidenceName)-surface-failure")
            XCTAssertTrue(
                app.state == .runningForeground,
                "Enchron was no longer running in the foreground."
            )
            return nil
        }
        attachState(state, name: "\(evidenceName)-state")
        attachScreenshot(from: app, name: "\(evidenceName)-surface-observation")
        let surfaceDidNotRender: Bool
        if usesMainWindow {
            surfaceDidNotRender = state.bool("videoVisible") != true
                || state.bool("displayedPixel") != true
        } else {
            surfaceDidNotRender = state.bool("surfaceRenderingReady") != true
                || state.bool("surfaceSettled") != true
                || state.bool("displayedPixel") != true
        }
        if surfaceDidNotRender {
            observedFailures.append(
                "\(evidenceName): the real media pipeline advanced, but the wearer-visible surface did not display a video frame."
            )
        }
        XCTAssertFalse(app.alerts["Failed to Load"].exists)
        XCTAssertFalse(app.alerts["Playback Error"].exists)
        XCTAssertEqual(app.state, .runningForeground)
        return state
    }

    @MainActor
    private func attachObservedRealMediaStates(
        _ states: [String: RegressionStateSnapshot],
        evidenceName: String
    ) {
        if let window = states["PlayerUI-window-control-plane"] {
            attachState(window, name: "\(evidenceName)-window-state-at-failure")
        }
        if let spatial = states["PlayerUI-spatial-state"] {
            attachState(spatial, name: "\(evidenceName)-spatial-state-at-failure")
        }
        if let application = states["PlayerUI-application-state"] {
            attachState(
                application,
                name: "\(evidenceName)-application-state-at-failure"
            )
        }
        if states.isEmpty {
            let attachment = XCTAttachment(string: "No public playback state element was present.")
            attachment.name = "\(evidenceName)-state-elements-absent"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func ensureRealMediaPlaybackAdvances(
        in stateElement: XCUIElement,
        presentation: String,
        app: XCUIApplication,
        evidenceName: String,
        requiresCurrentPixelEpoch: Bool = true,
        observedFailures: inout [String]
    ) -> RegressionStateSnapshot? {
        var state = RegressionStateSnapshot(
            rawValue: stateElement.value as? String ?? ""
        )
        if let position = state.double("position"),
           let duration = state.double("duration"),
           duration > 0,
           duration - position < 5 {
            if state.string("lifecycle")?.lowercased() != "ended" {
                _ = waitForState(stateElement, timeout: 6) {
                    $0.string("presentation") == presentation
                        && $0.string("lifecycle")?.lowercased() == "ended"
                }
                state = RegressionStateSnapshot(
                    rawValue: stateElement.value as? String ?? ""
                )
            }
        }
        if state.string("lifecycle")?.lowercased() != "playing"
            || (state.double("actualRate") ?? 0) <= 0.1 {
            let play = app.buttons.matching(
                identifier: "PlayerPanel-button-play"
            ).firstMatch
            guard requireHittable(
                play,
                named: "Play or Replay real media in \(presentation)"
            ) else { return nil }
            play.tap()
            guard let playing = waitForState(stateElement, timeout: 15, where: {
                $0.string("presentation") == presentation
                    && $0.string("lifecycle")?.lowercased() == "playing"
                    && ($0.double("actualRate") ?? 0) > 0.5
            }) else { return nil }
            state = playing
        }
        guard let baselinePosition = state.double("position"),
              let baselineVideoSamples = state.uint64("videoSamples"),
              let baselineRendererInputs = state.uint64("rendererInputs"),
              let baselineSession = state.string("session"),
              let baselineEpoch = state.uint64("streamEpoch") else {
            attachState(state, name: "\(evidenceName)-baseline-state-invalid")
            attachScreenshot(from: app, name: "\(evidenceName)-baseline-invalid")
            XCTFail(
                "\(evidenceName) did not expose a complete playback baseline."
            )
            return nil
        }
        guard baselineSession != "none" else {
            XCTFail("\(evidenceName) exposed no active media session.")
            return nil
        }
        let usesMainWindow = presentation == "window" || presentation == "portal"
        let minimumObservationTime = ContinuousClock.now.advanced(by: .seconds(1))
        guard let continuous = waitForState(stateElement, timeout: 12, where: {
            ContinuousClock.now >= minimumObservationTime
                && $0.string("presentation") == presentation
                && $0.string("lifecycle")?.lowercased() == "playing"
                && ($0.double("position") ?? 0) >= baselinePosition + 0.25
                && ($0.uint64("videoSamples") ?? 0) > baselineVideoSamples
                && ($0.uint64("rendererInputs") ?? 0) > baselineRendererInputs
                && $0.string("session") == baselineSession
                && $0.uint64("streamEpoch") == baselineEpoch
                && $0.bool("displayedPixel") == true
                && (presentation != "portal"
                    || ($0.bool("videoVisible") == true
                        && $0.string("actualImmersiveMode")?.lowercased()
                            == "portal"))
        }) else {
            attachCurrentState(
                of: stateElement,
                name: "\(evidenceName)-continuous-state-at-failure"
            )
            attachScreenshot(from: app, name: "\(evidenceName)-continuous-failure")
            return nil
        }
        attachState(continuous, name: "\(evidenceName)-continuous-state")
        attachScreenshot(from: app, name: "\(evidenceName)-continuous-frame")
        assertStablePlaybackIdentity(
            from: state,
            to: continuous,
            expectsSameFormatRevision: true,
            requiresCurrentPixelEpoch: requiresCurrentPixelEpoch,
            context: "\(evidenceName) continuous playback"
        )
        let surfaceDidNotRender: Bool
        if usesMainWindow {
            surfaceDidNotRender = continuous.bool("videoVisible") != true
                || continuous.bool("displayedPixel") != true
        } else {
            surfaceDidNotRender = continuous.bool("surfaceRenderingReady") != true
                || continuous.bool("surfaceSettled") != true
                || continuous.bool("displayedPixel") != true
        }
        if surfaceDidNotRender {
            observedFailures.append(
                "\(evidenceName): playback time and renderer input advanced, but no wearer-visible video frame appeared."
            )
        }
        return continuous
    }

    @MainActor
    private func showWindowPlaybackControls(
        windowState: XCUIElement,
        app: XCUIApplication,
        evidenceName: String
    ) -> Bool {
        let currentStateElement = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let current = RegressionStateSnapshot(
            rawValue: currentStateElement.value as? String ?? ""
        )
        if current.string("controls") == "shown"
            && current.string("chrome") == "on" {
            return true
        }
        guard current.bool("videoVisible") == true else {
            attachState(
                current,
                name: "\(evidenceName)-visible-video-prerequisite-failure"
            )
            attachScreenshot(
                from: app,
                name: "\(evidenceName)-visible-video-prerequisite-failure"
            )
            return false
        }

        attachCurrentState(
            of: currentStateElement,
            name: "\(evidenceName)-state-failure"
        )
        attachScreenshot(from: app, name: "\(evidenceName)-failure")
        XCTFail(
            "Window controls were hidden and synthetic input cannot summon them:"
                + " the playback surface is a RealityKit input target that only real"
                + " gaze plus pinch reaches. Keep controls visible via"
                + " ENCHRON_CONTROLS_AUTO_HIDE_SECONDS or drive toggleControls"
                + " through the host-side test channel."
        )
        return false
    }

    @MainActor
    private func ensureRealMediaImported(
        card: XCUIElement,
        identifier: String,
        pickerPath: [String],
        pickerLabels: [String],
        filename: String,
        reuseExistingReference: Bool = true,
        in app: XCUIApplication
    ) -> Bool {
        if reuseExistingReference,
           waitForHittableRegisteredMediaCard(
            identifier: identifier,
            in: app,
            timeout: 30
        ) != nil {
            return true
        }

        openManageAction("Add Files", in: app)
        guard waitForFilePicker(in: app, timeout: 20) else {
            XCTFail("The system file picker did not open for real media import.")
            return false
        }
        guard navigateToFixturePath(
            pickerPath.map { [$0] },
            selectDirectory: false,
            in: app
        ) else { return false }
        guard let item = waitForHittableFilePickerItem(
            matchingAnyLabel: pickerLabels,
            in: app,
            timeout: 30
        ) else {
            attachFilePickerState(app, name: "real-media-\(filename)-missing")
            XCTFail("The configured real media file \(filename) was missing from iCloud Drive.")
            return false
        }
        selectFilePickerItem(item, in: app)
        confirmPickerIfNeeded(for: card, in: app)
        guard card.waitForExistence(timeout: 45) else {
            XCTFail("Importing real media \(filename) did not create a Media Library card.")
            return false
        }
        guard waitForHittableRegisteredMediaCard(
            identifier: identifier,
            in: app,
            timeout: 30
        ) != nil else {
            attachScreenshot(
                from: app,
                name: "real-media-\(filename)-card-not-hittable"
            )
            XCTFail(
                "Importing real media \(filename) created a card that could not be reached through the Media Library."
            )
            return false
        }
        return true
    }

    @MainActor
    private func importExactRealMediaReference(
        card: XCUIElement,
        identifier: String,
        pickerPath: [String],
        pickerLabels: [String],
        filename: String,
        in app: XCUIApplication
    ) -> Bool {
        let matchingCards = app.buttons.matching(identifier: identifier)
        while matchingCards.count > 0 {
            guard let existingCard = waitForHittableRegisteredMediaCard(
                identifier: identifier,
                in: app,
                timeout: 5
            ) else {
                XCTFail("An existing \(filename) Media Reference could not be reached for removal.")
                return false
            }
            let countBeforeRemoval = matchingCards.count
            guard removeMediaReference(existingCard, in: app) else { return false }
            let countDecreased = XCTNSPredicateExpectation(
                predicate: NSPredicate { object, _ in
                    ((object as? XCUIElementQuery)?.count ?? countBeforeRemoval)
                        < countBeforeRemoval
                },
                object: matchingCards
            )
            guard XCTWaiter.wait(for: [countDecreased], timeout: 10) == .completed else {
                XCTFail("Removing an existing \(filename) Media Reference did not reduce its duplicate count.")
                return false
            }
        }
        return ensureRealMediaImported(
            card: card,
            identifier: identifier,
            pickerPath: pickerPath,
            pickerLabels: pickerLabels,
            filename: filename,
            reuseExistingReference: false,
            in: app
        )
    }

    @MainActor
    private func addBaselineFile(
        using mediaCard: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        openManageAction("Add Files", in: app)
        guard waitForFilePicker(in: app, timeout: 20) else {
            XCTFail("The system file picker did not expose a browsable interface.")
            return false
        }
        attachFilePickerState(app, name: "baseline-file-picker-opened")
        guard navigateToGeneratedFixtureDirectory(in: app) else { return false }
        let fixture = waitForHittableFilePickerItem(
            matchingAnyLabel: [baselineFixturePickerLabel],
            in: app,
            timeout: 30
        )
        guard let fixture else {
            attachFilePickerState(app, name: "baseline-source-file-missing")
            XCTFail(
                "The baseline source file no longer exists in its system-owned location."
            )
            return false
        }
        selectFilePickerItem(fixture, in: app)
        confirmPickerIfNeeded(for: mediaCard, in: app)
        guard mediaCard.waitForExistence(timeout: 30) else {
            XCTFail("The selected file did not create a Media Reference.")
            return false
        }
        return waitForElementToBecomeHittable(mediaCard, timeout: 10)
    }

    @MainActor
    private func removeMediaReference(
        _ mediaCard: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        guard waitForElementToBecomeHittable(mediaCard, timeout: 10) else {
            XCTFail("The Media Reference card was not available for removal.")
            return false
        }
        mediaCard.press(forDuration: 1)
        let remove = app.buttons["Remove from Library"].firstMatch
        guard requireHittable(remove, named: "Remove from Library") else { return false }
        remove.tap()
        return true
    }

    @MainActor
    private func launchMediaLibrary() -> XCUIApplication {
        launchVisionProRegressionApp()
    }

    @MainActor
    private func ensureGeneratedFolderImported(
        for mediaCard: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        if mediaCard.waitForExistence(timeout: 3),
           mediaCard.isEnabled,
           mediaCard.isHittable {
            return true
        }

        let importedFolder = app.descendants(matching: .any)[
            "MediaLibrary-grid-folder-Generated"
        ].firstMatch

        if importedFolder.waitForExistence(timeout: 3) == false {
            openManageAction("Add Folder", in: app)
            guard waitForFilePicker(in: app, timeout: 20) else {
                XCTFail("The folder importer did not expose a browsable interface.")
                return false
            }
            guard navigateToGeneratedFixtureDirectory(
                in: app,
                selectDirectory: true
            ) else { return false }
            attachFilePickerState(app, name: "generated-folder-visible")
            confirmPickerIfNeeded(for: importedFolder, in: app)
        }
        guard importedFolder.waitForExistence(timeout: 30),
              waitForElementToBecomeHittable(importedFolder, timeout: 10) else {
            XCTFail("Importing Generated did not add its folder to the Media Library.")
            return false
        }
        importedFolder.tap()
        guard mediaCard.waitForExistence(timeout: 30) else {
            XCTFail(
                "Opening the imported Generated folder did not show the required media."
            )
            return false
        }
        return waitForElementToBecomeHittable(mediaCard, timeout: 10)
    }

    @MainActor
    private func openManageAction(_ actionLabel: String, in app: XCUIApplication) {
        let manage = app.buttons["Manage media library"].firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 20))
        XCTAssertTrue(manage.isEnabled)
        manage.tap()

        let action = app.buttons[actionLabel].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 12))
        XCTAssertTrue(action.isEnabled)
        action.tap()
    }

    @MainActor
    private func navigateToGeneratedFixtureDirectory(
        in app: XCUIApplication,
        selectDirectory: Bool = false
    ) -> Bool {
        navigateToFixtureDirectory(
            named: "Generated",
            selectDirectory: selectDirectory,
            in: app
        )
    }

    @MainActor
    private func navigateToFixtureDirectory(
        named directoryName: String,
        selectDirectory: Bool,
        in app: XCUIApplication
    ) -> Bool {
        navigateToFixturePath(
            [[directoryName]],
            selectDirectory: selectDirectory,
            in: app
        )
    }

    @MainActor
    private func navigateToFixturePath(
        _ pathComponents: [[String]],
        selectDirectory: Bool,
        in app: XCUIApplication
    ) -> Bool {
        let path: [[String]] = [
            ["iCloud Drive", "iCloud云盘", "iCloud 云盘"],
            ["Desktop", "桌面"],
            ["TestMedia", "Test Video", "Text Video"]
        ] + pathComponents
        for (index, labels) in path.enumerated() {
            if index == 0 {
                guard let location = waitForHittableElement(
                    matchingAnyLabel: labels,
                    in: app,
                    timeout: 15
                ) else {
                    attachFilePickerState(
                        app,
                        name: "fixture-path-missing-\(labels[0])"
                    )
                    XCTFail("The system file picker did not expose \(labels.joined(separator: "/")).")
                    return false
                }
                location.tap()
                guard waitForFilePickerNavigationTitle(
                    matchingAnyLabel: labels,
                    in: app,
                    timeout: 10
                ) else {
                    attachFilePickerState(
                        app,
                        name: "fixture-path-not-entered-\(labels[0])"
                    )
                    XCTFail("The system file picker did not enter \(labels.joined(separator: "/")).")
                    return false
                }
            } else {
                guard let folder = waitForHittableFilePickerFolder(
                    matchingAnyLabel: labels,
                    in: app,
                    timeout: 15
                ) else {
                    attachFilePickerState(
                        app,
                        name: "fixture-path-missing-\(labels[0])"
                    )
                    XCTFail("The system file picker did not expose \(labels.joined(separator: "/")).")
                    return false
                }

                if selectDirectory, index == path.count - 1 {
                    folder.tap()
                    return true
                }

                if isFilePickerFolderExpanded(folder) {
                    continue
                }

                guard openFilePickerFolder(
                    folder,
                    matchingAnyNavigationTitle: labels,
                    in: app,
                    timeout: 10
                ) else {
                    attachFilePickerState(
                        app,
                        name: "fixture-path-not-opened-\(labels[0])"
                    )
                    XCTFail("The system file picker did not open \(labels.joined(separator: "/")).")
                    return false
                }
            }
        }
        return true
    }

    @MainActor
    private func openFilePickerFolder(
        _ folder: XCUIElement,
        matchingAnyNavigationTitle labels: [String],
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        folder.tap()
        if waitForFilePickerFolderOpen(
            folder,
            matchingAnyNavigationTitle: labels,
            in: app,
            timeout: min(2, timeout)
        ) {
            return true
        }

        folder.doubleTap()
        if waitForFilePickerFolderOpen(
            folder,
            matchingAnyNavigationTitle: labels,
            in: app,
            timeout: min(3, timeout)
        ) {
            return true
        }

        guard let disclosure = waitForFilePickerDisclosureButton(
            for: folder,
            in: app,
            timeout: max(timeout - 5, 1)
        ) else {
            return false
        }
        disclosure.tap()
        return waitForFilePickerFolderOpen(
            folder,
            matchingAnyNavigationTitle: labels,
            in: app,
            timeout: min(5, timeout)
        )
    }

    @MainActor
    private func waitForFilePickerFolderOpen(
        _ folder: XCUIElement,
        matchingAnyNavigationTitle labels: [String],
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if waitForFilePickerNavigationTitle(
                matchingAnyLabel: labels,
                in: app,
                timeout: 0.1
            ) {
                return true
            }
            if folder.exists == false {
                return true
            }
            if isFilePickerFolderExpanded(folder) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    @MainActor
    private func isFilePickerFolderExpanded(_ folder: XCUIElement) -> Bool {
        guard folder.exists else { return false }
        guard let value = folder.value as? String else { return false }
        let normalizedValue = value.lowercased()
        return normalizedValue.contains("expanded")
            || normalizedValue.contains("已展开")
    }

    @MainActor
    private func waitForFilePickerDisclosureButton(
        for folder: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let folderFrame = folder.frame
            let disclosures = app.buttons.matching(
                NSPredicate(format: "identifier == 'DisclosureTriangle'")
            )
            let matchCount = min(disclosures.count, 50)
            for index in 0..<matchCount {
                let disclosure = disclosures.element(boundBy: index)
                guard disclosure.exists else { continue }
                let midpoint = CGPoint(
                    x: disclosure.frame.midX,
                    y: disclosure.frame.midY
                )
                if folderFrame.contains(midpoint) {
                    return disclosure
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    @MainActor
    private func waitForFilePickerNavigationTitle(
        matchingAnyLabel labels: [String],
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                let title = app.navigationBars.staticTexts.matching(
                    NSPredicate(format: "label == %@", label)
                ).firstMatch
                if title.exists {
                    return true
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    @MainActor
    private func waitForHittableFilePickerFolder(
        matchingAnyLabel labels: [String],
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> XCUIElement? {
        switchFilePickerToListModeIfAvailable(in: app)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let fileView = app.collectionViews["File View"].firstMatch
            for label in labels {
                let folders = fileView.cells.matching(
                    NSPredicate(format: "label == %@ OR label BEGINSWITH[c] %@", label, label)
                )
                let folder = folders.firstMatch
                if folder.exists, folder.isEnabled, folder.isHittable {
                    return folder
                }
            }

            if fileView.exists {
                fileView.swipeUp()
            } else {
                let fileScrollView = app.scrollViews["File View"].firstMatch
                if fileScrollView.exists {
                    fileScrollView.swipeUp()
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    @MainActor
    private func confirmPickerIfNeeded(
        for expectedElement: XCUIElement,
        in app: XCUIApplication
    ) {
        guard expectedElement.waitForExistence(timeout: 3) == false else { return }
        if let confirm = waitForHittableElement(
            matchingAnyLabel: ["Open", "打开", "Add", "添加", "Done", "完成"],
            in: app,
            timeout: 3
        ) {
            confirm.tap()
            return
        }
        if waitForFilePicker(in: app, timeout: 1) {
            attachFilePickerState(app, name: "file-picker-confirmation-missing")
            XCTFail("The file picker remained open without an enabled confirmation action.")
        }
    }

    @MainActor
    private func confirmPickerIfAvailable(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        if let labeledAction = waitForHittableElement(
            matchingAnyLabel: ["Open", "打开", "Add", "添加", "Done", "完成"],
            in: app,
            timeout: timeout
        ) {
            labeledAction.tap()
            return true
        }
        let systemAction = app.descendants(matching: .any)[
            "DOCPicker.actionButton"
        ].firstMatch
        if systemAction.waitForExistence(timeout: timeout),
           systemAction.isEnabled,
           systemAction.isHittable {
            systemAction.tap()
            return true
        }
        return false
    }

    @MainActor
    private func selectFilePickerItem(
        _ item: XCUIElement?,
        in app: XCUIApplication
    ) {
        guard let item else { return }
        if waitForElementToBecomeHittable(item, timeout: 1) == false {
            let fileView = app.collectionViews["File View"].firstMatch
            if fileView.exists {
                fileView.swipeDown()
            }
        }
        guard waitForElementToBecomeHittable(item, timeout: 10) else {
            attachFilePickerState(app, name: "file-picker-row-not-hittable")
            XCTFail("The selected file row did not become hittable.")
            return
        }
        item.tap()
        if item.waitForNonExistence(timeout: 2) {
            return
        }
        guard confirmPickerIfAvailable(in: app, timeout: 10) else {
            attachFilePickerState(app, name: "file-picker-selection-not-confirmed")
            XCTFail("The selected file remained in the picker without an enabled confirmation action.")
            return
        }
        XCTAssertTrue(
            item.waitForNonExistence(timeout: 10),
            "Confirming the selected file did not close the system file picker."
        )
    }

    @MainActor
    private func openWindowSubtitleMenu(in app: XCUIApplication) {
        openWindowMenu(named: "Subtitles", in: app)
    }

    @MainActor
    private func openWindowMenu(named menuName: String, in app: XCUIApplication) {
        let more = app.descendants(matching: .any)["PlayerUI-TopAction-more"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertTrue(more.isEnabled)
        more.tap()
        let labeledMenu = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", menuName))
            .firstMatch
        let menu: XCUIElement
        if menuName == "Subtitles" {
            let identifiedMenu = app.descendants(matching: .any)[
                "PlayerUI-menu-subtitles"
            ].firstMatch
            menu = identifiedMenu.waitForExistence(timeout: 1)
                ? identifiedMenu
                : labeledMenu
        } else {
            menu = labeledMenu
        }
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.isEnabled)
        menu.tap()
    }

    @MainActor
    private func closeAndReopen(
        mediaIdentifier: String,
        controlPlane: XCUIElement,
        in app: XCUIApplication
    ) throws {
        let back = app.buttons["PlayerUI-InfoBar-button-back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isEnabled)
        XCTAssertTrue(back.isHittable)
        back.tap()
        let mediaCard = app.descendants(matching: .any)[mediaIdentifier].firstMatch
        XCTAssertTrue(mediaCard.waitForExistence(timeout: 30))
        XCTAssertTrue(controlPlane.waitForNonExistence(timeout: 15))
        mediaCard.tap()
    }

    @MainActor
    private func waitForAccessibilityValue(
        _ element: XCUIElement,
        containing expectedText: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists,
               let value = element.value as? String,
               value.contains(expectedText) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    @MainActor
    private func assertScreenshot(
        from app: XCUIApplication,
        containsText expectedText: String,
        attachmentName: String
    ) throws {
        let screenshot = app.screenshot()
        let pngRepresentation = screenshot.pngRepresentation
        let screenshotAttachment = XCTAttachment(
            uniformTypeIdentifier: "public.png",
            name: attachmentName,
            payload: pngRepresentation,
            userInfo: nil
        )
        screenshotAttachment.lifetime = .keepAlways
        add(screenshotAttachment)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        let imageSource = try XCTUnwrap(
            CGImageSourceCreateWithData(pngRepresentation as CFData, nil)
        )
        let recognitionImage = try XCTUnwrap(
            CGImageSourceCreateThumbnailAtIndex(
                imageSource,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1_600
                ] as CFDictionary
            )
        )
        let handler = VNImageRequestHandler(
            cgImage: recognitionImage,
            options: [:]
        )
        try handler.perform([request])
        let recognizedCandidates = (request.results ?? []).flatMap { observation in
            observation.topCandidates(3).map(\.string)
        }
        let recognizedText = recognizedCandidates
            .joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        let recognizedTextAttachment = XCTAttachment(
            string: recognizedCandidates.joined(separator: "\n")
        )
        recognizedTextAttachment.name = "\(attachmentName)-recognized-text"
        recognizedTextAttachment.lifetime = .keepAlways
        add(recognizedTextAttachment)

        XCTAssertTrue(
            recognizedText.contains(expectedText),
            "The physical-device screenshot did not visibly render \(expectedText). "
                + "Vision recognized: \(recognizedCandidates)"
        )
    }

    @MainActor
    private func assertGeneratedColorBarsBecomeVisible(
        in app: XCUIApplication,
        timeout: TimeInterval,
        attachmentName: String
    ) throws {
        let windowSurface = app.descendants(matching: .any)["WindowPlayback-root"].firstMatch
        XCTAssertTrue(
            windowSurface.waitForExistence(timeout: 5),
            "The Window playback surface was not available for rendered-pixel inspection."
        )
        let deadline = Date().addingTimeInterval(timeout)
        var lastScreenshot = app.screenshot()
        var lastChromaticPixelRatio = 0.0
        while Date() < deadline {
            lastScreenshot = app.screenshot()
            lastChromaticPixelRatio = try generatedColorBarPixelRatio(
                in: lastScreenshot,
                surfaceFrame: windowSurface.frame,
                applicationFrame: app.frame
            )
            if lastChromaticPixelRatio >= 0.20 {
                attachScreenshot(lastScreenshot, name: attachmentName)
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        attachScreenshot(lastScreenshot, name: attachmentName)
        XCTFail(
            "The generated color-bar fixture did not become wearer-visible within "
                + "\(timeout) seconds; chromatic pixel ratio was "
                + String(format: "%.3f", lastChromaticPixelRatio) + "."
        )
    }

    private func generatedColorBarPixelRatio(
        in screenshot: XCUIScreenshot,
        surfaceFrame: CGRect,
        applicationFrame: CGRect
    ) throws -> Double {
        let screenshotData = screenshot.pngRepresentation
        let imageSource = try XCTUnwrap(
            CGImageSourceCreateWithData(screenshotData as CFData, nil)
        )
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        guard applicationFrame.width > 0, applicationFrame.height > 0 else { return 0 }

        let inspectedSurface = CGRect(
            x: surfaceFrame.minX + surfaceFrame.width * 0.08,
            y: surfaceFrame.minY + surfaceFrame.height * 0.08,
            width: surfaceFrame.width * 0.84,
            height: surfaceFrame.height * 0.58
        )
        let imageRect = CGRect(
            x: (inspectedSurface.minX - applicationFrame.minX)
                / applicationFrame.width * CGFloat(image.width),
            y: (inspectedSurface.minY - applicationFrame.minY)
                / applicationFrame.height * CGFloat(image.height),
            width: inspectedSurface.width / applicationFrame.width * CGFloat(image.width),
            height: inspectedSurface.height / applicationFrame.height * CGFloat(image.height)
        ).integral.intersection(
            CGRect(
                x: 0,
                y: 0,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        let cropped = try XCTUnwrap(image.cropping(to: imageRect))

        let sampleWidth = 96
        let sampleHeight = 64
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        let drewImage = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: sampleWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(
                cropped,
                in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
            )
            return true
        }
        guard drewImage else { return 0 }

        var chromaticPixelCount = 0
        for pixelOffset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[pixelOffset])
            let green = Int(pixels[pixelOffset + 1])
            let blue = Int(pixels[pixelOffset + 2])
            let highestComponent = max(red, max(green, blue))
            let lowestComponent = min(red, min(green, blue))
            if highestComponent >= 140,
               highestComponent - lowestComponent >= 80 {
                chromaticPixelCount += 1
            }
        }
        return Double(chromaticPixelCount) / Double(sampleWidth * sampleHeight)
    }

    @MainActor
    private func attachScreenshot(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(
            uniformTypeIdentifier: "public.png",
            name: name,
            payload: screenshot.pngRepresentation,
            userInfo: nil
        )
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitForElementToBecomeHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isEnabled, element.isHittable {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    @MainActor
    private func waitForFilePicker(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let labels = [
                "Browse", "浏览", "Recents", "最近项目", "iCloud Drive", "iCloud云盘",
                "iCloud 云盘"
            ]
            if labels.contains(where: { label in
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", label))
                    .firstMatch.exists
            }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    @MainActor
    private func waitForHittableElement(
        matchingAnyLabel labels: [String],
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                let exactMatches = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", label))
                if let element = firstHittableElement(in: exactMatches) {
                    return element
                }

                let prefixedMatches = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label BEGINSWITH[c] %@", label))
                if let element = firstHittableElement(in: prefixedMatches) {
                    return element
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    @MainActor
    private func waitForHittableFilePickerItem(
        matchingAnyLabel labels: [String],
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> XCUIElement? {
        switchFilePickerToListModeIfAvailable(in: app)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                let cells = app.cells.matching(
                    NSPredicate(format: "label BEGINSWITH[c] %@", label)
                )
                if let cell = firstHittableElement(in: cells) {
                    return cell
                }
                let filenames = app.staticTexts.matching(
                    NSPredicate(format: "label BEGINSWITH[c] %@", label)
                )
                if let filename = firstHittableElement(in: filenames) {
                    return filename
                }
            }

            let fileView = app.collectionViews["File View"].firstMatch
            if fileView.exists {
                fileView.swipeUp()
            } else {
                let fileScrollView = app.scrollViews["File View"].firstMatch
                if fileScrollView.exists {
                    fileScrollView.swipeUp()
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    @MainActor
    private func switchFilePickerToListModeIfAvailable(in app: XCUIApplication) {
        let modeButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'DOC.itemCollectionMenuButton.'")
        ).firstMatch
        guard modeButton.exists else { return }
        if ["List", "列表"].contains(modeButton.label) { return }

        modeButton.tap()
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            for label in ["List", "列表"] {
                let option = app.buttons
                    .matching(NSPredicate(format: "label == %@", label))
                    .firstMatch
                if option.exists, option.isEnabled {
                    option.tap()
                    Thread.sleep(forTimeInterval: 0.5)
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    @MainActor
    private func firstHittableElement(in query: XCUIElementQuery) -> XCUIElement? {
        let matchCount = min(query.count, 20)
        for index in 0..<matchCount {
            let element = query.element(boundBy: index)
            if element.exists, element.isEnabled, element.isHittable {
                return element
            }
        }
        return nil
    }

    @MainActor
    private func attachFilePickerState(_ app: XCUIApplication, name: String) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        attachScreenshot(from: app, name: name)
    }
}
