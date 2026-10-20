import GameStreaming
import XCTest

nonisolated final class StreamOptionsCompatibilityTests: XCTestCase {
    func testStoredSettingsWithoutTheNewPreferencesDecodeWithThemOff() throws {
        let stored = Data("""
        {"resolution":"r1920x1080","frameRate":60,"bitrateKbps":20000,"codec":"hevc",\
        "hdrEnabled":true,"framePacing":false,"customBitrateEnabled":true}
        """.utf8)

        let options = try JSONDecoder().decode(StreamOptions.self, from: stored)

        XCTAssertEqual(options.resolution, .r1920x1080)
        XCTAssertEqual(options.frameRate, 60)
        XCTAssertEqual(options.bitrateKbps, 20000)
        XCTAssertEqual(options.codec, .hevc)
        XCTAssertTrue(options.hdrEnabled)
        XCTAssertFalse(options.framePacing)
        XCTAssertTrue(options.customBitrateEnabled)
        XCTAssertFalse(options.swapABXYButtons)
        XCTAssertFalse(options.playAudioOnPC)
        XCTAssertFalse(options.bluetoothMouseEnabled)
        XCTAssertFalse(options.optimizeGameSettings)
    }

    func testRoundTripKeepsTheNewPreferences() throws {
        var options = StreamOptions()
        options.swapABXYButtons = true
        options.playAudioOnPC = true
        options.bluetoothMouseEnabled = true
        options.optimizeGameSettings = true

        let decoded = try JSONDecoder().decode(
            StreamOptions.self,
            from: JSONEncoder().encode(options)
        )

        XCTAssertEqual(decoded, options)
    }

    func testReadableValueCarriesTheNewPreferencesInWireOrder() {
        var options = StreamOptions()
        options.swapABXYButtons = true
        options.playAudioOnPC = true
        options.bluetoothMouseEnabled = false
        options.optimizeGameSettings = true

        XCTAssertTrue(options.readableValue.hasSuffix(
            "swapABXY=true;audioOnPC=true;bluetoothMouse=false;optimizeGameSettings=true"
        ), options.readableValue)
    }
}
