import AppKit
import CryptoKit
import CoreMedia
import CoreVideo
import Foundation
import Observation
import PlaybackCore
import RealityKit
import SwiftUI

struct CorePlaybackScenarioView: View {
    @State private var scenario: CorePlaybackScenario

    init(backend: PlaybackVerificationModel.Backend) {
        _scenario = State(initialValue: CorePlaybackScenario(backend: backend))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityView { content in
                content.add(scenario.playback.videoEntity)
                scenario.playback.realityViewDidAttach()
            }
            Text(scenario.statusText)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .foregroundStyle(.white)
                .background(.black.opacity(0.7), in: .rect(cornerRadius: 6))
                .padding(12)
        }
        .frame(minWidth: 960, minHeight: 540)
        .background(.black)
        .task { await scenario.run() }
    }
}

@MainActor
@Observable
final class CorePlaybackScenario {
    let playback: PlaybackVerificationModel
    private(set) var statusText: String

    init(backend: PlaybackVerificationModel.Backend) {
        playback = PlaybackVerificationModel(backend: backend)
        statusText = backend == .core
            ? "Preparing Enchron L2 Core scenario"
            : "Preparing Enchron L2 App Adapter scenario"
    }

    private let environment = ProcessInfo.processInfo.environment
    private let clock = ContinuousClock()
    private var outputURL: URL {
        URL(fileURLWithPath: environment["ENCHRON_L2_OUTPUT"] ?? "/tmp/enchron-l2-core.json")
    }

    func run() async {
        var result: [String: Any] = baseResult()
        do {
            let fixture = try await loadFixture()
            result["fixture"] = fixture.evidence
            statusText = "Running playback verification"
            let playbackEvidence = try await run(fixture: fixture)
            result["playback"] = playbackEvidence
            result["completed"] = true
            result["passed"] = playbackEvidence["passed"] as? Bool == true
            result["audibleOutput"] = [
                "status": "humanObservationRequired",
                "reason": "AVSampleBufferAudioRenderer enqueue and shared-timeline facts cannot prove that sound reached a physical listener.",
            ]
        } catch {
            result["completed"] = true
            result["passed"] = false
            result["firstFailure"] = error.localizedDescription
        }
        await playback.close()
        write(result)
        let scenarioName = playback.backend == .core ? "Core" : "App Adapter"
        statusText = (result["passed"] as? Bool == true)
            ? "L2 \(scenarioName) machine checks passed"
            : "L2 \(scenarioName) machine checks failed"
        try? await Task.sleep(for: .milliseconds(250))
        NSApp.terminate(nil)
    }

