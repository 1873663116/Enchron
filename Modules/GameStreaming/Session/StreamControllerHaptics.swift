import CoreHaptics
import Foundation
import GameController

/// Plays the host's rumble amplitudes on the haptic engines a controller exposes.
///
/// The engines are created per locality because GameController routes each motor
/// through its own locality: the two handles carry the low and high frequency
/// rumble, and the two triggers carry the adaptive-trigger effect.
final class StreamControllerHaptics: @unchecked Sendable {
    enum Motor: CaseIterable {
        case lowFrequency
        case highFrequency
        case leftTrigger
        case rightTrigger

        var locality: GCHapticsLocality {
            switch self {
            case .lowFrequency: GCHapticsLocality.leftHandle
            case .highFrequency: GCHapticsLocality.rightHandle
            case .leftTrigger: GCHapticsLocality.leftTrigger
            case .rightTrigger: GCHapticsLocality.rightTrigger
            }
        }
    }

    private struct Channel {
        var engine: CHHapticEngine
        var player: (any CHHapticPatternPlayer)?
        var isPlaying = false
    }

    private var channels: [Motor: Channel] = [:]

    var supportedMotors: Set<Motor> {
        Set(channels.keys)
    }

    func attach(to controller: GCController) {
        detach()
        guard let haptics = controller.haptics else { return }
        for motor in Motor.allCases where haptics.supportedLocalities.contains(motor.locality) {
            guard let engine = haptics.createEngine(withLocality: motor.locality) else { continue }
            do {
                try engine.start()
            } catch {
                continue
            }
            engine.stoppedHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.channels[motor] = nil
                }
            }
            engine.resetHandler = { [weak self] in
                DispatchQueue.main.async {
                    self?.restart(motor)
                }
            }
            channels[motor] = Channel(engine: engine)
        }
    }

    func detach() {
        for channel in channels.values {
            try? channel.player?.stop(atTime: CHHapticTimeImmediate)
            channel.engine.stop()
        }
        channels.removeAll()
    }

    func setAmplitude(_ amplitude: UInt16, for motor: Motor) {
        guard var channel = channels[motor] else { return }

        if amplitude == 0 {
            if channel.isPlaying {
                try? channel.player?.stop(atTime: CHHapticTimeImmediate)
                channel.isPlaying = false
            }
            channels[motor] = channel
            return
        }

        if channel.player == nil {
            channel.player = makePlayer(engine: channel.engine)
        }
        guard let player = channel.player else {
            channels[motor] = channel
            return
        }

        let parameter = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: Float(amplitude) / 65535.0,
            relativeTime: 0
        )
        do {
            try player.sendParameters([parameter], atTime: CHHapticTimeImmediate)
        } catch {
            channels[motor] = channel
            return
        }

        if !channel.isPlaying {
            do {
                try player.start(atTime: CHHapticTimeImmediate)
                channel.isPlaying = true
            } catch {
                channel.player = nil
            }
        }
        channels[motor] = channel
    }

    private func restart(_ motor: Motor) {
        guard var channel = channels[motor] else { return }
        do {
            try channel.engine.start()
        } catch {
            channels[motor] = nil
            return
        }
        channel.player = nil
        channel.isPlaying = false
        channels[motor] = channel
    }

    private func makePlayer(engine: CHHapticEngine) -> (any CHHapticPatternPlayer)? {
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [intensity],
            relativeTime: 0,
            duration: TimeInterval(GCHapticDurationInfinite)
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            return try engine.makePlayer(with: pattern)
        } catch {
            return nil
        }
    }
}
