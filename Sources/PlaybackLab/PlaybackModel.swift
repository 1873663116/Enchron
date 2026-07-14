import Foundation
import AppKit
import AVFoundation
import CoreMedia
import Observation
import PlaybackCore
import RealityKit

@MainActor
@Observable
final class PlaybackModel {
    static let defaultVideoURL = URL(fileURLWithPath: "/Users/xiongzhipeng/Desktop/test/HDR10/HDR10.MP4")
    static let knownOverexposureTime = CMTime(value: 450 * 1001, timescale: 60_000)

    let videoEntity = Entity()
    let systemReferencePlayer = AVPlayer()

    private(set) var status: PlaybackStatus = .idle
    private(set) var selectedURL: URL?
    private(set) var selectedRoute = PlaybackRoute.appleCompressed
    private(set) var diagnostics = PlaybackDiagnostics()
    private(set) var currentSeconds = 0.0
    private(set) var durationSeconds = 0.0
    private(set) var playbackRate: Float = 1
    private(set) var volume: Float = 1
    private(set) var isMuted = false
    private(set) var audioTracks: [PlaybackAudioTrack] = []
    private(set) var selectedAudioStreamIndex: Int?
    private(set) var isMediaTransitioning = false
    private(set) var controlError: String?
    private let core = PlaybackCoreController()
    private var debugCommandBridge: PlaybackDebugCommandBridge?
    private var realityViewAttached = false
    private var progressTask: Task<Void, Never>?
    private var mediaOperationGeneration: UInt64 = 0

    init() {
        videoEntity.scale = SIMD3(repeating: 2.2)
        core.onStatusChange = { [weak self] status in
            self?.status = status
        }
        core.onDiagnosticsChange = { [weak self] diagnostics in
            self?.diagnostics = diagnostics
        }
        debugCommandBridge = PlaybackDebugCommandBridge { [weak self] command in
            try await self?.handleDebugCommand(command)
        }
    }

    func openDefaultVideo() async {
        guard FileManager.default.fileExists(atPath: Self.defaultVideoURL.path) else { return }
        await open(Self.defaultVideoURL)
    }

    func open(
        _ url: URL,
        route: PlaybackRoute? = nil,
        startTime: CMTime = .zero,
        startsPaused: Bool = false
    ) async {
        let generation = beginMediaTransition()
        defer { finishMediaTransition(generation) }
        await closeSessionAndWait()
        guard ownsMediaTransition(generation), !Task.isCancelled else { return }
        let route = route ?? selectedRoute
        selectedRoute = route
        status = .loading
        selectedURL = url

        var openedSession: SampleBufferPlaybackSession?
        do {
            let session = try await core.open(
                url,
                route: route,
                startTime: startTime,
                startsPaused: startsPaused
            )
            openedSession = session
            guard ownsMediaTransition(generation), !Task.isCancelled,
                  core.activeSession === session else {
                if ownsMediaTransition(generation), core.activeSession === session {
                    core.close(clearSource: false)
                }
                return
            }

            try attach(session)
            durationSeconds = diagnostics.durationSeconds
            audioTracks = core.availableAudioTracks
            selectedAudioStreamIndex = session.selectedAudioStreamIndex
            try startIfPresentationAttached(session)
            playbackRate = session.preferredPlaybackRate
            volume = session.currentVolume
            isMuted = session.isMuted
        } catch {
            guard ownsMediaTransition(generation) else { return }
            if let openedSession, core.activeSession === openedSession {
                core.close(clearSource: false)
                videoEntity.components.remove(VideoPlayerComponent.self)
            }
            resetPlaybackFacts()
            status = .failed(error.localizedDescription)
        }
    }

    func selectRoute(_ route: PlaybackRoute) async {
        do {
            try await switchRoute(route)
        } catch {
            if !isMediaTransitioning {
                controlError = error.localizedDescription
            }
        }
    }

