import XCTest
import CoreGraphics
@testable import XrPlayerCore

// MARK: - MediaProfile Tests

final class MediaProfileTests: XCTestCase {
    func testResolutionClampsNegativeValues() {
        let r = PlaybackCoreDomain.MediaProfile.Resolution(width: -10, height: -5)
        XCTAssertEqual(r.width, 0)
        XCTAssertEqual(r.height, 0)
    }

    func testResolutionAcceptsValidValues() {
        let r = PlaybackCoreDomain.MediaProfile.Resolution(width: 3840, height: 2160)
        XCTAssertEqual(r.width, 3840)
        XCTAssertEqual(r.height, 2160)
    }

    func testMediaProfileEquality() {
        let a = PlaybackCoreDomain.MediaProfile(
            projectionType: .flat,
            hdrType: .hdr10,
            resolution: .init(width: 1920, height: 1080),
            frameRate: 24
        )
        let b = PlaybackCoreDomain.MediaProfile(
            projectionType: .flat,
            hdrType: .hdr10,
            resolution: .init(width: 1920, height: 1080),
            frameRate: 24
        )
        XCTAssertEqual(a, b)
    }

    func testMediaProfileFrameRateClamped() {
        let p = PlaybackCoreDomain.MediaProfile(
            projectionType: .flat,
            hdrType: .sdr,
            resolution: .init(width: 1920, height: 1080),
            frameRate: -1
        )
        XCTAssertEqual(p.frameRate, 0)
    }

    func testHDRTypeAllCasesEnumerated() {
        let cases = PlaybackCoreDomain.HDRType.allCases
        XCTAssertTrue(cases.contains(.sdr))
        XCTAssertTrue(cases.contains(.hdr10))
        XCTAssertTrue(cases.contains(.hdr10Plus))
        XCTAssertTrue(cases.contains(.dolbyVision))
        XCTAssertTrue(cases.contains(.hlg))
        XCTAssertEqual(cases.count, 5)
    }

    func testHDRTypeRawValues() {
        XCTAssertEqual(PlaybackCoreDomain.HDRType.sdr.rawValue, "sdr")
        XCTAssertEqual(PlaybackCoreDomain.HDRType.hdr10.rawValue, "hdr10")
        XCTAssertEqual(PlaybackCoreDomain.HDRType.dolbyVision.rawValue, "dolbyVision")
    }
}

// MARK: - PlaybackSpeed Tests

final class PlaybackSpeedTests: XCTestCase {
    func testSpeedClampedAtMaximum() {
        XCTAssertEqual(PlaybackCoreDomain.PlaybackSpeed(99).value, 5.0)
    }

    func testSpeedClampedAtMinimum() {
        XCTAssertEqual(PlaybackCoreDomain.PlaybackSpeed(0.0).value, 0.25)
        XCTAssertEqual(PlaybackCoreDomain.PlaybackSpeed(-1).value, 0.25)
    }

    func testSpeedPreservedInValidRange() {
        XCTAssertEqual(PlaybackCoreDomain.PlaybackSpeed(1.5).value, 1.5)
        XCTAssertEqual(PlaybackCoreDomain.PlaybackSpeed(2.0).value, 2.0)
    }

    func testDefaultSpeedIsOne() {
        XCTAssertEqual(PlaybackCoreDomain.PlaybackSpeed.default.value, 1.0)
    }

    func testAllPresetsAreInValidRange() {
        for speed in PlaybackCoreDomain.PlaybackSpeed.allCases {
            XCTAssertGreaterThanOrEqual(speed.value, 0.25)
            XCTAssertLessThanOrEqual(speed.value, 5.0)
        }
    }

    func testSpeedEquality() {
        XCTAssertEqual(PlaybackCoreDomain.PlaybackSpeed(1.0), PlaybackCoreDomain.PlaybackSpeed(1.0))
        XCTAssertNotEqual(PlaybackCoreDomain.PlaybackSpeed(1.0), PlaybackCoreDomain.PlaybackSpeed(2.0))
    }
}

// MARK: - PlaybackPosition Tests

final class PlaybackPositionTests: XCTestCase {
    func testProgressCalculation() {
        let pos = PlaybackCoreDomain.PlaybackPosition(seconds: 50, duration: 100)
        XCTAssertEqual(pos.progress, 0.5, accuracy: 1e-9)
    }

    func testProgressClampedToOne() {
        let pos = PlaybackCoreDomain.PlaybackPosition(seconds: 200, duration: 100)
        XCTAssertEqual(pos.progress, 1.0)
    }

