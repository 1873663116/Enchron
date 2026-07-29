#!/usr/bin/env swift

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

private struct Arguments {
    let appURL: URL
    let fixtureURL: URL
    let evidenceDirectory: URL
    let scenario: String

    init() throws {
        let values = CommandLine.arguments.dropFirst()
        var options: [String: String] = [:]
        var index = values.startIndex
        while index < values.endIndex {
            let key = values[index]
            let valueIndex = values.index(after: index)
            guard key.hasPrefix("--"), valueIndex < values.endIndex else {
                throw AcceptanceError.usage
            }
            options[String(key)] = String(values[valueIndex])
            index = values.index(after: valueIndex)
        }
        guard let appPath = options["--app"],
              let fixturePath = options["--fixture"],
              let evidencePath = options["--evidence"] else {
            throw AcceptanceError.usage
        }
        appURL = URL(fileURLWithPath: appPath).standardizedFileURL
        fixtureURL = URL(fileURLWithPath: fixturePath).standardizedFileURL
        evidenceDirectory = URL(fileURLWithPath: evidencePath).standardizedFileURL
        scenario = options["--scenario"] ?? "transport"
        guard ["transport", "tracks"].contains(scenario) else {
            throw AcceptanceError.usage
        }
    }
}

private struct PlaybackState {
    let fields: [String: String]

    init?(_ value: String) {
        var fields: [String: String] = [:]
        for field in value.split(separator: ";") {
            guard let separator = field.firstIndex(of: "=") else { continue }
            fields[String(field[..<separator])] = String(field[field.index(after: separator)...])
        }
        guard fields["presentation"] != nil,
              fields["attached"] != nil,
              fields["lifecycle"] != nil,
              fields["session"] != nil,
              fields["position"].flatMap(Double.init) != nil,
              fields["duration"].flatMap(Double.init) != nil else { return nil }
        self.fields = fields
    }

    var presentation: String { fields["presentation"] ?? "" }
    var attached: String { fields["attached"] ?? "" }
    var lifecycle: String { fields["lifecycle"]?.lowercased() ?? "" }
    var session: String { fields["session"] ?? "" }
    var position: Double { fields["position"].flatMap(Double.init) ?? 0 }
    var duration: Double { fields["duration"].flatMap(Double.init) ?? 0 }
}

private enum AcceptanceError: LocalizedError {
    case usage
    case missingFile(String)
    case permission(String)
    case launch(String)
    case timeout(String)
    case accessibility(String)
    case assertion(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: macos_ui_acceptance.swift --app <EnchronMacOS.app> --fixture <media> --evidence <directory> [--scenario transport|tracks]"
        case .missingFile(let path): "Required file does not exist: \(path)"
        case .permission(let message): message
        case .launch(let message): message
        case .timeout(let message): message
        case .accessibility(let message): message
        case .assertion(let message): message
        }
    }
}

private final class AcceptanceHarness {
    private let arguments: Arguments
    private let executableURL: URL
    private var process: Process?
    private var applicationElement: AXUIElement?
    private var records: [[String: Any]] = []