    private func switchRoute(_ route: PlaybackRoute) async throws {
        guard route != selectedRoute else { return }
        guard selectedURL != nil else {
            selectedRoute = route
            diagnostics.requestedRoute = route.rawValue
            diagnostics.selectedRoute = route.rawValue
            diagnostics.rendererInputKind = route.rendererInputKind.rawValue
            return
        }
        let generation = beginMediaTransition()
        defer { finishMediaTransition(generation) }
        let oldSession = core.activeSession
        if realityViewAttached {
            oldSession?.recordPresentationBinding(
                realityViewIdentity: "macOS.mainRealityView",
                platform: "macOS",
                attached: false
            )
        }
        oldSession?.recordRealityKitBinding(
            entityIdentity: PlaybackTrace.identity(videoEntity),
            active: false
        )
        videoEntity.components.remove(VideoPlayerComponent.self)
        selectedRoute = route
        status = .loading
        var switchedSession: SampleBufferPlaybackSession?
        do {
            let session = try await core.switchRoute(to: route)
            switchedSession = session
            guard ownsMediaTransition(generation), !Task.isCancelled,
                  core.activeSession === session else {
                if ownsMediaTransition(generation), core.activeSession === session {
                    core.close(clearSource: false)
                }
                throw PlaybackControlError.openTerminatedByCleanup
            }
            try attach(session)
            try startIfPresentationAttached(session)
            audioTracks = core.availableAudioTracks
            selectedAudioStreamIndex = session.selectedAudioStreamIndex
            playbackRate = session.preferredPlaybackRate
            volume = session.currentVolume
            isMuted = session.isMuted
        } catch {
            guard ownsMediaTransition(generation) else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            if let switchedSession, core.activeSession === switchedSession {
                core.close(clearSource: false)
                videoEntity.components.remove(VideoPlayerComponent.self)
            }
            resetPlaybackFacts()
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    func play() {
        do {
            try core.play()
            controlError = nil
        } catch {
            controlError = error.localizedDescription
        }
    }

    func pause() {
        do {
            try core.pause()
            controlError = nil
        } catch {
            controlError = error.localizedDescription
        }
    }

    func seek(to seconds: Double) async {
        do {
            try await core.seek(to: CMTime(seconds: seconds, preferredTimescale: 60_000))
            currentSeconds = seconds
            controlError = nil
        } catch {
            if case PlaybackControlError.seekSuperseded = error { return }
            controlError = error.localizedDescription
        }
    }

    func setRate(_ rate: Float) {
        do {
            try core.setRate(rate)
            playbackRate = rate
            controlError = nil
        } catch {
            controlError = error.localizedDescription
        }
    }

    func setVolume(_ value: Float) {
        do {
            try core.setVolume(value)
            volume = value
            controlError = nil
        } catch {
            controlError = error.localizedDescription
        }
    }

    func setMuted(_ muted: Bool) {
        do {
            try core.setMuted(muted)
            isMuted = muted
            controlError = nil
        } catch {
            controlError = error.localizedDescription
        }
    }

    func reopen() async {
        guard selectedURL != nil else { return }
        let generation = beginMediaTransition()
        defer { finishMediaTransition(generation) }
        let oldSession = core.activeSession
        progressTask?.cancel()
        progressTask = nil
        if realityViewAttached {
            oldSession?.recordPresentationBinding(
                realityViewIdentity: "macOS.mainRealityView",
                platform: "macOS",
                attached: false
            )
        }
        oldSession?.recordRealityKitBinding(
            entityIdentity: PlaybackTrace.identity(videoEntity),
            active: false
        )
        videoEntity.components.remove(VideoPlayerComponent.self)
        status = .loading

        var reopenedSession: SampleBufferPlaybackSession?
        do {
            let session = try await core.reopen()
            reopenedSession = session
            guard ownsMediaTransition(generation), !Task.isCancelled,
                  core.activeSession === session else {
                if ownsMediaTransition(generation), core.activeSession === session {
                    core.close(clearSource: false)
                }
                return
            }
            try attach(session)
            durationSeconds = diagnostics.durationSeconds
            audioTracks = core.availableAudioTracks
            selectedAudioStreamIndex = session.selectedAudioStreamIndex
            try startIfPresentationAttached(session)
            playbackRate = session.preferredPlaybackRate
            volume = session.currentVolume
            isMuted = session.isMuted
        } catch {
            guard ownsMediaTransition(generation) else { return }
            if let reopenedSession, core.activeSession === reopenedSession {
                core.close(clearSource: false)
                videoEntity.components.remove(VideoPlayerComponent.self)
            }
            resetPlaybackFacts()
            status = .failed(error.localizedDescription)
        }
    }

    func reportFileImportFailure(_ error: Error) {
        controlError = "Open failed: \(error.localizedDescription)"
    }

    func selectAudioTrack(_ streamIndex: Int) {
        do {
            try core.selectAudioTrack(streamIndex: streamIndex)
            selectedAudioStreamIndex = streamIndex
            controlError = nil
        } catch { controlError = error.localizedDescription }
    }

    func openKnownOverexposurePoint() async {
        await open(Self.defaultVideoURL, startTime: Self.knownOverexposureTime, startsPaused: true)
    }

    func prepareSystemReference() async {
        systemReferencePlayer.replaceCurrentItem(with: AVPlayerItem(url: Self.defaultVideoURL))
        await systemReferencePlayer.seek(
            to: Self.knownOverexposureTime,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        systemReferencePlayer.pause()
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        let text = (try? core.activeSession?.debugSnapshotJSON()) ?? diagnostics.snapshotText
        NSPasteboard.general.setString(text, forType: .string)
    }

    func realityViewDidAttachEntity() {
        realityViewAttached = true
        guard let session = core.activeSession,
              let component = videoEntity.components[VideoPlayerComponent.self],
              component.videoRenderer === session.renderer else { return }
        session.recordPresentationBinding(
            realityViewIdentity: "macOS.mainRealityView",
            platform: "macOS",
            attached: true
        )
        do {
            try core.presentationDidAttach(session: session)
            if status == .loading || status == .ready {
                try startIfPresentationAttached(session)
            }
        } catch {
            controlError = error.localizedDescription
        }
    }

    func rendererDisplayedPixelBuffer() -> CVPixelBuffer? {
        core.activeSession?.renderer.displayedPixelBuffer()
    }

    func debugSnapshot() -> PlaybackDebugSnapshotV1? {
        core.activeSession?.debugSnapshot()
    }

    func activeSessionForProbe() -> SampleBufferPlaybackSession? {
        core.activeSession
    }

    func realityKitBindingSnapshot() -> [String: String] {
        guard let session = core.activeSession,
              let component = videoEntity.components[VideoPlayerComponent.self] else {
            return ["component": "missing"]
        }
        return [
            "component": "present",
            "rendererIdentityMatches": String(component.videoRenderer === session.renderer),
            "renderingStatus": String(describing: component.currentRenderingStatus)
        ]
    }

    func close() {
        invalidateMediaTransitions()
        progressTask?.cancel()
        progressTask = nil
        if let session = core.activeSession {
            if realityViewAttached {
                session.recordPresentationBinding(
                    realityViewIdentity: "macOS.mainRealityView",
                    platform: "macOS",
                    attached: false
                )
            }
            session.recordRealityKitBinding(
                entityIdentity: PlaybackTrace.identity(videoEntity),
                active: false
            )
        }
        core.close(clearSource: false)
        videoEntity.components.remove(VideoPlayerComponent.self)
        systemReferencePlayer.replaceCurrentItem(with: nil)
        status = .idle
        resetPlaybackFacts()
    }

    func closeAndWait() async {
        let generation = beginMediaTransition()
        defer { finishMediaTransition(generation) }
        await closeSessionAndWait()
    }

    private func closeSessionAndWait() async {
        progressTask?.cancel()
        progressTask = nil
        if let session = core.activeSession {
            if realityViewAttached {
                session.recordPresentationBinding(
                    realityViewIdentity: "macOS.mainRealityView",
                    platform: "macOS",
                    attached: false
                )
            }
            session.recordRealityKitBinding(
                entityIdentity: PlaybackTrace.identity(videoEntity),
                active: false
            )
        }
        await core.closeAndWait(clearSource: false)
        videoEntity.components.remove(VideoPlayerComponent.self)
        systemReferencePlayer.replaceCurrentItem(with: nil)
        status = .idle
        resetPlaybackFacts()
    }

    private func attach(_ session: SampleBufferPlaybackSession) throws {
        videoEntity.components.set(VideoPlayerComponent(videoRenderer: session.renderer))
        session.recordRealityKitBinding(
            entityIdentity: PlaybackTrace.identity(videoEntity),
            active: true
        )
        if realityViewAttached {
            session.recordPresentationBinding(
                realityViewIdentity: "macOS.mainRealityView",
                platform: "macOS",
                attached: true
            )
            try core.presentationDidAttach(session: session)
        }
    }

    private func startIfPresentationAttached(_ session: SampleBufferPlaybackSession) throws {
        guard session.debugSnapshot().presentationBinding?.entityAttached == true else { return }
        try core.start()
        startProgressUpdates()
    }

    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                currentSeconds = core.activeSession?.currentTime().seconds ?? 0
                durationSeconds = diagnostics.durationSeconds
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    var canPlay: Bool {
        !isMediaTransitioning && (status == .ready || status == .paused)
    }

    var canPause: Bool {
        !isMediaTransitioning && status == .playing
    }

    var canSeek: Bool {
        !isMediaTransitioning && durationSeconds > 0 &&
            (status == .ready || status == .playing || status == .paused)
    }

    var canAdjustPlayback: Bool {
        !isMediaTransitioning &&
            (status == .ready || status == .playing || status == .paused)
    }

    var canClose: Bool {
        !isMediaTransitioning && core.activeSession != nil
    }

    private func resetPlaybackFacts() {
        diagnostics = PlaybackDiagnostics()
        currentSeconds = 0
        durationSeconds = 0
        playbackRate = 1
        volume = 1
        isMuted = false
        audioTracks = []
        selectedAudioStreamIndex = nil
        controlError = nil
    }

    private func beginMediaTransition() -> UInt64 {
        mediaOperationGeneration &+= 1
        isMediaTransitioning = true
        controlError = nil
        return mediaOperationGeneration
    }

    private func ownsMediaTransition(_ generation: UInt64) -> Bool {
        mediaOperationGeneration == generation
    }

    private func finishMediaTransition(_ generation: UInt64) {
        guard ownsMediaTransition(generation) else { return }
        isMediaTransitioning = false
    }

    private func invalidateMediaTransitions() {
        mediaOperationGeneration &+= 1
        isMediaTransitioning = false
    }

    private func handleDebugCommand(_ command: PlaybackDebugCommand) async throws {
        switch command {
        case .snapshot:
            guard let session = core.activeSession else {
                throw PlaybackControlError.noActiveMediaSession
            }
            session.recordDebugCommand("snapshot")
            core.writeDebugSnapshot()
        case .play:
            guard let session = core.activeSession else {
                throw PlaybackControlError.noActiveMediaSession
            }
            session.recordDebugCommand("play")
            try core.play()
        case .pause:
            guard let session = core.activeSession else {
                throw PlaybackControlError.noActiveMediaSession
            }
            session.recordDebugCommand("pause")
            try core.pause()
        case .close:
            core.activeSession?.recordDebugCommand("close")
            await closeAndWait()
        case .reopen:
            guard let selectedURL else {
                throw PlaybackControlError.noActiveMediaSession
            }
            await open(selectedURL, route: selectedRoute)
            guard core.activeSession != nil else {
                throw PlaybackControlError.noActiveMediaSession
            }
        case .route(let route):
            guard let session = core.activeSession else {
                throw PlaybackControlError.noActiveMediaSession
            }
            session.recordDebugCommand("route:\(route.rawValue)")
            try await switchRoute(route)
        case .seek(let seconds):
            guard let session = core.activeSession else {
                throw PlaybackControlError.noActiveMediaSession
            }
            session.recordDebugCommand("seek:\(seconds)")
            try await core.seek(
                to: CMTime(seconds: seconds, preferredTimescale: 60_000)
            )
        case .rate(let rate):
            guard let session = core.activeSession else {
                throw PlaybackControlError.noActiveMediaSession
            }
            session.recordDebugCommand("rate:\(rate)")
            try core.setRate(rate)
        }
    }
}
