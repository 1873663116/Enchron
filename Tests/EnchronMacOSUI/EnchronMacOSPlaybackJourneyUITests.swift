import Foundation
import XCTest

nonisolated final class EnchronMacOSPlaybackJourneyUITests: XCTestCase {
    @MainActor
    func testExpandControlReceivesMouseClick() throws {
        continueAfterFailure = false
        let fixture = try fixtureURLFromHostEnvironment()
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture.path
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment["ENCHRON_AUTOMATION_PROBE"] = "1"
        app.launch()
        defer { app.terminate() }

        startFromBeginningIfNeeded(in: app)
        _ = try waitForControlState(in: app, timeout: 40) {
            $0.lifecycle == "playing"
        }

        let expand = element("PlayerPanel-button-expand", in: app)
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        XCTAssertEqual(expand.label, "Expand playback panel")
        mouseClick(expand, name: "Expand playback panel")

        let collapsedLabel = element("PlayerPanel-button-expand", in: app)
        let collapsed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Collapse playback panel"),
            object: collapsedLabel
        )
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed)
    }

    @MainActor
    func testPlayPauseControlChangesRuntimeState() throws {
        continueAfterFailure = false
        let fixture = try fixtureURLFromHostEnvironment()
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture.path
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment["ENCHRON_AUTOMATION_PROBE"] = "1"
        app.launch()
        defer { app.terminate() }

        startFromBeginningIfNeeded(in: app)
        _ = try waitForControlState(in: app, timeout: 40) {
            $0.lifecycle == "playing"
        }

        let playPause = element("PlayerPanel-button-play", in: app)
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        XCTAssertEqual(playPause.label, "Pause")
        mouseClick(playPause, name: "Pause")

        _ = try waitForControlState(in: app, timeout: 10) {
            $0.lifecycle == "paused"
        }
        XCTAssertEqual(playPause.label, "Play")
    }

    @MainActor
    func testExpandedTimelineReflectsLivePlaybackPosition() throws {
        continueAfterFailure = false
        let fixture = try fixtureURLFromHostEnvironment()
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture.path
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment["ENCHRON_AUTOMATION_PROBE"] = "1"
        app.launch()
        defer { app.terminate() }

        startFromBeginningIfNeeded(in: app)
        _ = try waitForControlState(in: app, timeout: 40) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
        }

        let expand = element("PlayerPanel-button-expand", in: app)
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        click(expand, name: "Expand precision timeline")

        let current = try waitForControlState(in: app, timeout: 10) {
            $0.lifecycle == "playing"
        }

        let timecode = element("DesignPreview-PrecisionTimeline-timecode", in: app)
        XCTAssertTrue(timecode.waitForExistence(timeout: 5))
        let timecodeText = (timecode.value as? String) ?? timecode.label
        let displayedSeconds = try XCTUnwrap(Self.seconds(fromTimecode: timecodeText))
        XCTAssertEqual(
            displayedSeconds,
            floor(current.position),
            accuracy: 2,
            "The expanded production timeline must open at the live playback position."
        )
    }

    @MainActor
    func testRealMediaWindowDockedRoundTripAndSeekControls() throws {
        continueAfterFailure = false
        let fixture = try fixtureURLFromHostEnvironment()
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture.path
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment["ENCHRON_AUTOMATION_PROBE"] = "1"
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launchEnvironment["ENCHRON_UI_INITIAL_MENU"] = "dock"
        app.launch()
        defer { app.terminate() }

        startFromBeginningIfNeeded(in: app)

        let initial = try waitForControlState(in: app, timeout: 40) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
                && $0.session != "none"
        }
        attachScreenshot(of: app, name: "01 Window real playback")

        let darkTheatre = element("PlayerUI-DockMenu-darkTheatre", in: app)
        XCTAssertTrue(darkTheatre.waitForExistence(timeout: 10))
        mouseClick(darkTheatre, name: "Dark Theatre")

        let docked = try waitForControlState(in: app, timeout: 30) {
            $0.presentation == "docked"
                && $0.attached == "docked"
                && $0.lifecycle == "playing"
                && $0.session == initial.session
        }
        XCTAssertEqual(docked.session, initial.session)
        let exitSpatial = element("PlayerPanel-button-exit-spatial", in: app)
        XCTAssertTrue(exitSpatial.waitForExistence(timeout: 10))
        XCTAssertEqual(exitSpatial.label, "Undock")
        attachScreenshot(of: app, name: "02 Docked real playback")

        typeKey(.escape, in: app)
        let returnedWindow = try waitForControlState(in: app, timeout: 30) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
                && $0.session == initial.session
        }
        XCTAssertEqual(returnedWindow.session, initial.session)
        attachScreenshot(of: app, name: "03 Window after Docked")

        let playPause = element("PlayerPanel-button-play", in: app)
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        XCTAssertEqual(playPause.label, "Pause")
        typeKey(.space, in: app)

        let paused = try waitForControlState(in: app, timeout: 10) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "paused"
                && $0.session == initial.session
        }
        XCTAssertGreaterThan(paused.duration - paused.position, 10)

        let forward = element("PlayerPanel-button-forward", in: app)
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
        typeKey(.rightArrow, in: app)

        let forwarded = try waitForControlState(in: app, timeout: 15) {
            $0.lifecycle == "paused"
                && $0.session == initial.session
                && abs($0.position - (paused.position + 10)) <= 2
        }
        XCTAssertEqual(forwarded.position, paused.position + 10, accuracy: 2)
        attachScreenshot(of: app, name: "04 Paused after Forward 10 seconds")

        XCTAssertEqual(playPause.label, "Play")
        typeKey(.space, in: app)
        let resumed = try waitForControlState(in: app, timeout: 10) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
                && $0.session == initial.session
        }
        XCTAssertEqual(resumed.session, initial.session)
        attachScreenshot(of: app, name: "05 Resumed real playback")

        let back = element("PlayerUI-InfoBar-button-back", in: app)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        typeKey("[", modifiers: .command, in: app)
        let browser = element("FileBrowsing-FilesScreen", in: app)
        XCTAssertTrue(
            browser.waitForExistence(timeout: 10),
            "Back must stop real playback and restore the production browser."
        )
        XCTAssertTrue(
            element("PlayerUI-docked-playback", in: app).waitForNonExistence(timeout: 5),
            "Stopping playback must not leave the macOS host in Docked presentation."
        )
        XCTAssertTrue(
            element("PlayerUI-window-control-plane", in: app).waitForNonExistence(timeout: 5),
            "Stopping playback must remove the active playback controls."
        )
        attachScreenshot(of: app, name: "06 Browser after Back")
    }

    @MainActor
    func testEmbeddedSubRipRendersAcrossWindowAndDockedRealityKitPlacement() throws {
        continueAfterFailure = false
        let fixture = try fixtureURLFromHostEnvironment(
            key: "ENCHRON_MACOS_UI_SUBTITLE_FIXTURE"
        )
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture.path
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment["ENCHRON_AUTOMATION_PROBE"] = "1"
        app.launch()
        defer { app.terminate() }

        startFromBeginningIfNeeded(in: app)
        _ = try waitForControlState(in: app, timeout: 40) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
        }

        let playPause = element("PlayerPanel-button-play", in: app)
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        typeKey(.space, in: app)
        _ = try waitForControlState(in: app, timeout: 10) {
            $0.lifecycle == "paused"
        }

        let more = element("PlayerPanel-menu-more", in: app)
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        click(more, name: "More")
        let subtitles = element("PlayerPanel-menu-subtitles", in: app)
        XCTAssertTrue(subtitles.waitForExistence(timeout: 5))
        typeKey(.downArrow, in: app)
        typeKey(.rightArrow, in: app)
        let embeddedTrack = element(
            "PlayerPanel-menu-subtitle-ffmpeg.subtitle.3",
            in: app
        )
        XCTAssertTrue(embeddedTrack.waitForExistence(timeout: 5))
        typeKey(.downArrow, in: app)
        typeKey(.return, in: app)

        let activeSubtitle = element("PlayerUI-active-subtitles", in: app)
        XCTAssertTrue(activeSubtitle.waitForExistence(timeout: 10))
        XCTAssertTrue(
            String(describing: activeSubtitle.value).contains("Enchron 字幕验证")
        )
        attachScreenshot(of: app, name: "Subtitle in Window RealityView")

        typeKey("d", modifiers: [.command, .shift], in: app)
        _ = try waitForControlState(in: app, timeout: 30) {
            $0.presentation == "docked"
                && $0.attached == "docked"
                && $0.lifecycle == "paused"
        }
        XCTAssertTrue(activeSubtitle.waitForExistence(timeout: 5))
        XCTAssertTrue(
            String(describing: activeSubtitle.value).contains("Enchron 字幕验证")
        )
        attachScreenshot(of: app, name: "Subtitle in Docked RealityView")
    }

    @MainActor
    private func fixtureURLFromHostEnvironment(
        key: String = "ENCHRON_MACOS_UI_FIXTURE"
    ) throws -> URL {
        let fixture: URL
        if let rawPath = ProcessInfo.processInfo.environment[key] {
            fixture = URL(fileURLWithPath: rawPath).standardizedFileURL
        } else {
            let fileName = switch key {
            case "ENCHRON_MACOS_UI_SUBTITLE_FIXTURE":
                "sdr-bframe-multiaudio-subrip-30s.mkv"
            default:
                "sdr-bframe-multiaudio-avsync-120s.mp4"
            }
            fixture = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "../TestMedia/Generated")
                .appending(path: fileName)
                .standardizedFileURL
        }
        var isDirectory = ObjCBool(false)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.path, isDirectory: &isDirectory),
            "\(key) does not exist: \(fixture.path)"
        )
        XCTAssertFalse(isDirectory.boolValue, "\(key) must be a media file.")
        return fixture
    }

    @MainActor
    private func startFromBeginningIfNeeded(in app: XCUIApplication) {
        let startOver = element("PlayerUI-resume-secondary", in: app)
        if startOver.waitForExistence(timeout: 2) {
            click(startOver, name: "Start Over")
        }
    }

    @MainActor
    private func waitForControlState(
        in app: XCUIApplication,
        timeout: TimeInterval,
        matching predicate: (PlaybackControlState) -> Bool
    ) throws -> PlaybackControlState {
        let controlPlane = element("PlayerUI-window-control-plane", in: app)
        XCTAssertTrue(
            controlPlane.waitForExistence(timeout: timeout),
            "The production playback control plane did not appear."
        )
        let stateProbe = element("PlayerUI-playback-state", in: app)
        XCTAssertTrue(
            stateProbe.waitForExistence(timeout: timeout),
            "The external playback state probe did not appear."
        )
        let deadline = Date().addingTimeInterval(timeout)
        var lastValue = ""
        while Date() < deadline {
            let values = [
                stateProbe.label,
                stateProbe.value as? String,
                controlPlane.value as? String
            ].compactMap { $0 }
            for value in values where value.isEmpty == false {
                lastValue = value
                if let state = PlaybackControlState(value: value), predicate(state) {
                    return state
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Playback state did not satisfy the expected contract. Last value: \(lastValue)")
        throw PlaybackJourneyError.stateTimeout(lastValue)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func click(_ element: XCUIElement, name: String) {
        _ = interactionFrame(for: element, name: name)
        element.click()
    }

    @MainActor
    private func mouseClick(_ element: XCUIElement, name: String) {
        click(element, name: name)
    }

    @MainActor
    private func typeKey(
        _ key: XCUIKeyboardKey,
        modifiers: XCUIElement.KeyModifierFlags = [],
        in app: XCUIApplication
    ) {
        app.typeKey(key.rawValue, modifierFlags: modifiers)
    }

    @MainActor
    private func typeKey(
        _ key: String,
        modifiers: XCUIElement.KeyModifierFlags = [],
        in app: XCUIApplication
    ) {
        app.typeKey(key, modifierFlags: modifiers)
    }

    @MainActor
    private func interactionFrame(for element: XCUIElement, name: String) -> CGRect {
        if element.isHittable == false {
            let hittable = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == true"),
                object: element
            )
            _ = XCTWaiter.wait(for: [hittable], timeout: 3)
        }
        if element.isHittable == false {
            let screenshot = XCUIScreen.main.screenshot()
            attach(screenshot, name: "Visual fallback before \(name)")
        }
        XCTAssertFalse(
            element.frame.isEmpty || element.frame.isNull || element.frame.isInfinite,
            "\(name) has no usable accessibility geometry."
        )
        return element.frame
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func seconds(fromTimecode value: String) -> Double? {
        let fields = value.split(separator: ":").compactMap { Double($0) }
        guard fields.count == 4 else { return nil }
        return fields[0] * 3_600 + fields[1] * 60 + fields[2]
    }
}

private struct PlaybackControlState {
    let presentation: String
    let attached: String
    let lifecycle: String
    let session: String
    let position: Double
    let duration: Double

    init?(value: String) {
        var fields: [String: String] = [:]
        for field in value.split(separator: ";") {
            guard let separator = field.firstIndex(of: "=") else { continue }
            let key = String(field[..<separator])
            let valueStart = field.index(after: separator)
            fields[key] = String(field[valueStart...])
        }
        guard let presentation = fields["presentation"],
              let attached = fields["attached"],
              let lifecycle = fields["lifecycle"],
              let session = fields["session"],
              let position = fields["position"].flatMap(Double.init),
              let duration = fields["duration"].flatMap(Double.init) else { return nil }
        self.presentation = presentation
        self.attached = attached
        self.lifecycle = lifecycle.lowercased()
        self.session = session
        self.position = position
        self.duration = duration
    }
}

private enum PlaybackJourneyError: LocalizedError {
    case stateTimeout(String)

    var errorDescription: String? {
        switch self {
        case .stateTimeout(let value):
            "Playback state timed out. Last accessibility value: \(value)"
        }
    }
}
