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
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-loadFailure-panel"].exists)

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

        openManageAction("Add Folder Contents", in: app)
        guard waitForFilePicker(in: app, timeout: 20) else {
            XCTFail("The folder importer did not expose a browsable interface.")
            return false
        }
        guard navigateToGeneratedFixtureDirectory(
            in: app,
            selectDirectory: true
        ) else { return false }
        attachFilePickerState(app, name: "generated-folder-visible")
        confirmPickerIfNeeded(for: mediaCard, in: app)
        guard mediaCard.waitForExistence(timeout: 30) else {
            XCTFail(
                "Importing the Generated folder did not add the required registered media."
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
        XCTAssertTrue(action.waitForExistence(timeout: 5))
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
        let path: [[String]] = [
            ["iCloud Drive", "iCloud云盘", "iCloud 云盘"],
            ["Desktop", "桌面"],
            ["TestMedia"],
            [directoryName]
        ]
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

                guard let disclosure = waitForFilePickerDisclosureButton(
                    for: folder,
                    in: app,
                    timeout: 3
                ) else {
                    attachFilePickerState(
                        app,
                        name: "fixture-folder-disclosure-missing-\(labels[0])"
                    )
                    XCTFail("The system file picker did not expose the navigation control for \(labels.joined(separator: "/")).")
                    return false
                }
                disclosure.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                ).tap()
                if index == path.count - 1 {
                    return true
                }
                guard waitForFilePickerFolderOpen(
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
            if isFilePickerFolderExpanded(folder) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    @MainActor
    private func isFilePickerFolderExpanded(_ folder: XCUIElement) -> Bool {
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
                app.swipeUp()
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
                let scrollView = app.scrollViews.firstMatch
                if scrollView.exists {
                    scrollView.swipeUp()
                } else {
                    app.swipeUp()
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
                let option = app.descendants(matching: .any)
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
