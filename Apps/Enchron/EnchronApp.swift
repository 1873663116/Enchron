@preconcurrency import AVFoundation
import CryptoKit
import RealityKitScripting
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

@main
struct EnchronApp: App {
    @State private var application: EnchronApplication
    @State private var immersionStyle: ImmersionStyle = .progressive(
        SpatialImmersiveSpacePolicy.progressiveImmersionRange
    )

    init() {
        do {
            try RKS.initialize()
        } catch {
            assertionFailure("RealityKitScripting initialization failed: \(error)")
        }
        _application = State(initialValue: EnchronApplication())
    }

    var body: some Scene {
        Window("Enchron", id: "main") {
            Group {
#if DEBUG
                if ProcessInfo.processInfo.environment[
                    "ENCHRON_SAMPLE_BUFFER_ACOUSTIC_CALIBRATION"
                ] == "1" {
                    SampleBufferAcousticCalibrationView()
                } else if ProcessInfo.processInfo.environment[
                    "ENCHRON_ACOUSTIC_CALIBRATION"
                ] == "1" {
                    AcousticCalibrationView()
                } else {
                    MainView()
                }
#else
                MainView()
#endif
            }
                .enchronEnvironment(application)
        }
        .defaultSize(
            width: WindowPlaybackLayout.fallback.defaultSize.width,
            height: WindowPlaybackLayout.fallback.defaultSize.height
        )
        // Playback supplies the visible video surface. Browser pages restore
        // the system-shaped glass explicitly inside MainView.
        .windowStyle(.plain)
        .windowResizability(.contentSize)

        Window("Player Controls", id: "playerControls") {
            SpatialPlaybackControlsRoot()
                .enchronEnvironment(application)
        }
        .defaultSize(width: 760, height: 220)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Window("Environment", id: AppModel.senseZoneVolumeID) {
            SenseZoneVolumeRoot()
                .enchronEnvironment(application)
                .onAppear {
                    application.appModel.receiveSpatialPlatformResult(
                        .environmentCardAppeared
                    )
                }
                .onDisappear {
                    application.appModel.receiveSpatialPlatformResult(
                        .environmentCardDisappeared
                    )
                }
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.4, height: 0.9, depth: 0.8, in: .meters)

        ImmersiveSpace(id: application.appModel.immersiveSpaceID) {
            ImmersiveSpaceView()
                .environment(application.appModel)
                .environment(application.playbackRuntime)
                .onImmersionChange { _, newImmersion in
                    application.appModel.recordImmersionAmount(newImmersion.amount)
                }
                .onAppear {
                    application.spatialPlatformEffectCoordinator
                        .recordImmersiveSpaceResidency(.open)
                    application.appModel.receiveSpatialPlatformResult(
                        .immersiveSpaceAppeared
                    )
                    Task { await application.appModel.loadScreenPosition() }
                }
                .onDisappear {
                    application.spatialPlatformEffectCoordinator
                        .recordImmersiveSpaceResidency(.closed)
                    let playbackContext = application.playbackRuntime.activeSessionID.map {
                        SpatialPlaybackTransitionContext(
                            mediaSessionID: $0,
                            wasPlaying: application.playbackRuntime.productLifecycle == .playing
                        )
                    }
                    if application.playbackRuntime.attachedPresentation != .window {
                        application.playbackRuntime.detach()
                    }
                    application.appModel.receiveSpatialPlatformResult(
                        .immersiveSpaceDisappeared(playbackContext)
                    )
                }
        }
        .immersionStyle(selection: $immersionStyle, in: .progressive)
        .onChange(of: application.appModel.immersiveSpaceStyleRevision) { _, _ in
            immersionStyle = .progressive(
                SpatialImmersiveSpacePolicy.progressiveImmersionRange,
                initialAmount: application.appModel.immersiveSpaceOpeningInitialAmount
            )
        }
    }
}

#if DEBUG
private struct AcousticCalibrationView: View {
    @State private var status = "ready"
    @State private var engineSnapshot = "engineStatus=stopped;engineError=none"
    @State private var toneManifest = ""
    @State private var sourceEvidence = ""
    @State private var runtimeTimeline = ""
    @State private var mixerTapEnvelope = ""
    @State private var mixerTapEnvelopeHash = ""
    @State private var tonePlayer = AcousticCalibrationTonePlayer()

    private var armingDelaySeconds: Double {
        guard let value = ProcessInfo.processInfo.environment[
            "ENCHRON_ACOUSTIC_ARMING_DELAY_SECONDS"
        ].flatMap(Double.init), value.isFinite, value > 0 else {
            return 0
        }
        return value
    }

    private var audioSessionMode: AVAudioSession.Mode {
        ProcessInfo.processInfo.environment["ENCHRON_ACOUSTIC_SESSION_MODE"]
            == "moviePlayback" ? .moviePlayback : .default
    }

