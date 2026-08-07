import Foundation
import ImageIO
import XCTest

nonisolated struct RegressionStateSnapshot: Equatable {
    let rawValue: String
    private let fields: [String: String]

    init(rawValue: String) {
        self.rawValue = rawValue
        fields = Dictionary(
            uniqueKeysWithValues: rawValue
                .split(separator: ";")
                .compactMap { field -> (String, String)? in
                    let parts = field.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    return (String(parts[0]), String(parts[1]))
                }
        )
    }

    func string(_ key: String) -> String? {
        fields[key]
    }

    func double(_ key: String) -> Double? {
        fields[key].flatMap(Double.init)
    }

    func uint64(_ key: String) -> UInt64? {
        fields[key].flatMap(UInt64.init)
    }

    func bool(_ key: String) -> Bool? {
        fields[key].flatMap(Bool.init)
    }

    func hasRecognizedPanoramaContentType() -> Bool {
        switch fields["surfaceContentType"] {
        case "equirectangular", "halfEquirectangular", "parametricImmersive":
            true
        default:
            false
        }
    }
}

enum DeviceRegressionFailure: LocalizedError {
    case targetControlsUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .targetControlsUnavailable(let presentation):
            "The \(presentation) controls did not become usable during the presentation handoff."
        }
    }
}

enum VisionProRegressionConfiguration {
    static let generatedMediaCardIdentifiers = [
        "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-30s.mp4",
        "MediaLibrary-grid-video-sdr-bframe-multiaudio-subtitles-30s.mkv"
    ]

    static func mediaCardIdentifiers(minimumCount: Int) throws -> [String] {
        let configuredIdentifiers = ProcessInfo.processInfo.environment[
            "ENCHRON_DEVICE_REGRESSION_MEDIA_CARD_IDS"
        ]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false } ?? []
        let identifiers = configuredIdentifiers.isEmpty
            ? generatedMediaCardIdentifiers
            : configuredIdentifiers
        guard identifiers.count >= minimumCount else {
            throw XCTSkip(
                "The regression configuration needs at least \(minimumCount) Media Library accessibility identifiers."
            )
        }
        return identifiers
    }

}

