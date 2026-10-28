import GameStreaming
import XCTest

nonisolated final class StreamOptionsCompatibilityTests: XCTestCase {
    func testStoredSettingsWithoutTheNewPreferencesDecodeWithTheirDefaults() throws {
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
        XCTAssertFalse(options.frameBuffer)
        XCTAssertTrue(options.customBitrateEnabled)
        XCTAssertFalse(options.swapABXYButtons)
        XCTAssertFalse(options.playAudioOnPC)
        XCTAssertEqual(options.mouseTrackingMode, .relative)
        XCTAssertFalse(options.optimizeGameSettings)
    }

    func testStoredFramePacingPreferenceBecomesTheFrameBufferPreference() throws {
        let stored = Data("""
        {"framePacing":true}
        """.utf8)

        let options = try JSONDecoder().decode(StreamOptions.self, from: stored)

        XCTAssertTrue(options.frameBuffer)
    }

    func testStoredFrameBufferPreferenceWins() throws {
        let stored = Data("""
        {"framePacing":true,"frameBuffer":false}
        """.utf8)

        let options = try JSONDecoder().decode(StreamOptions.self, from: stored)

        XCTAssertFalse(options.frameBuffer)
    }

    func testStoredRecordsWithTheRemovedMouseAndTouchFieldsStillDecode() throws {
        let stored = Data("""
        {"bluetoothMouseEnabled":false,"absoluteTouchMode":true}
        """.utf8)

        let options = try JSONDecoder().decode(StreamOptions.self, from: stored)

        XCTAssertEqual(options.mouseTrackingMode, .relative)
    }

    func testMouseTrackingDefaultsToRelative() {
        let options = StreamOptions()
        XCTAssertEqual(options.mouseTrackingMode, .relative)
        XCTAssertFalse(options.swapABXYButtons)
        XCTAssertFalse(options.playAudioOnPC)
        XCTAssertFalse(options.optimizeGameSettings)
    }

    func testCustomResolutionDrivesTheStreamDimensions() {
        var options = StreamOptions()
        options.resolution = .custom
        options.customWidth = 1600
        options.customHeight = 900

        XCTAssertEqual(options.streamWidth, 1600)
        XCTAssertEqual(options.streamHeight, 900)
        XCTAssertTrue(options.readableValue.hasPrefix("resolution=1600x900;"), options.readableValue)
    }

    func testRoundTripKeepsTheNewPreferences() throws {
        var options = StreamOptions()
        options.swapABXYButtons = true
        options.playAudioOnPC = true
        options.mouseTrackingMode = .absolute
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
        options.mouseTrackingMode = .absolute
        options.optimizeGameSettings = true

        XCTAssertTrue(options.readableValue.hasSuffix(
            "swapABXY=true;audioOnPC=true;mouseTracking=absolute;optimizeGameSettings=true;audioLayout=stereo;statsOverlay=false"
        ), options.readableValue)
    }

    func testTheDefaultAudioLayoutIsStereo() {
        XCTAssertEqual(StreamOptions().audioLayout, .stereo)
        XCTAssertEqual(StreamAudioLayout.stereo.channelCount, 2)
        XCTAssertEqual(StreamAudioLayout.surround51.channelCount, 6)
        XCTAssertEqual(StreamAudioLayout.surround71.channelCount, 8)
    }

    func testHostAudioPlaybackTurnsLocalPlaybackOff() {
        XCTAssertTrue(StreamOptions().playsAudioLocally)
        XCTAssertFalse(StreamOptions(playAudioOnPC: true).playsAudioLocally)
    }

    func testThePerformanceOverlayIsOffByDefaultAndSurvivesARoundTrip() throws {
        XCTAssertFalse(StreamOptions().showPerformanceOverlay)

        var options = StreamOptions()
        options.showPerformanceOverlay = true
        let decoded = try JSONDecoder().decode(
            StreamOptions.self,
            from: JSONEncoder().encode(options)
        )
        XCTAssertTrue(decoded.showPerformanceOverlay)
    }

    func testTheAudioLayoutSurvivesARoundTrip() throws {
        var options = StreamOptions()
        options.audioLayout = .surround51

        let decoded = try JSONDecoder().decode(
            StreamOptions.self,
            from: JSONEncoder().encode(options)
        )

        XCTAssertEqual(decoded.audioLayout, .surround51)
    }

    func testAnOlderStoredRecordWithoutAnAudioLayoutDecodesAsStereo() throws {
        let legacy = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(StreamOptions.self, from: legacy)
        XCTAssertEqual(decoded.audioLayout, .stereo)
    }
}