    private var manualStartEnabled: Bool {
        ProcessInfo.processInfo.environment[
            "ENCHRON_ACOUSTIC_MANUAL_START"
        ] == "1"
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform")
                .font(.system(size: 54))
            Text("Acoustic Calibration")
                .font(.title)
            Text("997 Hz / 1499 Hz")
                .foregroundStyle(.secondary)
            Text(status.capitalized)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Acoustic Calibration Status")
                .accessibilityIdentifier("AcousticCalibration-status")
                .accessibilityValue(status)
            Text("Engine diagnostics")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("AcousticCalibration-engine-snapshot")
                .accessibilityValue(engineSnapshot)
            Text("Tone manifest")
                .accessibilityIdentifier("AcousticCalibration-tone-manifest")
                .accessibilityValue(toneManifest)
            Text("Source evidence")
                .accessibilityIdentifier("AcousticCalibration-source-evidence")
                .accessibilityValue(sourceEvidence)
            Text("Runtime timeline")
                .accessibilityIdentifier("AcousticCalibration-runtime-timeline")
                .accessibilityValue(runtimeTimeline)
            Text("Mixer tap envelope")
                .accessibilityIdentifier("AcousticCalibration-mixer-tap-envelope")
                .accessibilityValue(mixerTapEnvelope)
            Text("Mixer tap envelope hash")
                .accessibilityIdentifier("AcousticCalibration-mixer-tap-envelope-sha256")
                .accessibilityValue(mixerTapEnvelopeHash)
            if manualStartEnabled {
                Button("Start Calibration") {
                    Task { await beginPlayback() }
                }
                .accessibilityIdentifier("AcousticCalibration-start")
                .disabled(status != "ready")
            }
        }
        .padding(48)
        .task {
            tonePlayer.prepareSessionIfNeeded()
            engineSnapshot = tonePlayer.snapshot(audioSessionMode: audioSessionMode)
            toneManifest = tonePlayer.manifestJSON()
            sourceEvidence = tonePlayer.sourceEvidenceJSON()
            runtimeTimeline = tonePlayer.runtimeTimelineJSON()
            mixerTapEnvelope = tonePlayer.mixerTapEnvelopeJSON()
            mixerTapEnvelopeHash = tonePlayer.mixerTapEnvelopeSHA256()
            guard manualStartEnabled == false else { return }
            if armingDelaySeconds > 0 {
                do {
                    try await Task.sleep(for: .seconds(armingDelaySeconds))
                } catch {
                    return
                }
            }
            await beginPlayback()
        }
    }

    private func beginPlayback() async {
        guard status == "ready" else { return }
        status = "playing"
        do {
            try await tonePlayer.play(audioSessionMode: audioSessionMode)
            engineSnapshot = tonePlayer.snapshot(audioSessionMode: audioSessionMode)
            toneManifest = tonePlayer.manifestJSON()
            sourceEvidence = tonePlayer.sourceEvidenceJSON()
            runtimeTimeline = tonePlayer.runtimeTimelineJSON()
            mixerTapEnvelope = tonePlayer.mixerTapEnvelopeJSON()
            mixerTapEnvelopeHash = tonePlayer.mixerTapEnvelopeSHA256()
            status = "finished"
        } catch {
            engineSnapshot = tonePlayer.snapshot(
                audioSessionMode: audioSessionMode,
                error: error
            )
            toneManifest = tonePlayer.manifestJSON()
            sourceEvidence = tonePlayer.sourceEvidenceJSON()
            runtimeTimeline = tonePlayer.runtimeTimelineJSON()
            mixerTapEnvelope = tonePlayer.mixerTapEnvelopeJSON()
            mixerTapEnvelopeHash = tonePlayer.mixerTapEnvelopeSHA256()
            status = "failed:\(error.localizedDescription)"
        }
    }
}

@MainActor
private final class AcousticCalibrationTonePlayer {
    private let duration = 8.0
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var calibrationSessionID: String?
    private var scheduledBufferEvidence: AcousticScheduledBufferEvidence?
    private var runtimeSamples: [AcousticRuntimeSample] = []
    private var maximumObservedSampleTime: AVAudioFramePosition?
    private let mixerTapRecorder = AcousticMixerTapRecorder()

    func prepareSessionIfNeeded() {
        if calibrationSessionID == nil {
            calibrationSessionID = UUID().uuidString
        }
    }

    func play(audioSessionMode: AVAudioSession.Mode = .default) async throws {
        prepareSessionIfNeeded()
        runtimeSamples = []
        maximumObservedSampleTime = nil
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: audioSessionMode)
        try session.setActive(true)
        defer {
            engine.mainMixerNode.removeTap(onBus: 0)
            mixerTapRecorder.finish()
            engine.stop()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }

        let sampleRate = 48_000.0
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) else {
            throw AcousticCalibrationError.audioFormatUnavailable
        }
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ), let samples = buffer.floatChannelData?[0] else {
            throw AcousticCalibrationError.audioBufferUnavailable
        }
        buffer.frameLength = frameCount

        for frame in 0 ..< Int(frameCount) {
            let time = Double(frame) / sampleRate
            let positionInCycle = time.truncatingRemainder(dividingBy: 1.5)
            let toneFrequency: Double?
            switch positionInCycle {
            case 0 ..< 0.5:
                toneFrequency = 997
            case 0.75 ..< 1.25:
                toneFrequency = 1_499
            default:
                toneFrequency = nil
            }
            guard let toneFrequency else {
                samples[frame] = 0
                continue
            }

            let tonePosition = positionInCycle < 0.5
                ? positionInCycle
                : positionInCycle - 0.75
            let ramp = min(1, tonePosition / 0.01, (0.5 - tonePosition) / 0.01)
            samples[frame] = Float(
                0.18 * ramp * sin(2 * .pi * toneFrequency * time)
            )
        }
        scheduledBufferEvidence = makeScheduledBufferEvidence(
            buffer: buffer,
            samples: samples
        )

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        let tapFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        mixerTapRecorder.begin(
            calibrationSessionID: calibrationSessionID ?? "notPrepared",
            format: tapFormat
        )
        installAcousticMixerTap(
            on: engine.mainMixerNode,
            recorder: mixerTapRecorder
        )
        try engine.start()
        player.scheduleBuffer(
            buffer,
            at: nil,
            options: [],
            completionHandler: nil
        )
        player.play()
        recordRuntimeSample()
        for _ in 0 ..< 33 {
            try await Task.sleep(for: .milliseconds(250))
            recordRuntimeSample()
        }
    }

    func snapshot(
        audioSessionMode: AVAudioSession.Mode,
        error: Error? = nil
    ) -> String {
        [
            "engineStatus=\(engine.isRunning ? "running" : "stopped")",
            "engineError=\(error?.localizedDescription ?? "none")",
            "playerStatus=\(player.isPlaying ? "playing" : "stopped")",
            "audioSessionMode=\(audioSessionMode.rawValue)",
            "calibrationSessionID=\(calibrationSessionID ?? "notPrepared")",
        ].joined(separator: ";")
    }

    func manifestJSON() -> String {
        AcousticToneManifest.make(
            engineOutputSampleRate: engine.outputNode.outputFormat(forBus: 0).sampleRate,
            mainMixerSampleRate: engine.mainMixerNode.outputFormat(forBus: 0).sampleRate,
            scheduledBufferEvidence: scheduledBufferEvidence,
            calibrationSessionID: calibrationSessionID
        )
    }

    func sourceEvidenceJSON() -> String {
        encodeJSON(scheduledBufferEvidence)
    }

    func runtimeTimelineJSON() -> String {
        encodeJSON(AcousticRuntimeTimeline(
            calibrationSessionID: calibrationSessionID ?? "notPrepared",
            samples: runtimeSamples,
            maximumObservedSampleTime: maximumObservedSampleTime,
            expectedFinalSampleTime: 384_000,
            reachedExpectedFinalSampleTime: (maximumObservedSampleTime ?? -1) >= 384_000
        ))
    }

    func mixerTapEnvelopeJSON() -> String {
        mixerTapRecorder.json()
    }

    func mixerTapEnvelopeSHA256() -> String {
        mixerTapRecorder.sha256()
    }

    private func recordRuntimeSample() {
        let nodeTime = player.lastRenderTime
        let playerTime = nodeTime.flatMap { player.playerTime(forNodeTime: $0) }
        if let sampleTime = playerTime?.sampleTime {
            maximumObservedSampleTime = max(maximumObservedSampleTime ?? sampleTime, sampleTime)
        }
        runtimeSamples.append(AcousticRuntimeSample(
            wallClock: Date().timeIntervalSince1970,
            engineOutputSampleRate: engine.outputNode.outputFormat(forBus: 0).sampleRate,
            mainMixerSampleRate: engine.mainMixerNode.outputFormat(forBus: 0).sampleRate,
            playerSampleTime: playerTime?.sampleTime,
            playerSampleRate: playerTime?.sampleRate,
            engineRunning: engine.isRunning,
            playerPlaying: player.isPlaying
        ))
    }

    private func makeScheduledBufferEvidence(
        buffer: AVAudioPCMBuffer,
        samples: UnsafeMutablePointer<Float>
    ) -> AcousticScheduledBufferEvidence {
        let frameLength = Int(buffer.frameLength)
        let bytes = UnsafeRawBufferPointer(
            start: samples,
            count: frameLength * MemoryLayout<Float>.size
        )
        let sourceHash = SHA256.hash(data: Data(bytes))
            .map { String(format: "%02x", $0) }
            .joined()
        return AcousticScheduledBufferEvidence(
            sourcePCMHashAlgorithm: "sha256-float32-native-bytes",
            sourcePCMHash: sourceHash,
            frameLength: frameLength,
            formatSampleRate: buffer.format.sampleRate,
            scannedBursts: scanBursts(samples: samples, frameLength: frameLength)
        )
    }

    private func scanBursts(
        samples: UnsafeMutablePointer<Float>,
        frameLength: Int
    ) -> [AcousticSourceBurst] {
        let windowFrames = 480
        var labels: [(startFrame: Int, frequencyHz: Int?)] = []
        for startFrame in stride(from: 0, to: frameLength, by: windowFrames) {
            let endFrame = min(frameLength, startFrame + windowFrames)
            let values = UnsafeBufferPointer(
                start: samples + startFrame,
                count: endFrame - startFrame
            )
            let rms = sqrt(values.reduce(0.0) { $0 + Double($1 * $1) } / Double(values.count))
            guard rms > 0.005 else {
                labels.append((startFrame, nil))
                continue
            }
            let energy997 = goertzelEnergy(values, frequencyHz: 997, sampleRate: 48_000)
            let energy1499 = goertzelEnergy(values, frequencyHz: 1_499, sampleRate: 48_000)
            labels.append((startFrame, energy997 >= energy1499 ? 997 : 1_499))
        }
        var bursts: [AcousticSourceBurst] = []
        var activeFrequency: Int?
        var activeStart = 0
        for label in labels + [(frameLength, nil)] {
            if label.frequencyHz == activeFrequency { continue }
            if let activeFrequency {
                bursts.append(AcousticSourceBurst(
                    frequencyHz: activeFrequency,
                    startFrame: activeStart,
                    endFrame: label.startFrame
                ))
            }
            activeFrequency = label.frequencyHz
            activeStart = label.startFrame
        }
        return bursts
    }

    private func goertzelEnergy(
        _ samples: UnsafeBufferPointer<Float>,
        frequencyHz: Double,
        sampleRate: Double
    ) -> Double {
        let coefficient = 2 * cos(2 * .pi * frequencyHz / sampleRate)
        var previous = 0.0
        var previousPrevious = 0.0
        for sample in samples {
            let current = Double(sample) + coefficient * previous - previousPrevious
            previousPrevious = previous
            previous = current
        }
        return previousPrevious * previousPrevious + previous * previous
            - coefficient * previous * previousPrevious
    }

    private func encodeJSON<T: Encodable>(_ value: T?) -> String {
        guard let value else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private enum AcousticCalibrationError: Error {
        case audioFormatUnavailable
        case audioBufferUnavailable
    }
}

