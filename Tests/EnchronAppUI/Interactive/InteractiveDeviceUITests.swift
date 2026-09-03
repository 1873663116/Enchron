import Foundation
import XCTest

nonisolated final class InteractiveDeviceUITests: XCTestCase {
    private static let maximumIdleInterval: TimeInterval = 30 * 60

    @MainActor
    func testInteractiveDeviceSession() async throws {
        continueAfterFailure = true
        addUIInterruptionMonitor(
            withDescription: "Visible system permission request"
        ) { alert in
            for label in ["Allow", "允许"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_TEST_CHANNEL"] = "1"
        app.launchEnvironment["ENCHRON_SPATIAL_ACCEPTANCE"] = "1"
        app.launchEnvironment["ENCHRON_AUTOMATION_PROBE"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        for (name, value) in ProcessInfo.processInfo.environment
        where name.hasPrefix("ENCHRON_") {
            app.launchEnvironment[name] = value
        }
        app.launch()
        let channel = try InteractiveDeviceUIChannel(app: app)
        try channel.publishReadyState()

        while true {
            let commandArrived = await channel.waitForCommand(
                within: Self.maximumIdleInterval
            )
            guard let command = try channel.consumeCommandIfPresent() else {
                if commandArrived { continue }
                return
            }
            let shouldStop = try channel.executeAndPublish(command)
            if shouldStop { return }
        }
    }
}

@MainActor
private final class InteractiveDeviceUIChannel {
    private static let commandNotification =
        "com.enchron.interactive-device-ui.command"
    private static let responseNotificationPrefix =
        "com.enchron.interactive-device-ui.response."

    private let app: XCUIApplication
    private let fileManager = FileManager.default
    private let sessionID = UUID().uuidString
    private let rootURL: URL
    private let responsesURL: URL
    private let commandURL: URL
    private let readyURL: URL
    private let signal: InteractiveDeviceUICommandSignal

    init(app: XCUIApplication) throws {
        self.app = app
        let documentsURL = try XCTUnwrap(
            fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
        )
        rootURL = documentsURL.appending(
            path: "EnchronInteractiveUI",
            directoryHint: .isDirectory
        )
        responsesURL = rootURL.appending(
            path: "responses",
            directoryHint: .isDirectory
        )
        commandURL = rootURL.appending(path: "command.json")
        readyURL = rootURL.appending(path: "ready.json")
        signal = InteractiveDeviceUICommandSignal(
            notificationName: Self.commandNotification
        )

        try fileManager.createDirectory(
            at: responsesURL,
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: commandURL.path) {
            try fileManager.removeItem(at: commandURL)
        }
    }

    func publishReadyState() throws {
        let ready = InteractiveDeviceUIReadyState(
            sessionID: sessionID,
            commandNotification: Self.commandNotification,
            responseNotificationPrefix: Self.responseNotificationPrefix,
            appState: appStateDescription
        )
        try writeJSON(ready, to: readyURL)
    }

    func waitForCommand(within maximumIdleInterval: TimeInterval) async -> Bool {
        if fileManager.fileExists(atPath: commandURL.path) { return true }
        return await signal.wait(within: maximumIdleInterval)
    }

    func consumeCommandIfPresent() throws -> InteractiveDeviceUICommand? {
        guard fileManager.fileExists(atPath: commandURL.path) else { return nil }
        let data = try Data(contentsOf: commandURL)
        let command = try JSONDecoder().decode(
            InteractiveDeviceUICommand.self,
            from: data
        )
        try fileManager.removeItem(at: commandURL)
        guard command.sessionID == sessionID else {
            try publish(
                responseFor: command,
                success: false,
                message: "The command belongs to a previous interactive UI session.",
                matchedElement: nil
            )
            return nil
        }
        return command
    }

    func executeAndPublish(_ command: InteractiveDeviceUICommand) throws -> Bool {
        if command.action == .tapFirstMatch {
            let result = executeTapFirstMatch(command)
            try publish(
                responseFor: command,
                success: result.success,
                message: result.message,
                matchedElement: result.matchedElement
            )
            return false
        }
        if command.action == .tapSequence {
            let result = executeTapSequence(command)
            try publish(
                responseFor: command,
                success: result.success,
                message: result.message,
                matchedElement: nil,
                alsoInspected: result.alsoInspected,
                assertAbsentObservations: result.assertAbsentObservations,
                routeElements: result.routeElements
            )
            return false
        }
        let observationBeforeAction = command.action == .snapshot
            ? nil
            : matchedElementObservation(for: command)
        let result = execute(command)
        // A snapshot only reads, so the reading it publishes as matchedElement is
        // already the state the command found. Every other action changes what it
        // addressed, and the element it addressed is the one that has to exist for
        // the action to be admissible, so matchedElement stays the pre-action
        // reading -- a tap that dismisses its own target still has to say what it
        // tapped. What the action did to that element is a second reading, taken
        // here after execute, and nil when the element left the hierarchy.
        let observationAfterAction = matchedElementObservation(for: command)
        let observation = command.action == .snapshot
            ? observationAfterAction
            : observationBeforeAction
        let tapStep = command.identifier ?? command.label ?? ""
        try publish(
            responseFor: command,
            success: result.success,
            message: result.message,
            matchedElement: observation,
            elementAfterAction: observationAfterAction,
            assertAbsentObservations: command.action == .tap && result.success
                ? inspectIdentifiers(command.assertAbsent, afterStep: tapStep)
                : []
        )
        return command.action == .stop
    }

    private func executeTapFirstMatch(
        _ command: InteractiveDeviceUICommand
    ) -> (
        success: Bool,
        message: String,
        matchedElement: InteractiveDeviceUIElementObservation?
    ) {
        guard let route = command.identifiers, route.isEmpty == false else {
            return (false, "tapFirstMatch requires route identifiers.", nil)
        }
        guard let prefix = command.identifierPrefix, prefix.isEmpty == false else {
            return (false, "tapFirstMatch requires an identifier prefix.", nil)
        }
        for (position, identifier) in route.enumerated() {
            let element = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .element(boundBy: 0)
            guard element.waitForExistence(timeout: 3) else {
                return (
                    false,
                    "tapFirstMatch stopped at [\(position)] \(identifier): no matching element appeared.",
                    nil
                )
            }
            guard element.isHittable else {
                return (
                    false,
                    "tapFirstMatch stopped at [\(position)] \(identifier): the element is not hittable.",
                    nil
                )
            }
            element.tap()
        }
        let predicate: NSPredicate
        if let label = command.label, label.isEmpty == false {
            predicate = NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                prefix,
                label
            )
        } else {
            predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        }
        let matches = app.descendants(matching: .any).matching(predicate)
        let count = matches.count
        guard count > 0 else {
            return (false, "tapFirstMatch found no matching public element.", nil)
        }
        guard count == 1 else {
            return (false, "tapFirstMatch found \(count) matching public elements.", nil)
        }
        let element = matches.element(boundBy: 0)
        guard element.isHittable else {
            return (false, "The matching public element is not currently hittable.", nil)
        }
        let observation = matchedElementObservation(for: element)
        element.tap()
        return (true, "Matching public element tapped.", observation)
    }

    private func execute(
        _ command: InteractiveDeviceUICommand
    ) -> (success: Bool, message: String) {
        switch command.action {
        case .snapshot:
            return (true, "Current UI state captured.")
        case .activate:
            app.activate()
            return (true, "Application activated.")
        case .tap:
            guard let element = element(for: command) else {
                return (false, "No current element matches the requested identifier and index.")
            }
            guard element.isHittable else {
                return (false, "The requested element exists but is not currently hittable.")
            }
            element.tap()
            return (true, "Element tapped.")
        case .tapSequence:
            return (false, "tapSequence must execute through its sequence transaction.")
        case .tapFirstMatch:
            return (false, "tapFirstMatch must execute through its matching transaction.")
        case .doubleTap:
            guard let element = element(for: command) else {
                return (false, "No current element matches the requested identifier and index.")
            }
            guard element.isHittable else {
                return (false, "The requested element exists but is not currently hittable.")
            }
            element.doubleTap()
            return (true, "Element double-tapped.")
        case .press:
            guard let element = element(for: command) else {
                return (false, "No current element matches the requested identifier and index.")
            }
            guard element.isHittable else {
                return (false, "The requested element exists but is not currently hittable.")
            }
            guard let duration = command.duration, duration >= 0 else {
                return (false, "Press requires a nonnegative duration.")
            }
            element.press(forDuration: duration)
            return (true, "Element pressed.")
        case .adjust:
            guard let element = element(for: command) else {
                return (false, "No current element matches the requested identifier and index.")
            }
            guard element.isHittable else {
                return (false, "The requested element exists but is not currently hittable.")
            }
            guard let position = command.normalizedX,
                  (0...1).contains(position) else {
                return (false, "Adjust requires normalizedX between 0 and 1.")
            }
            element.adjust(toNormalizedSliderPosition: position)
            return (true, "Element adjusted through Accessibility.")
        case .typeText, .replaceText:
            guard let text = command.text else {
                return (false, "typeText requires text.")
            }
            guard let element = textInputElement(for: command) else {
                return (false, "No current element matches the requested identifier and index.")
            }
            guard element.isHittable else {
                return (false, "The requested element exists but is not currently hittable.")
            }
            element.tap()
            if command.action == .replaceText {
                element.typeKey(XCUIKeyboardKey(rawValue: "a"), modifierFlags: .command)
            }
            element.typeText(text)
            return (
                true,
                command.action == .replaceText ? "Text replaced." : "Text entered."
            )
        case .swipeUp, .swipeDown, .swipeLeft, .swipeRight:
            let surface: XCUIElement
            if command.identifier == nil {
                return (
                    false,
                    "A swipe requires --identifier or --label:"
                        + " swiping the application element kills the session"
                        + " on visionOS."
                )
            } else if let element = element(for: command) {
                surface = element
            } else {
                return (false, "No current element matches the requested identifier and index.")
            }
            guard surface.isHittable else {
                return (false, "The requested swipe surface is not currently hittable.")
            }
            switch command.action {
            case .swipeUp: surface.swipeUp()
            case .swipeDown: surface.swipeDown()
            case .swipeLeft: surface.swipeLeft()
            case .swipeRight: surface.swipeRight()
            default: break
            }
            return (true, "Swipe performed.")
        case .coordinateTap:
            guard let x = command.normalizedX,
                  let y = command.normalizedY,
                  (0...1).contains(x),
                  (0...1).contains(y) else {
                return (false, "coordinateTap requires normalizedX and normalizedY between 0 and 1.")
            }
            let surface: XCUIElement
            if command.identifier == nil {
                surface = app
            } else if let element = element(for: command) {
                surface = element
            } else {
                return (false, "No current coordinate surface matches the requested identifier and index.")
            }
            guard surface.isHittable else {
                return (false, "The requested coordinate surface is not currently hittable.")
            }
            surface.coordinate(
                withNormalizedOffset: CGVector(dx: x, dy: y)
            ).tap()
            return (true, "Normalized coordinate tapped in the requested UI surface.")
        case .relaunch:
            app.terminate()
            app.launch()
            return (true, "Target app relaunched through the resident XCTest session.")
        case .terminate:
            app.terminate()
            return (true, "Target app terminated; the interactive runner remains active.")
        case .stop:
            return (true, "Interactive UI session stopped cleanly.")
        }
    }

    private func executeTapSequence(
        _ command: InteractiveDeviceUICommand
    ) -> (
        success: Bool,
        message: String,
        alsoInspected: [InteractiveDeviceUIInspectedElement],
        assertAbsentObservations: [InteractiveDeviceUIInspectedElement],
        routeElements: [InteractiveDeviceUIElementObservation]
    ) {
        guard let identifiers = command.identifiers,
              identifiers.isEmpty == false else {
            return (false, "tapSequence requires identifiers.", [], [], [])
        }
        var alsoInspected: [InteractiveDeviceUIInspectedElement] = []
        var observations: [InteractiveDeviceUIInspectedElement] = []
        // The route each step resolved, read while the element is still on
        // screen. A tapped element is gone by the time the response is
        // published, so this is the only place its label can be recorded.
        var routeElements: [InteractiveDeviceUIElementObservation] = []

        func record(afterStep: String) {
            alsoInspected.append(
                contentsOf: inspectIdentifiers(
                    command.alsoInspect,
                    afterStep: afterStep
                )
            )
            observations.append(
                contentsOf: inspectIdentifiers(
                    command.assertAbsent,
                    afterStep: afterStep
                )
            )
        }

        if let label = command.label, label.isEmpty == false {
            let matches = app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", label)
            )
            let element = matches.element(boundBy: 0)
            guard element.waitForExistence(timeout: 3) else {
                return (
                    false,
                    "tapSequence stopped at label \(label): no matching element appeared.",
                    alsoInspected,
                    observations,
                    routeElements
                )
            }
            guard element.isHittable else {
                return (
                    false,
                    "tapSequence stopped at label \(label): the element is not hittable.",
                    alsoInspected,
                    observations,
                    routeElements
                )
            }
            if let observation = matchedElementObservation(for: element) {
                routeElements.append(observation)
            }
            element.tap()
            record(afterStep: "label:\(label)")
        }
        for (position, identifier) in identifiers.enumerated() {
            let element = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .element(boundBy: 0)
            guard element.waitForExistence(timeout: 3) else {
                return (
                    false,
                    "tapSequence stopped at [\(position)] \(identifier): no matching element appeared.",
                    alsoInspected,
                    observations,
                    routeElements
                )
            }
            guard element.isHittable else {
                return (
                    false,
                    "tapSequence stopped at [\(position)] \(identifier): the element is not hittable.",
                    alsoInspected,
                    observations,
                    routeElements
                )
            }
            if let observation = matchedElementObservation(for: element) {
                routeElements.append(observation)
            }
            element.tap()
            record(afterStep: identifier)
        }
        // A nested menu route addresses its leaf row by label, and that row
        // only exists once the identifier steps above have opened the submenu.
        // `label` is tapped before the identifiers, so a route that ends on a
        // label needs this step instead of a second command: the menu does not
        // survive two controller round trips.
        if let trailingLabel = command.trailingLabel,
           trailingLabel.isEmpty == false {
            let matches = app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", trailingLabel)
            )
            let element = matches.element(boundBy: 0)
            guard element.waitForExistence(timeout: 3) else {
                return (
                    false,
                    "tapSequence stopped at trailing label \(trailingLabel): no matching element appeared.",
                    alsoInspected,
                    observations,
                    routeElements
                )
            }
            guard element.isHittable else {
                return (
                    false,
                    "tapSequence stopped at trailing label \(trailingLabel): the element is not hittable.",
                    alsoInspected,
                    observations,
                    routeElements
                )
            }
            if let observation = matchedElementObservation(for: element) {
                routeElements.append(observation)
            }
            element.tap()
            record(afterStep: "label:\(trailingLabel)")
            return (
                true,
                "Tapped \(identifiers.count) elements in sequence, then label \(trailingLabel).",
                alsoInspected,
                observations,
                routeElements
            )
        }
        return (
            true,
            "Tapped \(identifiers.count) elements in sequence.",
            alsoInspected,
            observations,
            routeElements
        )
    }

    private func inspectIdentifiers(
        _ identifiers: [String]?,
        afterStep: String
    ) -> [InteractiveDeviceUIInspectedElement] {
        guard let identifiers else { return [] }
        return identifiers.map { identifier in
            let element = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .element(boundBy: 0)
            let exists = element.exists
            return InteractiveDeviceUIInspectedElement(
                afterStep: afterStep,
                identifier: identifier,
                exists: exists,
                isEnabled: exists && element.isEnabled,
                isHittable: exists && element.isHittable,
                label: exists ? element.label : ""
            )
        }
    }

    private func element(
        for command: InteractiveDeviceUICommand
    ) -> XCUIElement? {
        let descendants = app.descendants(matching: .any)
        let matches: XCUIElementQuery
        if let identifier = command.identifier,
           identifier.isEmpty == false {
            matches = descendants.matching(identifier: identifier)
        } else if let label = command.label,
                  label.isEmpty == false {
            matches = descendants.matching(
                NSPredicate(format: "label == %@", label)
            )
        } else {
            return nil
        }
        let element = matches.element(boundBy: command.index ?? 0)
        return element.exists ? element : nil
    }

    private func textInputElement(
        for command: InteractiveDeviceUICommand
    ) -> XCUIElement? {
        let index = command.index ?? 0
        var queries: [XCUIElementQuery] = []
        if let identifier = command.identifier, identifier.isEmpty == false {
            queries += [
                app.textFields.matching(identifier: identifier),
                app.secureTextFields.matching(identifier: identifier)
            ]
        }
        if let label = command.label, label.isEmpty == false {
            for format in ["label == %@", "placeholderValue == %@"] {
                let predicate = NSPredicate(format: format, label)
                queries += [
                    app.textFields.matching(predicate),
                    app.secureTextFields.matching(predicate)
                ]
            }
        }
        for query in queries {
            let element = query.element(boundBy: index)
            if element.exists { return element }
        }
        return nil
    }

    private func capturedScreenPNG() -> Data {
        let screen = XCUIScreen.main.screenshot()
        if screen.image.size.width > 1, screen.image.size.height > 1 {
            return screen.pngRepresentation
        }
        return app.screenshot().pngRepresentation
    }

    private func publish(
        responseFor command: InteractiveDeviceUICommand,
        success: Bool,
        message: String,
        matchedElement: InteractiveDeviceUIElementObservation?,
        elementAfterAction: InteractiveDeviceUIElementObservation? = nil,
        alsoInspected: [InteractiveDeviceUIInspectedElement] = [],
        assertAbsentObservations: [InteractiveDeviceUIInspectedElement] = [],
        routeElements: [InteractiveDeviceUIElementObservation] = []
    ) throws {
        let screenshotName: String?
        if command.includeScreenshot == false {
            screenshotName = nil
        } else {
            let name = "\(command.id).png"
            let screenshotURL = responsesURL.appending(path: name)
            try capturedScreenPNG().write(to: screenshotURL, options: .atomic)
            screenshotName = "responses/\(name)"
        }

        let response = InteractiveDeviceUIResponse(
            id: command.id,
            sessionID: sessionID,
            success: success,
            message: message,
            appState: appStateDescription,
            hierarchy: app.debugDescription,
            matchedElement: matchedElement,
            elementAfterAction: elementAfterAction,
            screenshotRelativePath: screenshotName,
            alsoInspected: alsoInspected,
            assertAbsentObservations: assertAbsentObservations,
            routeElements: routeElements
        )
        let responseURL = responsesURL.appending(
            path: "\(command.id).json"
        )
        try writeJSON(response, to: responseURL)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(
                (Self.responseNotificationPrefix + command.id) as CFString
            ),
            nil,
            nil,
            true
        )
    }

    private var appStateDescription: String {
        switch app.state {
        case .unknown: "unknown"
        case .notRunning: "notRunning"
        case .runningBackgroundSuspended: "runningBackgroundSuspended"
        case .runningBackground: "runningBackground"
        case .runningForeground: "runningForeground"
        @unknown default: "futureState"
        }
    }

    private func matchedElementObservation(
        for command: InteractiveDeviceUICommand
    ) -> InteractiveDeviceUIElementObservation? {
        guard let element = element(for: command) else { return nil }
        return matchedElementObservation(for: element)
    }

    private func matchedElementObservation(
        for element: XCUIElement
    ) -> InteractiveDeviceUIElementObservation? {
        guard let snapshot = try? element.snapshot() else { return nil }
        let frame = snapshot.frame
        return InteractiveDeviceUIElementObservation(
            identifier: snapshot.identifier,
            label: snapshot.label,
            value: snapshot.value.map { String(describing: $0) },
            elementType: String(describing: snapshot.elementType),
            isEnabled: snapshot.isEnabled,
            isHittable: element.isHittable,
            isSelected: snapshot.isSelected,
            frame: .init(
                x: Double(frame.origin.x),
                y: Double(frame.origin.y),
                width: Double(frame.size.width),
                height: Double(frame.size.height)
            )
        )
    }

    private func writeJSON<Value: Encodable>(
        _ value: Value,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

private struct InteractiveDeviceUIReadyState: Codable {
    let sessionID: String
    let commandNotification: String
    let responseNotificationPrefix: String
    let appState: String
}

private struct InteractiveDeviceUICommand: Codable {
    enum Action: String, Codable {
        case snapshot
        case tap
        case tapSequence
        case tapFirstMatch
        case doubleTap
        case press
        case adjust
        case typeText
        case replaceText
        case swipeUp
        case swipeDown
        case swipeLeft
        case swipeRight
        case coordinateTap
        case activate
        case relaunch
        case terminate
        case stop
    }

    let id: String
    let sessionID: String
    let action: Action
    let identifier: String?
    let identifiers: [String]?
    let identifierPrefix: String?
    let assertAbsent: [String]?
    let alsoInspect: [String]?
    let label: String?
    let trailingLabel: String?
    let index: Int?
    let text: String?
    let duration: TimeInterval?
    let normalizedX: Double?
    let normalizedY: Double?
    let includeScreenshot: Bool?
}

private struct InteractiveDeviceUIResponse: Codable {
    let id: String
    let sessionID: String
    let success: Bool
    let message: String
    let appState: String
    let hierarchy: String
    let matchedElement: InteractiveDeviceUIElementObservation?
    let elementAfterAction: InteractiveDeviceUIElementObservation?
    let screenshotRelativePath: String?
    let alsoInspected: [InteractiveDeviceUIInspectedElement]
    let assertAbsentObservations: [InteractiveDeviceUIInspectedElement]
    let routeElements: [InteractiveDeviceUIElementObservation]
}

private struct InteractiveDeviceUIInspectedElement: Codable {
    let afterStep: String
    let identifier: String
    let exists: Bool
    let isEnabled: Bool
    let isHittable: Bool
    let label: String
}

private struct InteractiveDeviceUIElementObservation: Codable {
    struct Frame: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    let identifier: String
    let label: String
    let value: String?
    let elementType: String
    let isEnabled: Bool
    let isHittable: Bool
    let isSelected: Bool
    let frame: Frame
}

@MainActor
private final class InteractiveDeviceUICommandSignal {
    private let notificationName: String
    private var continuation: CheckedContinuation<Bool, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var signalIsPending = false

    init(notificationName: String) {
        self.notificationName = notificationName
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let signal = Unmanaged<InteractiveDeviceUICommandSignal>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                Task { @MainActor in signal.receive() }
            },
            notificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(notificationName as CFString),
            nil
        )
    }

    func wait(within maximumIdleInterval: TimeInterval) async -> Bool {
        if signalIsPending {
            signalIsPending = false
            return true
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            deadlineTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(maximumIdleInterval))
                guard Task.isCancelled == false else { return }
                finish(commandArrived: false)
            }
        }
    }

    private func receive() {
        if continuation != nil {
            finish(commandArrived: true)
        } else {
            signalIsPending = true
        }
    }

    private func finish(commandArrived: Bool) {
        deadlineTask?.cancel()
        deadlineTask = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: commandArrived)
    }
}