    private func run(fixture: LoadedFixture) async throws -> [String: Any] {
        trace("phase=open")
        await playback.open(fixture.sourceURL)
        try await waitForVisibleProgress(minimumTime: 0.75)

        let initial = try requireSnapshot("initial playback")
        let initialSession = try requireSession("initial playback")
        let initialMediaSessionID = try require(initial.mediaSession?.mediaSessionID, "media session ID")
        let initialRendererIdentity = try require(initial.rendererState?.rendererIdentity, "renderer identity")
        let initialGraphID = try require(initial.rendererState?.graphID, "renderer graph ID")
        trace("phase=stability")
        let stability = try await observeStability(seconds: fixture.stabilitySeconds)
        trace("phase=controls")
        let controls = try await exerciseControls(mediaSessionID: initialMediaSessionID)
        trace("phase=color")
        let color = try verifyColor(oracle: fixture.registry.oracle)
        let beforeClose = try requireSnapshot("before close")

        await playback.close()
        trace("phase=reopen")
        let cleanup = initialSession.debugSnapshot().cleanupState
        let cleanupFailures = [
            cleanup?.videoProviderCancelled == true ? nil : "videoProviderNotCancelled",
            cleanup?.audioProviderCancelled == true || beforeClose.audioRendererState == nil ? nil : "audioProviderNotCancelled",
            cleanup?.videoRendererFlushed == true ? nil : "videoRendererNotFlushed",
            cleanup?.audioRendererFlushed == true || beforeClose.audioRendererState == nil ? nil : "audioRendererNotFlushed",
            playback.activeSessionForProbe() == nil ? nil : "activeSessionSurvivedClose",
        ].compactMap { $0 }
        guard cleanupFailures.isEmpty else {
            throw ScenarioError.assertions(cleanupFailures)
        }

        await playback.open(fixture.sourceURL)
        try await waitForVisibleProgress(minimumTime: 0.5)
        let reopened = try requireSnapshot("reopen")
        let reopenFailures = [
            reopened.mediaSession?.mediaSessionID != initialMediaSessionID ? nil : "reopenReusedMediaSession",
            reopened.rendererState?.rendererIdentity != initialRendererIdentity ? nil : "reopenReusedRenderer",
            reopened.rendererState?.graphID != initialGraphID ? nil : "reopenReusedRendererGraph",
            reopened.realityKitBinding?.active == true ? nil : "reopenRealityKitBindingMissing",
            reopened.presentationBinding?.entityAttached == true ? nil : "reopenPresentationBindingMissing",
            playback.rendererDisplayedPixelBuffer() != nil ? nil : "reopenDisplayedPixelMissing",
        ].compactMap { $0 }
        guard reopenFailures.isEmpty else { throw ScenarioError.assertions(reopenFailures) }

        let reopenedEvidence = snapshotObject(reopened)
        await playback.close()
        return [
            "passed": true,
            "initial": snapshotObject(initial),
            "stability": stability,
            "controls": controls,
            "color": color,
            "cleanup": snapshotObject(initialSession.debugSnapshot()),
            "reopen": reopenedEvidence,
        ]
    }