nonisolated private func installAcousticMixerTap(
    on mixer: AVAudioMixerNode,
    recorder: AcousticMixerTapRecorder
) {
    mixer.installTap(onBus: 0, bufferSize: 480, format: nil) { buffer, time in
        recorder.observe(buffer: buffer, time: time)
    }
}

nonisolated private final class AcousticMixerTapRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calibrationSessionID = "notPrepared"
    private var preStartBusSampleRate = 0.0
    private var preStartBusChannelCount = 0
    private var callbackCount = 0
    private var totalFrames = 0
    private var discontinuityCount = 0
    private var overrunCount = 0
    private var previousEndSampleTime: AVAudioFramePosition?
    private var firstSampleTime: AVAudioFramePosition?
    private var lastSampleTime: AVAudioFramePosition?
    private var firstHostTime: UInt64?
    private var lastHostTime: UInt64?
    private var windows: [AcousticMixerTapWindow] = []
    private var callbacks: [AcousticMixerTapCallback] = []
    private var isFinished = false

    func begin(calibrationSessionID: String, format: AVAudioFormat) {
        lock.withLock {
            self.calibrationSessionID = calibrationSessionID
            preStartBusSampleRate = format.sampleRate
            preStartBusChannelCount = Int(format.channelCount)
            callbackCount = 0
            totalFrames = 0
            discontinuityCount = 0
            overrunCount = 0
            previousEndSampleTime = nil
            firstSampleTime = nil
            lastSampleTime = nil
            firstHostTime = nil
            lastHostTime = nil
            windows = []
            callbacks = []
            isFinished = false
        }
    }

    func observe(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        let started = ContinuousClock.now
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frames = Int(buffer.frameLength)
        let channelsCount = Int(buffer.format.channelCount)
        let rate = buffer.format.sampleRate
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0 ..< frames {
            var sum: Float = 0
            for channel in 0 ..< channelsCount { sum += channels[channel][frame] }
            mono[frame] = sum / Float(max(1, channelsCount))
        }
        let windowFrames = max(1, Int((rate * 0.01).rounded()))
        let elapsed = started.duration(to: .now)
        let elapsedSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        let sampleTime = time.isSampleTimeValid ? time.sampleTime : nil
        let hostTime = time.isHostTimeValid ? time.hostTime : nil
        let hostTimeSeconds = hostTime.map(AVAudioTime.seconds(forHostTime:))
        var callbackWindows: [AcousticMixerTapWindow] = []
        for startFrame in stride(from: 0, to: frames, by: windowFrames) {
            let endFrame = min(frames, startFrame + windowFrames)
            let values = Array(mono[startFrame ..< endFrame])
            let rms = sqrt(values.reduce(0.0) { $0 + Double($1 * $1) } / Double(values.count))
            let peak997 = localPeak(values, around: 997, sampleRate: rate)
            let peak1499 = localPeak(values, around: 1_499, sampleRate: rate)
            let label: Int? = if rms > 0.001
                && max(peak997.energy, peak1499.energy) > 4 * min(peak997.energy, peak1499.energy) {
                peak997.energy >= peak1499.energy ? 997 : 1_499
            } else {
                nil
            }
            let offsetSeconds = Double(startFrame) / rate
            callbackWindows.append(AcousticMixerTapWindow(
                sampleTime: sampleTime.map { $0 + AVAudioFramePosition(startFrame) },
                hostTime: hostTime.map {
                    $0 + AVAudioTime.hostTime(forSeconds: offsetSeconds)
                },
                hostTimeSeconds: hostTimeSeconds.map { $0 + offsetSeconds },
                frameCount: endFrame - startFrame,
                sampleRate: rate,
                rmsDBFS: rms > 0 ? 20 * log10(rms) : -160,
                energy997: peak997.energy,
                energy1499: peak1499.energy,
                localPeak997Hz: peak997.frequency,
                localPeak1499Hz: peak1499.frequency,
                labelHz: label
            ))
        }
        lock.withLock {
            callbackCount += 1
            totalFrames += frames
            if let sampleTime, let previousEndSampleTime,
               sampleTime != previousEndSampleTime {
                discontinuityCount += 1
            }
            if elapsedSeconds > Double(frames) / rate { overrunCount += 1 }
            if firstSampleTime == nil { firstSampleTime = sampleTime }
            if firstHostTime == nil { firstHostTime = hostTime }
            lastSampleTime = sampleTime
            lastHostTime = hostTime
            if let sampleTime { previousEndSampleTime = sampleTime + AVAudioFramePosition(frames) }
            callbacks.append(AcousticMixerTapCallback(
                bufferSampleRate: rate,
                bufferChannelCount: channelsCount,
                bufferFrameLength: frames,
                audioTimeSampleRate: time.isSampleTimeValid ? time.sampleRate : nil,
                sampleTime: sampleTime,
                hostTime: hostTime,
                hostTimeSeconds: hostTimeSeconds
            ))
            windows.append(contentsOf: callbackWindows)
        }
    }

    func finish() { lock.withLock { isFinished = true } }

    func json() -> String {
        let envelope = lock.withLock { snapshot() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func sha256() -> String {
        SHA256.hash(data: Data(json().utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func snapshot() -> AcousticMixerTapEnvelope {
        AcousticMixerTapEnvelope(
            schemaVersion: 1,
            calibrationSessionID: calibrationSessionID,
            preStartBusFormat: AcousticMixerTapFormat(
                sampleRate: preStartBusSampleRate,
                channelCount: preStartBusChannelCount
            ),
            callbacks: callbacks,
            callbackCount: callbackCount,
            totalFrames: totalFrames,
            discontinuityCount: discontinuityCount,
            overrunCount: overrunCount,
            firstSampleTime: firstSampleTime,
            lastSampleTime: lastSampleTime,
            firstHostTime: firstHostTime,
            lastHostTime: lastHostTime,
            finished: isFinished,
            bursts: summarizedBursts()
        )
    }

    private func summarizedBursts() -> [AcousticMixerTapBurst] {
        var result: [AcousticMixerTapBurst] = []
        var run: [AcousticMixerTapWindow] = []
        func appendRun() {
            guard let label = run.first?.labelHz, let first = run.first, let last = run.last else {
                run = []
                return
            }
            let peaks = run.map {
                label == 997 ? Double($0.localPeak997Hz) : Double($0.localPeak1499Hz)
            }.sorted()
            result.append(AcousticMixerTapBurst(
                frequencyHz: label,
                startSampleTime: first.sampleTime,
                endSampleTime: last.sampleTime.map { $0 + AVAudioFramePosition(last.frameCount) },
                startHostTime: first.hostTime,
                endHostTime: last.hostTime,
                startHostTimeSeconds: first.hostTimeSeconds,
                endHostTimeSeconds: last.hostTimeSeconds.map {
                    $0 + Double(last.frameCount) / last.sampleRate
                },
                windowCount: run.count,
                medianLocalPeakHz: peaks[peaks.count / 2],
                meanRMSDBFS: run.map(\.rmsDBFS).reduce(0, +) / Double(run.count)
            ))
            run = []
        }
        for window in windows {
            guard window.labelHz != nil else {
                appendRun()
                continue
            }
            if let active = run.first?.labelHz, active != window.labelHz { appendRun() }
            run.append(window)
        }
        appendRun()
        return result
    }

    private func localPeak(
        _ samples: [Float],
        around target: Int,
        sampleRate: Double
    ) -> (frequency: Int, energy: Double) {
        (-20 ... 20).map { offset -> (Int, Double) in
            let frequency = target + offset
            let coefficient = 2 * cos(2 * .pi * Double(frequency) / sampleRate)
            var previous = 0.0
            var previousPrevious = 0.0
            for sample in samples {
                let current = Double(sample) + coefficient * previous - previousPrevious
                previousPrevious = previous
                previous = current
            }
            let energy = previousPrevious * previousPrevious + previous * previous
                - coefficient * previous * previousPrevious
            return (frequency, energy)
        }.max { $0.1 < $1.1 } ?? (target, 0)
    }
}

nonisolated private struct AcousticMixerTapWindow: Codable {
    let sampleTime: AVAudioFramePosition?
    let hostTime: UInt64?
    let hostTimeSeconds: Double?
    let frameCount: Int
    let sampleRate: Double
    let rmsDBFS: Double
    let energy997: Double
    let energy1499: Double
    let localPeak997Hz: Int
    let localPeak1499Hz: Int
    let labelHz: Int?
}

nonisolated private struct AcousticMixerTapEnvelope: Codable {
    let schemaVersion: Int
    let calibrationSessionID: String
    let preStartBusFormat: AcousticMixerTapFormat
    let callbacks: [AcousticMixerTapCallback]
    let callbackCount: Int
    let totalFrames: Int
    let discontinuityCount: Int
    let overrunCount: Int
    let firstSampleTime: AVAudioFramePosition?
    let lastSampleTime: AVAudioFramePosition?
    let firstHostTime: UInt64?
    let lastHostTime: UInt64?
    let finished: Bool
    let bursts: [AcousticMixerTapBurst]
}

nonisolated private struct AcousticMixerTapBurst: Codable {
    let frequencyHz: Int
    let startSampleTime: AVAudioFramePosition?
    let endSampleTime: AVAudioFramePosition?
    let startHostTime: UInt64?
    let endHostTime: UInt64?
    let startHostTimeSeconds: Double?
    let endHostTimeSeconds: Double?
    let windowCount: Int
    let medianLocalPeakHz: Double
    let meanRMSDBFS: Double
}

nonisolated private struct AcousticMixerTapFormat: Codable {
    let sampleRate: Double
    let channelCount: Int
}

nonisolated private struct AcousticMixerTapCallback: Codable {
    let bufferSampleRate: Double
    let bufferChannelCount: Int
    let bufferFrameLength: Int
    let audioTimeSampleRate: Double?
    let sampleTime: AVAudioFramePosition?
    let hostTime: UInt64?
    let hostTimeSeconds: Double?
}

private struct AcousticSourceBurst: Codable {
    let frequencyHz: Int
    let startFrame: Int
    let endFrame: Int
}

private struct AcousticScheduledBufferEvidence: Codable {
    let sourcePCMHashAlgorithm: String
    let sourcePCMHash: String
    let frameLength: Int
    let formatSampleRate: Double
    let scannedBursts: [AcousticSourceBurst]
}

private struct AcousticRuntimeSample: Codable {
    let wallClock: TimeInterval
    let engineOutputSampleRate: Double
    let mainMixerSampleRate: Double
    let playerSampleTime: AVAudioFramePosition?
    let playerSampleRate: Double?
    let engineRunning: Bool
    let playerPlaying: Bool
}

private struct AcousticRuntimeTimeline: Codable {
    let calibrationSessionID: String
    let samples: [AcousticRuntimeSample]
    let maximumObservedSampleTime: AVAudioFramePosition?
    let expectedFinalSampleTime: AVAudioFramePosition
    let reachedExpectedFinalSampleTime: Bool
}

private enum AcousticToneManifest {
    private struct Phase: Codable {
        let frequencyHz: Int
        let startFrame: Int
        let endFrame: Int
    }

    private struct SourceContract: Codable {
        let schemaVersion = 1
        let generatorID = "com.enchron.acoustic.dual-tone-cycle.v1"
        let sampleRate = 48_000
        let totalFrames = 384_000
        let cycleFrames = 72_000
        let rampFrames = 480
        let phases = [
            Phase(frequencyHz: 997, startFrame: 0, endFrame: 24_000),
            Phase(frequencyHz: 1_499, startFrame: 36_000, endFrame: 60_000),
        ]
        let requestedPlaybackRate = "1.0"
    }

    private struct Runtime: Codable {
        let engineOutputSampleRate: Double
        let mainMixerSampleRate: Double
    }

    private struct Manifest: Codable {
        let sourceContract: SourceContract
        let sourceHashAlgorithm: String
        let sourceHash: String
        let runtime: Runtime
        let scheduledBufferEvidence: AcousticScheduledBufferEvidence?
        let calibrationSessionID: String?
        let nextCaptureChannelSelection: ChannelSelection
    }

    private struct ChannelSelection: Codable {
        let selectedChannel: String
        let selectionEvidencePath: String
        let selectionEvidenceSHA256: String
        let rationale: String
    }

    static func make(
        engineOutputSampleRate: Double,
        mainMixerSampleRate: Double,
        scheduledBufferEvidence: AcousticScheduledBufferEvidence?,
        calibrationSessionID: String?
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let source = SourceContract()
        guard let sourceData = try? encoder.encode(source) else { return "" }
        let sourceHash = SHA256.hash(data: sourceData)
            .map { String(format: "%02x", $0) }
            .joined()
        let manifest = Manifest(
            sourceContract: source,
            sourceHashAlgorithm: "sha256-json-sorted-keys",
            sourceHash: sourceHash,
            runtime: Runtime(
                engineOutputSampleRate: engineOutputSampleRate,
                mainMixerSampleRate: mainMixerSampleRate
            ),
            scheduledBufferEvidence: scheduledBufferEvidence,
            calibrationSessionID: calibrationSessionID,
            nextCaptureChannelSelection: ChannelSelection(
                selectedChannel: "channel-1",
                selectionEvidencePath: "/private/tmp/enchron-validation-evidence/visionpro-acoustic-measurement-contract-engine-control-20260731/measurement-contract-analysis-offline-retry.json",
                selectionEvidenceSHA256: "5805f490e12b84df6f9ce7f5e6131eb85a301570ed9953e93ac9897f3bb6318b",
                rationale: "Prior independent capture measured channel 1 at -34.33 dBFS and channel 2 at -90.86 dBFS."
            )
        )
        guard let data = try? encoder.encode(manifest) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

// This DEBUG-only path isolates the AVSampleBufferAudioRenderer hardware route
// from PlaybackCore's demuxed compressed samples and product playback state.
private struct SampleBufferAcousticCalibrationView: View {
    @State private var status = "ready"
    @State private var rendererSnapshot = "rendererStatus=unknown;rendererError=none"
    @State private var tonePlayer = SampleBufferAcousticCalibrationTonePlayer()

    private var armingDelaySeconds: Double {
        guard let value = ProcessInfo.processInfo.environment[
            "ENCHRON_SAMPLE_BUFFER_ACOUSTIC_ARMING_DELAY_SECONDS"
        ].flatMap(Double.init), value.isFinite, value > 0 else {
            return 0
        }
        return value
    }

    private var manualStartEnabled: Bool {
        ProcessInfo.processInfo.environment[
            "ENCHRON_SAMPLE_BUFFER_ACOUSTIC_MANUAL_START"
        ] == "1"
    }

    private var audioSessionMode: AVAudioSession.Mode {
        ProcessInfo.processInfo.environment[
            "ENCHRON_SAMPLE_BUFFER_ACOUSTIC_SESSION_MODE"
        ] == "default" ? .default : .moviePlayback
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 54))
            Text("Sample Buffer Acoustic Calibration")
                .font(.title)
            Text("997 Hz / 1499 Hz")
                .foregroundStyle(.secondary)
            Text(status.capitalized)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Sample Buffer Acoustic Calibration Status")
                .accessibilityIdentifier("SampleBufferAcousticCalibration-status")
                .accessibilityValue(status)
            Text("Renderer diagnostics")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(
                    "SampleBufferAcousticCalibration-renderer-snapshot"
                )
                .accessibilityValue(rendererSnapshot)
            if manualStartEnabled {
                Button("Start Calibration") {
                    Task { await beginPlayback() }
                }
                .accessibilityIdentifier("SampleBufferAcousticCalibration-start")
                .disabled(status != "ready")
            }
        }
        .padding(48)
        .task {
            rendererSnapshot = tonePlayer.snapshot(audioSessionMode: audioSessionMode)
            guard manualStartEnabled == false else { return }
            if armingDelaySeconds > 0 {
                do {
                    try await Task.sleep(for: .seconds(armingDelaySeconds))
                } catch {
                    return
                }
            }
            await beginPlayback()
        }
    }

    private func beginPlayback() async {
        guard status == "ready" else { return }
        status = "playing"
        do {
            try await tonePlayer.play(audioSessionMode: audioSessionMode)
            rendererSnapshot = tonePlayer.snapshot(audioSessionMode: audioSessionMode)
            status = "finished"
        } catch {
            rendererSnapshot = tonePlayer.snapshot(audioSessionMode: audioSessionMode)
            status = "failed:\(tonePlayer.failureDescription(for: error))"
        }
    }
}

@MainActor
private final class SampleBufferAcousticCalibrationTonePlayer {
    private let duration = 8.0
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()

    func play(audioSessionMode: AVAudioSession.Mode = .moviePlayback) async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: audioSessionMode)
        try session.setActive(true)
        defer {
            synchronizer.rate = 0
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }

        let receiver = synchronizer.sampleBufferReceiver(adding: renderer)
        let sample = try makeToneSampleBuffer()
        let readySample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
            unsafeBuffer: sample
        )
        renderer.volume = 1
        renderer.isMuted = false
        let enqueueResult = receiver.enqueueImmediately(readySample)
        guard case .enqueued = enqueueResult else {
            throw AcousticCalibrationError.rendererRejected(String(describing: enqueueResult))
        }
        synchronizer.setRate(1, time: .zero)
        try await Task.sleep(for: .seconds(duration + 0.25))
        if renderer.status == .failed {
            throw AcousticCalibrationError.rendererFailed(
                renderer.error?.localizedDescription ?? "unknown renderer error"
            )
        }
    }

    func failureDescription(for error: Error) -> String {
        "\(error.localizedDescription); "
            + "rendererError=\(renderer.error?.localizedDescription ?? "none")"
    }

    func snapshot(audioSessionMode: AVAudioSession.Mode) -> String {
        let rendererStatus = switch renderer.status {
        case .unknown: "unknown"
        case .rendering: "rendering"
        case .failed: "failed"
        @unknown default: "unrecognized"
        }
        return [
            "rendererStatus=\(rendererStatus)",
            "rendererError=\(renderer.error?.localizedDescription ?? "none")",
            "rendererVolume=\(renderer.volume)",
            "rendererMuted=\(renderer.isMuted)",
            "audioSessionMode=\(audioSessionMode.rawValue)",
        ].joined(separator: ";")
    }

    private func makeToneSampleBuffer() throws -> CMSampleBuffer {
        let sampleRate = 48_000
        let channelCount = 1
        let frameCount = Int(Double(sampleRate) * duration)
        let bytesPerFrame = channelCount * MemoryLayout<Float>.size
        let byteCount = frameCount * bytesPerFrame
        var samples = [Float](repeating: 0, count: frameCount)
        for frame in samples.indices {
            let time = Double(frame) / Double(sampleRate)
            let positionInCycle = time.truncatingRemainder(dividingBy: 1.5)
            let toneFrequency: Double?
            switch positionInCycle {
            case 0 ..< 0.5:
                toneFrequency = 997
            case 0.75 ..< 1.25:
                toneFrequency = 1_499
            default:
                toneFrequency = nil
            }
            guard let toneFrequency else { continue }
            let tonePosition = positionInCycle < 0.5
                ? positionInCycle
                : positionInCycle - 0.75
            let ramp = min(1, tonePosition / 0.01, (0.5 - tonePosition) / 0.01)
            samples[frame] = Float(
                0.18 * ramp * sin(2 * .pi * toneFrequency * time)
            )
        }

        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerFrame),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerFrame),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        var status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDescription else {
            throw AcousticCalibrationError.coreMedia(status)
        }

        var blockBuffer: CMBlockBuffer?
        status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else {
            throw AcousticCalibrationError.coreMedia(status)
        }
        status = samples.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard status == noErr else {
            throw AcousticCalibrationError.coreMedia(status)
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleSize = bytesPerFrame
        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw AcousticCalibrationError.coreMedia(status)
        }
        return sampleBuffer
    }

    private enum AcousticCalibrationError: LocalizedError {
        case coreMedia(OSStatus)
        case rendererRejected(String)
        case rendererFailed(String)

        var errorDescription: String? {
            switch self {
            case .coreMedia(let status):
                "Core Media failed with status \(status)."
            case .rendererRejected(let result):
                "Audio renderer rejected the calibration sample: \(result)."
            case .rendererFailed(let error):
                "Audio renderer failed during calibration: \(error)."
            }
        }
    }
}
#endif
