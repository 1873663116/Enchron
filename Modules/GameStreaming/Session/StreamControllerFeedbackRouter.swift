import Foundation
import GameController

/// Owns everything the host pushes back at a controller: rumble, motion
/// sampling, indicator light and battery reporting.
///
/// Entry points that touch GameController run on the main queue, which is where
/// GameController delivers its callbacks. Host requests arrive on the network
/// thread, so `handle` crosses to the main queue first.
final class StreamControllerFeedbackRouter: @unchecked Sendable {
    private enum MotionType {
        static let acceleration: UInt8 = 0x01
        static let rotation: UInt8 = 0x02
    }

    private enum BatteryState {
        static let unknown: UInt8 = 0x00
        static let discharging: UInt8 = 0x02
        static let charging: UInt8 = 0x03
        static let full: UInt8 = 0x05
    }

    var sendMotion: (@Sendable (UInt8, UInt8, Float, Float, Float) -> Void)?
    var sendBattery: (@Sendable (UInt8, UInt8, UInt8) -> Void)?

    private let haptics = StreamControllerHaptics()
    private var controller: GCController?
    private var accelerationTimer: Timer?
    private var rotationTimer: Timer?
    private var batteryTimer: Timer?
    private var lastAcceleration = GCAcceleration()
    private var lastRotation = GCRotationRate()
    private var lastBatteryState: GCDeviceBattery.State?
    private var lastBatteryLevel: Float?

    func attach(to controller: GCController?) {
        detach()
        guard let controller else { return }
        self.controller = controller
        haptics.attach(to: controller)
        startBatteryReporting()
    }

    func detach() {
        accelerationTimer?.invalidate()
        accelerationTimer = nil
        rotationTimer?.invalidate()
        rotationTimer = nil
        batteryTimer?.invalidate()
        batteryTimer = nil
        deactivateMotionSensorsIfNeeded()
        haptics.detach()
        controller = nil
        lastBatteryState = nil
        lastBatteryLevel = nil
    }

    func reportCurrentBattery() {
        reportBattery()
    }

    func handle(_ feedback: StreamControllerFeedback) {
        DispatchQueue.main.async {
            self.apply(feedback)
        }
    }

    private func apply(_ feedback: StreamControllerFeedback) {
        switch feedback {
        case .rumble(_, let lowFrequency, let highFrequency):
            StreamSessionProbes.record(
                "gamepad rumble recv low=\(lowFrequency) high=\(highFrequency)",
                retention: .evidence
            )
            haptics.setAmplitude(lowFrequency, for: .lowFrequency)
            haptics.setAmplitude(highFrequency, for: .highFrequency)
            StreamSessionProbes.record(
                "gamepad rumble applied low=\(lowFrequency) high=\(highFrequency)",
                retention: .evidence
            )
        case .triggerRumble(_, let leftTrigger, let rightTrigger):
            haptics.setAmplitude(leftTrigger, for: .leftTrigger)
            haptics.setAmplitude(rightTrigger, for: .rightTrigger)
            StreamSessionProbes.record(
                "gamepad trigger rumble applied left=\(leftTrigger) right=\(rightTrigger)",
                retention: .evidence
            )
        case .motionRequest(_, let motionType, let reportRateHz):
            applyMotionRequest(motionType: motionType, reportRateHz: reportRateHz)
        case .indicatorLight(_, let red, let green, let blue):
            applyIndicatorLight(red: red, green: green, blue: blue)
        }
    }

    private func applyMotionRequest(motionType: UInt8, reportRateHz: UInt16) {
        switch motionType {
        case MotionType.acceleration:
            accelerationTimer?.invalidate()
            accelerationTimer = nil
            guard reportRateHz > 0, controller?.motion?.hasGravityAndUserAcceleration == true else {
                deactivateMotionSensorsIfNeeded()
                return
            }
            lastAcceleration = GCAcceleration()
            accelerationTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0 / Double(reportRateHz),
                repeats: true
            ) { [weak self] _ in
                self?.sampleAcceleration()
            }
            StreamSessionProbes.record(
                "gamepad motion sampling type=acceleration rate=\(reportRateHz)",
                retention: .evidence
            )
        case MotionType.rotation:
            rotationTimer?.invalidate()
            rotationTimer = nil
            guard reportRateHz > 0, controller?.motion?.hasRotationRate == true else {
                deactivateMotionSensorsIfNeeded()
                return
            }
            lastRotation = GCRotationRate()
            rotationTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0 / Double(reportRateHz),
                repeats: true
            ) { [weak self] _ in
                self?.sampleRotation()
            }
            StreamSessionProbes.record(
                "gamepad motion sampling type=rotation rate=\(reportRateHz)",
                retention: .evidence
            )
        default:
            return
        }
        activateMotionSensorsIfNeeded()
    }

    private func sampleAcceleration() {
        guard let motion = controller?.motion else { return }
        let sample = motion.acceleration
        guard sample.x != lastAcceleration.x
            || sample.y != lastAcceleration.y
            || sample.z != lastAcceleration.z
        else {
            return
        }
        lastAcceleration = sample
        sendMotion?(
            0,
            MotionType.acceleration,
            Float(sample.x * -9.80665),
            Float(sample.y * -9.80665),
            Float(sample.z * -9.80665)
        )
    }

    private func sampleRotation() {
        guard let motion = controller?.motion else { return }
        let sample = motion.rotationRate
        guard sample.x != lastRotation.x
            || sample.y != lastRotation.y
            || sample.z != lastRotation.z
        else {
            return
        }
        lastRotation = sample
        sendMotion?(
            0,
            MotionType.rotation,
            Float(sample.x * 57.2957795),
            Float(sample.z * 57.2957795),
            Float(sample.y * -57.2957795)
        )
    }

    private func activateMotionSensorsIfNeeded() {
        guard let motion = controller?.motion, motion.sensorsRequireManualActivation else { return }
        motion.sensorsActive = accelerationTimer != nil || rotationTimer != nil
    }

    private func deactivateMotionSensorsIfNeeded() {
        guard let motion = controller?.motion, motion.sensorsRequireManualActivation else { return }
        if accelerationTimer == nil, rotationTimer == nil {
            motion.sensorsActive = false
        }
    }

    private func applyIndicatorLight(red: UInt8, green: UInt8, blue: UInt8) {
        guard let light = controller?.light else { return }
        light.color = GCColor(
            red: Float(red) / 255.0,
            green: Float(green) / 255.0,
            blue: Float(blue) / 255.0
        )
        StreamSessionProbes.record(
            "gamepad indicator light applied rgb=\(red),\(green),\(blue)",
            retention: .evidence
        )
    }

    private func startBatteryReporting() {
        guard controller?.battery != nil else { return }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.reportBattery()
        }
        reportBattery()
    }

    private func reportBattery() {
        guard let battery = controller?.battery else { return }
        guard battery.batteryState != lastBatteryState
            || battery.batteryLevel != lastBatteryLevel
        else {
            return
        }
        lastBatteryState = battery.batteryState
        lastBatteryLevel = battery.batteryLevel
        let state: UInt8 = switch battery.batteryState {
        case .discharging: BatteryState.discharging
        case .charging: BatteryState.charging
        case .full: BatteryState.full
        default: BatteryState.unknown
        }
        let percentage = UInt8(max(0, min(100, battery.batteryLevel * 100)))
        sendBattery?(0, state, percentage)
        StreamSessionProbes.record(
            "gamepad battery reported state=\(state) level=\(percentage)",
            retention: .evidence
        )
    }
}