    func testProgressIsZeroWhenDurationIsZero() {
        let pos = PlaybackCoreDomain.PlaybackPosition(seconds: 10, duration: 0)
        XCTAssertEqual(pos.progress, 0.0)
    }

    func testNegativeSecondsClampedToZero() {
        let pos = PlaybackCoreDomain.PlaybackPosition(seconds: -5, duration: 100)
        XCTAssertEqual(pos.seconds, 0)
    }

    func testNegativeDurationClampedToZero() {
        let pos = PlaybackCoreDomain.PlaybackPosition(seconds: 10, duration: -1)
        XCTAssertEqual(pos.duration, 0)
        XCTAssertEqual(pos.progress, 0)
    }

    func testFullProgress() {
        let pos = PlaybackCoreDomain.PlaybackPosition(seconds: 100, duration: 100)
        XCTAssertEqual(pos.progress, 1.0)
    }
}

// MARK: - AudioTrack / SubtitleTrack Tests

final class TrackTests: XCTestCase {
    func testAudioTrackIdentifiable() {
        let t = PlaybackCoreDomain.AudioTrack(id: "1", languageCode: "en", displayName: "English", isDefault: true)
        XCTAssertEqual(t.id, "1")
        XCTAssertEqual(t.languageCode, "en")
        XCTAssertEqual(t.displayName, "English")
        XCTAssertTrue(t.isDefault)
    }

    func testAudioTrackDefaultFalse() {
        let t = PlaybackCoreDomain.AudioTrack(id: "2", languageCode: nil, displayName: "Unknown")
        XCTAssertFalse(t.isDefault)
        XCTAssertNil(t.languageCode)
    }

    func testSubtitleTrackEquality() {
        let a = PlaybackCoreDomain.SubtitleTrack(id: "s1", languageCode: "ja", displayName: "Japanese")
        let b = PlaybackCoreDomain.SubtitleTrack(id: "s1", languageCode: "ja", displayName: "Japanese")
        XCTAssertEqual(a, b)
    }

