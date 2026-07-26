import Foundation
import XCTest

nonisolated final class EnchronMacOSPlaybackJourneyUITests: XCTestCase {
    @MainActor
    func testAdvancedSettingsControlReceivesMouseClick() throws {
        continueAfterFailure = false
        let fixture = try fixtureURLFromHostEnvironment()
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture.path
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment["ENCHRON_PLAYBACK_SPEED_OVERRIDE"] = "1"
        app.launchEnvironment["ENCHRON_AUTOMATION_PROBE"] = "1"
        app.launch()
        defer { app.terminate() }

        startFromBeginningIfNeeded(in: app)
        _ = try waitForControlState(in: app, timeout: 40) {
            $0.lifecycle == "playing"
        }

        let settings = app.buttons["Open Advanced Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        mouseClick(settings, name: "Open Advanced Settings")

        XCTAssertTrue(
            app.buttons["Close Advanced Settings"].firstMatch.waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testPlayPauseControlChangesRuntimeState() throws {
        continueAfterFailure = false
        let fixture = try fixtureURLFromHostEnvironment()
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture.path
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment["ENCHRON_PLAYBACK_SPEED_OVERRIDE"] = "1"
        app.launchEnvironment["ENCHRON_AUTOMATION_PROBE"] = "1"
        app.launch()
        defer { app.terminate() }

        startFromBeginningIfNeeded(in: app)
        _ = try waitForControlState(in: app, timeout: 40) {
            $0.lifecycle == "playing"
        }

        let playPause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        mouseClick(playPause, name: "Pause")

        _ = try waitForControlState(in: app, timeout: 10) {
            $0.lifecycle == "paused"
        }
        XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testExpandedTimelineReflectsLivePlaybackPosition() throws {
        continueAfterFailure = false
        let fixture = try fixtureURLFromHostEnvironment()
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture.path
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment["ENCHRON_PLAYBACK_SPEED_OVERRIDE"] = "1"
        app.launchEnvironment["ENCHRON_AUTOMATION_PROBE"] = "1"
        app.launch()
        defer { app.terminate() }

        startFromBeginningIfNeeded(in: app)
        _ = try waitForControlState(in: app, timeout: 40) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
        }

        let settings = app.buttons["Open Advanced Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        click(settings, name: "Open Advanced Settings")

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
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture.path
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment["ENCHRON_PLAYBACK_SPEED_OVERRIDE"] = "1"
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

        let dayAppearance = element("PlayerUI-DockMenu-day", in: app)
        XCTAssertTrue(dayAppearance.waitForExistence(timeout: 10))
        mouseClick(dayAppearance, name: "Day")

        let docked = try waitForControlState(in: app, timeout: 30) {
            $0.presentation == "docked"
                && $0.attached == "docked"
                && $0.lifecycle == "playing"
                && $0.session == initial.session
        }
        XCTAssertEqual(docked.session, initial.session)
        let exitSpatial = app.buttons["Return to Window"].firstMatch
        XCTAssertTrue(exitSpatial.waitForExistence(timeout: 10))
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

        let playPause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        typeKey(.space, in: app)

        let paused = try waitForControlState(in: app, timeout: 10) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "paused"
                && $0.session == initial.session
        }
        XCTAssertGreaterThan(paused.duration - paused.position, 10)

        let forward = app.buttons["Forward 10 seconds"].firstMatch
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
        typeKey(.rightArrow, in: app)

        let forwarded = try waitForControlState(in: app, timeout: 15) {
            $0.lifecycle == "paused"
                && $0.session == initial.session
                && abs($0.position - (paused.position + 10)) <= 2
        }
        XCTAssertEqual(forwarded.position, paused.position + 10, accuracy: 2)
        attachScreenshot(of: app, name: "04 Paused after Forward 10 seconds")

        XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 5))
        typeKey(.space, in: app)
        let resumed = try waitForControlState(in: app, timeout: 10) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
                && $0.session == initial.session
        }
        XCTAssertEqual(resumed.session, initial.session)
        attachScreenshot(of: app, name: "05 Resumed real playback")

        let back = app.buttons["Back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        click(back, name: "Back")
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
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture.path
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment["ENCHRON_PLAYBACK_SPEED_OVERRIDE"] = "1"
        app.launchEnvironment["ENCHRON_AUTOMATION_PROBE"] = "1"
        app.launch()
        defer { app.terminate() }

        startFromBeginningIfNeeded(in: app)
        _ = try waitForControlState(in: app, timeout: 40) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
        }

        let playPause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        typeKey(.space, in: app)
        _ = try waitForControlState(in: app, timeout: 10) {
            $0.lifecycle == "paused"
        }

        let more = app.menuButtons["More playback settings"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        click(more, name: "More")
        let subtitles = app.menuItems["Subtitles"].firstMatch
        XCTAssertTrue(subtitles.waitForExistence(timeout: 5))
        click(subtitles, name: "Subtitles")
        let embeddedTrack = app.menuItems["Enchron acceptance subtitles"].firstMatch
        XCTAssertTrue(embeddedTrack.waitForExistence(timeout: 5))
        click(embeddedTrack, name: "Enchron acceptance subtitles")

        let activeSubtitle = element("PlayerUI-active-subtitles", in: app)
        XCTAssertTrue(activeSubtitle.waitForExistence(timeout: 10))
        XCTAssertTrue(
            String(describing: activeSubtitle.value).contains("Enchron 字幕验证")
        )
        attachScreenshot(of: app, name: "Subtitle in Window RealityView")

        let dock = app.buttons["Dock"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 5))
        click(dock, name: "Dock")
        let day = app.buttons["Day"].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        click(day, name: "Day")
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
    func testEndedStopExposesReplayAndDisablesForwardOnly() throws {
        continueAfterFailure = false
        let fixture = try fixtureURLFromHostEnvironment(
            key: "ENCHRON_MACOS_UI_ENDED_FIXTURE"
        )
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture.path
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launch()
        defer { app.terminate() }

        let replay = app.buttons["Replay"].firstMatch
        let rewind = app.buttons["Rewind 10 seconds"].firstMatch
        let forward = app.buttons["Forward 10 seconds"].firstMatch
        XCTAssertTrue(replay.waitForExistence(timeout: 45))
        XCTAssertTrue(rewind.isEnabled)
        XCTAssertFalse(forward.isEnabled)

        let settings = app.buttons["Open Advanced Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        click(settings, name: "Open Advanced Settings from Ended")

        XCTAssertTrue(app.buttons["Close Advanced Settings"].waitForExistence(timeout: 5))
        let previousFrame = app.buttons["Previous frame"].firstMatch
        let nextFrame = app.buttons["Next frame"].firstMatch
        XCTAssertTrue(previousFrame.waitForExistence(timeout: 5))
        XCTAssertTrue(previousFrame.isEnabled)
        XCTAssertTrue(nextFrame.waitForExistence(timeout: 5))
        XCTAssertFalse(nextFrame.isEnabled)
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
            case "ENCHRON_MACOS_UI_ENDED_FIXTURE":
                "sdr-bframe-multiaudio-avsync-30s.mp4"
            default:
                "sdr-bframe-multiaudio-avsync-120s.mp4"
            }
            fixture = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
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
        let stateProbe = element("PlayerUI-playback-state", in: app)
        guard stateProbe.waitForExistence(timeout: min(timeout, 10)) else {
            let hierarchy = app.debugDescription
            XCTFail("The external playback state probe did not appear. Hierarchy: \(hierarchy)")
            throw PlaybackJourneyError.stateTimeout(hierarchy)
        }
        let controlPlane = element("PlayerUI-window-control-plane", in: app)
        XCTAssertTrue(
            controlPlane.waitForExistence(timeout: min(timeout, 10)),
            "The production playback control plane did not appear. State: \(stateProbe.label)"
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