@MainActor
extension XCTestCase {
    func launchVisionProRegressionApp(
        controlsAutoHideSeconds: Int = 300,
        isolatesPlaybackState: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_SPATIAL_ACCEPTANCE"] = "1"
        let preferencesToken = UUID().uuidString
        app.launchEnvironment["ENCHRON_DEVICE_REGRESSION_PREFERENCES_SUITE"] =
            "app.enchron.device-regression"
        app.launchEnvironment["ENCHRON_DEVICE_REGRESSION_PREFERENCES_RESET_TOKEN"] =
            preferencesToken
        if isolatesPlaybackState {
            app.launchEnvironment["ENCHRON_TEST_MEDIA_STATE_SUITE"] = "1"
        }
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] =
            String(controlsAutoHideSeconds)
        app.launch()
        return app
    }

    func launchSpatialRegressionApp(
        controlsAutoHideSeconds: Int = 300
    ) -> XCUIApplication {
        launchVisionProRegressionApp(
            controlsAutoHideSeconds: controlsAutoHideSeconds
        )
    }

    func launchRegisteredWindowMedia(
        identifier: String,
        controlsAutoHideSeconds: Int = 300,
        isolatesPlaybackState: Bool = true
    ) -> XCUIApplication? {
        let app = launchVisionProRegressionApp(
            controlsAutoHideSeconds: controlsAutoHideSeconds,
            isolatesPlaybackState: isolatesPlaybackState
        )
        guard let card = waitForHittableRegisteredMediaCard(
            identifier: identifier,
            in: app,
            timeout: 30
        ) else {
            XCTFail(
                "Registered media \(identifier) did not become hittable while scrolling the Media Library."
            )
            attachScreenshot(from: app, name: "registered-window-media-not-hittable")
            return nil
        }
        card.tap()
        resolveResumeDecisionIfNeeded(in: app)
        return app
    }

    func launchRegisteredSpatialMedia(
        identifier: String,
        controlsAutoHideSeconds: Int = 300
    ) -> XCUIApplication? {
        let app = launchSpatialRegressionApp(
            controlsAutoHideSeconds: controlsAutoHideSeconds
        )

        guard let card = waitForHittableRegisteredMediaCard(
            identifier: identifier,
            in: app,
            timeout: 30
        ) else {
            XCTFail(
                "Registered media \(identifier) did not become hittable while scrolling the Media Library."
            )
            attachScreenshot(
                from: app,
                name: "registered-media-card-not-hittable"
            )
            return nil
        }
        card.tap()
        let resume = app.buttons["PlayerUI-resumeDecision-primary"].firstMatch
        if resume.waitForExistence(timeout: 2) {
            resume.tap()
        }
        return app
    }

    func selectDefaultScenicEnvironment(
        named title: String,
        currentTitle: String = "Scenic Environment 1",
        in app: XCUIApplication
    ) -> Bool {
        let settingsTab = app.descendants(matching: .any)[
            "Navigation-Ornament-tab-settings"
        ].firstMatch
        guard requireHittable(settingsTab, named: "Settings") else { return false }
        settingsTab.tap()

        let playbackCategory = app.descendants(matching: .any)[
            "Settings-category-playback"
        ].firstMatch
        guard playbackCategory.waitForExistence(timeout: 10),
              playbackCategory.isEnabled else {
            XCTFail("Playback Settings category did not become available.")
            return false
        }
        if playbackCategory.isSelected == false {
            playbackCategory.tap()
        }
        guard app.descendants(matching: .any)[
            "Settings-Playback-group"
        ].firstMatch.waitForExistence(timeout: 10) else {
            XCTFail("Playback Settings did not become visible.")
            return false
        }

        // SwiftUI Menu can report isHittable=false on physical visionOS while
        // still accepting its semantic XCTest tap. The observable contract is
        // an enabled menu followed by an enabled public option and the changed
        // setting title, so isHittable alone must not reject this system control.
        let defaultEnvironmentMenu = app.buttons[currentTitle].firstMatch
        guard defaultEnvironmentMenu.waitForExistence(timeout: 10),
              defaultEnvironmentMenu.isEnabled else {
            XCTFail("Default Scenic Environment menu did not become available.")
            return false
        }
        defaultEnvironmentMenu.tap()

        let option = app.buttons[title].firstMatch
        guard option.waitForExistence(timeout: 10), option.isEnabled else {
            XCTFail("Default Scenic Environment option \(title) did not appear.")
            return false
        }
        option.tap()
        guard app.buttons[title].firstMatch.waitForExistence(timeout: 10) else {
            XCTFail("Default Scenic Environment did not update to \(title).")
            return false
        }
        return true
    }

    func waitForHittableRegisteredMediaCard(
        identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let card = app.buttons.matching(identifier: identifier).firstMatch

        if card.waitForExistence(timeout: min(2, timeout)),
           card.isEnabled,
           card.isHittable {
            return card
        }

        if card.exists {
            app.activate()
            let reactivatedCard = app.buttons.matching(
                identifier: identifier
            ).firstMatch
            if reactivatedCard.waitForExistence(timeout: min(2, timeout)),
               reactivatedCard.isEnabled,
               reactivatedCard.isHittable {
                return reactivatedCard
            }
        }

        guard let libraryScrollView = largestMediaLibraryScrollView(in: app) else {
            return nil
        }

        // A previous launch can restore an arbitrary scroll offset. Normalize at
        // the beginning of the library before searching in its stable sort order.
        for _ in 0..<8 where Date() < deadline {
            libraryScrollView.swipeDown()
            if card.exists, card.isEnabled, card.isHittable {
                return card
            }
        }

        while Date() < deadline {
            if card.exists, card.isEnabled, card.isHittable {
                return card
            }
            libraryScrollView.swipeUp()
        }
        return nil
    }

    func resolveResumeDecisionIfNeeded(in app: XCUIApplication) {
        let resume = app.buttons["PlayerUI-resumeDecision-primary"].firstMatch
        if resume.waitForExistence(timeout: 2) {
            resume.tap()
            return
        }
        let restart = app.buttons["PlayerUI-resumeDecision-secondary"].firstMatch
        if restart.waitForExistence(timeout: 0.5) {
            restart.tap()
        }
    }

    func requireContinuousPlayback(
        after baseline: RegressionStateSnapshot,
        in stateElement: XCUIElement,
        app: XCUIApplication,
        name: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> RegressionStateSnapshot? {
        let baselinePosition = baseline.double("position") ?? 0
        let baselineVideoSamples = baseline.uint64("videoSamples") ?? 0
        let baselineRendererInputs = baseline.uint64("rendererInputs") ?? 0
        let baselineSession = baseline.string("session")
        let baselineEpoch = baseline.uint64("streamEpoch")
        let minimumObservationTime = ContinuousClock.now.advanced(by: .seconds(1))
        guard let continuous = waitForState(
            stateElement,
            timeout: timeout,
            file: file,
            line: line,
            where: {
                ContinuousClock.now >= minimumObservationTime
                    && $0.string("lifecycle")?.lowercased() == "playing"
                    && ($0.double("position") ?? 0) >= baselinePosition + 0.25
                    && ($0.uint64("videoSamples") ?? 0) > baselineVideoSamples
                    && ($0.uint64("rendererInputs") ?? 0) > baselineRendererInputs
                    && $0.bool("displayedPixel") == true
                    && $0.string("session") == baselineSession
                    && $0.uint64("streamEpoch") == baselineEpoch
            }
        ) else {
            attachCurrentState(of: stateElement, name: "\(name)-state-at-failure")
            attachScreenshot(from: app, name: "\(name)-failure")
            return nil
        }
        attachState(continuous, name: "\(name)-state")
        attachScreenshot(from: app, name: name)
        return continuous
    }

    func assertMechanicalAudioOutputAdvanced(
        from baseline: RegressionStateSnapshot,
        to current: RegressionStateSnapshot,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard current.bool("hasAudio") == true else { return }
        XCTAssertGreaterThan(
            current.uint64("audioSamples") ?? 0,
            baseline.uint64("audioSamples") ?? 0,
            "\(context) did not deliver additional audio samples.",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            current.uint64("audioRendererSamples") ?? 0,
            baseline.uint64("audioRendererSamples") ?? 0,
            "\(context) did not deliver additional audio renderer samples.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            current.bool("audioSessionActive"),
            true,
            "\(context) did not keep the system audio session active.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            current.string("audioOutputPorts"),
            "",
            "\(context) did not expose an active audio output route.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            current.string("audioRendererError"),
            "none",
            "\(context) reported an audio renderer error.",
            file: file,
            line: line
        )
    }

    func attachHumanReviewBoundary(_ description: String, name: String) {
        let attachment = XCTAttachment(string: description)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func largestMediaLibraryScrollView(
        in app: XCUIApplication
    ) -> XCUIElement? {
        let filesScreen = app.descendants(matching: .any)[
            "FileBrowsing-FilesScreen"
        ].firstMatch
        guard filesScreen.waitForExistence(timeout: 10) else { return nil }

        var result: XCUIElement?
        var resultArea: CGFloat = 0
        for index in 0..<8 {
            let candidate = filesScreen.scrollViews.element(boundBy: index)
            guard candidate.exists else { break }
            let area = candidate.frame.width * candidate.frame.height
            if area > resultArea {
                result = candidate
                resultArea = area
            }
        }
        return result
    }

    func restoreWindowPlaybackIfSpatialPresentationIsActive(
        in app: XCUIApplication,
        timeout: TimeInterval = 20
    ) -> Bool {
        let exitSpatial = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        guard exitSpatial.exists else { return true }

        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        guard let settledSpatialState = waitForState(
            in: app,
            identifier: "PlayerUI-spatial-state",
            timeout: timeout,
            where: {
                $0.string("presentation") == "panorama"
                    && $0.string("transition") == "none"
                    && $0.string("immersiveSpaceResidency") == "open"
                    && $0.string("attached") == "panorama"
                    && $0.bool("surfaceSettled") == true
                    && $0.bool("surfaceRenderingReady") == true
                    && $0.hasRecognizedPanoramaContentType()
            }
        ) else {
            attachCurrentState(
                of: spatialState,
                name: "spatial-baseline-before-window-restoration-failure"
            )
            attachScreenshot(
                from: app,
                name: "spatial-baseline-before-window-restoration-failure"
            )
            return false
        }
        attachState(
            settledSpatialState,
            name: "spatial-baseline-before-window-restoration"
        )
        let lifecycleBeforeReturn = settledSpatialState.uint64(
            "immersiveSpaceLifecycleRevision"
        ) ?? 0
        guard requireHittable(
            exitSpatial,
            named: "Return to Window before starting a Window handoff test",
            timeout: timeout
        ) else { return false }
        exitSpatial.tap()

        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let restored = waitForState(windowState, timeout: timeout) {
            $0.string("presentation") == "window"
                && $0.string("transition") == "none"
                && $0.string("pendingSpatialEffect") == "none"
                && $0.string("attached") == "window"
                && $0.bool("videoVisible") == true
                && $0.string("chrome") == "on"
                && ($0.uint64("immersiveSpaceLifecycleRevision") ?? 0)
                    > lifecycleBeforeReturn
        }
        guard restored != nil else {
            attachCurrentState(
                of: windowState,
                name: "window-baseline-state-at-failure"
            )
            attachCurrentState(
                of: spatialState,
                name: "spatial-state-during-window-restoration-failure"
            )
            attachScreenshot(
                from: app,
                name: "window-baseline-restoration-failure"
            )
            return false
        }
        return true
    }

    func restoreFlatWindowFormatIfNeeded(
        in app: XCUIApplication,
        timeout: TimeInterval = 25
    ) -> Bool {
        let dock = app.descendants(matching: .any)[
            "PlayerUI-TopAction-dock"
        ].firstMatch
        let format = app.descendants(matching: .any)[
            "PlayerUI-TopAction-videoFormat"
        ].firstMatch
        if dock.exists, format.exists { return true }

        let applicationState = app.descendants(matching: .any)[
            "PlayerUI-application-state"
        ].firstMatch
        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        let loadFailure = app.alerts["Failed to Load"].firstMatch
        let settings = app.descendants(matching: .any)[
            "PlayerPanel-button-settings"
        ].firstMatch
        let readinessDeadline = Date().addingTimeInterval(timeout)
        while Date() < readinessDeadline {
            if dock.exists, format.exists { return true }
            if settings.exists { break }
            if loadFailure.exists {
                attachCurrentState(
                    of: applicationState,
                    name: "automatic-panorama-entry-application-state-at-failure"
                )
                attachCurrentState(
                    of: spatialState,
                    name: "automatic-panorama-entry-spatial-state-at-failure"
                )
                attachScreenshot(
                    from: app,
                    name: "automatic-panorama-entry-failure"
                )
                XCTFail("The persisted Panorama format could not restore automatically.")
                return false
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        if settings.exists == false {
            attachCurrentState(
                of: applicationState,
                name: "window-format-restoration-application-state-at-failure"
            )
            attachCurrentState(
                of: spatialState,
                name: "window-format-restoration-spatial-state-at-failure"
            )
            attachScreenshot(
                from: app,
                name: "window-format-restoration-controls-unavailable"
            )
            XCTFail(
                "Playback controls did not reach either the Window or panoramic control surface."
            )
            return false
        }

        guard requireHittable(
            settings,
            named: "Advanced Settings for restoring Flat video format"
        ) else { return false }
        settings.tap()

        let windowFormat = app.descendants(matching: .any)[
            "PlayerPanel-Advanced-ReturnToMonoWindow"
        ].firstMatch
        guard requireHittable(
            windowFormat,
            named: "Window video format"
        ) else { return false }
        windowFormat.tap()

        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let restored = waitForState(windowState, timeout: timeout) {
            $0.string("presentation") == "window"
                && $0.string("attached") == "window"
                && $0.string("projection") == "flat"
                && $0.string("stereoLayout") == "mono"
                && $0.bool("videoVisible") == true
                && $0.string("chrome") == "on"
        }
        guard restored != nil,
              requireHittable(dock, named: "Dock after restoring Flat video format"),
              requireHittable(format, named: "Video Format after restoring Flat video format") else {
            attachCurrentState(
                of: windowState,
                name: "flat-window-format-restoration-state-at-failure"
            )
            attachScreenshot(
                from: app,
                name: "flat-window-format-restoration-failure"
            )
            return false
        }
        return true
    }

    @discardableResult
    func requireHittable(
        _ element: XCUIElement,
        named name: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let exists = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "\(name) did not appear.", file: file, line: line)
        guard exists else { return false }
        if element.isEnabled == false || element.isHittable == false {
            let attachment = XCTAttachment(
                string: """
                name=\(name)
                exists=\(exists)
                enabled=\(element.isEnabled)
                hittable=\(element.isHittable)
                frame=\(element.frame)

                \(element.debugDescription)
                """
            )
            attachment.name = "\(name)-accessibility-hit-diagnostic"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(element.isEnabled, "\(name) is disabled.", file: file, line: line)
        XCTAssertTrue(element.isHittable, "\(name) is not hittable.", file: file, line: line)
        return element.isEnabled && element.isHittable
    }

    func firstHittableElement(
        matching identifier: String,
        in query: XCUIElementQuery,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let matches = query.matching(identifier: identifier)
        while Date() < deadline {
            for index in 0..<matches.count {
                let candidate = matches.element(boundBy: index)
                if candidate.exists,
                   candidate.isEnabled,
                   candidate.isHittable {
                    return candidate
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    func waitForState(
        _ element: XCUIElement,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line,
        where predicate: (RegressionStateSnapshot) -> Bool
    ) -> RegressionStateSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = RegressionStateSnapshot(rawValue: "")
        while Date() < deadline {
            if element.exists {
                let rawValue = element.value as? String ?? ""
                if rawValue.isEmpty == false {
                    latest = RegressionStateSnapshot(rawValue: rawValue)
                    if predicate(latest) {
                        return latest
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail(
            "State did not reach the required condition. Latest value: \(latest.rawValue)",
            file: file,
            line: line
        )
        return nil
    }

    func waitForState(
        in app: XCUIApplication,
        identifier: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line,
        where predicate: (RegressionStateSnapshot) -> Bool
    ) -> RegressionStateSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        var latestValues: [String] = []
        while Date() < deadline {
            let element = app.descendants(matching: .any)[identifier].firstMatch
            if element.exists,
               let rawValue = element.value as? String,
               rawValue.isEmpty == false {
                latestValues = [rawValue]
                let snapshot = RegressionStateSnapshot(rawValue: rawValue)
                if predicate(snapshot) {
                    return snapshot
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail(
            "No current \(identifier) value reached the required condition. Latest values: \(latestValues)",
            file: file,
            line: line
        )
        return nil
    }

    func attachScreenshot(
        from app: XCUIApplication,
        name: String
    ) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        writeAcceptanceShot(screenshot, name: name)
    }

    func writeAcceptanceShot(_ screenshot: XCUIScreenshot, name: String) {
        let shots = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".cursor/acceptance-shots", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: shots,
            withIntermediateDirectories: true
        )
        let slug = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let url = shots.appendingPathComponent("\(slug)-screen.png")
        try? screenshot.pngRepresentation.write(to: url)
    }

    func requireGeneratedColorBarsAreWearerVisible(
        in app: XCUIApplication,
        timeout: TimeInterval,
        attachmentName: String,
        minimumChromaticPixelRatio: Double = 0.05,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastScreenshot = app.screenshot()
        var lastChromaticPixelRatio = 0.0
        while Date() < deadline {
            lastScreenshot = app.screenshot()
            lastChromaticPixelRatio = try chromaticPixelRatio(in: lastScreenshot)
            if lastChromaticPixelRatio >= minimumChromaticPixelRatio {
                attachScreenshot(lastScreenshot, name: attachmentName)
                attachChromaticPixelRatio(
                    lastChromaticPixelRatio,
                    minimum: minimumChromaticPixelRatio,
                    attachmentName: attachmentName
                )
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        attachScreenshot(lastScreenshot, name: attachmentName)
        attachChromaticPixelRatio(
            lastChromaticPixelRatio,
            minimum: minimumChromaticPixelRatio,
            attachmentName: attachmentName
        )
        XCTFail(
            "The generated color-bar fixture did not become wearer-visible within "
                + "\(timeout) seconds; chromatic pixel ratio was "
                + String(format: "%.4f", lastChromaticPixelRatio)
                + ", below the required "
                + String(format: "%.4f", minimumChromaticPixelRatio) + ".",
            file: file,
            line: line
        )
        return false
    }

    private func chromaticPixelRatio(in screenshot: XCUIScreenshot) throws -> Double {
        let imageSource = try XCTUnwrap(
            CGImageSourceCreateWithData(screenshot.pngRepresentation as CFData, nil)
        )
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let sampleWidth = 192
        let sampleHeight = 108
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
                image,
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

    private func attachChromaticPixelRatio(
        _ ratio: Double,
        minimum: Double,
        attachmentName: String
    ) {
        let measurement = XCTAttachment(
            string: "chromaticPixelRatio="
                + String(format: "%.4f", ratio)
                + ";minimum="
                + String(format: "%.4f", minimum)
        )
        measurement.name = "\(attachmentName)-pixel-measurement"
        measurement.lifetime = .keepAlways
        add(measurement)
    }

    func attachState(
        _ snapshot: RegressionStateSnapshot,
        name: String
    ) {
        let attachment = XCTAttachment(string: snapshot.rawValue)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func attachCurrentState(
        of element: XCUIElement,
        name: String
    ) {
        let rawValue: String
        if element.exists {
            rawValue = element.value as? String ?? "element=present;value=unavailable"
        } else {
            rawValue = "element=absent"
        }
        let attachment = XCTAttachment(string: rawValue)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func requirePresentationRequest(
        in app: XCUIApplication,
        windowState: XCUIElement,
        targetPresentation: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        let exitSpatial = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exitSpatial.exists || spatialState.exists {
                return true
            }
            if windowState.exists {
                let snapshot = RegressionStateSnapshot(
                    rawValue: windowState.value as? String ?? ""
                )
                if snapshot.string("transition") == targetPresentation
                    || snapshot.string("presentation") == targetPresentation {
                    return true
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        attachCurrentState(
            of: windowState,
            name: "\(targetPresentation)-request-window-state-at-failure"
        )
        attachCurrentState(
            of: spatialState,
            name: "\(targetPresentation)-request-target-state-at-failure"
        )
        attachScreenshot(
            from: app,
            name: "\(targetPresentation)-request-failure"
        )
        XCTFail(
            "Selecting \(targetPresentation) did not start the requested presentation."
        )
        return false
    }

    func dragDetentedSlider(
        _ element: XCUIElement,
        from currentPosition: CGFloat,
        to targetPosition: CGFloat,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard requireHittable(
            element,
            named: name,
            file: file,
            line: line
        ) else { return }
        let start = element.coordinate(
            withNormalizedOffset: CGVector(
                dx: min(max(currentPosition, 0), 1),
                dy: 0.35
            )
        )
        let end = element.coordinate(
            withNormalizedOffset: CGVector(
                dx: min(max(targetPosition, 0), 1),
                dy: 0.35
            )
        )
        start.press(forDuration: 0.2, thenDragTo: end)
    }
}
