import XCTest

nonisolated final class VisionProDeviceAcceptanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        throw XCTSkip("Final spatial presentation requires Apple Vision Pro.")
#endif
    }

    @MainActor
    func testRealPlaybackCapturesPhysicalScreenAndState() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launch()

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        if controlPlane.waitForExistence(timeout: 3) == false {
            let media = app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "identifier BEGINSWITH 'MediaLibrary-grid-video-'"
                    )
                )
                .firstMatch
            XCTAssertTrue(
                media.waitForExistence(timeout: 20),
                "The installed device library has no media available for playback diagnostics."
            )
            media.tap()
        }

        XCTAssertTrue(
            controlPlane.waitForExistence(timeout: 30),
            "Real playback never exposed the Window control plane."
        )
        let rewind = app.buttons["PlayerPanel-button-rewind"].firstMatch
        let playPause = app.buttons["PlayerPanel-button-play"].firstMatch
        let forward = app.buttons["PlayerPanel-button-forward"].firstMatch
        let progress = app.descendants(matching: .any)["PlayerPanel-progress"].firstMatch
        XCTAssertTrue(rewind.waitForExistence(timeout: 10))
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        XCTAssertTrue(forward.waitForExistence(timeout: 10))
        XCTAssertTrue(progress.waitForExistence(timeout: 10))

        waitForLifecycle("playing", in: controlPlane)
        Thread.sleep(forTimeInterval: 0.5)
        let startupA = attachCheckpoint(
            name: "01-startup-a",
            controlPlane: controlPlane,
            app: app
        )
        Thread.sleep(forTimeInterval: 1)
        let startupB = attachCheckpoint(
            name: "02-startup-b",
            controlPlane: controlPlane,
            app: app
        )
        assertContinuousPlayback(from: startupA, to: startupB, context: "startup")

        playPause.tap()
        waitForLifecycle("paused", in: controlPlane)
        let paused = attachCheckpoint(
            name: "03-paused",
            controlPlane: controlPlane,
            app: app
        )
        XCTAssertEqual(paused.lifecycle?.lowercased(), "paused")
        XCTAssertEqual(paused.double("actualRate") ?? .nan, 0, accuracy: 0.01)

        playPause.tap()
        waitForLifecycle("playing", in: controlPlane)
        let resumedA = attachCheckpoint(
            name: "04-resumed-a",
            controlPlane: controlPlane,
            app: app
        )
        Thread.sleep(forTimeInterval: 1)
        let resumedB = attachCheckpoint(
            name: "05-resumed-b",
            controlPlane: controlPlane,
            app: app
        )
        assertContinuousPlayback(from: resumedA, to: resumedB, context: "resume")

        forward.tap()
        waitForStreamEpoch(after: resumedB.uint64("streamEpoch"), in: controlPlane)
        let seekA = attachCheckpoint(
            name: "06-forward-seek-a",
            controlPlane: controlPlane,
            app: app
        )
        Thread.sleep(forTimeInterval: 1)
        let seekB = attachCheckpoint(
            name: "07-forward-seek-b",
            controlPlane: controlPlane,
            app: app
        )
        assertContinuousPlayback(from: seekA, to: seekB, context: "playing seek")

        playPause.tap()
        waitForLifecycle("paused", in: controlPlane)
        attachCheckpoint(
            name: "08-forward-seek-paused",
            controlPlane: controlPlane,
            app: app
        )
    }

    @MainActor
    func testRealPlaybackSeekToEndDoesNotPresentLoadError() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launch()

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        if controlPlane.waitForExistence(timeout: 3) == false {
            let media = app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "identifier BEGINSWITH 'MediaLibrary-grid-video-'"
                    )
                )
                .firstMatch
            XCTAssertTrue(
                media.waitForExistence(timeout: 20),
                "The installed device library has no media available for playback diagnostics."
            )
            media.tap()
        }

        XCTAssertTrue(controlPlane.waitForExistence(timeout: 30))
        let progress = app.descendants(matching: .any)["PlayerPanel-progress"].firstMatch
        let thumb = app.descendants(matching: .any)["PlayerPanel-thumb"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertTrue(thumb.waitForExistence(timeout: 10))
        waitForLifecycle("playing", in: controlPlane)

        let before = PlaybackCheckpoint(
            rawValue: controlPlane.value as? String ?? ""
        )
        let start = thumb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = progress.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5))
        start.press(forDuration: 0.5, thenDragTo: end)

        waitForStreamEpoch(after: before.uint64("streamEpoch"), in: controlPlane)
        Thread.sleep(forTimeInterval: 1)

        let errorTitle = app.staticTexts["Failed to Load"].firstMatch
        XCTAssertFalse(
            errorTitle.exists,
            "Seeking to the media end presented the playback error overlay."
        )
        let after = attachCheckpoint(
            name: "seek-to-end-after",
            controlPlane: controlPlane,
            app: app
        )
        XCTAssertNotEqual(after.lifecycle?.lowercased(), "failed")
    }

    @MainActor
    func testRealVideoAACDiagnostic() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment[
            "ENCHRON_VERIFICATION_DISABLE_PLAYBACK_DEBUG_RECORDER"
        ] = "1"
        app.launch()

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        if controlPlane.waitForExistence(timeout: 3) == false {
            let media = app.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "identifier BEGINSWITH 'MediaLibrary-grid-video-'"
                ))
                .firstMatch
            XCTAssertTrue(
                media.waitForExistence(timeout: 20),
                "The installed device library has no reusable real-video diagnostic entry."
            )
            media.tap()
        }
        XCTAssertTrue(controlPlane.waitForExistence(timeout: 30))
        waitForLifecycle("playing", in: controlPlane)
        waitForPreRateMediaEvidence(in: controlPlane)
        attachCheckpoint(
            name: "real-video-aac-00-pre-rate",
            controlPlane: controlPlane,
            app: app
        )
        Thread.sleep(forTimeInterval: 2.2)
        let tailCheckpoint = attachCheckpoint(
            name: "real-video-aac-00-tail",
            controlPlane: controlPlane,
            app: app
        )
        XCTAssertGreaterThan(
            tailCheckpoint.double("actualRate") ?? 0,
            0.5,
            "Playback timebase did not start after the fixed observation window."
        )
        guard tailCheckpoint.double("actualRate") ?? 0 > 0.5 else { return }
        Thread.sleep(forTimeInterval: 1)
        let checkpointA = attachCheckpoint(
            name: "real-video-aac-01-a",
            controlPlane: controlPlane,
            app: app
        )
        Thread.sleep(forTimeInterval: 1)
        let checkpointB = attachCheckpoint(
            name: "real-video-aac-02-b",
            controlPlane: controlPlane,
            app: app
        )
        assertContinuousPlayback(from: checkpointA, to: checkpointB, context: "real AAC")
        XCTAssertGreaterThan(
            checkpointB.uint64("audioRendererSamples") ?? 0,
            checkpointA.uint64("audioRendererSamples") ?? 0
        )
    }

    @MainActor
    func testRealVideoSufficientRateReapplyDiagnostic() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment[
            "ENCHRON_VERIFICATION_DISABLE_PLAYBACK_DEBUG_RECORDER"
        ] = "1"
        app.launchEnvironment["ENCHRON_VERIFY_SUFFICIENT_RATE_REAPPLY"] = "1"
        app.launch()

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        if controlPlane.waitForExistence(timeout: 3) == false {
            let media = app.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "identifier BEGINSWITH 'MediaLibrary-grid-video-'"
                ))
                .firstMatch
            XCTAssertTrue(
                media.waitForExistence(timeout: 20),
                "The installed device library has no reusable real-video diagnostic entry."
            )
            media.tap()
        }
        XCTAssertTrue(controlPlane.waitForExistence(timeout: 30))
        waitForLifecycle("playing", in: controlPlane)
        waitForPreRateMediaEvidence(in: controlPlane)
        let preRate = attachCheckpoint(
            name: "real-video-aac-00-pre-rate",
            controlPlane: controlPlane,
            app: app
        )
        XCTAssertEqual(
            preRate.double("actualRate") ?? .nan,
            0,
            accuracy: 0.01,
            "The causal experiment did not capture the stopped pre-reapply timebase."
        )

        let terminal = waitForReapplyTerminalState(in: controlPlane)
        if terminal.bool("reapplyVideoSufficient") != true {
            attachCheckpoint(
                name: "real-video-aac-00-tail",
                controlPlane: controlPlane,
                app: app
            )
            XCTFail(
                "classification=videoNeverSufficient; the rate-reapply hypothesis was not evaluated."
            )
            return
        }
        if terminal.bool("hasAudio") == true,
           terminal.bool("reapplyAudioSufficient") != true {
            attachCheckpoint(
                name: "real-video-aac-00-tail",
                controlPlane: controlPlane,
                app: app
            )
            XCTFail(
                "classification=audioNeverSufficient; the rate-reapply hypothesis was not evaluated."
            )
            return
        }

        waitForReappliedRates(in: controlPlane)
        let tail = attachCheckpoint(
            name: "real-video-aac-00-tail",
            controlPlane: controlPlane,
            app: app
        )
        XCTAssertNotNil(tail.uint64("reapplyActivationSequence"))
        XCTAssertNotNil(tail.int64("reapplyAnchorValue"))
        XCTAssertNotNil(tail.int64("reapplyAnchorTimescale"))
        XCTAssertNotNil(tail.int64("reapplyAnchorEpoch"))
        XCTAssertNotNil(tail.uint64("reapplyAnchorFlags"))
        XCTAssertGreaterThan(tail.double("reapplyRequestedRate") ?? 0, 0)
        XCTAssertEqual(tail.bool("reapplyVideoSufficient"), true)
        if tail.bool("hasAudio") == true {
            XCTAssertEqual(tail.bool("reapplyAudioRequired"), true)
            XCTAssertEqual(tail.bool("reapplyAudioSufficient"), true)
        }
        XCTAssertEqual(tail.double("reapplyDirectRate") ?? .nan, 0, accuracy: 0.01)
        XCTAssertEqual(tail.double("reapplyEffectiveRate") ?? .nan, 0, accuracy: 0.01)
        XCTAssertEqual(tail.uint64("reapplyAttemptCount"), 1)
        XCTAssertEqual(tail.uint64("reapplyClaimCount"), 1)
        XCTAssertEqual(tail.string("reapplyOutcome"), "reapplied")
        XCTAssertGreaterThan(tail.double("actualRate") ?? 0, 0.5)
        XCTAssertGreaterThan(tail.double("effectiveRate") ?? 0, 0.5)
        guard tail.double("actualRate") ?? 0 > 0.5,
              tail.double("effectiveRate") ?? 0 > 0.5,
              tail.uint64("reapplyAttemptCount") == 1,
              tail.uint64("reapplyClaimCount") == 1,
              tail.string("reapplyOutcome") == "reapplied" else { return }

        Thread.sleep(forTimeInterval: 1)
        let checkpointA = attachCheckpoint(
            name: "real-video-aac-01-a",
            controlPlane: controlPlane,
            app: app
        )
        Thread.sleep(forTimeInterval: 1)
        let checkpointB = attachCheckpoint(
            name: "real-video-aac-02-b",
            controlPlane: controlPlane,
            app: app
        )
        assertContinuousPlayback(
            from: checkpointA,
            to: checkpointB,
            context: "sufficient-media rate reapply"
        )
        XCTAssertGreaterThan(
            checkpointB.uint64("audioRendererSamples") ?? 0,
            checkpointA.uint64("audioRendererSamples") ?? 0
        )
    }

    @MainActor
    func testUR12AcousticCalibrationTone() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_ACOUSTIC_CALIBRATION"] = "1"
        app.launchEnvironment["ENCHRON_ACOUSTIC_SESSION_MODE"] = "default"
        app.launchEnvironment["ENCHRON_ACOUSTIC_ARMING_DELAY_SECONDS"] = "2"
        app.launch()

        let status = app.descendants(matching: .any)["AcousticCalibration-status"]
            .firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))

        let playing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'playing'"),
            object: status
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [playing], timeout: 10),
            .completed,
            "Audio-engine default tone never began. Current state: \(String(describing: status.value))"
        )
        attachAcousticStatusMarker("audioengine-default-calibration-start", status: status)

        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'finished'"),
            object: status
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [finished], timeout: 15),
            .completed,
            "Calibration tone did not finish. Current state: \(String(describing: status.value))"
        )
        attachAcousticStatusMarker("audioengine-default-calibration-end", status: status)
    }

    @MainActor
    func testAudioEngineMoviePlaybackAcousticCalibrationTone() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_ACOUSTIC_CALIBRATION"] = "1"
        app.launchEnvironment["ENCHRON_ACOUSTIC_SESSION_MODE"] = "moviePlayback"
        app.launchEnvironment["ENCHRON_ACOUSTIC_ARMING_DELAY_SECONDS"] = "2"
        app.launch()

        let status = app.descendants(matching: .any)["AcousticCalibration-status"]
            .firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))

        let playing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'playing'"),
            object: status
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [playing], timeout: 10),
            .completed,
            "Audio-engine moviePlayback tone never began. Current state: \(String(describing: status.value))"
        )
        attachAcousticStatusMarker("audioengine-movie-calibration-start", status: status)

        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'finished'"),
            object: status
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [finished], timeout: 15),
            .completed,
            "Audio-engine moviePlayback tone did not finish. Current state: \(String(describing: status.value))"
        )
        attachAcousticStatusMarker("audioengine-movie-calibration-end", status: status)
    }

    @MainActor
    func testAudioEngineDefaultManualPhaseAcousticCalibrationTone() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_ACOUSTIC_CALIBRATION"] = "1"
        app.launchEnvironment["ENCHRON_ACOUSTIC_SESSION_MODE"] = "default"
        app.launchEnvironment["ENCHRON_ACOUSTIC_MANUAL_START"] = "1"
        app.launch()

        let status = app.descendants(matching: .any)["AcousticCalibration-status"]
            .firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let engineSnapshot = app.descendants(matching: .any)[
            "AcousticCalibration-engine-snapshot"
        ].firstMatch
        XCTAssertTrue(engineSnapshot.waitForExistence(timeout: 10))
        let toneManifest = app.descendants(matching: .any)[
            "AcousticCalibration-tone-manifest"
        ].firstMatch
        XCTAssertTrue(toneManifest.waitForExistence(timeout: 10))
        let sourceEvidence = app.descendants(matching: .any)[
            "AcousticCalibration-source-evidence"
        ].firstMatch
        XCTAssertTrue(sourceEvidence.waitForExistence(timeout: 10))
        let runtimeTimeline = app.descendants(matching: .any)[
            "AcousticCalibration-runtime-timeline"
        ].firstMatch
        XCTAssertTrue(runtimeTimeline.waitForExistence(timeout: 10))
        let mixerTapEnvelope = app.descendants(matching: .any)[
            "AcousticCalibration-mixer-tap-envelope"
        ].firstMatch
        XCTAssertTrue(mixerTapEnvelope.waitForExistence(timeout: 10))
        let mixerTapEnvelopeHash = app.descendants(matching: .any)[
            "AcousticCalibration-mixer-tap-envelope-sha256"
        ].firstMatch
        XCTAssertTrue(mixerTapEnvelopeHash.waitForExistence(timeout: 10))
        let start = app.buttons["AcousticCalibration-start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))

        attachAcousticStatusMarker(
            "audioengine-default-calibration-manual-phase-start",
            status: status,
            rendererSnapshot: engineSnapshot
        )
        start.tap()

        let playing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'playing'"),
            object: status
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [playing], timeout: 10),
            .completed,
            "Manual audio-engine tone never began. Current state: \(String(describing: status.value))"
        )

        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'finished'"),
            object: status
        )
        let finishedResult = XCTWaiter.wait(for: [finished], timeout: 15)
        attachAcousticStatusMarker(
            "audioengine-default-calibration-manual-phase-end",
            status: status,
            rendererSnapshot: engineSnapshot
        )
        let observedEngine = engineSnapshot.value as? String ?? ""
        let observedManifest = toneManifest.value as? String ?? ""
        attachToneManifest(observedManifest)
        let observedSource = sourceEvidence.value as? String ?? ""
        let observedTimeline = runtimeTimeline.value as? String ?? ""
        let observedMixerEnvelope = mixerTapEnvelope.value as? String ?? ""
        let observedMixerEnvelopeHash = mixerTapEnvelopeHash.value as? String ?? ""
        attachAcousticJSONEvidence(
            name: "acoustic-source-envelope",
            json: observedSource
        )
        attachAcousticJSONEvidence(
            name: "acoustic-runtime-timeline",
            json: observedTimeline
        )
        attachAcousticJSONEvidence(
            name: "acoustic-mixer-tap-envelope",
            json: observedMixerEnvelope
        )
        attachAcousticTextEvidence(
            name: "acoustic-mixer-tap-envelope-sha256",
            text: observedMixerEnvelopeHash
        )
        let sourceObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(observedSource.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(sourceObject["frameLength"] as? Int, 384_000)
        XCTAssertEqual(sourceObject["formatSampleRate"] as? Double, 48_000)
        XCTAssertEqual((sourceObject["sourcePCMHash"] as? String)?.count, 64)
        XCTAssertEqual((sourceObject["scannedBursts"] as? [[String: Any]])?.count, 11)
        let timelineObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(observedTimeline.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(timelineObject["expectedFinalSampleTime"] as? Int, 384_000)
        XCTAssertGreaterThanOrEqual(
            (timelineObject["samples"] as? [[String: Any]])?.count ?? 0,
            30
        )
        let calibrationSessionID = try XCTUnwrap(
            timelineObject["calibrationSessionID"] as? String
        )
        let mixerObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(observedMixerEnvelope.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(mixerObject["calibrationSessionID"] as? String, calibrationSessionID)
        let preStartBusFormat = try XCTUnwrap(
            mixerObject["preStartBusFormat"] as? [String: Any]
        )
        XCTAssertGreaterThan(preStartBusFormat["sampleRate"] as? Double ?? 0, 0)
        let callbacks = try XCTUnwrap(
            mixerObject["callbacks"] as? [[String: Any]]
        )
        XCTAssertGreaterThan(callbacks.count, 0)
        let callbackRates = Set(callbacks.compactMap { $0["bufferSampleRate"] as? Double })
        let callbackChannels = Set(callbacks.compactMap { $0["bufferChannelCount"] as? Int })
        let audioTimeRates = Set(callbacks.compactMap { $0["audioTimeSampleRate"] as? Double })
        XCTAssertEqual(callbackRates.count, 1)
        XCTAssertEqual(callbackChannels.count, 1)
        XCTAssertEqual(audioTimeRates, callbackRates)
        XCTAssertGreaterThan(mixerObject["callbackCount"] as? Int ?? 0, 0)
        XCTAssertGreaterThanOrEqual(mixerObject["totalFrames"] as? Int ?? 0, 384_000)
        XCTAssertEqual(observedMixerEnvelopeHash.count, 64)
        XCTAssertTrue(observedEngine.contains("calibrationSessionID=\(calibrationSessionID)"))
        XCTAssertEqual(
            finishedResult,
            .completed,
            "Manual audio-engine tone did not finish. Current state: \(String(describing: status.value))"
        )
        XCTAssertTrue(
            observedEngine.contains("engineError=none"),
            "Audio engine reported an error: \(observedEngine)"
        )
        XCTAssertTrue(
            observedEngine.contains("audioSessionMode=AVAudioSessionModeDefault"),
            "Audio-engine session mode did not remain default: \(observedEngine)"
        )
    }

    @MainActor
    func testSampleBufferAudioRendererAcousticCalibrationTone() throws {
        try runSampleBufferAcousticCalibration(
            audioSessionMode: "moviePlayback",
            markerPrefix: "sample-buffer-calibration"
        )
    }

    @MainActor
    func testSampleBufferDefaultAudioSessionAcousticCalibrationTone() throws {
        try runSampleBufferAcousticCalibration(
            audioSessionMode: "default",
            markerPrefix: "sample-buffer-default-calibration"
        )
    }

    @MainActor
    private func runSampleBufferAcousticCalibration(
        audioSessionMode: String,
        markerPrefix: String
    ) throws {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_SAMPLE_BUFFER_ACOUSTIC_CALIBRATION"] = "1"
        app.launchEnvironment[
            "ENCHRON_SAMPLE_BUFFER_ACOUSTIC_SESSION_MODE"
        ] = audioSessionMode
        app.launchEnvironment[
            "ENCHRON_SAMPLE_BUFFER_ACOUSTIC_ARMING_DELAY_SECONDS"
        ] = "2"
        app.launchEnvironment["ENCHRON_SAMPLE_BUFFER_ACOUSTIC_MANUAL_START"] = "1"
        app.launch()

        let status = app.descendants(matching: .any)[
            "SampleBufferAcousticCalibration-status"
        ].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let rendererSnapshot = app.descendants(matching: .any)[
            "SampleBufferAcousticCalibration-renderer-snapshot"
        ].firstMatch
        XCTAssertTrue(rendererSnapshot.waitForExistence(timeout: 10))

        let start = app.buttons["SampleBufferAcousticCalibration-start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        attachAcousticStatusMarker(
            "\(markerPrefix)-start",
            status: status,
            rendererSnapshot: rendererSnapshot
        )
        start.tap()

        let playing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'playing'"),
            object: status
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [playing], timeout: 10),
            .completed,
            "Sample-buffer tone never began. Current state: \(String(describing: status.value))"
        )

        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'finished'"),
            object: status
        )
        let finishedResult = XCTWaiter.wait(for: [finished], timeout: 15)
        attachAcousticStatusMarker(
            "\(markerPrefix)-end",
            status: status,
            rendererSnapshot: rendererSnapshot
        )
        let observedRenderer = rendererSnapshot.value as? String ?? ""
        XCTAssertEqual(
            finishedResult,
            .completed,
            "Sample-buffer tone did not finish. Current state: \(String(describing: status.value))"
        )
        XCTAssertTrue(
            observedRenderer.contains("rendererError=none"),
            "Sample-buffer renderer reported an error: \(observedRenderer)"
        )
        XCTAssertFalse(
            observedRenderer.contains("rendererStatus=failed"),
            "Sample-buffer renderer failed: \(observedRenderer)"
        )
        let expectedMode = audioSessionMode == "default"
            ? "AVAudioSessionModeDefault"
            : "AVAudioSessionModeMoviePlayback"
        XCTAssertTrue(
            observedRenderer.contains("audioSessionMode=\(expectedMode)"),
            "Sample-buffer session mode did not match C/D matrix input: \(observedRenderer)"
        )
    }

    @MainActor
    func testRealPlaybackAcousticTimeline() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launch()

        let controlPlane = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        if controlPlane.waitForExistence(timeout: 3) == false {
            let media = app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "identifier BEGINSWITH 'MediaLibrary-grid-video-'"
                    )
                )
                .firstMatch
            XCTAssertTrue(media.waitForExistence(timeout: 20))
            media.tap()
        }

        XCTAssertTrue(controlPlane.waitForExistence(timeout: 30))
        let playPause = app.buttons["PlayerPanel-button-play"].firstMatch
        let forward = app.buttons["PlayerPanel-button-forward"].firstMatch
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        XCTAssertTrue(forward.waitForExistence(timeout: 10))

        waitForLifecycle("playing", in: controlPlane)
        waitForActualRate(above: 0.5, in: controlPlane)
        attachAcousticMarker("initial-play-start", controlPlane: controlPlane)
        Thread.sleep(forTimeInterval: 6)
        attachAcousticMarker("initial-play-end", controlPlane: controlPlane)

        playPause.tap()
        waitForLifecycle("paused", in: controlPlane)
        attachAcousticMarker("pause-start", controlPlane: controlPlane)
        Thread.sleep(forTimeInterval: 4)
        attachAcousticMarker("pause-end", controlPlane: controlPlane)

        playPause.tap()
        waitForLifecycle("playing", in: controlPlane)
        waitForActualRate(above: 0.5, in: controlPlane)
        attachAcousticMarker("resume-start", controlPlane: controlPlane)
        Thread.sleep(forTimeInterval: 6)
        let resumed = attachAcousticMarker("resume-end", controlPlane: controlPlane)

        forward.tap()
        waitForStreamEpoch(after: resumed.uint64("streamEpoch"), in: controlPlane)
        waitForActualRate(above: 0.5, in: controlPlane)
        attachAcousticMarker("seek-play-start", controlPlane: controlPlane)
        Thread.sleep(forTimeInterval: 6)
        attachAcousticMarker("seek-play-end", controlPlane: controlPlane)

        playPause.tap()
        waitForLifecycle("paused", in: controlPlane)
        attachAcousticMarker("final-pause-start", controlPlane: controlPlane)
        Thread.sleep(forTimeInterval: 4)
        attachAcousticMarker("final-pause-end", controlPlane: controlPlane)
    }

    @MainActor
    func testDockAndPanoramaRoundTripsInOneLaunch() throws {
        guard let fixture = ProcessInfo.processInfo
            .environment["ENCHRON_DEVICE_ACCEPTANCE_FIXTURE_URL"] else {
            throw XCTSkip(
                "Set ENCHRON_DEVICE_ACCEPTANCE_FIXTURE_URL to a media URL reachable from Apple Vision Pro."
            )
        }
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture
        app.launch()

        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 20))
        dock.tap()

        let environment = app.descendants(matching: .any)["PlayerUI-DockMenu-day"].firstMatch
        XCTAssertTrue(environment.waitForExistence(timeout: 5))
        environment.tap()

        let exitSpatial = app.descendants(matching: .any)["PlayerPanel-button-exit-spatial"].firstMatch
        XCTAssertTrue(exitSpatial.waitForExistence(timeout: 20))
        XCTAssertEqual(exitSpatial.label, "Return to Window")
        let settings = app.descendants(matching: .any)["PlayerPanel-button-expand"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerPanel-ScreenSize-slider"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.descendants(matching: .any)["PlayerPanel-button-back"].exists)
        exitSpatial.tap()
        XCTAssertTrue(dock.waitForExistence(timeout: 20))

        let format = app.descendants(matching: .any)["PlayerUI-TopAction-videoFormat"].firstMatch
        XCTAssertTrue(format.waitForExistence(timeout: 5))
        format.tap()

        let panorama360 = app.descendants(matching: .any)["PlayerUI-VideoFormat-Projection-360°"].firstMatch
        XCTAssertTrue(panorama360.waitForExistence(timeout: 5))
        panorama360.tap()
        app.buttons["PlayerUI-VideoFormat-apply"].tap()

        XCTAssertTrue(exitSpatial.waitForExistence(timeout: 20))
        XCTAssertEqual(exitSpatial.label, "Return to Window")
        XCTAssertTrue(app.descendants(matching: .any)["PlayerPanel-button-back"].exists)
        exitSpatial.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerUI-TopAction-resumePanorama"]
                .waitForExistence(timeout: 20)
        )
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-TopAction-dock"].exists)
    }

    @MainActor
    private func attachCheckpoint(
        name: String,
        controlPlane: XCUIElement,
        app: XCUIApplication
    ) -> PlaybackCheckpoint {
        let state = controlPlane.value as? String ?? "<missing control-plane value>"
        let checkpoint = PlaybackCheckpoint(rawValue: state)
        let stateAttachment = XCTAttachment(string: state)
        stateAttachment.name = "\(name)-state"
        stateAttachment.lifetime = .keepAlways
        add(stateAttachment)

        let hierarchyAttachment = XCTAttachment(string: app.debugDescription)
        hierarchyAttachment.name = "\(name)-hierarchy"
        hierarchyAttachment.lifetime = .keepAlways
        add(hierarchyAttachment)

        let screenshotAttachment = XCTAttachment(
            screenshot: XCUIScreen.main.screenshot(),
            quality: .original
        )
        screenshotAttachment.name = "\(name)-screen"
        screenshotAttachment.lifetime = .keepAlways
        add(screenshotAttachment)
        return checkpoint
    }

    @MainActor
    private func attachAcousticMarker(
        _ name: String,
        controlPlane: XCUIElement
    ) -> PlaybackCheckpoint {
        let state = controlPlane.value as? String ?? "<missing control-plane value>"
        let marker = "wallClock=\(Date().timeIntervalSince1970);state=\(state)"
        let attachment = XCTAttachment(string: marker)
        attachment.name = "acoustic-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        return PlaybackCheckpoint(rawValue: state)
    }

    @MainActor
    private func attachAcousticStatusMarker(
        _ name: String,
        status: XCUIElement,
        rendererSnapshot: XCUIElement? = nil
    ) {
        let observedStatus = status.value as? String ?? "<missing calibration status>"
        let observedRenderer = rendererSnapshot?.value as? String
            ?? "rendererSnapshot=notRequested"
        let marker = "wallClock=\(Date().timeIntervalSince1970);state="
            + "status=\(observedStatus);\(observedRenderer)"
        let attachment = XCTAttachment(string: marker)
        attachment.name = "acoustic-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachToneManifest(_ manifest: String) {
        XCTAssertFalse(manifest.isEmpty, "AcousticToneManifest accessibility value is empty")
        let manifestAttachment = XCTAttachment(string: manifest)
        manifestAttachment.name = "acoustic-tone-manifest"
        manifestAttachment.lifetime = .keepAlways
        add(manifestAttachment)

        let sourceHash = (try? JSONSerialization.jsonObject(
            with: Data(manifest.utf8)
        ) as? [String: Any])?["sourceHash"] as? String ?? "missing"
        XCTAssertNotEqual(sourceHash, "missing", "AcousticToneManifest sourceHash is missing")
        let hashAttachment = XCTAttachment(string: sourceHash)
        hashAttachment.name = "acoustic-tone-manifest-sha256"
        hashAttachment.lifetime = .keepAlways
        add(hashAttachment)
    }

    private func attachAcousticJSONEvidence(name: String, json: String) {
        XCTAssertFalse(json.isEmpty, "\(name) accessibility value is empty")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(json.utf8)))
        let attachment = XCTAttachment(string: json)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachAcousticTextEvidence(name: String, text: String) {
        XCTAssertFalse(text.isEmpty, "\(name) accessibility value is empty")
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitForLifecycle(_ lifecycle: String, in controlPlane: XCUIElement) {
        let predicate = NSPredicate(
            format: "value CONTAINS[c] %@",
            "lifecycle=\(lifecycle)"
        )
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: controlPlane)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 10),
            .completed,
            "Playback never reached \(lifecycle). Current state: \(String(describing: controlPlane.value))"
        )
    }

    @MainActor
    private func waitForStreamEpoch(
        after previousEpoch: UInt64?,
        in controlPlane: XCUIElement
    ) {
        guard let previousEpoch else {
            XCTFail("The pre-seek checkpoint did not expose streamEpoch.")
            return
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let checkpoint = PlaybackCheckpoint(
                rawValue: controlPlane.value as? String ?? ""
            )
            if let currentEpoch = checkpoint.uint64("streamEpoch"),
               currentEpoch > previousEpoch {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail(
            "Seek did not establish a new stream epoch. Current state: \(String(describing: controlPlane.value))"
        )
    }

    @MainActor
    private func waitForActualRate(
        above minimumRate: Double,
        in controlPlane: XCUIElement
    ) {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let checkpoint = PlaybackCheckpoint(
                rawValue: controlPlane.value as? String ?? ""
            )
            if checkpoint.double("actualRate") ?? 0 > minimumRate {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail(
            "Playback timebase did not start. Current state: \(String(describing: controlPlane.value))"
        )
    }

    @MainActor
    private func waitForPreRateMediaEvidence(in controlPlane: XCUIElement) {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let checkpoint = PlaybackCheckpoint(
                rawValue: controlPlane.value as? String ?? ""
            )
            if checkpoint.bool("displayedPixel") == true,
               checkpoint.uint64("videoSamples") ?? 0 > 0,
               checkpoint.uint64("audioSamples") ?? 0 > 0,
               checkpoint.uint64("audioRendererSamples") ?? 0 > 0 {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail(
            "Real-video pre-rate media evidence did not become observable. Current state: \(String(describing: controlPlane.value))"
        )
    }

    @MainActor
    private func waitForReapplyTerminalState(
        in controlPlane: XCUIElement
    ) -> PlaybackCheckpoint {
        let terminalOutcomes = Set([
            "reapplied",
            "rateAlreadyActive",
            "timedOut",
            "staleBeforeReapply",
            "invalidatedByNewActivation",
            "invalidatedBySeek",
            "invalidatedByPause",
            "invalidatedByRateChange",
            "invalidatedByEpochChange",
            "invalidatedByStop",
            "invalidatedByClose",
        ])
        let deadline = Date().addingTimeInterval(5)
        var latest = PlaybackCheckpoint(rawValue: "")
        while Date() < deadline {
            latest = PlaybackCheckpoint(
                rawValue: controlPlane.value as? String ?? ""
            )
            if let outcome = latest.string("reapplyOutcome"),
               terminalOutcomes.contains(outcome) {
                return latest
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail(
            "Rate-reapply verification did not reach a terminal state. Current state: \(String(describing: controlPlane.value))"
        )
        return latest
    }

    @MainActor
    private func waitForReappliedRates(in controlPlane: XCUIElement) {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let checkpoint = PlaybackCheckpoint(
                rawValue: controlPlane.value as? String ?? ""
            )
            if checkpoint.double("actualRate") ?? 0 > 0.5,
               checkpoint.double("effectiveRate") ?? 0 > 0.5 {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func assertContinuousPlayback(
        from previous: PlaybackCheckpoint,
        to current: PlaybackCheckpoint,
        context: String
    ) {
        XCTAssertEqual(current.lifecycle?.lowercased(), "playing", context)
        XCTAssertEqual(current.string("session"), previous.string("session"), context)
        XCTAssertEqual(current.uint64("streamEpoch"), previous.uint64("streamEpoch"), context)
        XCTAssertGreaterThan(current.double("actualRate") ?? 0, 0.5, context)
        XCTAssertGreaterThan(
            current.double("position") ?? 0,
            (previous.double("position") ?? 0) + 0.25,
            context
        )
        XCTAssertGreaterThan(
            current.uint64("videoSamples") ?? 0,
            previous.uint64("videoSamples") ?? 0,
            context
        )
        XCTAssertGreaterThan(
            current.uint64("rendererInputs") ?? 0,
            previous.uint64("rendererInputs") ?? 0,
            context
        )
        XCTAssertEqual(current.bool("bootstrapComplete"), true, context)
        XCTAssertEqual(current.bool("componentReady"), true, context)
        XCTAssertEqual(current.bool("displayedPixel"), true, context)
        if current.bool("hasAudio") == true {
            XCTAssertGreaterThan(
                current.uint64("audioSamples") ?? 0,
                previous.uint64("audioSamples") ?? 0,
                context
            )
            XCTAssertGreaterThan(
                current.uint64("audioRendererSamples") ?? 0,
                previous.uint64("audioRendererSamples") ?? 0,
                context
            )
            XCTAssertEqual(current.string("audioRendererStatus"), "rendering", context)
            XCTAssertEqual(current.double("audioRendererVolume") ?? 0, 1, accuracy: 0.01)
            XCTAssertEqual(current.bool("audioRendererMuted"), false, context)
            XCTAssertEqual(current.string("audioRendererError"), "none", context)
            XCTAssertEqual(current.bool("audioSessionActive"), true, context)
            XCTAssertEqual(
                current.string("audioSessionCategory"),
                "AVAudioSessionCategoryPlayback",
                context
            )
            XCTAssertEqual(
                current.string("audioSessionMode"),
                "AVAudioSessionModeMoviePlayback",
                context
            )
            XCTAssertFalse(current.string("audioOutputPorts", default: "").isEmpty, context)
            XCTAssertGreaterThan(current.double("systemOutputVolume") ?? 0, 0, context)
        }
    }

    private struct PlaybackCheckpoint {
        let rawValue: String
        let fields: [String: String]

        init(rawValue: String) {
            self.rawValue = rawValue
            fields = Dictionary(
                uniqueKeysWithValues: rawValue.split(separator: ";").compactMap { item in
                    let pair = item.split(separator: "=", maxSplits: 1)
                    guard pair.count == 2 else { return nil }
                    return (String(pair[0]), String(pair[1]))
                }
            )
        }

        var lifecycle: String? { fields["lifecycle"] }

        func string(_ key: String) -> String? { fields[key] }
        func string(_ key: String, default defaultValue: String) -> String {
            fields[key] ?? defaultValue
        }
        func double(_ key: String) -> Double? { fields[key].flatMap(Double.init) }
        func int64(_ key: String) -> Int64? { fields[key].flatMap(Int64.init) }
        func uint64(_ key: String) -> UInt64? { fields[key].flatMap(UInt64.init) }
        func bool(_ key: String) -> Bool? { fields[key].flatMap(Bool.init) }
    }

}

nonisolated final class PhotosPlaybackDeviceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        let explicitlyEnabled = ProcessInfo.processInfo.environment["ENCHRON_RUN_PHOTOS_TEST"] == "1"
            || UserDefaults.standard.bool(forKey: "ENCHRON_RUN_PHOTOS_TEST")
        guard explicitlyEnabled else {
            throw XCTSkip("Run Scripts/verification/verify-photos-simulator.zsh to seed a Simulator Photos library.")
        }
#endif
    }

    @MainActor
    func testFreshPhotosImportStartsRealPlayback() {
        let app = XCUIApplication()
        let permissionLabels = [
            "Allow Full Access",
            "Allow Access to All Photos",
            "Continue",
            "允许完全访问",
            "允许访问所有照片",
            "继续"
        ]
        addUIInterruptionMonitor(withDescription: "Photos access") { alert in
            for label in permissionLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            let buttons = alert.buttons
            guard buttons.count >= 2 else { return false }
            buttons.element(boundBy: buttons.count == 3 ? 1 : 0).tap()
            return true
        }
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launch()

        let existingMedia = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'MediaLibrary-grid-video-'"))
        XCTAssertEqual(existingMedia.count, 0, "The device import test must begin with an empty media library.")

        let manage = app.buttons["Manage media library"]
        XCTAssertTrue(manage.waitForExistence(timeout: 20))
        manage.tap()
        let addPhotos = app.buttons["Add from Photos"]
        XCTAssertTrue(addPhotos.waitForExistence(timeout: 5))
        addPhotos.tap()
#if !targetEnvironment(simulator)
        Thread.sleep(forTimeInterval: 3)
        app.tap()
#endif

        let firstPhoto = app.collectionViews.cells.firstMatch
        XCTAssertTrue(
            firstPhoto.waitForExistence(timeout: 20),
            "Photos Picker did not expose a selectable video. App hierarchy: \(app.debugDescription)"
        )
        firstPhoto.tap()
        let add = app.buttons["Add"]
        let done = app.buttons["Done"]
        if add.waitForExistence(timeout: 5) {
            add.tap()
        } else {
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap()
        }

        let media = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'MediaLibrary-grid-video-'"))
            .firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 20), "Fresh Photos import did not create a media reference.")
        media.tap()

        let player = app.descendants(matching: .any)["PlayerUI-window-playback"].firstMatch
        let libraryError = app.alerts["Media Library Error"]
        XCTAssertTrue(
            player.waitForExistence(timeout: 30),
            "Real playback did not open. Media library error: \(libraryError.label)"
        )
        let playing = NSPredicate(format: "value ==[c] 'playing'")
        let ready = XCTNSPredicateExpectation(predicate: playing, object: player)
        XCTAssertEqual(
            XCTWaiter.wait(for: [ready], timeout: 30),
            .completed,
            "Playback window appeared but never reached the playing state. Current value: \(player.value)"
        )
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-loadFailure-panel"].exists)
    }
}
