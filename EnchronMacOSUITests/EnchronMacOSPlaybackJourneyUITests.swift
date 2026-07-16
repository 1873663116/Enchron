import Foundation
import XCTest

nonisolated final class EnchronMacOSPlaybackJourneyUITests: XCTestCase {
    @MainActor
    func testRealMediaWindowDockedRoundTripAndSeekControls() throws {
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

        let initial = try waitForControlState(in: app, timeout: 40) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
                && $0.session != "none"
        }
        attachScreenshot(of: app, name: "01 Window real playback")

        let dock = element("PlayerUI-TopAction-dock", in: app)
        XCTAssertTrue(dock.waitForExistence(timeout: 10))
        XCTAssertTrue(dock.isEnabled)
        tap(dock, name: "Dock")

        let darkTheatre = element("PlayerUI-DockMenu-darkTheatre", in: app)
        XCTAssertTrue(darkTheatre.waitForExistence(timeout: 5))
        tap(darkTheatre, name: "Dark Theatre")

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

        tap(exitSpatial, name: "Undock")
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
        tap(playPause, name: "Pause")

        let paused = try waitForControlState(in: app, timeout: 10) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "paused"
                && $0.session == initial.session
        }
        XCTAssertGreaterThan(paused.duration - paused.position, 10)

        let forward = element("PlayerPanel-button-forward", in: app)
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
        tap(forward, name: "Forward 10 seconds")

        let forwarded = try waitForControlState(in: app, timeout: 15) {
            $0.lifecycle == "paused"
                && $0.session == initial.session
                && abs($0.position - (paused.position + 10)) <= 2
        }
        XCTAssertEqual(forwarded.position, paused.position + 10, accuracy: 2)
        attachScreenshot(of: app, name: "04 Paused after Forward 10 seconds")

        XCTAssertEqual(playPause.label, "Play")
        tap(playPause, name: "Resume")
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
        tap(back, name: "Back")
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

        let more = element("PlayerPanel-menu-more", in: app)
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        tap(more, name: "More")
        let subtitles = element("PlayerPanel-menu-subtitles", in: app)
        XCTAssertTrue(subtitles.waitForExistence(timeout: 5))
        tap(subtitles, name: "Subtitles")
        let embeddedTrack = element(
            "PlayerPanel-menu-subtitle-ffmpeg.subtitle.3",
            in: app
        )
        XCTAssertTrue(embeddedTrack.waitForExistence(timeout: 5))
        tap(embeddedTrack, name: "Embedded SubRip")

        let activeSubtitle = element("PlayerUI-active-subtitles", in: app)
        XCTAssertTrue(activeSubtitle.waitForExistence(timeout: 10))
        XCTAssertTrue(
            String(describing: activeSubtitle.value).contains("Enchron 字幕验证")
        )
        attachScreenshot(of: app, name: "Subtitle in Window RealityView")

        tap(element("PlayerUI-TopAction-dock", in: app), name: "Dock")
        let darkTheatre = element("PlayerUI-DockMenu-darkTheatre", in: app)
        XCTAssertTrue(darkTheatre.waitForExistence(timeout: 5))
        tap(darkTheatre, name: "Dark Theatre")
        _ = try waitForControlState(in: app, timeout: 30) {
            $0.presentation == "docked"
                && $0.attached == "docked"
                && $0.lifecycle == "playing"
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
                "sdr-bframe-multiaudio-avsync-30s.mp4"
            }
            fixture = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: ".verification-fixtures")
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
            tap(startOver, name: "Start Over")
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
            let value = stateProbe.label
            lastValue = value
            if let state = PlaybackControlState(value: value), predicate(state) {
                return state
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
    private func tap(_ element: XCUIElement, name: String) {
        if element.isHittable {
            element.tap()
            return
        }
        let screenshot = XCUIScreen.main.screenshot()
        attach(screenshot, name: "Visual fallback before \(name)")
        XCTAssertFalse(
            element.frame.isEmpty || element.frame.isNull || element.frame.isInfinite,
            "\(name) has no usable accessibility geometry."
        )
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
