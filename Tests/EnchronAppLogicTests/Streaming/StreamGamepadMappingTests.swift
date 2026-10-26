import GameStreaming
import XCTest

nonisolated final class StreamGamepadMappingTests: XCTestCase {
    private static let wireFlags: [(StreamGamepadButton, Int32)] = [
        (.a, 0x1000),
        (.b, 0x2000),
        (.x, 0x4000),
        (.y, 0x8000),
        (.dpadUp, 0x0001),
        (.dpadDown, 0x0002),
        (.dpadLeft, 0x0004),
        (.dpadRight, 0x0008),
        (.leftShoulder, 0x0100),
        (.rightShoulder, 0x0200),
        (.menu, 0x0010),
        (.options, 0x0020),
        (.leftThumbstickButton, 0x0040),
        (.rightThumbstickButton, 0x0080),
        (.special, 0x0400)
    ]

    func testEveryButtonCarriesItsLimelightFlag() {
        for (button, flag) in Self.wireFlags {
            XCTAssertEqual(
                StreamGamepadMapping.buttonFlags([button], swapABXYButtons: false),
                flag,
                "\(button.rawValue) must send \(String(format: "0x%04X", flag))"
            )
        }
    }

    func testSwapExchangesAWithBAndXWithYOnly() {
        let swapped: [(StreamGamepadButton, Int32)] = [
            (.a, 0x2000),
            (.b, 0x1000),
            (.x, 0x8000),
            (.y, 0x4000)
        ]
        for (button, flag) in swapped {
            XCTAssertEqual(StreamGamepadMapping.buttonFlags([button], swapABXYButtons: true), flag)
        }

        let untouched = Self.wireFlags.filter { button, _ in
            ![.a, .b, .x, .y].contains(button)
        }
        for (button, flag) in untouched {
            XCTAssertEqual(
                StreamGamepadMapping.buttonFlags([button], swapABXYButtons: true),
                flag,
                "\(button.rawValue) must not move when ABXY is swapped"
            )
        }
    }

    func testCombinedPressesCombineTheirFlags() {
        let flags = StreamGamepadMapping.buttonFlags(
            [.a, .y, .dpadUp, .menu],
            swapABXYButtons: false
        )
        XCTAssertEqual(flags, 0x1000 | 0x8000 | 0x0001 | 0x0010)
    }

    func testEmptyPressSendsNoFlagsInEitherMode() {
        XCTAssertEqual(StreamGamepadMapping.buttonFlags([], swapABXYButtons: false), 0)
        XCTAssertEqual(StreamGamepadMapping.buttonFlags([], swapABXYButtons: true), 0)
    }

    func testSticksAndTriggersUseTheUpstreamRanges() {
        XCTAssertEqual(StreamGamepadMapping.axisValue(1), 32_766)
        XCTAssertEqual(StreamGamepadMapping.axisValue(-1), -32_766)
        XCTAssertEqual(StreamGamepadMapping.axisValue(0), 0)
        XCTAssertEqual(StreamGamepadMapping.triggerByte(1), 255)
        XCTAssertEqual(StreamGamepadMapping.triggerByte(0.5), 127)
        XCTAssertEqual(StreamGamepadMapping.triggerByte(0), 0)
    }

    func testMissingOptionsIsEmulatedFromLeftShoulderAndStart() {
        let combined = StreamGamepadMapping.combinedButtons(
            [.menu, .leftShoulder],
            hasPhysicalOptions: false,
            hasPhysicalHome: false
        )
        XCTAssertEqual(combined, [.options])
    }

    func testMissingHomeIsEmulatedFromRightShoulderAndStartWhenOptionsIsMissing() {
        let combined = StreamGamepadMapping.combinedButtons(
            [.menu, .rightShoulder],
            hasPhysicalOptions: false,
            hasPhysicalHome: false
        )
        XCTAssertEqual(combined, [.special])
    }

    func testMissingHomeIsEmulatedFromStartAndOptionsWhenOptionsIsPhysical() {
        let combined = StreamGamepadMapping.combinedButtons(
            [.menu, .options],
            hasPhysicalOptions: true,
            hasPhysicalHome: false
        )
        XCTAssertEqual(combined, [.special])
    }

    func testPhysicalHomeAndOptionsLeaveTheStatesAlone() {
        let held: Set<StreamGamepadButton> = [.menu, .options, .leftShoulder, .rightShoulder]
        XCTAssertEqual(
            StreamGamepadMapping.combinedButtons(held, hasPhysicalOptions: true, hasPhysicalHome: true),
            held
        )
    }

    func testStartAloneIsNotRewritten() {
        XCTAssertEqual(
            StreamGamepadMapping.combinedButtons([.menu], hasPhysicalOptions: false, hasPhysicalHome: false),
            [.menu]
        )
    }
}
