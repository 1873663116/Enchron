#if DEBUG
import GameStreaming
import XCTest

nonisolated final class StreamDebugInjectionTests: XCTestCase {
    func testControllerKindNamesMapToKinds() {
        XCTAssertEqual(StreamDebugInjection.controllerKind("xbox"), .xbox)
        XCTAssertEqual(StreamDebugInjection.controllerKind("DualSense"), .playStation)
        XCTAssertEqual(StreamDebugInjection.controllerKind("nintendo"), .nintendo)
        XCTAssertEqual(StreamDebugInjection.controllerKind("steam"), .steam)
        XCTAssertEqual(StreamDebugInjection.controllerKind(""), .unknown)
    }

    func testCapabilitiesParseFromNamesAndFromTheRawField() {
        XCTAssertEqual(
            StreamDebugInjection.capabilities("rumble,touchpad,gyroscope"),
            [.rumble, .touchpad, .gyroscope]
        )
        XCTAssertEqual(StreamDebugInjection.capabilities("all"), [
            .analogTriggers, .rumble, .triggerRumble, .touchpad,
            .accelerometer, .gyroscope, .battery, .indicatorLight
        ])
        XCTAssertEqual(StreamDebugInjection.capabilities("0x42"), [.rumble, .battery])
        XCTAssertEqual(StreamDebugInjection.capabilities("nonsense"), [])
    }

    func testButtonNamesProduceTheSameFlagsAsTheMapping() {
        XCTAssertEqual(
            StreamDebugInjection.buttons("a,b"),
            StreamGamepadMapping.buttonFlags([.a, .b], swapABXYButtons: false)
        )
        XCTAssertEqual(
            StreamDebugInjection.buttons("special,paddle1,share,touchpad"),
            StreamGamepadMapping.buttonFlags(
                [.special, .paddle1, .share, .touchpad],
                swapABXYButtons: false
            )
        )
        XCTAssertEqual(StreamDebugInjection.buttons("0x20"), 0x20)
        XCTAssertEqual(StreamDebugInjection.buttons("not-a-button"), 0)
    }

    func testEveryFeedbackCaseParsesItsArguments() {
        XCTAssertEqual(
            StreamDebugInjection.feedback(type: "rumble", args: ["low": "100", "high": "200"]),
            .rumble(controllerNumber: 0, lowFrequency: 100, highFrequency: 200)
        )
        XCTAssertEqual(
            StreamDebugInjection.feedback(type: "trigger", args: ["left": "10", "right": "20"]),
            .triggerRumble(controllerNumber: 0, leftTrigger: 10, rightTrigger: 20)
        )
        XCTAssertEqual(
            StreamDebugInjection.feedback(type: "motion", args: ["type": "1", "rate": "60"]),
            .motionRequest(controllerNumber: 0, motionType: 1, reportRateHz: 60)
        )
        XCTAssertEqual(
            StreamDebugInjection.feedback(type: "light", args: ["r": "255", "g": "128", "b": "0"]),
            .indicatorLight(controllerNumber: 0, red: 255, green: 128, blue: 0)
        )
    }

    func testFeedbackParsingRefusesIncompleteOrUnknownTypes() {
        XCTAssertNil(StreamDebugInjection.feedback(type: "rumble", args: ["low": "100"]))
        XCTAssertNil(StreamDebugInjection.feedback(type: "light", args: ["r": "1", "g": "2"]))
        XCTAssertNil(StreamDebugInjection.feedback(type: "shrug", args: [:]))
    }

    func testAnInjectedArrivalCarriesWhatTheArgumentsSaid() {
        let arrival = StreamDebugInjection.arrival(
            controllerNumber: 1,
            activeGamepadMask: 2,
            kind: "playstation",
            capabilities: "rumble,gyroscope",
            buttons: "a,special"
        )
        XCTAssertEqual(arrival.controllerNumber, 1)
        XCTAssertEqual(arrival.activeGamepadMask, 2)
        XCTAssertEqual(arrival.kind, .playStation)
        XCTAssertEqual(arrival.capabilities, [.rumble, .gyroscope])
        XCTAssertEqual(
            arrival.supportedButtons,
            StreamGamepadMapping.buttonFlags([.a, .special], swapABXYButtons: false)
        )
    }
}
#endif
