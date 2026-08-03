import XCTest

/// Device diagnostics for the current Vision Pro UI/playback defects.
/// Uses the production media library (no `ENCHRON_UI_TESTING` fixtures).
nonisolated final class VisionProIssueDiagnosticsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        throw XCTSkip("These diagnostics require Apple Vision Pro.")
#endif
    }

    @MainActor
    func testInventoryLibraryMediaCards() throws {
        let app = launchProductionApp()
        let cards = mediaCards(in: app)
        XCTAssertFalse(cards.isEmpty, "Device library has no media cards.")
        let names = cards.map(\.identifier)
        let inventory = XCTAttachment(string: names.joined(separator: "\n"))
        inventory.name = "library-media-inventory"
        inventory.lifetime = .keepAlways
        add(inventory)
        attachScreenshot(name: "00-library-inventory", app: app)
        XCTAssertGreaterThanOrEqual(cards.count, 1)
    }

    @MainActor
    func testLibraryGridCardHeightsAreAligned() throws {
        let app = launchProductionApp()
        let cards = mediaCards(in: app)
        XCTAssertGreaterThanOrEqual(
            cards.count,
            2,
            "Need at least two media cards to judge height alignment. Hierarchy: \(app.debugDescription)"
        )
        attachScreenshot(name: "01-library-grid", app: app)

        let heights = cards.map { $0.frame.height }
        let minHeight = heights.min() ?? 0
        let maxHeight = heights.max() ?? 0
        XCTAssertEqual(
            maxHeight,
            minHeight,
            accuracy: 1.0,
            "Media cards are vertically uneven. heights=\(heights)"
        )
    }

    @MainActor
    func testLoadingUsesSystemWindowAndProductSpinner() throws {
        let app = launchProductionApp(controlsAutoHideSeconds: 300)
        let card = try XCTUnwrap(mediaCards(in: app).first)
        let cardLabel = card.identifier
        card.tap()
        resolveResumePromptIfNeeded(in: app)

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        XCTAssertTrue(
            controlPlane.waitForExistence(timeout: 20),
            "Playback never mounted the Window control plane."
        )

        let spinner = app.descendants(matching: .any)["PlayerUI-loading-spinner"].firstMatch
        let plate = app.descendants(matching: .any)["PlayerUI-window-loading-plate"].firstMatch
        // Poll briefly; loading can be short on warm device media.
        var sawSpinner = false
        var sawLoadingPlate = false
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let checkpoint = PlaybackCheckpoint(
                rawValue: controlPlane.value as? String ?? ""
            )
            if plate.exists {
                sawLoadingPlate = true
                break
            }
            if spinner.exists {
                sawSpinner = true
                break
            }
            if checkpoint.lifecycle?.lowercased().contains("playing") == true
                || checkpoint.bool("displayedPixel") == true {
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        attachScreenshot(name: "02-loading-or-early-playback", app: app)
        attachControlPlane(name: "02-loading-state", controlPlane: controlPlane)

        XCTAssertFalse(
            sawLoadingPlate,
            "Loading must use the automatic system Window without a custom glass plate."
        )
        if sawSpinner {
            XCTAssertTrue(
                spinner.exists
                    || PlaybackCheckpoint(
                        rawValue: controlPlane.value as? String ?? ""
                    ).bool("displayedPixel") == true,
                "The product LoadingSpinner must remain until video becomes visible."
            )
        }

        try awaitPlayingOrCollectFailure(in: app, controlPlane: controlPlane, label: cardLabel)
        attachScreenshot(name: "03-playing-after-load", app: app)
        XCTAssertFalse(
            spinner.exists,
            "LoadingSpinner must dismiss once video is visible."
        )
    }

    @MainActor
    func testProductionRealityViewTapTogglesControls() throws {
        let app = launchProductionApp(controlsAutoHideSeconds: 300)
        let playingCard = try openFirstPlayableMedia(in: app)

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        XCTAssertTrue(controlPlane.waitForExistence(timeout: 30))
        waitForLifecycle("playing", in: controlPlane, timeout: 45)

        XCTAssertFalse(
            app.descendants(matching: .any)["PlayerUI-surface-toggle"].firstMatch.exists,
            "Production RealityView interaction must not rely on an XCUI-only surface Button."
        )

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "production-reality-view-accessibility-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)

        let playbackSurface = app.buttons["Playback surface"].firstMatch
        XCTAssertTrue(
            playbackSurface.waitForExistence(timeout: 10),
            "The production RealityView must expose its own accessibility surface. Playing media: \(playingCard)"
        )
        XCTAssertTrue(
            playbackSurface.isHittable,
            "The production RealityView exists but XCUI cannot tap it. frame=\(playbackSurface.frame)"
        )

        let before = PlaybackCheckpoint(
            rawValue: controlPlane.value as? String ?? ""
        )
        let expectedControls = before.string("controls") == "shown" ? "hidden" : "shown"
        attachScreenshot(name: "04-production-reality-view-before-tap", app: app)

        playbackSurface.tap()

        let deadline = Date().addingTimeInterval(8)
        var after = PlaybackCheckpoint(rawValue: controlPlane.value as? String ?? "")
        while Date() < deadline {
            after = PlaybackCheckpoint(rawValue: controlPlane.value as? String ?? "")
            if after.string("controls") == expectedControls {
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        attachScreenshot(name: "05-production-reality-view-after-tap", app: app)
        attachControlPlane(name: "05-production-reality-view-after-tap", controlPlane: controlPlane)
        XCTAssertEqual(
            after.string("controls"),
            expectedControls,
            "The production RealityView tap did not toggle Window Playback controls. before=\(before.rawValue) after=\(after.rawValue)"
        )
    }

    @MainActor
    func testWindowTopChromeReceivesTapAboveRealityViewTarget() throws {
        let app = launchProductionApp(controlsAutoHideSeconds: 300)
        let playingCard = try openFirstPlayableMedia(in: app)

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        XCTAssertTrue(controlPlane.waitForExistence(timeout: 30))
        waitForLifecycle("playing", in: controlPlane, timeout: 45)

        let videoFormat = app.buttons["PlayerUI-TopAction-videoFormat"].firstMatch
        XCTAssertTrue(
            videoFormat.waitForExistence(timeout: 10),
            "Window top chrome did not appear for playing media \(playingCard)."
        )
        XCTAssertTrue(
            videoFormat.isHittable,
            "Video Format exists but is not hittable above the RealityView target. frame=\(videoFormat.frame)"
        )
        attachScreenshot(name: "06-top-chrome-before-video-format-tap", app: app)

        videoFormat.tap()

        let cancel = app.buttons["PlayerUI-VideoFormat-cancel"].firstMatch
        XCTAssertTrue(
            cancel.waitForExistence(timeout: 8),
            "Tapping Video Format did not open its menu; the RealityView target may have intercepted the tap."
        )
        attachScreenshot(name: "07-top-chrome-video-format-menu-open", app: app)
        cancel.tap()
    }

    @MainActor
    func testProgressTimeBubbleStaysInsidePlayerControlsAtBothEnds() throws {
        let app = launchProductionApp(controlsAutoHideSeconds: 300)
        _ = try openFirstPlayableMedia(in: app)

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        XCTAssertTrue(controlPlane.waitForExistence(timeout: 30))
        waitForLifecycle("playing", in: controlPlane, timeout: 45)

        let controls = app.descendants(matching: .any)["PlayerPanel-controls"].firstMatch
        let progress = app.descendants(matching: .any)["PlayerPanel-progress"].firstMatch
        let thumb = app.descendants(matching: .any)["PlayerPanel-thumb"].firstMatch
        let bubble = app.descendants(matching: .any)[
            "PlayerPanel-progress-time-bubble"
        ].firstMatch
        XCTAssertTrue(controls.waitForExistence(timeout: 10))
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertTrue(thumb.waitForExistence(timeout: 10))
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))

        let leftEndpointBubbleMinX = progress.frame.minX
            + thumb.frame.width / 2
            - bubble.frame.width / 2
        let rightEndpointBubbleMaxX = progress.frame.maxX
            - thumb.frame.width / 2
            + bubble.frame.width / 2

        attachScreenshot(name: "08-progress-bubble-endpoint-geometry", app: app)
        XCTAssertGreaterThanOrEqual(
            leftEndpointBubbleMinX,
            controls.frame.minX - 1,
            "At 0%, the time bubble crosses the left edge of Player Controls. endpointMinX=\(leftEndpointBubbleMinX) controls=\(controls.frame)"
        )
        XCTAssertLessThanOrEqual(
            rightEndpointBubbleMaxX,
            controls.frame.maxX + 1,
            "At 100%, the time bubble crosses the right edge of Player Controls. endpointMaxX=\(rightEndpointBubbleMaxX) controls=\(controls.frame)"
        )
    }

    @MainActor
    func testSurfaceTapTogglesControlsAndResetsExpandedPanels() throws {
        let app = launchProductionApp(controlsAutoHideSeconds: 300)
        let playingCard = try openFirstPlayableMedia(in: app)

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        XCTAssertTrue(controlPlane.waitForExistence(timeout: 30))
        waitForLifecycle("playing", in: controlPlane, timeout: 45)

        let playPause = app.buttons["PlayerPanel-button-play"].firstMatch
        XCTAssertTrue(playPause.waitForExistence(timeout: 10), "Playing media \(playingCard)")
        attachScreenshot(name: "04-controls-shown", app: app)

        // Expand precision timeline via scrubber double-activation path when available.
        let progress = app.descendants(matching: .any)["PlayerPanel-progress"].firstMatch
        if progress.waitForExistence(timeout: 5) {
            progress.doubleTap()
            let timeline = app.descendants(matching: .any)[
                "PlayerPanel-precision-timeline"
            ].firstMatch
            _ = timeline.waitForExistence(timeout: 3)
            attachScreenshot(name: "05-timeline-expanded", app: app)
        }

        // AppModel ignores surface taps within 0.5s of control interaction.
        Thread.sleep(forTimeInterval: 1.2)
        tapPlaybackSurface(in: app, controlPlane: controlPlane)
        let hideDeadline = Date().addingTimeInterval(8)
        var controlsHidden = false
        while Date() < hideDeadline {
            let checkpoint = PlaybackCheckpoint(
                rawValue: controlPlane.value as? String ?? ""
            )
            if checkpoint.string("controls") == "hidden" {
                controlsHidden = true
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        attachScreenshot(name: "06-controls-hidden", app: app)
        attachControlPlane(name: "06-controls-hidden", controlPlane: controlPlane)
        XCTAssertTrue(
            controlsHidden,
            "A blank-surface tap should hide Player Controls. State: \(String(describing: controlPlane.value))"
        )

        tapPlaybackSurface(in: app, controlPlane: controlPlane)
        let showDeadline = Date().addingTimeInterval(8)
        var controlsShown = false
        while Date() < showDeadline {
            let checkpoint = PlaybackCheckpoint(
                rawValue: controlPlane.value as? String ?? ""
            )
            if checkpoint.string("controls") == "shown" {
                controlsShown = true
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        attachScreenshot(name: "07-controls-reshown", app: app)
        XCTAssertTrue(
            controlsShown,
            "A second blank-surface tap should show Player Controls again. State: \(String(describing: controlPlane.value))"
        )
        XCTAssertTrue(
            playPause.waitForExistence(timeout: 5),
            "Player Controls should be interactable after reshown."
        )

        let timeline = app.descendants(matching: .any)[
            "PlayerPanel-precision-timeline"
        ].firstMatch
        XCTAssertFalse(
            timeline.exists,
            "Expanded timeline must reset after controls were hidden."
        )
    }

    @MainActor
    func testEveryLibraryVideoPlaysOrFailsOnlyForUnsupportedCodec() throws {
        continueAfterFailure = true
        let app = launchProductionApp(controlsAutoHideSeconds: 300)
        let cardIDs = mediaCards(in: app).map(\.identifier)
        XCTAssertFalse(cardIDs.isEmpty, "Device library has no media cards.")
        attachScreenshot(name: "08-library-before-all-videos", app: app)

        var report: [String] = []
        for (index, title) in cardIDs.enumerated() {
            if index > 0 || app.descendants(matching: .any)["PlayerUI-window-control-plane"].firstMatch.exists {
                dismissPlaybackIfNeeded(in: app)
            }
            let target = app.descendants(matching: .any)[title].firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 20), "Missing card \(title)")
            target.tap()
            resolveResumePromptIfNeeded(in: app)

            let controlPlane = app.descendants(matching: .any)[
                "PlayerUI-window-control-plane"
            ].firstMatch
            let failure = app.descendants(matching: .any)["PlayerUI-loadFailure-panel"].firstMatch
            var opened = false
            let openDeadline = Date().addingTimeInterval(30)
            while Date() < openDeadline {
                resolveResumePromptIfNeeded(in: app)
                if controlPlane.exists || failure.exists {
                    opened = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
            XCTAssertTrue(opened, "\(title) neither opened playback nor showed a load failure.")

            attachScreenshot(name: String(format: "09-%02d-%@", index, sanitized(title)), app: app)

            if failure.exists {
                let message = failureMessage(in: app, failure: failure)
                attachControlPlane(name: "fail-\(index)", controlPlane: controlPlane)
                // Only true unsupported-codec messaging is allowed. Format-description
                // construction failures (-12710 / CMVideoFormatDescription) are product
                // defects for supported H.264/H.265/AV1 assets and must fail the suite.
                let unsupported = message.localizedCaseInsensitiveContains("unsupported codec")
                    || message.localizedCaseInsensitiveContains("codec not supported")
                    || message.localizedCaseInsensitiveContains("不支持的编码")
                if unsupported == false {
                    XCTFail("\(title) failed for a reason other than unsupported codec: \(message)")
                }
                report.append(
                    unsupported
                        ? "\(title)=unsupportedCodec:\(message)"
                        : "\(title)=unexpectedFailure:\(message)"
                )
                app.buttons["PlayerUI-loadFailure-secondary"].firstMatch.tap()
                continue
            }

            waitForLifecycle("playing", in: controlPlane, timeout: 45)
            let before = PlaybackCheckpoint(rawValue: controlPlane.value as? String ?? "")
            // Success requires real displayed video, not audio-only sample counts.
            XCTAssertTrue(
                before.bool("displayedPixel") == true,
                "\(title) has no displayed video pixel (audio-only is failure): \(before.rawValue)"
            )
            let spinner = app.descendants(matching: .any)["PlayerUI-loading-spinner"].firstMatch
            XCTAssertFalse(
                spinner.exists,
                "\(title) still shows LoadingSpinner after video should be visible."
            )
            Thread.sleep(forTimeInterval: 1.0)
            // videoSamples can briefly stall in the control-plane diagnostic while
            // position and displayed pixels already prove continuous playback.
            var after = PlaybackCheckpoint(rawValue: controlPlane.value as? String ?? "")
            let sampleDeadline = Date().addingTimeInterval(3)
            while Date() < sampleDeadline {
                after = PlaybackCheckpoint(rawValue: controlPlane.value as? String ?? "")
                let samplesAdvanced =
                    (after.uint64("videoSamples") ?? 0) > (before.uint64("videoSamples") ?? 0)
                let positionAdvanced =
                    (after.double("position") ?? 0) > (before.double("position") ?? 0) + 0.2
                if samplesAdvanced || (positionAdvanced && after.bool("displayedPixel") == true) {
                    break
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
            _ = attachControlPlane(
                name: String(format: "play-%02d", index),
                controlPlane: controlPlane
            )
            after = PlaybackCheckpoint(rawValue: controlPlane.value as? String ?? "")
            attachScreenshot(
                name: String(format: "10-%02d-playing-%@", index, sanitized(title)),
                app: app
            )

            XCTAssertEqual(after.lifecycle?.lowercased(), "playing", title)
            XCTAssertEqual(after.string("controls"), "shown", "\(title) controls should appear only after video is visible")
            XCTAssertGreaterThan(after.double("actualRate") ?? 0, 0.5, title)
            XCTAssertGreaterThan(
                after.double("position") ?? 0,
                (before.double("position") ?? 0) + 0.2,
                "\(title) position did not advance"
            )
            let samplesAdvanced =
                (after.uint64("videoSamples") ?? 0) > (before.uint64("videoSamples") ?? 0)
            XCTAssertTrue(
                samplesAdvanced || after.bool("displayedPixel") == true,
                "\(title) neither videoSamples nor displayedPixel advanced: before=\(before.rawValue) after=\(after.rawValue)"
            )
            XCTAssertTrue(
                after.bool("displayedPixel") == true,
                "\(title) lost displayedPixel while playing"
            )
            report.append("\(title)=playing")
        }

        let reportAttachment = XCTAttachment(string: report.joined(separator: "\n"))
        reportAttachment.name = "all-videos-report"
        reportAttachment.lifetime = .keepAlways
        add(reportAttachment)
    }

    // MARK: - Helpers

    @MainActor
    private func launchProductionApp(
        controlsAutoHideSeconds: Int = 300
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] =
            String(controlsAutoHideSeconds)
        // Terminate any leftover foreground session so launch does not restore
        // a mid-playback window from the previous XCUI process.
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
        app.launch()
        resolveResumePromptIfNeeded(in: app)
        dismissPlaybackIfNeeded(in: app)
        // Retry once if Back did not clear residual playback chrome.
        if app.descendants(matching: .any)["PlayerUI-window-control-plane"].firstMatch.exists {
            dismissPlaybackIfNeeded(in: app)
        }
        resolveResumePromptIfNeeded(in: app)
        _ = app.descendants(matching: .any)["Navigation-Ornament-tab-files"]
            .firstMatch.waitForExistence(timeout: 8)
        return app
    }

    @MainActor
    private func resolveResumePromptIfNeeded(in app: XCUIApplication) {
        // Residual viewing progress shows Resume overlay and blocks Window mount.
        // Prefer Start Over so diagnostics exercise a clean open from t=0.
        let panel = app.descendants(matching: .any)["PlayerUI-resume-panel"].firstMatch
        guard panel.waitForExistence(timeout: 2) else { return }
        let startOver = app.buttons["PlayerUI-resume-secondary"].firstMatch
        if startOver.waitForExistence(timeout: 2) {
            startOver.tap()
            return
        }
        let resume = app.buttons["PlayerUI-resume-primary"].firstMatch
        if resume.exists {
            resume.tap()
        }
    }

    @MainActor
    private func mediaCards(in app: XCUIApplication) -> [XCUIElement] {
        // visionOS XCTest can throw when reading `.count` for an empty query.
        // Probe bounded indices with `.exists` instead.
        var cards: [XCUIElement] = []
        for index in 0..<32 {
            let element = app.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "identifier BEGINSWITH 'MediaLibrary-grid-video-'"
                ))
                .element(boundBy: index)
            if element.exists {
                cards.append(element)
            } else {
                break
            }
        }
        return cards
    }

    @MainActor
    private func openFirstMedia(in app: XCUIApplication) throws {
        let card = try XCTUnwrap(mediaCards(in: app).first)
        card.tap()
        resolveResumePromptIfNeeded(in: app)
    }

    @MainActor
    @discardableResult
    private func openFirstPlayableMedia(in app: XCUIApplication) throws -> String {
        let cardIDs = mediaCards(in: app).map(\.identifier)
        XCTAssertFalse(cardIDs.isEmpty)
        for (index, title) in cardIDs.enumerated() {
            if index > 0 || app.descendants(matching: .any)["PlayerUI-window-control-plane"].firstMatch.exists {
                dismissPlaybackIfNeeded(in: app)
            }
            let current = app.descendants(matching: .any)[title].firstMatch
            XCTAssertTrue(current.waitForExistence(timeout: 20), "Missing card \(title)")
            current.tap()
            resolveResumePromptIfNeeded(in: app)
            let controlPlane = app.descendants(matching: .any)[
                "PlayerUI-window-control-plane"
            ].firstMatch
            let failure = app.descendants(matching: .any)["PlayerUI-loadFailure-panel"].firstMatch
            _ = controlPlane.waitForExistence(timeout: 20) || failure.waitForExistence(timeout: 20)
            if failure.exists {
                attachScreenshot(name: "skip-unplayable-\(index)", app: app)
                app.buttons["PlayerUI-loadFailure-secondary"].firstMatch.tap()
                continue
            }
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                let checkpoint = PlaybackCheckpoint(
                    rawValue: controlPlane.value as? String ?? ""
                )
                if checkpoint.lifecycle?.lowercased() == "playing",
                   checkpoint.bool("displayedPixel") == true {
                    return title
                }
                if checkpoint.lifecycle?.lowercased().contains("failed") == true {
                    break
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
            dismissPlaybackIfNeeded(in: app)
        }
        XCTFail("No playable media card found in the device library.")
        return ""
    }

    @MainActor
    private func awaitPlayingOrCollectFailure(
        in app: XCUIApplication,
        controlPlane: XCUIElement,
        label: String
    ) throws {
        let failure = app.descendants(matching: .any)["PlayerUI-loadFailure-panel"].firstMatch
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            if failure.exists {
                let message = failureMessage(in: app, failure: failure)
                attachControlPlane(name: "failed-\(sanitized(label))", controlPlane: controlPlane)
                attachScreenshot(name: "failed-\(sanitized(label))", app: app)
                XCTFail("\(label) failed to play: \(message)")
                return
            }
            let checkpoint = PlaybackCheckpoint(
                rawValue: controlPlane.value as? String ?? ""
            )
            if checkpoint.lifecycle?.lowercased() == "playing",
               checkpoint.bool("displayedPixel") == true {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        attachControlPlane(name: "timeout-\(sanitized(label))", controlPlane: controlPlane)
        XCTFail(
            "\(label) never reached playing. Current state: \(String(describing: controlPlane.value))"
        )
    }

    @MainActor
    private func failureMessage(
        in app: XCUIApplication,
        failure: XCUIElement
    ) -> String {
        let texts = failure.descendants(matching: .staticText).allElementsBoundByIndex
            .compactMap { $0.label.isEmpty ? nil : $0.label }
        if texts.count > 1 {
            return texts.dropFirst().joined(separator: " | ")
        }
        return failure.label
    }

    @MainActor
    private func dismissPlaybackIfNeeded(in app: XCUIApplication) {
        let closeFailure = app.buttons["PlayerUI-loadFailure-secondary"].firstMatch
        if closeFailure.exists {
            closeFailure.tap()
        }
        let back = app.buttons["PlayerUI-InfoBar-button-back"].firstMatch
        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        if controlPlane.exists {
            if back.exists == false {
                tapPlaybackSurface(in: app, controlPlane: controlPlane)
            }
            if back.waitForExistence(timeout: 5) {
                back.tap()
            }
            // Wait until playback chrome is gone.
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline, controlPlane.exists {
                if back.exists {
                    back.tap()
                }
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        if closeFailure.waitForExistence(timeout: 1) {
            closeFailure.tap()
        }
    }

    @MainActor
    private func tapPlaybackSurface(
        in app: XCUIApplication,
        controlPlane: XCUIElement
    ) {
        // Activate the production RealityView accessibility surface. This has
        // the same full-window bounds and fallback TapGesture users receive.
        let before = controlPlane.value as? String ?? ""
        agentDebugHostLog(
            message: "tapPlaybackSurface.before",
            hypothesisId: "E",
            data: ["controlPlane": before]
        )
        let surface = app.buttons["Playback surface"].firstMatch
        if surface.waitForExistence(timeout: 5) {
            agentDebugHostLog(
                message: "tapPlaybackSurface.surfaceFound",
                hypothesisId: "I",
                data: [
                    "exists": surface.exists,
                    "isHittable": surface.isHittable,
                    "frame": "\(surface.frame)",
                    "value": surface.value as? String ?? "nil"
                ]
            )
            surface.tap()
            Thread.sleep(forTimeInterval: 0.5)
            let afterActivate = controlPlane.value as? String ?? ""
            agentDebugHostLog(
                message: "tapPlaybackSurface.afterAccessibilityTap",
                hypothesisId: "I",
                data: [
                    "tapTrace": PlaybackCheckpoint(rawValue: afterActivate).string("tapTrace") ?? "missing",
                    "controls": PlaybackCheckpoint(rawValue: afterActivate).string("controls") ?? "missing",
                    "loadingSpinner": PlaybackCheckpoint(rawValue: afterActivate).string("loadingSpinner") ?? "missing",
                    "surfaceValue": surface.value as? String ?? "nil"
                ]
            )
            return
        }
        XCTFail("The production RealityView accessibility surface is unavailable.")
    }

    @MainActor
    private func agentDebugHostLog(
        message: String,
        hypothesisId: String,
        data: [String: Any]
    ) {
        // #region agent log
        let payload: [String: Any] = [
            "sessionId": "2b511f",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "runId": "xcui-surface-tap",
            "hypothesisId": hypothesisId,
            "location": "VisionProIssueDiagnosticsUITests.swift",
            "message": message,
            "data": data
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: json, encoding: .utf8) else { return }
        line.append("\n")
        print("DBG2b511f-HOST \(line)")
        let urls = [
            URL(fileURLWithPath: "/Volumes/Cortisol/DevSpace/EnchronWorkspace/Enchron/.cursor/debug-2b511f.log"),
            URL(fileURLWithPath: "/tmp/enchron-codex/debug-2b511f.log")
        ]
        for url in urls {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: url.path) == false {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { continue }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
        // #endregion
    }

    @MainActor
    private func waitForLifecycle(
        _ lifecycle: String,
        in controlPlane: XCUIElement,
        timeout: TimeInterval
    ) {
        let predicate = NSPredicate(
            format: "value CONTAINS[c] %@",
            "lifecycle=\(lifecycle)"
        )
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: controlPlane)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Playback never reached \(lifecycle). Current state: \(String(describing: controlPlane.value))"
        )
    }

    @MainActor
    private func waitForDisplayedPixel(
        in controlPlane: XCUIElement,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let checkpoint = PlaybackCheckpoint(
                rawValue: controlPlane.value as? String ?? ""
            )
            if checkpoint.bool("displayedPixel") == true {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail(
            "displayedPixel never became true. Current state: \(String(describing: controlPlane.value))"
        )
    }

    @MainActor
    private func attachScreenshot(name: String, app: XCUIApplication) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(
            screenshot: screenshot,
            quality: .original
        )
        attachment.name = "\(name)-screen"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Stable on-disk copy for agent visual review. XCTest pass/fail alone is
        // not acceptance — screenshots must show advancing picture, not only
        // spinner / black plate / audio-only chrome.
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".cursor/acceptance-shots")
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appendingPathComponent("\(name)-screen.png")
        try? screenshot.pngRepresentation.write(to: fileURL, options: .atomic)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    @MainActor
    @discardableResult
    private func attachControlPlane(
        name: String,
        controlPlane: XCUIElement
    ) -> PlaybackCheckpoint {
        let state = controlPlane.value as? String ?? "<missing control-plane value>"
        let attachment = XCTAttachment(string: state)
        attachment.name = "\(name)-state"
        attachment.lifetime = .keepAlways
        add(attachment)
        return PlaybackCheckpoint(rawValue: state)
    }

    private func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "MediaLibrary-grid-video-", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private struct PlaybackCheckpoint {
        let rawValue: String
        let fields: [String: String]

        init(rawValue: String) {
            self.rawValue = rawValue
            fields = Dictionary(
                uniqueKeysWithValues: rawValue.split(separator: ";").compactMap { item in
                    let pair = item.split(separator: "=", maxSplits: 1)
                    guard pair.count == 2 else { return nil }
                    return (String(pair[0]), String(pair[1]))
                }
            )
        }

        var lifecycle: String? { fields["lifecycle"] }
        func string(_ key: String) -> String? { fields[key] }
        func double(_ key: String) -> Double? { fields[key].flatMap(Double.init) }
        func uint64(_ key: String) -> UInt64? { fields[key].flatMap(UInt64.init) }
        func bool(_ key: String) -> Bool? { fields[key].flatMap(Bool.init) }
    }
}
