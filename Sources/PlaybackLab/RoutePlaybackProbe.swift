import AppKit
import CoreMedia
import Foundation
import Observation
import PlaybackCore
import RealityKit
import SwiftUI

struct RoutePlaybackProbeView: View {
    @State private var probe = RoutePlaybackProbeModel()

    var body: some View {
        ZStack {
            RealityView { content in
                content.add(probe.playback.videoEntity)
                probe.playback.realityViewDidAttachEntity()
            }
            Text(probe.currentRoute?.label ?? "Preparing route probe")
                .padding(8)
                .background(.black.opacity(0.65), in: .rect(cornerRadius: 4))
                .foregroundStyle(.white)
        }
        .frame(width: 960, height: 540)
        .background(.black)
        .task {
            await probe.run()
        }
    }
}

private struct ActivePlaybackIdentity {
    var mediaSessionID: String
    var rendererIdentity: String
    var graphID: String
    var sourceSummary: String
    var route: PlaybackRoute
    var flushCount: UInt64
}

private struct ProbeFixtureExpectationFile: Decodable {
    var schemaVersion: Int
    var fixtures: [ProbeFixtureExpectation]
}

private struct ProbeFixtureExpectation: Decodable {
    var sourcePathSuffix: String
    var fileSizeBytes: Int
    var coverageSeek: ProbeCoverageSeekExpectation
}

private struct ProbeCoverageSeekExpectation: Decodable {
    var availability: String
    var reason: String
    var declaredDurationSeconds: Double
    var availablePayloadEvidence: ProbeAvailablePayloadEvidence
}

private struct ProbeAvailablePayloadEvidence: Decodable {
    var probe: String
    var integrity: String
    var maxVideoPTSSeconds: Double
}

@MainActor
@Observable
private final class RoutePlaybackProbeModel {
    let playback = PlaybackModel()
    private(set) var currentRoute: PlaybackRoute?

