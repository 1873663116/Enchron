import Foundation

public nonisolated struct PlaybackSurfaceGesturePreview: Sendable, Equatable {
    public let originSeconds: Double
    public let offsetSeconds: Double
    public let targetSeconds: Double
    public let lowerReachableOffsetSeconds: Double
    public let upperReachableOffsetSeconds: Double

    init(originSeconds: Double, durationSeconds: Double, translation: Double, width: Double) {
        let origin = min(max(0, originSeconds.rounded(.down)), durationSeconds.rounded(.down))
        let lower = -min(30, origin)
        let upper = min(30, max(0, durationSeconds.rounded(.down) - origin))
        let normalized = min(1, abs(translation) / (width / 2))
        let damped = 30 * sin(normalized * .pi / 2) * (translation < 0 ? -1 : 1)
        let offset = min(upper, max(lower, damped.rounded()))
        self.originSeconds = origin
        offsetSeconds = offset
        targetSeconds = origin + offset
        lowerReachableOffsetSeconds = lower
        upperReachableOffsetSeconds = upper
    }
}

public nonisolated enum PlaybackSurfaceGesturePhase: String, Sendable, Equatable {
    case idle
    case pressing
    case waitingForSecondTap
    case holding
    case seeking
    case rejected
}

nonisolated struct PlaybackSurfaceGestureContext: Sendable {
    var controlsVisible: Bool
    var enabled: Bool
    var isPlaying: Bool
    var positionSeconds: Double
    var durationSeconds: Double
    var playbackRate: Double
    var holdPlaybackRate: Double
}

nonisolated enum PlaybackSurfaceGestureEffect: Sendable, Equatable {
    case toggleControls
    case dismissControls
    case togglePlayback
    case setRate(Double)
    case seekPreviewActive(Bool)
    case seek(targetSeconds: Double, wasPlaying: Bool)
}

