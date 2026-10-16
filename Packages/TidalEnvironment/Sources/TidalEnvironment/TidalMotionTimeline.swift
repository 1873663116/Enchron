import EnvironmentSceneContract
import Foundation

nonisolated struct TidalMotionTimeline {
    static let transitionDuration = 1.2
    static let skyPeriod = 7200.0
    static let orbitPeriod = 3600.0

    struct Sample {
        var darkMix: Float
        var skyYaw: Float
        var orbitYaw: Float
    }

    private struct Transition {
        let target: EnvironmentAppearance
        let start: Double
        let fromMix: Double
        let fromTurn: Double
        let fromVelocity: Double
    }

    private enum Phase {
        case prepared(EnvironmentAppearance)
        case settled(EnvironmentAppearance)
        case transitioning(Transition)

        var target: EnvironmentAppearance {
            switch self {
            case .prepared(let value), .settled(let value): value
            case .transitioning(let transition): transition.target
            }
        }
    }

    private var phase: Phase = .prepared(.light)
    private var elapsed = 0.0
    private var turnOffset = 0.0

    private var visual: (mix: Double, turn: Double, velocity: Double) {
        guard case .transitioning(let transition) = phase else {
            return (phase.target == .dark ? 1 : 0, turnOffset, 0)
        }
        let p = min(max((elapsed - transition.start) / Self.transitionDuration, 0), 1)
        let ease = p * p * (3 - 2 * p)
        let target = transition.target == .dark ? 1.0 : 0.0
        let turn = transition.fromTurn + .pi * ease
            + (p * p * p - 2 * p * p + p) * Self.transitionDuration * transition.fromVelocity
        let velocity = .pi * (6 * p - 6 * p * p) / Self.transitionDuration
            + (3 * p * p - 4 * p + 1) * transition.fromVelocity
        return (transition.fromMix + (target - transition.fromMix) * ease, turn, velocity)
    }

    var sample: Sample {
        let value = visual
        return Sample(
            darkMix: Float(value.mix),
            skyYaw: Float((elapsed.truncatingRemainder(dividingBy: Self.skyPeriod) * 2 * .pi / Self.skyPeriod
                + value.turn).truncatingRemainder(dividingBy: 2 * .pi)),
            orbitYaw: Float(elapsed.truncatingRemainder(dividingBy: Self.orbitPeriod) * 2 * .pi / Self.orbitPeriod)
        )
    }

    mutating func request(_ appearance: EnvironmentAppearance) {
        guard phase.target != appearance else { return }
        if case .prepared = phase {
            phase = .prepared(appearance)
            return
        }
        let value = visual
        phase = .transitioning(Transition(
            target: appearance, start: elapsed, fromMix: value.mix,
            fromTurn: value.turn, fromVelocity: value.velocity
        ))
    }

    mutating func advance(by delta: Double) {
        if case .prepared(let appearance) = phase { phase = .settled(appearance) }
        elapsed += delta
        if case .transitioning(let transition) = phase,
           elapsed - transition.start >= Self.transitionDuration {
            turnOffset = (transition.fromTurn + .pi).truncatingRemainder(dividingBy: 2 * .pi)
            phase = .settled(transition.target)
        }
    }
}