    init(arguments: Arguments) throws {
        self.arguments = arguments
        executableURL = arguments.appURL
            .appending(path: "Contents")
            .appending(path: "MacOS")
            .appending(path: "EnchronMacOS")
        for url in [arguments.appURL, executableURL, arguments.fixtureURL] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw AcceptanceError.missingFile(url.path)
            }
        }
        guard AXIsProcessTrusted() else {
            throw AcceptanceError.permission("The acceptance host does not have Accessibility permission.")
        }
        guard CGPreflightPostEventAccess() else {
            throw AcceptanceError.permission("The acceptance host does not have input-event permission.")
        }
        try FileManager.default.createDirectory(
            at: arguments.evidenceDirectory,
            withIntermediateDirectories: true
        )
    }

    func run() throws {
        try launch()
        defer { terminate() }
        do {
            if let startOver = try find(identifier: "PlayerUI-resume-secondary", timeout: 2) {
                try click(startOver, name: "Start Over")
            }

            switch arguments.scenario {
            case "transport": try runTransportScenario()
            case "tracks": try runTrackScenario()
            default: throw AcceptanceError.usage
            }
            try writeResult(status: "passed", failure: nil)
        } catch {
            _ = try? record("failure", state: nil)
            try? writeResult(status: "failed", failure: error.localizedDescription)
            throw error
        }
    }

    private func runTransportScenario() throws {
        let initial = try waitForState(timeout: 45) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
                && $0.session != "none"
        }
        try record("01-window-playing", state: initial)

        try click(identifier: "PlayerUI-TopAction-dock", name: "Dock")
        try click(identifier: "PlayerUI-DockMenu-darkTheatre", name: "Dark Theatre")
        let docked = try waitForState(timeout: 30) {
            $0.presentation == "docked"
                && $0.attached == "docked"
                && $0.lifecycle == "playing"
                && $0.session == initial.session
        }
        try record("02-docked-playing", state: docked)

        try click(identifier: "PlayerPanel-button-exit-spatial", name: "Undock")
        let returned = try waitForState(timeout: 30) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
                && $0.session == initial.session
        }
        try record("03-window-returned", state: returned)

        try click(identifier: "PlayerUI-TopAction-videoFormat", name: "Video Format")
        try click(
            identifier: "PlayerUI-VideoFormat-Projection-360°",
            name: "360 degree projection"
        )
        try click(identifier: "PlayerUI-VideoFormat-apply", name: "Apply Video Format")
        let panoramaSimulation = try waitForState(timeout: 30) {
            $0.presentation == "panorama"
                && $0.fields["hosted"] == "window"
                && $0.fields["simulation"] == "panorama"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
                && $0.session == initial.session
        }
        try record("04-panorama-simulation-playing", state: panoramaSimulation)

        try click(identifier: "PlayerPanel-button-exit-spatial", name: "Exit Panorama")
        let returnedFromPanorama = try waitForState(timeout: 30) {
            $0.presentation == "window"
                && $0.fields["hosted"] == "window"
                && $0.fields["simulation"] == "none"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
                && $0.session == initial.session
        }
        try record("05-window-returned-from-panorama", state: returnedFromPanorama)

        try click(identifier: "PlayerPanel-button-play", name: "Pause")
        let paused = try waitForState(timeout: 15) {
            $0.lifecycle == "paused" && $0.session == initial.session
        }
        guard paused.duration - paused.position > 10 else {
            throw AcceptanceError.assertion("The long fixture ended before the forward-seek assertion.")
        }

        try click(identifier: "PlayerPanel-button-forward", name: "Forward 15 seconds")
        let forwarded = try waitForState(timeout: 20) {
            $0.lifecycle == "paused"
                && $0.session == initial.session
                && abs($0.position - (paused.position + 15)) <= 2
        }
        try record("06-paused-forward-10", state: forwarded)

        try click(identifier: "PlayerPanel-button-play", name: "Resume")
        let resumed = try waitForState(timeout: 15) {
            $0.lifecycle == "playing" && $0.session == initial.session
        }
        try record("07-resumed", state: resumed)

        try click(identifier: "PlayerUI-InfoBar-button-back", name: "Back")
        guard try find(identifier: "FileBrowsing-FilesScreen", timeout: 15) != nil else {
            throw AcceptanceError.timeout("The browser did not return after Back.")
        }
        guard try find(identifier: "PlayerUI-window-control-plane", timeout: 2) == nil else {
            throw AcceptanceError.assertion("Playback controls remained after Back.")
        }
        try record("08-browser-after-back", state: nil)
    }

    private func runTrackScenario() throws {
        let initial = try waitForState(timeout: 45) {
            $0.presentation == "window"
                && $0.attached == "window"
                && $0.lifecycle == "playing"
                && $0.session != "none"
        }
        try click(identifier: "PlayerPanel-button-play", name: "Pause")
        _ = try waitForState(timeout: 15) {
            $0.lifecycle == "paused" && $0.session == initial.session
        }
        Thread.sleep(forTimeInterval: 0.8)
        let paused = try waitForState(timeout: 5) {
            $0.lifecycle == "paused" && $0.session == initial.session
        }
        let sceneHost = try applicationWindowFrame()
        Thread.sleep(forTimeInterval: 0.8)
        let subtitleOffScreenshot = try record("00-window-subtitle-off", state: paused)

        try click(identifier: "PlayerPanel-menu-more", name: "More")
        try click(title: "Subtitles", name: "Subtitles")
        try click(title: "Enchron acceptance subtitles", name: "Embedded SubRip")
        _ = try waitForState(timeout: 15) {
            $0.fields["subtitleTrack"] == "ffmpeg.subtitle.3"
                && ($0.fields["subtitleCues"].flatMap(Int.init) ?? 0) > 0
                && $0.session == initial.session
        }
        guard let subRipElement = try find(identifier: "PlayerUI-active-subtitles", timeout: 10),
              accessibilityText(from: subRipElement).contains("Enchron 字幕验证") else {
            throw AcceptanceError.assertion("The selected SubRip cue was not exposed by the active subtitle surface.")
        }
        Thread.sleep(forTimeInterval: 0.8)
        let subRipScreenshot = try captureScreenshot("00-window-subrip-on")
        let safeSubtitleFrame = CGRect(
            x: sceneHost.minX + sceneHost.width * 0.28,
            y: sceneHost.minY + sceneHost.height * 0.49,
            width: sceneHost.width * 0.44,
            height: sceneHost.height * 0.11
        )
        let subRipPixelEvidence = try pixelDifference(
            before: subtitleOffScreenshot,
            after: subRipScreenshot,
            in: safeSubtitleFrame
        )
        guard subRipPixelEvidence.changedPixels >= 300,
              subRipPixelEvidence.totalChannelDifference >= 30_000 else {
            throw AcceptanceError.assertion(
                "The selected SubRip subtitle was not visible above the control plane " +
                "(changedPixels=\(subRipPixelEvidence.changedPixels), " +
                "totalChannelDifference=\(subRipPixelEvidence.totalChannelDifference))."
            )
        }
        records.append([
            "name": "00-window-subrip-safe-area-proof",
            "screenshot": subRipScreenshot.path,
            "sceneFrame": NSStringFromRect(safeSubtitleFrame),
            "changedPixels": subRipPixelEvidence.changedPixels,
            "totalChannelDifference": subRipPixelEvidence.totalChannelDifference,
        ])

        try click(identifier: "PlayerPanel-menu-more", name: "More")
        try click(title: "Subtitles", name: "Subtitles")
        try click(title: "Enchron styled libass proof", name: "Styled ASS")
        _ = try waitForState(timeout: 15) {
            $0.fields["subtitleTrack"] == "ffmpeg.subtitle.4"
                && $0.fields["subtitleFrame"] == "libass"
                && ($0.fields["subtitleCues"].flatMap(Int.init) ?? 0) > 0
                && $0.session == initial.session
        }
        guard let subtitleElement = try find(identifier: "PlayerUI-active-subtitles", timeout: 10),
              accessibilityText(from: subtitleElement).contains("Enchron GPU PIXEL PROOF") else {
            throw AcceptanceError.assertion("The selected ASS cue was not exposed by the active subtitle surface.")
        }
        Thread.sleep(forTimeInterval: 0.8)
        let subtitleOnScreenshot = try captureScreenshot("00-window-subtitle-on")
        let proofFrame = CGRect(
            x: sceneHost.minX + sceneHost.width * 0.28,
            y: sceneHost.minY + sceneHost.height * 0.25,
            width: sceneHost.width * 0.44,
            height: sceneHost.height * 0.25
        )
        let pixelEvidence = try pixelDifference(
            before: subtitleOffScreenshot,
            after: subtitleOnScreenshot,
            in: proofFrame
        )
        guard pixelEvidence.changedPixels >= 300,
              pixelEvidence.totalChannelDifference >= 30_000 else {
            throw AcceptanceError.assertion(
                "The selected subtitle produced no visible scene pixels " +
                "(changedPixels=\(pixelEvidence.changedPixels), " +
                "totalChannelDifference=\(pixelEvidence.totalChannelDifference))."
            )
        }
        records.append([
            "name": "00-window-subtitle-pixel-proof",
            "screenshot": subtitleOnScreenshot.path,
            "sceneFrame": NSStringFromRect(proofFrame),
            "changedPixels": pixelEvidence.changedPixels,
            "totalChannelDifference": pixelEvidence.totalChannelDifference,
        ])

        try click(identifier: "PlayerPanel-menu-more", name: "More")
        try click(title: "Subtitles", name: "Subtitles")
        try click(title: "Enchron generated bitmap proof", name: "Generated bitmap")
        let bitmapSelected = try waitForState(timeout: 15) {
            $0.fields["subtitleTrack"] == "ffmpeg.subtitle.5"
                && $0.fields["subtitleFrame"] == "bitmap"
                && $0.session == initial.session
        }
        Thread.sleep(forTimeInterval: 0.8)
        let bitmapScreenshot = try captureScreenshot("00-window-bitmap-on")
        let bitmapPixelEvidence = try pixelDifference(
            before: subtitleOffScreenshot,
            after: bitmapScreenshot,
            in: proofFrame
        )
        guard bitmapPixelEvidence.changedPixels >= 300,
              bitmapPixelEvidence.totalChannelDifference >= 30_000 else {
            throw AcceptanceError.assertion(
                "The generated DVB bitmap subtitle produced no visible scene pixels " +
                "(changedPixels=\(bitmapPixelEvidence.changedPixels), " +
                "totalChannelDifference=\(bitmapPixelEvidence.totalChannelDifference))."
            )
        }
        records.append([
            "name": "00-window-bitmap-pixel-proof",
            "screenshot": bitmapScreenshot.path,
            "state": bitmapSelected.fields,
            "sceneFrame": NSStringFromRect(proofFrame),
            "changedPixels": bitmapPixelEvidence.changedPixels,
            "totalChannelDifference": bitmapPixelEvidence.totalChannelDifference,
        ])

        try click(identifier: "PlayerPanel-menu-more", name: "More")
        try click(title: "Audio Track", name: "Audio Track")
        try click(title: "Track 2 · aac · 2ch", name: "Second audio track")
        let tracksSelected = try waitForState(timeout: 15) {
            $0.fields["audioTrack"] == "2"
                && $0.fields["subtitleTrack"] == "ffmpeg.subtitle.5"
                && $0.fields["subtitleFrame"] == "bitmap"
                && $0.session == initial.session
        }
        try record("01-window-subtitle-audio-selected", state: tracksSelected)

        try click(identifier: "PlayerPanel-button-dock", name: "Docking")
        let docked = try waitForState(timeout: 30) {
            $0.presentation == "docked"
                && $0.attached == "docked"
                && $0.lifecycle == "paused"
                && $0.fields["audioTrack"] == "2"
                && $0.fields["subtitleTrack"] == "ffmpeg.subtitle.5"
                && $0.fields["subtitleFrame"] == "bitmap"
                && $0.session == initial.session
        }
        try record("02-docked-subtitle-audio-selected", state: docked)
    }

    private func launch() throws {
        for application in NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.xiongzhipeng.EnchronMacOS"
        ) {
            application.terminate()
        }
        Thread.sleep(forTimeInterval: 0.5)

        let process = Process()
        process.executableURL = executableURL
        var environment = ProcessInfo.processInfo.environment
        environment["ENCHRON_AUTOPLAY_FILE"] = arguments.fixtureURL.path
        environment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        environment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        environment["ENCHRON_AUTOMATION_PROBE"] = "1"
        process.environment = environment
        do {
            try process.run()
        } catch {
            throw AcceptanceError.launch("Could not launch EnchronMacOS: \(error.localizedDescription)")
        }
        self.process = process
        applicationElement = AXUIElementCreateApplication(process.processIdentifier)
    }

    private func terminate() {
        process?.terminate()
        process = nil
        applicationElement = nil
    }

    private func waitForState(
        timeout: TimeInterval,
        matching predicate: (PlaybackState) -> Bool
    ) throws -> PlaybackState {
        let deadline = Date().addingTimeInterval(timeout)
        var lastValue = ""
        while Date() < deadline {
            if let probe = try find(identifier: "PlayerUI-playback-state", timeout: 0.5),
               let value = stateValue(from: probe) {
                lastValue = value
                if let state = PlaybackState(value), predicate(state) { return state }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw AcceptanceError.timeout("Playback state did not converge. Last value: \(lastValue)")
    }

    private func stateValue(from element: AXUIElement) -> String? {
        for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let value = copyAttribute(attribute, from: element) as? String,
               value.contains("presentation=") {
                return value
            }
        }
        return nil
    }

    private func accessibilityText(from element: AXUIElement) -> String {
        [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
            .compactMap { copyAttribute($0, from: element) as? String }
            .joined(separator: " ")
    }

    private func click(identifier: String, name: String) throws {
        guard let element = try find(identifier: identifier, timeout: 15) else {
            throw AcceptanceError.timeout("\(name) did not appear: \(identifier)")
        }
        try click(element, name: name)
    }

    private func click(title: String, name: String) throws {
        guard let element = try find(title: title, timeout: 15) else {
            throw AcceptanceError.timeout("\(name) did not appear with title: \(title)")
        }
        try click(element, name: name)
    }

    private func click(_ element: AXUIElement, name: String) throws {
        guard let positionValue = copyAttribute(kAXPositionAttribute, from: element),
              let sizeValue = copyAttribute(kAXSizeAttribute, from: element) else {
            throw AcceptanceError.accessibility("\(name) has no accessibility geometry.")
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0,
              size.height > 0 else {
            throw AcceptanceError.accessibility("\(name) has invalid accessibility geometry.")
        }
        let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        let role = copyAttribute(kAXRoleAttribute, from: element) as? String ?? "unknown"
        print("click name=\(name) role=\(role) point=\(Int(point.x)),\(Int(point.y))")
        if role == kAXMenuButtonRole || role == kAXMenuItemRole {
            guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
                throw AcceptanceError.accessibility("Could not activate menu element \(name).")
            }
            Thread.sleep(forTimeInterval: 0.2)
            return
        }
        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ), let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw AcceptanceError.accessibility("Could not create mouse events for \(name).")
        }
        CGWarpMouseCursorPosition(point)
        Thread.sleep(forTimeInterval: 0.05)
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.2)
    }

    private func clickWindowSurface(
        in frame: CGRect,
        yFraction: CGFloat = 0.5,
        name: String
    ) throws {
        let point = CGPoint(
            x: frame.midX,
            y: frame.minY + frame.height * yFraction
        )
        print("click name=\(name) role=surface point=\(Int(point.x)),\(Int(point.y))")
        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ), let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw AcceptanceError.accessibility("Could not create mouse events for \(name).")
        }
        CGWarpMouseCursorPosition(point)
        Thread.sleep(forTimeInterval: 0.05)
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.3)
    }

    private func find(
        identifier: String? = nil,
        title: String? = nil,
        timeout: TimeInterval
    ) throws -> AXUIElement? {
        guard let applicationElement else {
            throw AcceptanceError.accessibility("The application accessibility root is unavailable.")
        }
        guard identifier != nil || title != nil else {
            throw AcceptanceError.accessibility("An accessibility lookup requires an identifier or title.")
        }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            var queue: [AXUIElement] = [applicationElement]
            var visited = Set<CFHashCode>()
            var fallback: AXUIElement?
            var cursor = 0
            while cursor < queue.count, cursor < 20_000 {
                let element = queue[cursor]
                cursor += 1
                let identity = CFHash(element)
                guard visited.insert(identity).inserted else { continue }
                let identifierMatches = identifier.map {
                    copyAttribute(kAXIdentifierAttribute, from: element) as? String == $0
                } ?? true
                let titleMatches = title.map {
                    copyAttribute(kAXTitleAttribute, from: element) as? String == $0
                } ?? true
                if identifierMatches && titleMatches {
                    let role = copyAttribute(kAXRoleAttribute, from: element) as? String
                    if [kAXButtonRole, kAXMenuButtonRole, kAXMenuItemRole].contains(role) {
                        return element
                    }
                    fallback = fallback ?? element
                }
                if let children = copyAttribute(kAXChildrenAttribute, from: element) as? [AXUIElement] {
                    queue.append(contentsOf: children)
                }
            }
            if let fallback { return fallback }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return nil
    }

    private func copyAttribute(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    @discardableResult
    private func record(_ name: String, state: PlaybackState?) throws -> URL {
        let screenshotURL = try captureScreenshot(name)
        var record: [String: Any] = [
            "name": name,
            "screenshot": screenshotURL.path
        ]
        if let state { record["state"] = state.fields }
        records.append(record)
        return screenshotURL
    }

    private func captureScreenshot(_ name: String) throws -> URL {
        CGWarpMouseCursorPosition(.zero)
        Thread.sleep(forTimeInterval: 0.3)
        let screenshotURL = arguments.evidenceDirectory.appending(path: "\(name).png")
        let screenshot = Process()
        screenshot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        screenshot.arguments = ["-x", screenshotURL.path]
        try screenshot.run()
        screenshot.waitUntilExit()
        guard screenshot.terminationStatus == 0 else {
            throw AcceptanceError.assertion("Could not capture evidence screenshot \(name).")
        }
        return screenshotURL
    }

    private func applicationWindowFrame() throws -> CGRect {
        guard let process,
              let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else {
            throw AcceptanceError.accessibility("Could not inspect the Enchron window list.")
        }
        for window in windowInfo {
            guard window[kCGWindowOwnerPID as String] as? pid_t == process.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 0,
                  frame.height > 0 else { continue }
            return frame
        }
        throw AcceptanceError.accessibility("The Enchron application window is unavailable.")
    }

    private func pixelDifference(
        before: URL,
        after: URL,
        in frame: CGRect
    ) throws -> (changedPixels: Int, totalChannelDifference: Int) {
        guard let beforeRep = NSBitmapImageRep(data: try Data(contentsOf: before)),
              let afterRep = NSBitmapImageRep(data: try Data(contentsOf: after)),
              let beforeBytes = beforeRep.bitmapData,
              let afterBytes = afterRep.bitmapData,
              beforeRep.pixelsWide == afterRep.pixelsWide,
              beforeRep.pixelsHigh == afterRep.pixelsHigh,
              beforeRep.samplesPerPixel >= 3,
              afterRep.samplesPerPixel >= 3 else {
            throw AcceptanceError.assertion("Could not decode comparable acceptance screenshots.")
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let minX = max(0, Int((frame.minX * scale).rounded(.down)))
        let minY = max(0, Int((frame.minY * scale).rounded(.down)))
        let maxX = min(beforeRep.pixelsWide, Int((frame.maxX * scale).rounded(.up)))
        let maxY = min(beforeRep.pixelsHigh, Int((frame.maxY * scale).rounded(.up)))
        guard maxX > minX, maxY > minY else {
            throw AcceptanceError.assertion("The playback scene is outside the captured display.")
        }

        var changedPixels = 0
        var totalChannelDifference = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let beforeOffset = y * beforeRep.bytesPerRow + x * beforeRep.samplesPerPixel
                let afterOffset = y * afterRep.bytesPerRow + x * afterRep.samplesPerPixel
                var pixelDifference = 0
                for channel in 0..<3 {
                    pixelDifference += abs(
                        Int(beforeBytes[beforeOffset + channel]) -
                        Int(afterBytes[afterOffset + channel])
                    )
                }
                if pixelDifference >= 24 { changedPixels += 1 }
                totalChannelDifference += pixelDifference
            }
        }
        return (changedPixels, totalChannelDifference)
    }

    private func writeResult(status: String, failure: String?) throws {
        var result: [String: Any] = [
            "status": status,
            "scenario": arguments.scenario,
            "fixture": arguments.fixtureURL.path,
            "records": records
        ]
        if let failure { result["firstFailure"] = failure }
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: arguments.evidenceDirectory.appending(path: "result.json"))
    }
}

do {
    let arguments = try Arguments()
    let harness = try AcceptanceHarness(arguments: arguments)
    try harness.run()
    print(arguments.evidenceDirectory.appending(path: "result.json").path)
} catch {
    fputs("macOS UI acceptance failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
