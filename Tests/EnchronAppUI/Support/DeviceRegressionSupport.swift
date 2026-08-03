import Foundation
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
    static func fixtureURL() throws -> URL {
        guard let value = ProcessInfo.processInfo.environment[
            "ENCHRON_DEVICE_ACCEPTANCE_FIXTURE_URL"
        ], let url = URL(string: value), url.user == nil, url.password == nil else {
            throw XCTSkip(
                "Set ENCHRON_DEVICE_ACCEPTANCE_FIXTURE_URL to a credential-free media URL reachable from Apple Vision Pro."
            )
        }
        return url
    }

    static func mediaCardIdentifiers(minimumCount: Int) throws -> [String] {
        let identifiers = ProcessInfo.processInfo.environment[
            "ENCHRON_DEVICE_REGRESSION_MEDIA_CARD_IDS"
        ]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false } ?? []
        guard identifiers.count >= minimumCount else {
            throw XCTSkip(
                "Set ENCHRON_DEVICE_REGRESSION_MEDIA_CARD_IDS to at least \(minimumCount) comma-separated Media Library accessibility identifiers."
            )
        }
        return identifiers
    }

    static func requireReachableFixture(_ url: URL) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let statusCode = (response as? HTTPURLResponse)?.statusCode,
                  statusCode == 200 || statusCode == 206 else {
                throw XCTSkip(
                    "The configured Vision Pro fixture did not return a readable media response."
                )
            }
        } catch let skip as XCTSkip {
            throw skip
        } catch {
            throw XCTSkip(
                "The configured Vision Pro fixture is unavailable: \(error.localizedDescription)"
            )
        }
    }
}

@MainActor
extension XCTestCase {
    func launchSpatialFixtureApp(
        fixtureURL: URL,
        controlsAutoHideSeconds: Int = 300
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_SPATIAL_ACCEPTANCE"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] =
            String(controlsAutoHideSeconds)
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixtureURL.absoluteString
        app.launch()
        return app
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
        XCTAssertTrue(element.isEnabled, "\(name) is disabled.", file: file, line: line)
        XCTAssertTrue(element.isHittable, "\(name) is not hittable.", file: file, line: line)
        return element.isEnabled && element.isHittable
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
                latest = RegressionStateSnapshot(
                    rawValue: element.value as? String ?? ""
                )
                if predicate(latest) {
                    return latest
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

    func attachScreenshot(
        from app: XCUIApplication,
        name: String
    ) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