    private func waitForVisibleProgress(minimumTime: Double) async throws {
        let deadline = clock.now.advanced(by: .seconds(25))
        while clock.now < deadline {
            if case .failed(let message) = playback.status {
                throw ScenarioError.playback(message)
            }
            if let snapshot = playback.debugSnapshot() {
                if let error = snapshot.rendererState?.rendererError {
                    throw ScenarioError.playback("video renderer: \(error)")
                }
                if let error = snapshot.audioRendererState?.error {
                    throw ScenarioError.playback("audio renderer: \(error)")
                }
                let expectsAudio = !snapshot.availableAudioTracks.isEmpty
                let material = playback.realityKitBindingSnapshot()
                if snapshot.sampleCount >= 12,
                   playback.currentSeconds >= minimumTime,
                   playback.rendererDisplayedPixelBuffer() != nil,
                   snapshot.rendererState?.displayedPixelBuffer == true,
                   snapshot.lastAcceptedRendererInput?.outcome == .accepted,
                   snapshot.realityKitBinding?.active == true,
                   snapshot.presentationBinding?.entityAttached == true,
                   material["consumer"] == "videoPlayerComponent",
                   material["rendererIdentityMatches"] == "true",
                   material["entityActive"] == "true",
                   !expectsAudio || (
                       snapshot.audioTrack != nil &&
                       (snapshot.audioRendererState?.enqueuedSampleBufferCount ?? 0) > 0 &&
                       (snapshot.audioRendererState?.enqueuedAudioFrameCount ?? 0) > 0
                   ) {
                    if playback.diagnostics.timelineConfiguredBeforeFirstEnqueue == true {
                        return
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ScenarioError.playback("timed out waiting for displayed video and audio renderer progress")
    }

    private func observeStability(seconds: Double) async throws -> [String: Any] {
        let before = try requireSnapshot("stability start")
        let beforeTime = playback.currentSeconds
        let deadline = clock.now.advanced(by: .seconds(seconds))
        var displayedObservations = 0
        while clock.now < deadline {
            guard playback.rendererDisplayedPixelBuffer() != nil else {
                throw ScenarioError.assertions(["displayedPixelDroppedDuringStabilityWindow"])
            }
            displayedObservations += 1
            try await Task.sleep(for: .milliseconds(100))
        }
        let after = try requireSnapshot("stability end")
        let expectsAudio = !after.availableAudioTracks.isEmpty
        let failures = [
            playback.currentSeconds > beforeTime + max(0.5, seconds * 0.5) ? nil : "timelineDidNotAdvance",
            after.sampleCount > before.sampleCount ? nil : "videoSamplesDidNotAdvance",
            !expectsAudio || (after.audioRendererState?.enqueuedSampleBufferCount ?? 0) > (before.audioRendererState?.enqueuedSampleBufferCount ?? 0) ? nil : "audioSamplesDidNotAdvance",
            after.rendererState?.rendererError == nil ? nil : "videoRendererError",
            after.audioRendererState?.error == nil ? nil : "audioRendererError",
        ].compactMap { $0 }
        guard failures.isEmpty else { throw ScenarioError.assertions(failures) }
        return [
            "seconds": seconds,
            "timeBefore": beforeTime,
            "timeAfter": playback.currentSeconds,
            "videoSamplesBefore": before.sampleCount,
            "videoSamplesAfter": after.sampleCount,
            "audioBuffersBefore": before.audioRendererState?.enqueuedSampleBufferCount ?? 0,
            "audioBuffersAfter": after.audioRendererState?.enqueuedSampleBufferCount ?? 0,
            "displayedObservations": displayedObservations,
        ]
    }

    private func exerciseControls(mediaSessionID: String) async throws -> [String: Any] {
        let expectsAudio = !playback.availableAudioTracks.isEmpty
        playback.setVolume(0.35)
        try requireNoControlError("volume")
        playback.setMuted(true)
        try requireNoControlError("mute")
        let mutedState = playback.debugSnapshot()?.audioRendererState
        playback.setMuted(false)
        try requireNoControlError("unmute")

        playback.setRate(1.5)
        try requireNoControlError("rate")
        try await waitForRate(1.5)
        playback.pause()
        try requireNoControlError("pause")
        try await waitForStatus(.paused)
        let pausedAt = playback.currentSeconds
        try await Task.sleep(for: .milliseconds(500))
        let pausedDelta = abs(playback.currentSeconds - pausedAt)
        playback.play()
        try requireNoControlError("resume")
        try await waitForStatus(.playing)

        let duration = playback.durationSeconds
        let forwardTarget = boundedTarget(max(4, duration * 0.1), duration: duration)
        let beforeForward = try requireSnapshot("forward seek")
        await playback.seek(to: forwardTarget)
        try requireNoControlError("forward seek")
        let afterForward = try await waitForSeek(target: forwardTarget, afterEpoch: beforeForward.streamEpoch)

        let backwardTarget = boundedTarget(max(1, forwardTarget - 3), duration: duration)
        let beforeBackward = try requireSnapshot("backward seek")
        await playback.seek(to: backwardTarget)
        try requireNoControlError("backward seek")
        let afterBackward = try await waitForSeek(target: backwardTarget, afterEpoch: beforeBackward.streamEpoch)

        let rapidTargets = [
            boundedTarget(max(2, duration * 0.05), duration: duration),
            boundedTarget(max(5, duration * 0.15), duration: duration),
            boundedTarget(max(8, duration * 0.25), duration: duration),
        ]
        let rapidEpoch = try requireSnapshot("continuous seek").streamEpoch
        trace("controls phase=continuousSeek targets=\(rapidTargets)")
        var tasks = [Task<Void, Never>]()
        for target in rapidTargets {
            tasks.append(Task { @MainActor [playback] in await playback.seek(to: target) })
            try await Task.sleep(for: .milliseconds(20))
        }
        for task in tasks { await task.value }
        trace("controls phase=continuousSeek completed status=\(playback.status.label) error=\(playback.controlError ?? "none")")
        try requireNoControlError("continuous seek")
        let afterRapid = try await waitForSeek(target: rapidTargets.last!, afterEpoch: rapidEpoch)

        var audioSwitch: [String: Any] = ["availability": "singleTrack"]
        if playback.availableAudioTracks.count > 1 {
            let target = playback.availableAudioTracks[1]
            let beforeCount = afterRapid.audioRendererState?.enqueuedSampleBufferCount ?? 0
            await playback.selectAudioTrack(streamIndex: target.streamIndex)
            try requireNoControlError("audio track switch")
            let switched = try await waitForAudioTrack(target.streamIndex, after: beforeCount)
            audioSwitch = [
                "availability": "verified",
                "targetStreamIndex": target.streamIndex,
                "selectedStreamIndex": switched.audioTrack?.rawStreamIndex ?? -1,
                "audioBuffersBefore": beforeCount,
                "audioBuffersAfter": switched.audioRendererState?.enqueuedSampleBufferCount ?? 0,
            ]
        }

        playback.setRate(1)
        playback.setVolume(1)
        try requireNoControlError("restore controls")
        try await waitForRate(1)
        let final = try requireSnapshot("controls final")
        let failures = [
            final.mediaSession?.mediaSessionID == mediaSessionID ? nil : "controlsChangedMediaSession",
            !expectsAudio || mutedState?.volume == 0.35 ? nil : "volumeNotApplied",
            !expectsAudio || mutedState?.muted == true ? nil : "muteNotApplied",
            !expectsAudio || final.audioRendererState?.muted == false ? nil : "muteNotRestored",
            pausedDelta < 0.12 ? nil : "pauseDidNotHoldTimeline",
            afterForward.lastVideoSample?.presentationTimeSeconds ?? -.infinity >= forwardTarget ? nil : "forwardSeekVideoPTSBeforeTarget",
            afterBackward.lastVideoSample?.presentationTimeSeconds ?? -.infinity >= backwardTarget ? nil : "backwardSeekVideoPTSBeforeTarget",
            afterRapid.lastVideoSample?.presentationTimeSeconds ?? -.infinity >= rapidTargets.last! ? nil : "continuousSeekDidNotLandOnFinalTarget",
        ].compactMap { $0 }
        guard failures.isEmpty else { throw ScenarioError.assertions(failures) }
        return [
            "mediaSessionPreserved": true,
            "volumeApplied": expectsAudio,
            "muteAppliedAndRestored": expectsAudio,
            "rateAppliedAndRestored": true,
            "pauseHeldTimeline": true,
            "pausedDelta": pausedDelta,
            "forwardSeekTarget": forwardTarget,
            "forwardSeekEpoch": afterForward.streamEpoch,
            "backwardSeekTarget": backwardTarget,
            "backwardSeekEpoch": afterBackward.streamEpoch,
            "continuousSeekTargets": rapidTargets,
            "continuousSeekFinalEpoch": afterRapid.streamEpoch,
            "audioSwitch": audioSwitch,
        ]
    }

    private func waitForSeek(target: Double, afterEpoch: UInt64) async throws -> PlaybackDebugSnapshotV1 {
        let deadline = clock.now.advanced(by: .seconds(12))
        while clock.now < deadline {
            guard let snapshot = playback.debugSnapshot() else {
                try await Task.sleep(for: .milliseconds(50))
                continue
            }
            let expectsAudio = !snapshot.availableAudioTracks.isEmpty
            let videoReady = snapshot.streamEpoch > afterEpoch
                && snapshot.lastVideoSample?.streamEpoch == snapshot.streamEpoch
                && (snapshot.lastVideoSample?.presentationTimeSeconds ?? -.infinity) >= target
                && snapshot.lastAcceptedRendererInput?.streamEpoch == snapshot.streamEpoch
                && snapshot.lastAcceptedRendererInput?.outcome == .accepted
            let audioReady = !expectsAudio || (
                snapshot.audioRendererState?.streamEpoch == snapshot.streamEpoch &&
                snapshot.lastAudioSample?.streamEpoch == snapshot.streamEpoch &&
                (snapshot.lastAudioSample?.presentationTimeSeconds ?? -.infinity) >= target
            )
            if videoReady,
               audioReady,
               playback.currentSeconds >= target,
               playback.rendererDisplayedPixelBuffer() != nil {
                return snapshot
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ScenarioError.assertions(["seekDidNotRestoreAt\(target)"])
    }

    private func waitForAudioTrack(_ streamIndex: Int, after count: UInt64) async throws -> PlaybackDebugSnapshotV1 {
        let deadline = clock.now.advanced(by: .seconds(6))
        while clock.now < deadline {
            guard let snapshot = playback.debugSnapshot() else {
                try await Task.sleep(for: .milliseconds(50))
                continue
            }
            if snapshot.audioTrack?.rawStreamIndex == streamIndex,
               (snapshot.audioRendererState?.enqueuedSampleBufferCount ?? 0) > count {
                return snapshot
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ScenarioError.assertions(["audioTrackSwitchTimedOut"])
    }

    private func verifyColor(oracle: FixtureOracle) throws -> [String: Any] {
        let snapshot = try requireSnapshot("color")
        let signaling = try require(snapshot.lastVideoSample?.formatSignaling, "sample color signaling")
        let pixelBuffer = try require(playback.rendererDisplayedPixelBuffer(), "displayed pixel buffer")
        let displayed = displayedColor(pixelBuffer)
        let actual: [String: String] = [
            "samplePrimaries": signaling.colorPrimaries.value ?? "missing",
            "sampleTransfer": signaling.transferFunction.value ?? "missing",
            "sampleMatrix": signaling.yCbCrMatrix.value ?? "missing",
            "sampleRange": signaling.range.value ?? "missing",
            "displayedPrimaries": displayed["colorPrimaries"] ?? "missing",
            "displayedTransfer": displayed["transferFunction"] ?? "missing",
            "displayedMatrix": displayed["yCbCrMatrix"] ?? "missing",
            "displayedPixelFormat": displayed["pixelFormat"] ?? "missing",
        ]
        let expectations: [(String, [String])] = [
            ("samplePrimaries", oracle.sampleColorPrimaries),
            ("sampleTransfer", oracle.sampleTransferFunction),
            ("sampleMatrix", oracle.sampleYCbCrMatrix),
            ("sampleRange", oracle.sampleRange),
            ("displayedPrimaries", oracle.displayedColorPrimaries),
            ("displayedTransfer", oracle.displayedTransferFunction),
            ("displayedMatrix", oracle.displayedYCbCrMatrix),
            ("displayedPixelFormat", oracle.displayedPixelFormats),
        ]
        let failures = expectations.compactMap { key, accepted -> String? in
            accepted.contains(where: { normalized(actual[key] ?? "").contains(normalized($0)) })
                ? nil : "\(key)=\(actual[key] ?? "missing")"
        }
        guard failures.isEmpty else { throw ScenarioError.assertions(failures) }
        return ["passed": true, "actual": actual, "oracle": oracle.dictionary]
    }

    private func displayedColor(_ buffer: CVPixelBuffer) -> [String: String] {
        [
            "colorPrimaries": attachment(buffer, key: kCVImageBufferColorPrimariesKey),
            "transferFunction": attachment(buffer, key: kCVImageBufferTransferFunctionKey),
            "yCbCrMatrix": attachment(buffer, key: kCVImageBufferYCbCrMatrixKey),
            "pixelFormat": fourCC(CVPixelBufferGetPixelFormatType(buffer)),
        ]
    }

    private func currentDisplayedColor() -> [String: String] {
        guard let buffer = playback.rendererDisplayedPixelBuffer() else {
            return ["availability": "missing"]
        }
        return displayedColor(buffer)
    }

    private func attachment(_ buffer: CVPixelBuffer, key: CFString) -> String {
        guard let value = CVBufferCopyAttachment(buffer, key, nil) else { return "missing" }
        return String(describing: value)
    }

    private func loadFixture() async throws -> LoadedFixture {
        guard let sourcePath = environment["ENCHRON_L2_SOURCE"],
              let fixtureID = environment["ENCHRON_L2_FIXTURE_ID"],
              let registryPath = environment["ENCHRON_L2_FIXTURE_REGISTRY"] else {
            throw ScenarioError.configuration("ENCHRON_L2_SOURCE, ENCHRON_L2_FIXTURE_ID and ENCHRON_L2_FIXTURE_REGISTRY are required")
        }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let registry = try JSONDecoder().decode(
            FixtureRegistry.self,
            from: Data(contentsOf: URL(fileURLWithPath: registryPath))
        )
        guard registry.schemaVersion == 1 else {
            throw ScenarioError.configuration("unsupported fixture registry schema \(registry.schemaVersion)")
        }
        guard let fixture = registry.fixtures.first(where: { $0.id == fixtureID }) else {
            throw ScenarioError.configuration("fixture ID \(fixtureID) is not registered")
        }
        let hash = try await Task.detached { try Self.sha256(sourceURL) }.value
        guard hash.caseInsensitiveCompare(fixture.sha256) == .orderedSame else {
            throw ScenarioError.configuration("fixture hash mismatch: expected \(fixture.sha256), got \(hash)")
        }
        return LoadedFixture(
            sourceURL: sourceURL,
            registry: fixture,
            actualSHA256: hash,
            stabilitySeconds: environment["ENCHRON_L2_STABILITY_SECONDS"].flatMap(Double.init) ?? 3
        )
    }

    nonisolated private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func waitForRate(_ expected: Float) async throws {
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            if playback.debugSnapshot()?.rendererState?.rate == expected { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw ScenarioError.assertions(["rendererRateDidNotBecome\(expected)"])
    }

    private func waitForStatus(_ expected: PlaybackStatus) async throws {
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            if playback.status == expected { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw ScenarioError.assertions(["statusDidNotBecome\(expected.label)"])
    }

    private func requireNoControlError(_ operation: String) throws {
        if let error = playback.controlError {
            throw ScenarioError.assertions(["\(operation): \(error)"])
        }
    }

    private func requireSnapshot(_ phase: String) throws -> PlaybackDebugSnapshotV1 {
        guard let snapshot = playback.debugSnapshot() else {
            throw ScenarioError.assertions(["missingSnapshotAt\(phase)"])
        }
        return snapshot
    }

    private func requireSession(_ phase: String) throws -> SampleBufferPlaybackSession {
        guard let session = playback.activeSessionForProbe() else {
            throw ScenarioError.assertions(["missingSessionAt\(phase)"])
        }
        return session
    }

    private func require<T>(_ value: T?, _ label: String) throws -> T {
        guard let value else { throw ScenarioError.assertions(["missing \(label)"]) }
        return value
    }

    private func boundedTarget(_ value: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 1 else { return max(0, value) }
        return min(max(0, value), duration - 0.75)
    }

    private func normalized(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private func fourCC(_ value: OSType) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff),
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(value)
    }

    private func snapshotObject(_ snapshot: PlaybackDebugSnapshotV1) -> Any {
        guard let data = try? JSONEncoder().encode(snapshot),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return ["encoding": "failed"]
        }
        return object
    }

    private func baseResult() -> [String: Any] {
        [
            "schemaVersion": 1,
            "scope": playback.backend == .core
                ? "Enchron macOS L2 Core machine scenario"
                : "Enchron macOS L2 App Adapter machine scenario",
            "runID": environment["ENCHRON_L2_RUN_ID"] ?? UUID().uuidString,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "playbackCoreRevision": environment["ENCHRON_PLAYBACKCORE_REVISION"] ?? "unknown",
            "enchronRevision": environment["ENCHRON_REVISION"] ?? "unknown",
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "completed": false,
            "passed": false,
        ]
    }

    private func write(_ result: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: outputURL, options: .atomic)
            fputs("[ENCHRON-L2] \(outputURL.path)\n", stderr)
        } catch {
            fputs("[ENCHRON-L2] write failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private func trace(_ message: String) {
        fputs("[ENCHRON-L2] \(message)\n", stderr)
    }
}

private struct FixtureRegistry: Decodable {
    let schemaVersion: Int
    let fixtures: [RegisteredFixture]
}

private struct RegisteredFixture: Decodable {
    let id: String
    let sha256: String
    let license: String
    let acceptanceEligibility: String
    let container: String
    let videoCodec: String
    let audio: String
    let durationSeconds: Double
    let oracle: FixtureOracle
}

private struct FixtureOracle: Decodable {
    let sampleColorPrimaries: [String]
    let sampleTransferFunction: [String]
    let sampleYCbCrMatrix: [String]
    let sampleRange: [String]
    let displayedColorPrimaries: [String]
    let displayedTransferFunction: [String]
    let displayedYCbCrMatrix: [String]
    let displayedPixelFormats: [String]

    private enum CodingKeys: String, CodingKey {
        case sampleColorPrimaries
        case sampleTransferFunction
        case sampleYCbCrMatrix
        case sampleRange
        case displayedColorPrimaries
        case displayedTransferFunction
        case displayedYCbCrMatrix
        case displayedPixelFormats
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sampleColorPrimaries = try values.decodeIfPresent([String].self, forKey: .sampleColorPrimaries) ?? []
        sampleTransferFunction = try values.decodeIfPresent([String].self, forKey: .sampleTransferFunction) ?? []
        sampleYCbCrMatrix = try values.decodeIfPresent([String].self, forKey: .sampleYCbCrMatrix) ?? []
        sampleRange = try values.decodeIfPresent([String].self, forKey: .sampleRange) ?? []
        displayedColorPrimaries = try values.decodeIfPresent([String].self, forKey: .displayedColorPrimaries) ?? []
        displayedTransferFunction = try values.decodeIfPresent([String].self, forKey: .displayedTransferFunction) ?? []
        displayedYCbCrMatrix = try values.decodeIfPresent([String].self, forKey: .displayedYCbCrMatrix) ?? []
        displayedPixelFormats = try values.decodeIfPresent([String].self, forKey: .displayedPixelFormats) ?? []
    }

    var dictionary: [String: Any] {
        [
            "sampleColorPrimaries": sampleColorPrimaries,
            "sampleTransferFunction": sampleTransferFunction,
            "sampleYCbCrMatrix": sampleYCbCrMatrix,
            "sampleRange": sampleRange,
            "displayedColorPrimaries": displayedColorPrimaries,
            "displayedTransferFunction": displayedTransferFunction,
            "displayedYCbCrMatrix": displayedYCbCrMatrix,
            "displayedPixelFormats": displayedPixelFormats,
        ]
    }
}

private struct LoadedFixture {
    let sourceURL: URL
    let registry: RegisteredFixture
    let actualSHA256: String
    let stabilitySeconds: Double

    var evidence: [String: Any] {
        [
            "id": registry.id,
            "sha256": actualSHA256,
            "license": registry.license,
            "acceptanceEligibility": registry.acceptanceEligibility,
            "container": registry.container,
            "videoCodec": registry.videoCodec,
            "audio": registry.audio,
            "durationSeconds": registry.durationSeconds,
            "stabilitySeconds": stabilitySeconds,
        ]
    }
}

private enum ScenarioError: LocalizedError {
    case configuration(String)
    case playback(String)
    case assertions([String])

    var errorDescription: String? {
        switch self {
        case .configuration(let message): "Scenario configuration: \(message)"
        case .playback(let message): "Playback: \(message)"
        case .assertions(let failures): "Assertions failed: \(failures.joined(separator: ", "))"
        }
    }
}