nonisolated struct PlaybackSurfaceGestureState {
    struct Press {
        let startedAt: Double
        let width: Double
        let controlsVisible: Bool
        let enabled: Bool
        let isSecondTap: Bool
        var stationary = true
    }

    struct PendingTap {
        let deadline: Double
        let controlsVisible: Bool
    }

    enum Contact {
        case idle
        case pressing(Press)
        case holding(originalRate: Double)
        case seeking(origin: Double, duration: Double, width: Double, wasPlaying: Bool)
        case rejected
    }

    private var contact = Contact.idle
    private var pendingTap: PendingTap?
    private(set) var preview: PlaybackSurfaceGesturePreview?
    let doubleTapInterval = 0.3
    let holdInterval = 0.35

    var phase: PlaybackSurfaceGesturePhase {
        switch contact {
        case .idle: pendingTap == nil ? .idle : .waitingForSecondTap
        case .pressing: .pressing
        case .holding: .holding
        case .seeking: .seeking
        case .rejected: .rejected
        }
    }

    var isShortcutSequence: Bool {
        switch contact {
        case .pressing(let press): press.enabled && !press.controlsVisible
        case .holding, .seeking: true
        case .idle: pendingTap?.controlsVisible == false
        case .rejected: false
        }
    }

    var deadline: Double? {
        switch contact {
        case .idle: pendingTap?.deadline
        case .pressing(let press):
            press.enabled && !press.controlsVisible && press.stationary
                ? press.startedAt + holdInterval : nil
        case .holding, .seeking, .rejected: nil
        }
    }

    mutating func begin(at time: Double, width: Double, context: PlaybackSurfaceGestureContext) -> [PlaybackSurfaceGestureEffect] {
        guard case .idle = contact else { return [] }
        let effects = advance(to: time, context: context)
        let pending = pendingTap
        contact = .pressing(Press(
            startedAt: time,
            width: max(width, 0.0001),
            controlsVisible: pending?.controlsVisible ?? (effects.contains(.toggleControls) ? !context.controlsVisible : context.controlsVisible),
            enabled: context.enabled,
            isSecondTap: pending != nil
        ))
        return effects
    }

    mutating func update(horizontal: Double, vertical: Double, at time: Double, context: PlaybackSurfaceGestureContext) -> [PlaybackSurfaceGestureEffect] {
        switch contact {
        case .pressing(var press):
            let threshold = min(12, press.width * 0.025)
            guard press.enabled, !press.controlsVisible else {
                if max(abs(horizontal), abs(vertical)) >= threshold { contact = .rejected }
                return []
            }
            if time > press.startedAt + holdInterval && press.stationary && context.isPlaying {
                return advance(to: time, context: context)
            }
            if abs(horizontal) >= threshold && abs(horizontal) >= abs(vertical) {
                pendingTap = nil
                guard context.durationSeconds > 0 else {
                    contact = .rejected
                    return []
                }
                let origin = min(context.durationSeconds, context.positionSeconds)
                contact = .seeking(origin: origin, duration: context.durationSeconds, width: press.width, wasPlaying: context.isPlaying)
                preview = PlaybackSurfaceGesturePreview(originSeconds: origin, durationSeconds: context.durationSeconds, translation: horizontal, width: press.width)
                return [.seekPreviewActive(true)]
            }
            if abs(vertical) >= threshold || abs(horizontal) >= threshold {
                press.stationary = false
                pendingTap = nil
                contact = .rejected
                return []
            }
            contact = .pressing(press)
            return advance(to: time, context: context)
        case .seeking(let origin, let duration, let width, _):
            preview = PlaybackSurfaceGesturePreview(originSeconds: origin, durationSeconds: duration, translation: horizontal, width: width)
            return []
        case .idle, .holding, .rejected:
            return []
        }
    }

    mutating func advance(to time: Double, context: PlaybackSurfaceGestureContext) -> [PlaybackSurfaceGestureEffect] {
        switch contact {
        case .idle:
            guard let pendingTap, time >= pendingTap.deadline else { return [] }
            self.pendingTap = nil
            return pendingTap.controlsVisible ? [] : [.toggleControls]
        case .pressing(let press):
            guard press.enabled, !press.controlsVisible, press.stationary,
                  time >= press.startedAt + holdInterval else { return [] }
            pendingTap = nil
            guard context.isPlaying else {
                var waiting = press
                waiting.stationary = false
                contact = .pressing(waiting)
                return []
            }
            contact = .holding(originalRate: context.playbackRate)
            return [.setRate(context.holdPlaybackRate)]
        case .holding, .seeking, .rejected:
            return []
        }
    }

    mutating func end(at time: Double, context: PlaybackSurfaceGestureContext) -> [PlaybackSurfaceGestureEffect] {
        switch contact {
        case .pressing(let press):
            contact = .idle
            if time - press.startedAt >= holdInterval {
                pendingTap = nil
                return []
            }
            if press.enabled && !press.controlsVisible && !press.stationary {
                pendingTap = nil
                return []
            }
            if !press.enabled {
                pendingTap = nil
                return press.controlsVisible ? [.dismissControls] : [.toggleControls]
            }
            if press.isSecondTap {
                pendingTap = nil
                return press.controlsVisible ? [] : [.togglePlayback]
            }
            pendingTap = PendingTap(deadline: time + doubleTapInterval, controlsVisible: press.controlsVisible)
            return press.controlsVisible ? [.dismissControls] : []
        case .holding(let rate):
            contact = .idle
            return [.setRate(rate)]
        case .seeking(_, _, _, let wasPlaying):
            let target = preview
            preview = nil
            contact = .idle
            if let target, target.offsetSeconds != 0 {
                return [.seek(targetSeconds: target.targetSeconds, wasPlaying: wasPlaying), .seekPreviewActive(false)]
            }
            return [.seekPreviewActive(false)]
        case .rejected:
            contact = .idle
            pendingTap = nil
            return []
        case .idle:
            return []
        }
    }

    mutating func cancel() -> [PlaybackSurfaceGestureEffect] {
        let effects: [PlaybackSurfaceGestureEffect]
        switch contact {
        case .holding(let rate): effects = [.setRate(rate)]
        case .seeking: effects = [.seekPreviewActive(false)]
        case .idle, .pressing, .rejected: effects = []
        }
        contact = .idle
        pendingTap = nil
        preview = nil
        return effects
    }
}

nonisolated struct PlaybackSurfaceTransportIntent {
    private(set) var revision: UInt64 = 0
    private(set) var desiredPlaying: Bool?
    private(set) var desiredRate: Double?

    mutating func toggle(isPlaying: Bool) -> Bool {
        let desired = !(desiredPlaying ?? isPlaying)
        desiredPlaying = desired
        revision &+= 1
        return desired
    }

    mutating func preservePlayback(isPlaying: Bool) {
        if desiredPlaying == nil { desiredPlaying = isPlaying }
        revision &+= 1
    }

    mutating func setRate(_ rate: Double) {
        desiredRate = rate
        revision &+= 1
    }

    mutating func clear() {
        desiredPlaying = nil
        desiredRate = nil
        revision &+= 1
    }
}