    private let runID = ProcessInfo.processInfo.environment["PLAYBACKLAB_PROBE_RUN_ID"]
        ?? UUID().uuidString
    private let outputURL: URL = {
        let path = ProcessInfo.processInfo.environment["PLAYBACKLAB_PROBE_OUTPUT"]
            ?? "/tmp/playbacklab-route-probe.json"
        return URL(fileURLWithPath: path)
    }()
    private var sourceURLs: [URL] {
        guard let input = ProcessInfo.processInfo.environment["PLAYBACKLAB_PROBE_MANIFEST"] else {
            return [sourceURL]
        }
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: input, isDirectory: &isDirectory),
           isDirectory.boolValue {
            let root = URL(fileURLWithPath: input, isDirectory: true)
            let supportedExtensions = Set([
                "3g2", "3gp", "avi", "flv", "ivf", "m2ts", "mkv", "mov",
                "mp4", "mpeg", "mpg", "mts", "mxf", "ogv", "ts", "vob", "webm",
            ])
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return enumerator.compactMap { item -> URL? in
                guard let url = item as? URL,
                      supportedExtensions.contains(url.pathExtension.lowercased()),
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    return nil
                }
                return url
            }.sorted { $0.path < $1.path }
        }
        if FileManager.default.fileExists(atPath: input, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            let url = URL(fileURLWithPath: input)
            let supportedExtensions = Set([
                "3g2", "3gp", "avi", "flv", "ivf", "m2ts", "mkv", "mov",
                "mp4", "mpeg", "mpg", "mts", "mxf", "ogv", "ts", "vob", "webm",
            ])
            if supportedExtensions.contains(url.pathExtension.lowercased()) {
                return [url]
            }
        }
        guard let contents = try? String(contentsOfFile: input, encoding: .utf8) else {
            return []
        }
        return contents.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { URL(fileURLWithPath: $0) }
    }
    private var isCoverageProbe: Bool {
        ProcessInfo.processInfo.environment["PLAYBACKLAB_PROBE_MANIFEST"] != nil
    }
    private var exercisesControls: Bool {
        !isCoverageProbe || ProcessInfo.processInfo.environment[
            "PLAYBACKLAB_PROBE_EXERCISE_CONTROLS"
        ] == "1"
    }
    private var exercisesLifecycleControls: Bool {
        ProcessInfo.processInfo.environment["PLAYBACKLAB_PROBE_EXERCISE_CONTROLS"] == "1"
    }
    private var sourceURL: URL {
        ProcessInfo.processInfo.environment["PLAYBACKLAB_PROBE_SOURCE"]
            .map { URL(fileURLWithPath: $0) } ?? PlaybackModel.defaultVideoURL
    }
    private var startTime: CMTime {
        let seconds = ProcessInfo.processInfo.environment["PLAYBACKLAB_PROBE_START"]
            .flatMap(Double.init) ?? PlaybackModel.knownOverexposureTime.seconds
        return CMTime(seconds: seconds, preferredTimescale: 60_000)
    }
    private var routes: [PlaybackRoute] {
        guard let raw = ProcessInfo.processInfo.environment["PLAYBACKLAB_PROBE_ROUTE"],
              let route = PlaybackRoute(rawValue: raw) else { return PlaybackRoute.allCases }
        return [route]
    }

    func run() async {
        var results = [[String: Any]]()
        let sources = sourceURLs
        let resultCountPerRoute = exercisesLifecycleControls ? 5 : 1
        let expectedCount = max(1, sources.count * routes.count * resultCountPerRoute)
        let fixtureExpectations: [ProbeFixtureExpectation]
        do {
            fixtureExpectations = try loadFixtureExpectations()
        } catch {
            results.append([
                "phase": "fixtureExpectations",
                "route": routes.first?.rawValue ?? "none",
                "source": ProcessInfo.processInfo.environment[
                    "PLAYBACKLAB_PROBE_FIXTURE_EXPECTATIONS"
                ].map { URL(fileURLWithPath: $0).lastPathComponent } ?? "none",
                "result": "failed",
                "error": error.localizedDescription,
            ])
            writeResults(results, completed: true, expectedCount: expectedCount)
            NSApp.terminate(nil)
            return
        }
        if sources.isEmpty {
            results.append([
                "route": routes.first?.rawValue ?? "none",
                "source": ProcessInfo.processInfo.environment["PLAYBACKLAB_PROBE_MANIFEST"]
                    .map { URL(fileURLWithPath: $0).lastPathComponent } ?? "none",
                "result": "failed",
                "error": "The coverage input did not contain any readable media files.",
            ])
            writeResults(results, completed: true, expectedCount: expectedCount)
            NSApp.terminate(nil)
            return
        }
        for source in sources {
            for route in routes {
                var phase = exercisesLifecycleControls ? "initialPlaybackControls" : "playback"
                var phaseRoute = route
                currentRoute = route
                await playback.open(source, route: route, startTime: isCoverageProbe ? .zero : startTime)
                do {
                    try await waitForVisibleProgress(route: route, minimumTime: isCoverageProbe ? 0.1 : startTime.seconds + 0.25)
                    let mediaSessionID = playback.debugSnapshot()?.mediaSession?.mediaSessionID
                    var audioSwitch: [String: Any] = ["availability": "singleTrack"]
                    if exercisesControls, playback.audioTracks.count > 1 {
                        let target = playback.audioTracks[1]
                        let before = playback.debugSnapshot()?.audioRendererState?.enqueuedSampleBufferCount ?? 0
                        playback.selectAudioTrack(target.streamIndex)
                        try requireSuccessfulControl("audioTrack")
                        try await waitForAudioSwitch(streamIndex: target.streamIndex, after: before)
                        guard playback.debugSnapshot()?.mediaSession?.mediaSessionID == mediaSessionID else {
                            throw RoutePlaybackProbeError.controlAssertionFailed(["audioSwitchChangedMediaSession"])
                        }
                        audioSwitch = [
                            "targetStreamIndex": target.streamIndex,
                            "selectedStreamIndex": playback.debugSnapshot()?.audioTrack?.rawStreamIndex ?? -1,
                            "mediaSessionPreserved": playback.debugSnapshot()?.mediaSession?.mediaSessionID == mediaSessionID,
                            "sampleBuffersBefore": before,
                            "sampleBuffersAfter": playback.debugSnapshot()?.audioRendererState?.enqueuedSampleBufferCount ?? 0,
                        ]
                    }
                    let controls: [String: Any] = exercisesControls
                        ? try await exerciseControls(mediaSessionID: mediaSessionID)
                        : ["availability": "notRunInCoverageProbe"]
                    let coverageSeek: [String: Any] = isCoverageProbe && !exercisesControls
                        ? try await exerciseCoverageSeek(
                            source: source,
                            fixtureExpectations: fixtureExpectations
                        )
                        : ["availability": "notRun"]
                    if exercisesControls {
                        try await waitForVisibleProgress(route: route, minimumTime: 4.1)
                    }
                    let diagnostics = playback.diagnostics
                    let snapshot = playback.debugSnapshot()
                    results.append([
                    "phase": phase,
                    "route": route.rawValue,
                    "source": source.lastPathComponent,
                    "result": "passed",
                    "currentSeconds": diagnostics.currentSeconds,
                    "enqueuedSamples": diagnostics.enqueuedSampleCount,
                    "timelineConfiguredBeforeFirstEnqueue": diagnostics.timelineConfiguredBeforeFirstEnqueue as Any,
                    "rendererStatus": diagnostics.rendererStatus,
                    "rendererError": diagnostics.rendererError,
                    "sourceFormat": diagnostics.sourcePixelFormat,
                    "destinationFormat": diagnostics.destinationPixelFormat,
                    "displayedPixelBuffer": playback.rendererDisplayedPixelBuffer() != nil,
                    "providerOpen": providerSummary(snapshot?.providerOpen),
                    "firstLaneFacts": sampleSummary(snapshot?.lastVideoSample),
                    "rendererInput": rendererInputSummary(snapshot?.lastAcceptedRendererInput),
                    "audioTrack": audioTrackSummary(snapshot?.audioTrack),
                    "audioRenderer": audioRendererSummary(snapshot?.audioRendererState),
                    "availableAudioTracks": playback.audioTracks.map { track in
                        ["streamIndex": track.streamIndex, "codec": track.codecName,
                         "channels": track.channelCount, "language": track.language ?? ""] as [String: Any]
                    },
                    "audioSwitch": audioSwitch,
                    "controls": controls,
                    "coverageSeek": coverageSeek,
                    "realityKitBinding": snapshot?.realityKitBinding?.active == true,
                    "presentationBinding": snapshot?.presentationBinding?.entityAttached == true
                    ])
                    writeResults(results, completed: false, expectedCount: expectedCount)

                    if exercisesLifecycleControls {
                        let initialIdentity = try activePlaybackIdentity()
                        let initialSession = try activeSessionForProbe()

                        phase = "closeBarrier"
                        let closeFacts = try await closeAndVerify(
                            session: initialSession,
                            identity: initialIdentity
                        )
                        results.append(phaseResult(
                            phase: phase,
                            route: route,
                            source: source,
                            facts: closeFacts
                        ))
                        writeResults(results, completed: false, expectedCount: expectedCount)

                        phase = "reopen"
                        let reopened = try await reopenAndVerify(
                            previous: initialIdentity,
                            route: route,
                            source: source
                        )
                        results.append(phaseResult(
                            phase: phase,
                            route: route,
                            source: source,
                            facts: reopened.facts
                        ))
                        writeResults(results, completed: false, expectedCount: expectedCount)

                        phase = "coldRouteSwitch"
                        let targetRoute = oppositeRoute(to: route)
                        phaseRoute = targetRoute
                        currentRoute = targetRoute
                        let switched = try await switchRouteAndVerify(
                            from: reopened.identity,
                            session: reopened.session,
                            to: targetRoute,
                            source: source
                        )
                        results.append(phaseResult(
                            phase: phase,
                            route: targetRoute,
                            source: source,
                            facts: switched.facts
                        ))
                        writeResults(results, completed: false, expectedCount: expectedCount)

                        phase = "finalClose"
                        let finalCloseFacts = try await closeAndVerify(
                            session: switched.session,
                            identity: switched.identity
                        )
                        results.append(phaseResult(
                            phase: phase,
                            route: targetRoute,
                            source: source,
                            facts: finalCloseFacts
                        ))
                        writeResults(results, completed: false, expectedCount: expectedCount)
                    }
                } catch {
                    results.append([
                    "phase": phase,
                    "route": phaseRoute.rawValue,
                    "source": source.lastPathComponent,
                    "result": "failed",
                    "error": error.localizedDescription,
                    "status": playback.status.label,
                    "snapshot": playback.diagnostics.snapshotText
                    ])
                    writeResults(results, completed: false, expectedCount: expectedCount)
                }
                if playback.activeSessionForProbe() != nil {
                    await playback.closeAndWait()
                }
            }
        }

        await playback.closeAndWait()
        writeResults(results, completed: true, expectedCount: expectedCount)
        NSApp.terminate(nil)
    }

    private func loadFixtureExpectations() throws -> [ProbeFixtureExpectation] {
        guard let path = ProcessInfo.processInfo.environment[
            "PLAYBACKLAB_PROBE_FIXTURE_EXPECTATIONS"
        ] else { return [] }
        let file = try JSONDecoder().decode(
            ProbeFixtureExpectationFile.self,
            from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        guard file.schemaVersion == 1 else {
            throw RoutePlaybackProbeError.controlAssertionFailed([
                "unsupportedFixtureExpectationSchema:\(file.schemaVersion)",
            ])
        }
        return file.fixtures
    }

    private func writeResults(
        _ results: [[String: Any]],
        completed: Bool,
        expectedCount: Int
    ) {
        do {
            let failedCount = results.filter { ($0["result"] as? String) != "passed" }.count
            let data = try JSONSerialization.data(
                withJSONObject: [
                    "runID": runID,
                    "processID": ProcessInfo.processInfo.processIdentifier,
                    "completed": completed,
                    "passed": completed && results.count == expectedCount && failedCount == 0,
                    "completedCount": results.count,
                    "expectedCount": expectedCount,
                    "passedCount": results.count - failedCount,
                    "failedCount": failedCount,
                    "routes": results,
                ],
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: outputURL, options: .atomic)
            if completed {
                fputs("[ROUTE-PROBE] \(outputURL.path)\n", stderr)
            }
        } catch {
            fputs("[ROUTE-PROBE] write failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private func providerSummary(_ snapshot: ProviderOpenSnapshot?) -> [String: Any] {
        guard let snapshot else { return ["availability": "missing"] }
        return [
            "schemaVersion": snapshot.schemaVersion,
            "providerKind": snapshot.providerKind,
            "sourceSummary": snapshot.sourceSummary,
            "containerFormat": snapshot.containerFormat,
            "durationSeconds": snapshot.durationSeconds,
            "codecName": snapshot.codecName,
            "codecTag": snapshot.codecTag,
            "seekability": stringFact(snapshot.seekability),
            "codecConfiguration": stringFact(snapshot.codecConfigurationSummary),
            "formatSignaling": signalingSummary(snapshot.formatSignaling),
        ]
    }

    private func sampleSummary(_ sample: VideoSampleRecord?) -> [String: Any] {
        guard let sample else { return ["availability": "missing"] }
        return [
            "inputKind": sample.inputKind.rawValue,
            "streamEpoch": sample.streamEpoch,
            "formatRevision": sample.formatRevision,
            "mediaSubtype": sample.mediaSubtype,
            "sampleCount": sample.sampleCount,
            "syncSummary": sample.syncSummary,
            "dependencySummary": sample.dependencySummary,
            "payloadOwnershipState": sample.payloadOwnershipState,
            "formatSignaling": signalingSummary(sample.formatSignaling),
        ]
    }

    private func rendererInputSummary(_ input: RendererInputRecord?) -> [String: Any] {
        guard let input else { return ["availability": "missing"] }
        return [
            "inputKind": input.inputKind.rawValue,
            "streamEpoch": input.streamEpoch,
            "formatRevision": input.formatRevision,
            "timelineConfiguredBeforeFirstEnqueue": input.timelineConfiguredBeforeFirstEnqueue,
            "outcome": input.outcome.rawValue,
        ]
    }

    private func audioTrackSummary(_ track: AudioTrackRecord?) -> [String: Any] {
        guard let track else { return ["availability": "none"] }
        return [
            "streamIndex": track.rawStreamIndex,
            "codecName": track.codecName,
            "sampleRate": track.sampleRate,
            "channelCount": track.channelCount,
            "selected": track.selected,
        ]
    }

    private func audioRendererSummary(_ state: AudioRendererStateRecord?) -> [String: Any] {
        guard let state else { return ["availability": "none"] }
        return [
            "streamEpoch": state.streamEpoch,
            "enqueuedSampleBufferCount": state.enqueuedSampleBufferCount,
            "enqueuedAudioFrameCount": state.enqueuedAudioFrameCount,
            "volume": state.volume,
            "muted": state.muted,
            "error": state.error.map { $0 as Any } ?? NSNull(),
        ]
    }

    private func signalingSummary(_ value: VideoFormatSignalingSummary) -> [String: Any] {
        [
            "provenance": value.provenance,
            "colorPrimaries": stringFact(value.colorPrimaries),
            "transferFunction": stringFact(value.transferFunction),
            "yCbCrMatrix": stringFact(value.yCbCrMatrix),
            "range": stringFact(value.range),
            "projectionKind": stringFact(value.projectionKind),
            "viewPackingKind": stringFact(value.viewPackingKind),
            "masteringDisplayMetadata": booleanFact(value.masteringDisplayMetadata),
            "contentLightLevelMetadata": booleanFact(value.contentLightLevelMetadata),
            "hvcC": booleanFact(value.hvcC),
            "dvcC": booleanFact(value.dvcC),
            "dvvC": booleanFact(value.dvvC),
            "ambientViewingEnvironment": booleanFact(value.ambientViewingEnvironment),
        ]
    }

    private func stringFact(_ fact: ObservedStringFact) -> [String: Any] {
        [
            "availability": fact.availability.rawValue,
            "value": fact.value.map { $0 as Any } ?? NSNull(),
        ]
    }

    private func booleanFact(_ fact: ObservedBooleanFact) -> [String: Any] {
        [
            "availability": fact.availability.rawValue,
            "value": fact.value.map { $0 as Any } ?? NSNull(),
        ]
    }

    private func waitForVisibleProgress(route: PlaybackRoute, minimumTime: Double) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline {
            if case .failed(let message) = playback.status {
                throw RoutePlaybackProbeError.routeFailed(route, message)
            }
            let diagnostics = playback.diagnostics
            let snapshot = playback.debugSnapshot()
            let expectsAudio = !playback.audioTracks.isEmpty
            if diagnostics.rendererError != "none" {
                throw RoutePlaybackProbeError.controlAssertionFailed([
                    "renderer: \(diagnostics.rendererError)",
                ])
            }
            if let rendererError = snapshot?.rendererState?.rendererError {
                throw RoutePlaybackProbeError.controlAssertionFailed([
                    "renderer: \(rendererError)",
                ])
            }
            if let audioError = snapshot?.audioRendererState?.error {
                throw RoutePlaybackProbeError.controlAssertionFailed([
                    "audioRenderer: \(audioError)",
                ])
            }
            let component = playback.realityKitBindingSnapshot()
            if diagnostics.enqueuedSampleCount >= 12,
               diagnostics.currentSeconds >= minimumTime,
               playback.rendererDisplayedPixelBuffer() != nil,
               snapshot?.rendererState?.displayedPixelBuffer == true,
               snapshot?.lastAcceptedRendererInput?.outcome == .accepted,
               snapshot?.realityKitBinding?.active == true,
               snapshot?.presentationBinding?.entityAttached == true,
               component["component"] == "present",
               component["rendererIdentityMatches"] == "true",
               !expectsAudio ||
                   (snapshot?.audioTrack != nil &&
                    (snapshot?.audioRendererState?.enqueuedSampleBufferCount ?? 0) > 0) {
                guard diagnostics.timelineConfiguredBeforeFirstEnqueue == true else {
                    throw RoutePlaybackProbeError.timelineConfiguredAfterFirstEnqueue(route)
                }
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw RoutePlaybackProbeError.timedOut(route)
    }

    private func waitForAudioSwitch(streamIndex: Int, after count: UInt64) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            let snapshot = playback.debugSnapshot()
            if snapshot?.audioTrack?.rawStreamIndex == streamIndex,
               (snapshot?.audioRendererState?.enqueuedSampleBufferCount ?? 0) > count {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw RoutePlaybackProbeError.audioSwitchTimedOut(streamIndex)
    }

    private func exerciseCoverageSeek(
        source: URL,
        fixtureExpectations: [ProbeFixtureExpectation]
    ) async throws -> [String: Any] {
        guard let before = playback.debugSnapshot(),
              let mediaSessionID = before.mediaSession?.mediaSessionID else {
            throw RoutePlaybackProbeError.controlAssertionFailed([
                "coverageSeekMissingInitialSession",
            ])
        }
        let duration = before.providerOpen?.durationSeconds ?? playback.durationSeconds
        if let expectation = matchingFixtureExpectation(
            source: source,
            declaredDurationSeconds: duration,
            expectations: fixtureExpectations
        ) {
            return [
                "availability": expectation.coverageSeek.availability,
                "reason": expectation.coverageSeek.reason,
                "declaredDurationSeconds": duration,
                "sourceFileSizeBytes": expectation.fileSizeBytes,
                "availablePayloadEvidence": [
                    "probe": expectation.coverageSeek.availablePayloadEvidence.probe,
                    "integrity": expectation.coverageSeek.availablePayloadEvidence.integrity,
                    "maxVideoPTSSeconds": expectation.coverageSeek
                        .availablePayloadEvidence.maxVideoPTSSeconds,
                ],
            ]
        }
        guard duration.isFinite, duration > 0 else {
            return ["availability": "skippedUnknownDuration"]
        }
        guard duration > 2 else {
            return [
                "availability": "skippedShortDuration",
                "durationSeconds": duration,
            ]
        }

        let target = min(max(duration * 0.5, 1), duration - 1)
        let videoEpochBefore = before.streamEpoch
        let audioEpochBefore = before.audioRendererState?.streamEpoch ?? 0
        let expectsAudio = !playback.audioTracks.isEmpty
        await playback.seek(to: target)
        try requireSuccessfulControl("coverageSeek")

        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if case .failed(let message) = playback.status {
                throw RoutePlaybackProbeError.routeFailed(
                    currentRoute ?? .ffmpegCompressed,
                    message
                )
            }
            guard let snapshot = playback.debugSnapshot() else {
                try await Task.sleep(for: .milliseconds(50))
                continue
            }
            if let rendererError = snapshot.rendererState?.rendererError {
                throw RoutePlaybackProbeError.controlAssertionFailed([
                    "coverageSeekRenderer: \(rendererError)",
                ])
            }
            if let audioError = snapshot.audioRendererState?.error {
                throw RoutePlaybackProbeError.controlAssertionFailed([
                    "coverageSeekAudioRenderer: \(audioError)",
                ])
            }
            let videoSample = snapshot.lastVideoSample
            let rendererInput = snapshot.lastAcceptedRendererInput
            let audioSample = snapshot.lastAudioSample
            let audioState = snapshot.audioRendererState
            let audioReady = !expectsAudio || (
                (audioState?.streamEpoch ?? 0) > audioEpochBefore &&
                audioSample?.streamEpoch == audioState?.streamEpoch &&
                (audioSample?.presentationTimeSeconds ?? -.infinity) >= target
            )
            let currentTime = playback.activeSessionForProbe()?.currentTime().seconds ?? 0
            let component = playback.realityKitBindingSnapshot()
            if snapshot.mediaSession?.mediaSessionID == mediaSessionID,
               snapshot.streamEpoch > videoEpochBefore,
               videoSample?.streamEpoch == snapshot.streamEpoch,
               (videoSample?.presentationTimeSeconds ?? -.infinity) >= target,
               rendererInput?.streamEpoch == snapshot.streamEpoch,
               rendererInput?.sourceEventID == videoSample?.sourceEventID,
               rendererInput?.outcome == .accepted,
               currentTime >= target + 0.1,
               playback.rendererDisplayedPixelBuffer() != nil,
               snapshot.rendererState?.displayedPixelBuffer == true,
               snapshot.realityKitBinding?.active == true,
               snapshot.presentationBinding?.entityAttached == true,
               component["component"] == "present",
               component["rendererIdentityMatches"] == "true",
               audioReady {
                return [
                    "availability": "verified",
                    "durationSeconds": duration,
                    "targetSeconds": target,
                    "currentSeconds": currentTime,
                    "mediaSessionPreserved": true,
                    "videoEpochBefore": videoEpochBefore,
                    "videoEpochAfter": snapshot.streamEpoch,
                    "videoPTS": videoSample?.presentationTimeSeconds ?? 0,
                    "audioExpected": expectsAudio,
                    "audioEpochBefore": audioEpochBefore,
                    "audioEpochAfter": audioState?.streamEpoch ?? 0,
                    "audioPTS": audioSample.map { $0.presentationTimeSeconds as Any } ?? NSNull(),
                    "displayedAfterSeek": true,
                ]
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw RoutePlaybackProbeError.controlAssertionFailed([
            "coverageSeekDidNotRestoreAt\(target)",
        ])
    }

    private func matchingFixtureExpectation(
        source: URL,
        declaredDurationSeconds: Double,
        expectations: [ProbeFixtureExpectation]
    ) -> ProbeFixtureExpectation? {
        let path = source.standardizedFileURL.path
        let fileSize = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return expectations.first { expectation in
            let suffix = expectation.sourcePathSuffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return expectation.coverageSeek.availability == "notApplicable"
                && (path == suffix || path.hasSuffix("/\(suffix)"))
                && fileSize == expectation.fileSizeBytes
                && abs(declaredDurationSeconds - expectation.coverageSeek.declaredDurationSeconds) < 0.001
        }
    }

    private func exerciseControls(mediaSessionID: String?) async throws -> [String: Any] {
        let expectsAudio = !playback.audioTracks.isEmpty
        playback.setVolume(0.35)
        try requireSuccessfulControl("volume")
        playback.setMuted(true)
        try requireSuccessfulControl("mute")
        let mutedState = playback.debugSnapshot()?.audioRendererState
        playback.setMuted(false)
        try requireSuccessfulControl("unmute")
        playback.setRate(1.5)
        try requireSuccessfulControl("rate")
        try await waitForRendererRate(1.5)
        let rateState = playback.debugSnapshot()?.rendererState
        playback.pause()
        try requireSuccessfulControl("pause")
        try await waitForStatus(.paused)
        let pausedAt = playback.diagnostics.currentSeconds
        try await Task.sleep(for: .milliseconds(300))
        let pausedDelta = abs(playback.diagnostics.currentSeconds - pausedAt)
        playback.play()
        try requireSuccessfulControl("play")
        try await waitForStatus(.playing)
        let seekTarget = 4.0
        await playback.seek(to: seekTarget)
        try requireSuccessfulControl("seek")
        let deadline = ContinuousClock.now + .seconds(8)
        while ContinuousClock.now < deadline {
            let snapshot = playback.debugSnapshot()
            let audioSample = snapshot?.lastAudioSample
            let videoSample = snapshot?.lastVideoSample
            let audioReady = !expectsAudio || (
                audioSample?.streamEpoch == snapshot?.audioRendererState?.streamEpoch &&
                (audioSample?.presentationTimeSeconds ?? -.infinity) >= seekTarget
            )
            if playback.diagnostics.currentSeconds >= seekTarget + 0.2,
               audioReady,
               let videoSample,
               videoSample.presentationTimeSeconds >= seekTarget,
               playback.rendererDisplayedPixelBuffer() != nil {
                let assertions: [(Bool, String)] = [
                    (snapshot?.mediaSession?.mediaSessionID == mediaSessionID, "mediaSessionChanged"),
                    (!expectsAudio || mutedState?.volume == 0.35, "volumeNotApplied"),
                    (!expectsAudio || mutedState?.muted == true, "muteNotApplied"),
                    (!expectsAudio || snapshot?.audioRendererState?.muted == false, "muteNotRestored"),
                    (rateState?.rate == 1.5, "rateNotApplied"),
                    (pausedDelta < 0.1, "pauseDidNotHoldTimeline"),
                ]
                let failures = assertions.compactMap { $0.0 ? nil : $0.1 }
                guard failures.isEmpty else {
                    throw RoutePlaybackProbeError.controlAssertionFailed(failures)
                }
                playback.setRate(1)
                try requireSuccessfulControl("restoreRate")
                try await waitForRendererRate(1)
                var result: [String: Any] = [
                    "mediaSessionPreserved": true,
                    "rateApplied": true,
                    "pauseHeldTimeline": true,
                    "pausedDelta": pausedDelta,
                    "seekTarget": seekTarget,
                    "currentSeconds": playback.diagnostics.currentSeconds,
                    "audioStreamEpoch": snapshot?.audioRendererState?.streamEpoch ?? 0,
                    "videoStreamEpoch": snapshot?.lastVideoSample?.streamEpoch ?? 0,
                    "audioPTS": audioSample.map { $0.presentationTimeSeconds as Any } ?? NSNull(),
                    "videoPTS": videoSample.presentationTimeSeconds,
                    "displayedAfterSeek": true,
                ]
                if expectsAudio {
                    result["volumeApplied"] = true
                    result["muteApplied"] = true
                    result["muteRestored"] = true
                } else {
                    result["audioControls"] = [
                        "availability": "notApplicableNoAudioRenderer",
                    ]
                }
                return result
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw RoutePlaybackProbeError.controlSequenceTimedOut
    }

    private func activePlaybackIdentity() throws -> ActivePlaybackIdentity {
        guard let snapshot = playback.debugSnapshot(),
              let mediaSession = snapshot.mediaSession,
              let rendererState = snapshot.rendererState else {
            throw RoutePlaybackProbeError.controlAssertionFailed([
                "activePlaybackIdentityMissing",
            ])
        }
        guard rendererState.mediaSessionID == mediaSession.mediaSessionID,
              rendererState.route == mediaSession.route else {
            throw RoutePlaybackProbeError.controlAssertionFailed([
                "activeRendererOwnershipMismatch",
            ])
        }
        return ActivePlaybackIdentity(
            mediaSessionID: mediaSession.mediaSessionID,
            rendererIdentity: rendererState.rendererIdentity,
            graphID: rendererState.graphID,
            sourceSummary: mediaSession.sourceSummary,
            route: mediaSession.route,
            flushCount: rendererState.flushCount
        )
    }

    private func activeSessionForProbe() throws -> SampleBufferPlaybackSession {
        guard let session = playback.activeSessionForProbe() else {
            throw RoutePlaybackProbeError.controlAssertionFailed([
                "activeSessionReferenceMissing",
            ])
        }
        return session
    }

    private func phaseResult(
        phase: String,
        route: PlaybackRoute,
        source: URL,
        facts: [String: Any]
    ) -> [String: Any] {
        [
            "phase": phase,
            "route": route.rawValue,
            "source": source.lastPathComponent,
            "result": "passed",
            "facts": facts,
        ]
    }

    private func closedSessionFacts(
        session: SampleBufferPlaybackSession,
        identity: ActivePlaybackIdentity
    ) throws -> [String: Any] {
        let snapshot = session.debugSnapshot()
        let flushAfter = snapshot.rendererState?.flushCount ?? identity.flushCount
        let assertions: [(Bool, String)] = [
            (snapshot.lifecycle == .idle, "closedLifecycleNotIdle"),
            (snapshot.mediaSession == nil, "closedMediaSessionStillCurrent"),
            (snapshot.lastMediaSession?.mediaSessionID == identity.mediaSessionID,
             "closedLastSessionMismatch"),
            (snapshot.lastCompletedOperation?.kind == .close, "closeOperationMissing"),
            (snapshot.lastCompletedOperation?.state == .completed, "closeOperationIncomplete"),
            (snapshot.realityKitBinding == nil, "closedRealityKitBindingStillActive"),
            (snapshot.presentationBinding == nil, "closedPresentationBindingStillActive"),
            (snapshot.rendererState?.rendererIdentity == identity.rendererIdentity,
             "closedRendererIdentityChanged"),
            (flushAfter > identity.flushCount, "closeFlushDidNotComplete"),
            (snapshot.rendererState?.rendererError == nil, "closedRendererError"),
            (snapshot.audioRendererState?.error == nil, "closedAudioRendererError"),
        ]
        let failures = assertions.compactMap { $0.0 ? nil : $0.1 }
        guard failures.isEmpty else {
            throw RoutePlaybackProbeError.controlAssertionFailed(failures)
        }
        return [
            "mediaSessionID": identity.mediaSessionID,
            "rendererIdentity": identity.rendererIdentity,
            "graphID": identity.graphID,
            "lifecycle": snapshot.lifecycle.rawValue,
            "closeOperation": snapshot.lastCompletedOperation?.state.rawValue ?? "missing",
            "flushCountBefore": identity.flushCount,
            "flushCountAfter": flushAfter,
            "bindingsInvalidated": true,
        ]
    }

    private func closeAndVerify(
        session: SampleBufferPlaybackSession,
        identity: ActivePlaybackIdentity
    ) async throws -> [String: Any] {
        await playback.closeAndWait()
        var facts = try closedSessionFacts(session: session, identity: identity)
        let component = playback.realityKitBindingSnapshot()
        let assertions: [(Bool, String)] = [
            (playback.activeSessionForProbe() == nil, "activeSessionSurvivedClose"),
            (playback.debugSnapshot() == nil, "activeSnapshotSurvivedClose"),
            (component["component"] == "missing", "videoComponentSurvivedClose"),
            (playback.status == .idle, "publicStatusNotIdleAfterClose"),
            (!playback.isMediaTransitioning, "closeBarrierStillTransitioning"),
            (playback.selectedURL?.lastPathComponent == identity.sourceSummary,
             "closeDidNotPreserveReopenSource"),
        ]
        let failures = assertions.compactMap { $0.0 ? nil : $0.1 }
        guard failures.isEmpty else {
            throw RoutePlaybackProbeError.controlAssertionFailed(failures)
        }
        facts["activeSessionReleased"] = true
        facts["activeSnapshotAbsent"] = true
        facts["componentRemoved"] = true
        facts["sourcePreservedForReopen"] = true
        return facts
    }

    private func reopenAndVerify(
        previous: ActivePlaybackIdentity,
        route: PlaybackRoute,
        source: URL
    ) async throws -> (
        identity: ActivePlaybackIdentity,
        session: SampleBufferPlaybackSession,
        facts: [String: Any]
    ) {
        await playback.reopen()
        try requireSuccessfulControl("reopen")
        try await waitForVisibleProgress(route: route, minimumTime: 0.1)
        let identity = try activePlaybackIdentity()
        let session = try activeSessionForProbe()
        let snapshot = session.debugSnapshot()
        let assertions: [(Bool, String)] = [
            (identity.mediaSessionID != previous.mediaSessionID, "reopenReusedMediaSession"),
            (identity.rendererIdentity != previous.rendererIdentity, "reopenReusedRenderer"),
            (identity.graphID != previous.graphID, "reopenReusedRendererGraph"),
            (identity.route == route, "reopenChangedRoute"),
            (identity.sourceSummary == source.lastPathComponent, "reopenChangedSource"),
            (snapshot.mediaSession?.sourceProvenance == "reopen", "reopenProvenanceMissing"),
            (snapshot.lastOpenOperation?.state == .completed, "reopenOperationIncomplete"),
            (playback.selectedURL?.lastPathComponent == source.lastPathComponent,
             "reopenSelectedSourceMismatch"),
        ]
        let failures = assertions.compactMap { $0.0 ? nil : $0.1 }
        guard failures.isEmpty else {
            throw RoutePlaybackProbeError.controlAssertionFailed(failures)
        }
        return (
            identity,
            session,
            [
                "previousMediaSessionID": previous.mediaSessionID,
                "mediaSessionID": identity.mediaSessionID,
                "previousRendererIdentity": previous.rendererIdentity,
                "rendererIdentity": identity.rendererIdentity,
                "previousGraphID": previous.graphID,
                "graphID": identity.graphID,
                "newMediaSession": true,
                "newRenderer": true,
                "newRendererGraph": true,
                "sourcePreserved": true,
                "routePreserved": true,
                "bindingRestored": true,
                "displayedPixelBuffer": true,
                "openOperation": snapshot.lastOpenOperation?.state.rawValue ?? "missing",
            ]
        )
    }

    private func switchRouteAndVerify(
        from previous: ActivePlaybackIdentity,
        session previousSession: SampleBufferPlaybackSession,
        to targetRoute: PlaybackRoute,
        source: URL
    ) async throws -> (
        identity: ActivePlaybackIdentity,
        session: SampleBufferPlaybackSession,
        facts: [String: Any]
    ) {
        let rawTime = previousSession.currentTime().seconds
        let switchTime = rawTime.isFinite ? rawTime : 0
        await playback.selectRoute(targetRoute)
        try requireSuccessfulControl("coldRouteSwitch")
        try await waitForVisibleProgress(
            route: targetRoute,
            minimumTime: max(0.1, switchTime + 0.1)
        )
        let oldCleanup = try closedSessionFacts(
            session: previousSession,
            identity: previous
        )
        let identity = try activePlaybackIdentity()
        let session = try activeSessionForProbe()
        let snapshot = session.debugSnapshot()
        let routeSwitch = snapshot.lastRouteSwitchOperation
        let assertions: [(Bool, String)] = [
            (identity.mediaSessionID != previous.mediaSessionID,
             "coldSwitchReusedMediaSession"),
            (identity.rendererIdentity != previous.rendererIdentity, "coldSwitchReusedRenderer"),
            (identity.graphID != previous.graphID, "coldSwitchReusedRendererGraph"),
            (identity.route == targetRoute, "coldSwitchSelectedWrongRoute"),
            (identity.sourceSummary == source.lastPathComponent, "coldSwitchChangedSource"),
            (snapshot.mediaSession?.sourceProvenance == "coldRouteSwitch",
             "coldSwitchProvenanceMissing"),
            (abs((snapshot.mediaSession?.initialTimeSeconds ?? -.infinity) - switchTime) < 1,
             "coldSwitchDidNotPreserveTime"),
            (routeSwitch?.state == .completed, "coldSwitchOperationIncomplete"),
            (routeSwitch?.sourceRoute == previous.route, "coldSwitchSourceRouteMismatch"),
            (routeSwitch?.targetRoute == targetRoute, "coldSwitchTargetRouteMismatch"),
            (playback.selectedURL?.lastPathComponent == source.lastPathComponent,
             "coldSwitchSelectedSourceMismatch"),
        ]
        let failures = assertions.compactMap { $0.0 ? nil : $0.1 }
        guard failures.isEmpty else {
            throw RoutePlaybackProbeError.controlAssertionFailed(failures)
        }
        return (
            identity,
            session,
            [
                "previousMediaSessionID": previous.mediaSessionID,
                "mediaSessionID": identity.mediaSessionID,
                "previousRendererIdentity": previous.rendererIdentity,
                "rendererIdentity": identity.rendererIdentity,
                "previousGraphID": previous.graphID,
                "graphID": identity.graphID,
                "switchTimeSeconds": switchTime,
                "initialTimeSeconds": snapshot.mediaSession?.initialTimeSeconds ?? 0,
                "sourceRoute": previous.route.rawValue,
                "targetRoute": targetRoute.rawValue,
                "newMediaSession": true,
                "newRenderer": true,
                "newRendererGraph": true,
                "sourcePreserved": true,
                "bindingRestored": true,
                "displayedPixelBuffer": true,
                "routeSwitchOperation": routeSwitch?.state.rawValue ?? "missing",
                "oldSessionCleanup": oldCleanup,
            ]
        )
    }

    private func oppositeRoute(to route: PlaybackRoute) -> PlaybackRoute {
        route == .appleCompressed ? .ffmpegCompressed : .appleCompressed
    }

    private func requireSuccessfulControl(_ name: String) throws {
        if let error = playback.controlError {
            throw RoutePlaybackProbeError.controlAssertionFailed(["\(name): \(error)"])
        }
    }

    private func waitForRendererRate(_ expected: Float) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if playback.debugSnapshot()?.rendererState?.rate == expected { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw RoutePlaybackProbeError.controlAssertionFailed([
            "rendererRateDidNotBecome\(expected)",
        ])
    }

    private func waitForStatus(_ expected: PlaybackStatus) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if playback.status == expected { return }
            if case .failed(let message) = playback.status {
                throw RoutePlaybackProbeError.routeFailed(
                    currentRoute ?? .appleCompressed,
                    message
                )
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw RoutePlaybackProbeError.controlAssertionFailed([
            "statusDidNotBecome\(expected.label)",
        ])
    }
}

private enum RoutePlaybackProbeError: LocalizedError {
    case routeFailed(PlaybackRoute, String)
    case timelineConfiguredAfterFirstEnqueue(PlaybackRoute)
    case timedOut(PlaybackRoute)
    case audioSwitchTimedOut(Int)
    case controlSequenceTimedOut
    case controlAssertionFailed([String])

    var errorDescription: String? {
        switch self {
        case .routeFailed(let route, let message): "\(route.label) failed: \(message)"
        case .timelineConfiguredAfterFirstEnqueue(let route): "\(route.label) enqueued its first sample before configuring the synchronizer timeline."
        case .timedOut(let route): "\(route.label) did not produce visible progress within 20 seconds."
        case .audioSwitchTimedOut(let streamIndex): "Audio switch to stream \(streamIndex) timed out."
        case .controlSequenceTimedOut: "The runtime control sequence did not resume audio and video progress."
        case .controlAssertionFailed(let failures):
            "Runtime control assertions failed: \(failures.joined(separator: ", "))."
        }
    }
}
