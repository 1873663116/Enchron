import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Observation
import PlaybackCore
import PlaybackFeature
import RealityKit

@MainActor
@Observable
final class PlaybackVerificationModel {
    enum Backend {
        case core
        case appAdapter
    }

    let videoEntity = Entity()

    private(set) var status: PlaybackStatus = .idle
    private(set) var diagnostics = PlaybackDiagnostics()
    private(set) var selectedURL: URL?
    private(set) var currentSeconds = 0.0
    private(set) var durationSeconds = 0.0
    private(set) var displayedPixelFormat = "none"
    private(set) var displayedFrameAvailable = false
    private(set) var audioSampleBufferCount: UInt64 = 0
    private(set) var audioFrameCount: UInt64 = 0
    private(set) var audioError = "none"
    private(set) var availableAudioTracks: [PlaybackAudioTrack] = []
    private(set) var selectedAudioStreamIndex: Int?
    private(set) var controlError: String?
    private(set) var isTransitioning = false
    private(set) var playbackRate: Float = 1
    private(set) var volume: Float = 1
    private(set) var isMuted = false

    let backend: Backend
    private let controller: PlaybackCoreController?
    private let runtime: PlaybackRuntime?
    private var realityViewAttached = false
    private var progressTask: Task<Void, Never>?
    private var securityScopedURL: URL?
    private var lastProbeSession: SampleBufferPlaybackSession?

    init(backend: Backend = .core) {
        self.backend = backend
        switch backend {
        case .core:
            let controller = PlaybackCoreController()
            self.controller = controller
            runtime = nil
            controller.onStatusChange = { [weak self] status in
                self?.status = status
            }
            controller.onDiagnosticsChange = { [weak self] diagnostics in
                self?.diagnostics = diagnostics
                self?.durationSeconds = diagnostics.durationSeconds
            }
        case .appAdapter:
            controller = nil
            runtime = PlaybackRuntime()
        }
        videoEntity.position.z = -1
    }

    var canControl: Bool {
        switch status {
        case .ready, .playing, .paused, .ended: true
        case .idle, .loading, .failed: false
        }
    }

    func open(
        _ url: URL,
        startTime: CMTime = .zero,
        startsPaused: Bool = false
    ) async {
        isTransitioning = true
        controlError = nil
        await close()
        selectedURL = url
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }

        do {
            let session: SampleBufferPlaybackSession
            switch backend {
            case .core:
                guard let controller else { throw PlaybackControlError.noActiveMediaSession }
                session = try await controller.open(
                    url,
                    startTime: startTime,
                    startsPaused: startsPaused,
                    provenance: "enchronMacOSCoreScenario",
                    accessRequirement: "securityScopedFile"
                )
            case .appAdapter:
                guard let runtime else { throw PlaybackControlError.noActiveMediaSession }
                try await runtime.open(
                    PlaybackLaunchRequest(url: url, displayName: url.lastPathComponent),
                    startTimeSeconds: startTime.seconds
                )
                guard let openedSession = runtime.activeSessionForVerification() else {
                    throw PlaybackRuntime.RuntimeError.noSession
                }
                session = openedSession
            }
            lastProbeSession = session
            PlaybackRealityPresenter.configure(
                videoEntity,
                renderer: session.renderer,
                presentation: .window,
                stereoLayout: .mono
            )
            if backend == .core {
                session.recordRealityKitBinding(
                    entityIdentity: "EnchronMacOS.videoEntity",
                    active: true
                )
            }
            try startIfAttached(session)
            availableAudioTracks = session.availableAudioTracks
            selectedAudioStreamIndex = session.selectedAudioStreamIndex
            playbackRate = session.currentRate() == 0 ? 1 : session.currentRate()
            volume = session.currentVolume
            isMuted = session.isMuted
            startProgressObservation()
        } catch {
            controlError = error.localizedDescription
            status = .failed(error.localizedDescription)
        }
        isTransitioning = false
    }

    func realityViewDidAttach() {
        realityViewAttached = true
        guard let session = activeSession else { return }
        do {
            try startIfAttached(session)
        } catch {
            controlError = error.localizedDescription
        }
    }

    func playPause() {
        if status == .playing {
            pause()
        } else {
            play()
        }
    }

    func play() {
        if let runtime {
            runtime.resume()
            syncRuntimeError()
            return
        }
        do {
            guard let controller else { throw PlaybackControlError.noActiveMediaSession }
            try controller.play()
            controlError = nil
        } catch {
            controlError = error.localizedDescription
        }
    }

    func pause() {
        if let runtime {
            runtime.pause()
            syncRuntimeError()
            return
        }
        do {
            guard let controller else { throw PlaybackControlError.noActiveMediaSession }
            try controller.pause()
            controlError = nil
        } catch {
            controlError = error.localizedDescription
        }
    }

    func seek(to seconds: Double) async {
        if let runtime {
            runtime.seek(to: seconds)
            syncRuntimeError()
            return
        }
        do {
            guard let controller else { throw PlaybackControlError.noActiveMediaSession }
            try await controller.seek(
                to: CMTime(seconds: max(0, min(seconds, durationSeconds)), preferredTimescale: 60_000)
            )
            controlError = nil
        } catch {
            if case PlaybackControlError.seekSuperseded = error { return }
            controlError = error.localizedDescription
        }
    }

    func skip(by seconds: Double) async {
        await seek(to: currentSeconds + seconds)
    }

    func setRate(_ rate: Float) {
        if let runtime {
            runtime.setSpeed(.init(Double(rate)))
            playbackRate = rate
            syncRuntimeError()
            return
        }
        do {
            guard let controller else { throw PlaybackControlError.noActiveMediaSession }
            try controller.setRate(rate)
            playbackRate = rate
            controlError = nil
        } catch {
            controlError = error.localizedDescription
        }
    }

    func setVolume(_ value: Float) {
        if let runtime {
            runtime.setVolume(value)
            volume = value
            syncRuntimeError()
            return
        }
        do {
            guard let controller else { throw PlaybackControlError.noActiveMediaSession }
            try controller.setVolume(value)
            volume = value
            controlError = nil
        } catch {
            controlError = error.localizedDescription
        }
    }

    func setMuted(_ muted: Bool) {
        if let runtime {
            runtime.setMuted(muted)
            isMuted = muted
            syncRuntimeError()
            return
        }
        do {
            guard let controller else { throw PlaybackControlError.noActiveMediaSession }
            try controller.setMuted(muted)
            isMuted = muted
            controlError = nil
        } catch {
            controlError = error.localizedDescription
        }
    }

    func selectAudioTrack(streamIndex: Int) async {
        if let runtime,
           let track = runtime.availableAudioTracks.first(where: { $0.id == String(streamIndex) }) {
            runtime.selectAudioTrack(track)
            syncRuntimeError()
            return
        }
        do {
            guard let controller else { throw PlaybackControlError.noActiveMediaSession }
            try await controller.selectAudioTrack(streamIndex: streamIndex)
            selectedAudioStreamIndex = streamIndex
            controlError = nil
        } catch {
            controlError = error.localizedDescription
        }
    }

    func reopen() async {
        guard let url = selectedURL else { return }
        await open(url)
    }

    func close() async {
        progressTask?.cancel()
        progressTask = nil
        if let session = activeSession {
            lastProbeSession = session
            if backend == .core {
                session.recordPresentationBinding(
                    realityViewIdentity: "EnchronMacOS.mainRealityView",
                    platform: "macOS",
                    attached: false
                )
                session.recordRealityKitBinding(
                    entityIdentity: "EnchronMacOS.videoEntity",
                    active: false
                )
            }
        }
        if let runtime {
            runtime.stop()
            await runtime.waitForPendingClose()
        } else if let controller {
            await controller.closeAndWait(clearSource: false)
        }
        videoEntity.components.remove(VideoPlayerComponent.self)
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        currentSeconds = 0
        durationSeconds = 0
        displayedFrameAvailable = false
        displayedPixelFormat = "none"
        audioSampleBufferCount = 0
        audioFrameCount = 0
        audioError = "none"
        availableAudioTracks = []
        selectedAudioStreamIndex = nil
    }

    func debugSnapshot() -> PlaybackDebugSnapshotV1? {
        activeSession?.debugSnapshot()
    }

    func activeSessionForProbe() -> SampleBufferPlaybackSession? {
        activeSession
    }

    func lastSessionSnapshotForProbe() -> PlaybackDebugSnapshotV1? {
        lastProbeSession?.debugSnapshot()
    }

    func rendererDisplayedPixelBuffer() -> CVPixelBuffer? {
        activeSession?.renderer.displayedPixelBuffer()
    }

    func realityKitBindingSnapshot() -> [String: String] {
        guard let session = activeSession,
              let component = videoEntity.components[VideoPlayerComponent.self] else {
            return ["consumer": "missing"]
        }
        return [
            "consumer": "videoPlayerComponent",
            "rendererIdentityMatches": String(component.videoRenderer === session.renderer),
            "entityActive": String(videoEntity.isActive),
        ]
    }

    private func startIfAttached(_ session: SampleBufferPlaybackSession) throws {
        guard realityViewAttached else { return }
        if let runtime {
            try runtime.attach(
                entityID: "EnchronMacOS.videoEntity",
                realityViewID: "EnchronMacOS.mainRealityView",
                presentation: .window
            )
        } else if let controller {
            session.recordPresentationBinding(
                realityViewIdentity: "EnchronMacOS.mainRealityView",
                platform: "macOS",
                attached: true
            )
            try controller.presentationDidAttach(session: session)
            if status == .loading || status == .ready {
                try controller.start()
            }
        }
    }

    private func startProgressObservation() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let session = self.activeSession else { return }
                if let runtime = self.runtime {
                    self.status = runtime.lifecycle
                    self.diagnostics = runtime.diagnostics
                    self.durationSeconds = runtime.playbackPosition.duration
                    self.controlError = runtime.lastErrorMessage
                    self.availableAudioTracks = session.availableAudioTracks
                    self.selectedAudioStreamIndex = session.selectedAudioStreamIndex
                    self.playbackRate = Float(runtime.currentPlaybackSpeed.value)
                }
                self.currentSeconds = session.currentTime().seconds
                if let controller = self.controller {
                    self.durationSeconds = controller.diagnostics.durationSeconds
                }
                let snapshot = session.debugSnapshot()
                self.audioSampleBufferCount = snapshot.audioRendererState?.enqueuedSampleBufferCount ?? 0
                self.audioFrameCount = snapshot.audioRendererState?.enqueuedAudioFrameCount ?? 0
                self.audioError = snapshot.audioRendererState?.error ?? "none"
                if let pixelBuffer = session.renderer.displayedPixelBuffer() {
                    self.displayedFrameAvailable = true
                    self.displayedPixelFormat = Self.fourCC(CVPixelBufferGetPixelFormatType(pixelBuffer))
                } else {
                    self.displayedFrameAvailable = false
                    self.displayedPixelFormat = "none"
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private var activeSession: SampleBufferPlaybackSession? {
        controller?.activeSession ?? runtime?.activeSessionForVerification()
    }

    private func syncRuntimeError() {
        controlError = runtime?.lastErrorMessage
    }

    private static func fourCC(_ value: OSType) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(value)
    }
}
