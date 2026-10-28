#if DEBUG
import Foundation

/// Turns the test channel's string arguments into the values the session takes
/// for an injected controller profile or a host feedback event.
///
/// Kept apart from both the channel and the model so the parsing can be checked
/// without a running session: a simulator has no GameController and no host, so
/// these arguments are the only way those paths can be exercised there.
public enum StreamDebugInjection {
    public static func controllerKind(_ raw: String) -> StreamControllerKind {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "xbox": .xbox
        case "playstation", "ps", "dualsense", "dualshock": .playStation
        case "nintendo": .nintendo
        case "steam": .steam
        default: .unknown
        }
    }

    /// Accepts the capability names the protocol knows, a comma separated list
    /// of them, or the raw bit field as `0x…`.
    public static func capabilities(_ raw: String) -> StreamControllerCapabilities {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("0x"),
           let value = UInt16(trimmed.dropFirst(2), radix: 16) {
            return StreamControllerCapabilities(rawValue: value)
        }
        var result: StreamControllerCapabilities = []
        for token in trimmed.split(separator: ",") {
            switch token.trimmingCharacters(in: .whitespaces).lowercased() {
            case "analogtriggers", "analog": result.insert(.analogTriggers)
            case "rumble": result.insert(.rumble)
            case "triggerrumble": result.insert(.triggerRumble)
            case "touchpad": result.insert(.touchpad)
            case "accelerometer", "acceleration": result.insert(.accelerometer)
            case "gyroscope", "rotation": result.insert(.gyroscope)
            case "battery": result.insert(.battery)
            case "indicatorlight", "light", "led": result.insert(.indicatorLight)
            case "all":
                result = [
                    .analogTriggers, .rumble, .triggerRumble, .touchpad,
                    .accelerometer, .gyroscope, .battery, .indicatorLight
                ]
            default: break
            }
        }
        return result
    }

    /// Accepts up to eleven button names or the raw bit field as `0x…`.
    public static func buttons(_ raw: String) -> Int32 {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("0x"),
           let value = Int32(trimmed.dropFirst(2), radix: 16) {
            return value
        }
        var mask: Int32 = 0
        for token in trimmed.split(separator: ",") {
            guard let button = StreamGamepadButton(
                rawValue: token.trimmingCharacters(in: .whitespaces)
            ) else { continue }
            mask |= StreamGamepadMapping.buttonFlags([button], swapABXYButtons: false)
        }
        return mask
    }

    public static func arrival(
        controllerNumber: UInt8 = 0,
        activeGamepadMask: UInt16 = 1,
        kind: String,
        capabilities: String,
        buttons: String
    ) -> StreamControllerArrival {
        StreamControllerArrival(
            controllerNumber: controllerNumber,
            activeGamepadMask: activeGamepadMask,
            kind: controllerKind(kind),
            supportedButtons: Self.buttons(buttons),
            capabilities: Self.capabilities(capabilities)
        )
    }

    /// One feedback case per call. A missing argument yields `nil` rather than a
    /// zero, because a zero amplitude or an off channel would read as a real host
    /// request in the probes.
    public static func feedback(type: String, args: [String: String]) -> StreamControllerFeedback? {
        func number(_ key: String) -> Int? {
            args[key].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }
        switch type.trimmingCharacters(in: .whitespaces).lowercased() {
        case "rumble":
            guard let low = number("low"), let high = number("high") else { return nil }
            return .rumble(
                controllerNumber: 0,
                lowFrequency: UInt16(clamping: low),
                highFrequency: UInt16(clamping: high)
            )
        case "trigger", "triggerrumble":
            guard let left = number("left"), let right = number("right") else { return nil }
            return .triggerRumble(
                controllerNumber: 0,
                leftTrigger: UInt16(clamping: left),
                rightTrigger: UInt16(clamping: right)
            )
        case "motion", "motionrequest":
            guard let motionType = number("motionType") ?? number("type"),
                  let rate = number("rate")
            else { return nil }
            return .motionRequest(
                controllerNumber: 0,
                motionType: UInt8(clamping: motionType),
                reportRateHz: UInt16(clamping: rate)
            )
        case "light", "indicatorlight":
            guard let red = number("r"), let green = number("g"), let blue = number("b") else {
                return nil
            }
            return .indicatorLight(
                controllerNumber: 0,
                red: UInt8(clamping: red),
                green: UInt8(clamping: green),
                blue: UInt8(clamping: blue)
            )
        default:
            return nil
        }
    }
}
#endif