    func testSubtitleTrackInequality() {
        let a = PlaybackCoreDomain.SubtitleTrack(id: "s1", languageCode: "ja", displayName: "Japanese")
        let b = PlaybackCoreDomain.SubtitleTrack(id: "s2", languageCode: "zh", displayName: "Chinese")
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - DisambiguateGestureUseCase Tests

@MainActor
final class DisambiguateGestureUseCaseTests: XCTestCase {

    // MARK: Single pinch

    func testSinglePinchEmittedAfterObservationWindow() async {
        let sut = DisambiguateGestureUseCase()
        var received: GestureType?
        sut.onGestureResolved = { received = $0 }

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        sut.handlePinchEnded(at: t0.addingTimeInterval(0.05))   // quick tap

        // Wait beyond the 400ms observation window
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(received, .singlePinch)
    }

    // MARK: Double pinch

    func testDoublePinchEmittedWhenSecondPinchArrivesWithinWindow() async {
        let sut = DisambiguateGestureUseCase()
        var received: [GestureType] = []
        sut.onGestureResolved = { received.append($0) }

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        sut.handlePinchEnded(at: t0.addingTimeInterval(0.05))

        // Second pinch within 400ms window
        let t1 = t0.addingTimeInterval(0.20)
        sut.handlePinchBegan(at: t1)
        sut.handlePinchEnded(at: t1.addingTimeInterval(0.05))

        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(received, [.doublePinch])
    }

    func testDoublePinchNotEmittedWhenSecondPinchTooLate() async {
        let sut = DisambiguateGestureUseCase()
        var received: [GestureType] = []
        sut.onGestureResolved = { received.append($0) }

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        sut.handlePinchEnded(at: t0.addingTimeInterval(0.05))

        // Second pinch arrives AFTER the 400ms window
        try? await Task.sleep(for: .milliseconds(450))
        let t1 = Date()
        sut.handlePinchBegan(at: t1)
        sut.handlePinchEnded(at: t1.addingTimeInterval(0.05))

        try? await Task.sleep(for: .milliseconds(500))
        // First pinch should have resolved as singlePinch; second as another singlePinch
        XCTAssertEqual(received.count, 2)
        XCTAssertTrue(received.allSatisfy { $0 == .singlePinch })
    }

    // MARK: Long press

    func testLongPressEmittedWhenPinchHeldPastThreshold() async {
        let sut = DisambiguateGestureUseCase()
        var received: GestureType?
        sut.onGestureResolved = { received = $0 }

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        // Hold for > 200ms
        sut.handlePinchEnded(at: t0.addingTimeInterval(0.25))

        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(received, .longPress)
    }

    func testLongPressEmittedByTimerWhenPinchNotReleased() async {
        let sut = DisambiguateGestureUseCase()
        var longPressBegan = false
        sut.onLongPressBegan = { longPressBegan = true }

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        // Do NOT call handlePinchEnded — let the 200ms timer fire

        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(longPressBegan)
    }

    // MARK: Drag

    func testDragEmittedWhenTranslationExceedsThreshold() async {
        let sut = DisambiguateGestureUseCase()
        var received: GestureType?
        sut.onGestureResolved = { received = $0 }

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        sut.handlePinchChanged(translation: CGSize(width: 50, height: 0), at: t0.addingTimeInterval(0.02))

        XCTAssertEqual(received, .drag)
    }

    func testDragNotEmittedWhenTranslationBelowThreshold() {
        let sut = DisambiguateGestureUseCase()
        var received: GestureType?
        sut.onGestureResolved = { received = $0 }

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        sut.handlePinchChanged(translation: CGSize(width: 3, height: 3), at: t0.addingTimeInterval(0.02))

        XCTAssertNil(received)
    }

    func testDragDiagonalMagnitudeCheck() {
        let sut = DisambiguateGestureUseCase()
        var received: GestureType?
        sut.onGestureResolved = { received = $0 }

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        // hypot(6, 6) ≈ 8.49 >= threshold of 8
        sut.handlePinchChanged(translation: CGSize(width: 6, height: 6), at: t0.addingTimeInterval(0.02))

        XCTAssertEqual(received, .drag)
    }

    // MARK: State transitions

    func testStateIsIdleInitially() {
        let sut = DisambiguateGestureUseCase()
        if case .idle = sut.state { } else {
            XCTFail("Expected .idle, got \(sut.state)")
        }
    }

    func testStateBecomesObservingOnPinchBegan() {
        let sut = DisambiguateGestureUseCase()
        sut.handlePinchBegan(at: Date())
        if case .observing = sut.state { } else {
            XCTFail("Expected .observing, got \(sut.state)")
        }
    }

    func testStateBecomesAwaitingSecondPinchAfterQuickRelease() {
        let sut = DisambiguateGestureUseCase()
        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        sut.handlePinchEnded(at: t0.addingTimeInterval(0.05))
        if case .awaitingSecondPinch = sut.state { } else {
            XCTFail("Expected .awaitingSecondPinch, got \(sut.state)")
        }
    }

    func testStateBecomesConfirmedAfterGestureEmitted() async {
        let sut = DisambiguateGestureUseCase()

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        sut.handlePinchEnded(at: t0.addingTimeInterval(0.25))  // long press (> 200ms)

        if case .confirmed(.longPress) = sut.state { } else {
            XCTFail("Expected .confirmed(.longPress), got \(sut.state)")
        }
    }

    func testStateResetsToIdleAfterDelay() async {
        let sut = DisambiguateGestureUseCase()
        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        sut.handlePinchEnded(at: t0.addingTimeInterval(0.25))  // long press → confirmed

        // Wait for the 500ms reset delay
        try? await Task.sleep(for: .milliseconds(800))
        if case .idle = sut.state { } else {
            XCTFail("Expected .idle after reset delay, got \(sut.state)")
        }
    }

    // MARK: Edge cases

    func testChangedIgnoredWhenNoPinchBegan() {
        let sut = DisambiguateGestureUseCase()
        var received: GestureType?
        sut.onGestureResolved = { received = $0 }

        sut.handlePinchChanged(translation: CGSize(width: 100, height: 0), at: Date())
        XCTAssertNil(received)
    }

    func testEndedIgnoredWhenNoPinchBegan() {
        let sut = DisambiguateGestureUseCase()
        var received: GestureType?
        sut.onGestureResolved = { received = $0 }

        sut.handlePinchEnded(at: Date())
        XCTAssertNil(received)
    }

    func testDragDoesNotEmitAfterFirstDragEvent() {
        let sut = DisambiguateGestureUseCase()
        var count = 0
        sut.onGestureResolved = { _ in count += 1 }

        let t0 = Date()
        sut.handlePinchBegan(at: t0)
        sut.handlePinchChanged(translation: CGSize(width: 50, height: 0), at: t0.addingTimeInterval(0.01))
        // A second large translation should NOT emit a second drag
        sut.handlePinchChanged(translation: CGSize(width: 100, height: 0), at: t0.addingTimeInterval(0.02))
        XCTAssertEqual(count, 1)
    }
}
