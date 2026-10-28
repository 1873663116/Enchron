import Foundation
import Observation

@MainActor
@Observable
public final class PlaybackSurfaceGestureController {
    public private(set) var preview: PlaybackSurfaceGesturePreview?
    public private(set) var phase = PlaybackSurfaceGesturePhase.idle
    public private(set) var originalPlaybackRate: Double?

    @ObservationIgnored private weak var runtime: PlaybackRuntime?
    @ObservationIgnored let session: PlaybackSessionModel
    @ObservationIgnored private var inputOwner: UUID?
    @ObservationIgnored private var state = PlaybackSurfaceGestureState()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var runtimeGeneration: UInt64
    @ObservationIgnored private var presentation: PlaybackPresentation

    public init(runtime: PlaybackRuntime, session: PlaybackSessionModel) {
        self.runtime = runtime
        self.session = session
        runtimeGeneration = runtime.observationGeneration
        presentation = session.playbackPresentation
    }

    private var extraGesturesEnabled: Bool {
        guard runtime?.isStreamingPlayback != true else { return false }
        return session.playbackShortcutsEnabled
    }

    @discardableResult
    public func begin(owner: UUID) -> Bool {
        synchronize()
        if inputOwner != nil, inputOwner != owner { cancel() }
        guard phase == .idle || phase == .waitingForSecondTap, let context else { return false }
        inputOwner = owner
        apply(state.begin(
            at: now,
            width: PlaybackSurfaceSeekTravel.width(for: presentation),
            context: context
        ))
        return true
    }

    public func update(horizontalTranslation: Double, verticalTranslation: Double = 0, owner: UUID) {
        synchronize()
        guard inputOwner == owner, let context else { return }
        apply(state.update(horizontal: horizontalTranslation, vertical: verticalTranslation, at: now, context: context))
    }

    public func end(owner: UUID) {
        synchronize()
        guard inputOwner == owner, let context else { return }
        apply(state.end(at: now, context: context))
    }

    public func tap() {
        cancel()
        session.toggleControlsFromPlaybackSurface()
    }

    public func cancel(owner: UUID) {
        guard inputOwner == owner else { return }
        cancel()
    }

    public func cancel() {
        inputOwner = nil
        apply(state.cancel())
    }

    public func synchronize() {
        guard let runtime else {
            cancel()
            return
        }
        if runtimeGeneration != runtime.observationGeneration || presentation != session.playbackPresentation {
            cancel()
            runtimeGeneration = runtime.observationGeneration
            presentation = session.playbackPresentation
        }
        if (!session.playbackShortcutsEnabled && state.isShortcutSequence) || session.presentationTransition != nil {
            cancel()
        } else if session.showControls && state.isShortcutSequence {
            cancel()
        }
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    private var context: PlaybackSurfaceGestureContext? {
        guard let runtime else { return nil }
        return PlaybackSurfaceGestureContext(
            controlsVisible: session.showControls,
            enabled: session.playbackShortcutsEnabled && session.presentationTransition == nil,
            isPlaying: runtime.productLifecycle == .playing,
            positionSeconds: runtime.playbackPosition.seconds,
            durationSeconds: runtime.playbackPosition.duration,
            playbackRate: runtime.currentPlaybackSpeed.value,
            holdPlaybackRate: session.holdPlaybackSpeed
        )
    }

    private func apply(_ effects: [PlaybackSurfaceGestureEffect]) {
        let previousPhase = phase
        let previousPreview = preview
        let previousOriginalRate = originalPlaybackRate
        for effect in effects {
            switch effect {
            case .toggleControls:
                session.toggleControlsFromPlaybackSurface()
            case .dismissControls:
                if session.showControls || session.windowSecondaryMenuIsPresented {
                    session.toggleControlsFromPlaybackSurface()
                }
            case .togglePlayback:
                guard extraGesturesEnabled else { break }
                runtime?.togglePlaybackFromSurfaceGesture()
            case .setRate(let rate):
                guard extraGesturesEnabled else { break }
                if state.phase == .holding { originalPlaybackRate = runtime?.currentPlaybackSpeed.value }
                runtime?.setRateFromSurfaceGesture(rate)
            case .seekPreviewActive(let active):
                guard extraGesturesEnabled else { break }
                runtime?.setSurfaceGestureSeekPreviewActive(active)
            case .seek(let target, let wasPlaying):
                guard extraGesturesEnabled else { break }
                runtime?.seekFromSurfaceGesture(to: target, wasPlaying: wasPlaying)
            }
        }
        preview = state.preview
        phase = state.phase
        if phase == .idle { inputOwner = nil }
        if phase != .holding { originalPlaybackRate = nil }
        if previousPhase != phase || effects.isEmpty == false {
            let evidencePreview = preview ?? previousPreview
            let evidenceOriginalRate = originalPlaybackRate ?? previousOriginalRate
            SurfaceInputProbes.record(
                "gesture.phase=\(phase.rawValue) fixedOrigin=\(evidencePreview?.originSeconds ?? -1)"
                    + " offset=\(evidencePreview?.offsetSeconds ?? 0) target=\(evidencePreview?.targetSeconds ?? -1)"
                    + " originalRate=\(evidenceOriginalRate ?? -1) effectiveRate=\(runtime?.currentPlaybackSpeed.value ?? -1)"
                    + " presentation=\(presentation.rawValue)"
                    + " travelWidth=\(PlaybackSurfaceSeekTravel.width(for: presentation))"
                    + " effects=\(String(describing: effects))",
                retention: .evidence
            )
        }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.cancel()
        timer = nil
        guard let deadline = state.deadline else { return }
        let delay = max(0, deadline - now)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            synchronize()
            guard let context else { return }
            apply(state.advance(to: now, context: context))
        }
    }
}
