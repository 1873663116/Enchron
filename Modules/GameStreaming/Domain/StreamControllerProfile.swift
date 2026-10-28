import Foundation

public enum StreamControllerKind: UInt8, Sendable, Equatable {
    case unknown = 0
    case xbox = 1
    case playStation = 2
    case nintendo = 3
    case steam = 4
}

public struct StreamControllerCapabilities: OptionSet, Sendable, Equatable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let analogTriggers = StreamControllerCapabilities(rawValue: 0x01)
    public static let rumble = StreamControllerCapabilities(rawValue: 0x02)
    public static let triggerRumble = StreamControllerCapabilities(rawValue: 0x04)
    public static let touchpad = StreamControllerCapabilities(rawValue: 0x08)
    public static let accelerometer = StreamControllerCapabilities(rawValue: 0x10)
    public static let gyroscope = StreamControllerCapabilities(rawValue: 0x20)
    public static let battery = StreamControllerCapabilities(rawValue: 0x40)
    public static let indicatorLight = StreamControllerCapabilities(rawValue: 0x80)
}

public struct StreamControllerArrival: Sendable, Equatable {
    public var controllerNumber: UInt8
    public var activeGamepadMask: UInt16
    public var kind: StreamControllerKind
    public var supportedButtons: Int32
    public var capabilities: StreamControllerCapabilities

    public init(
        controllerNumber: UInt8,
        activeGamepadMask: UInt16,
        kind: StreamControllerKind,
        supportedButtons: Int32,
        capabilities: StreamControllerCapabilities
    ) {
        self.controllerNumber = controllerNumber
        self.activeGamepadMask = activeGamepadMask
        self.kind = kind
        self.supportedButtons = supportedButtons
        self.capabilities = capabilities
    }
}

public enum StreamControllerFeedback: Sendable, Equatable {
    case rumble(controllerNumber: UInt16, lowFrequency: UInt16, highFrequency: UInt16)
    case triggerRumble(controllerNumber: UInt16, leftTrigger: UInt16, rightTrigger: UInt16)
    case motionRequest(controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16)
    case indicatorLight(controllerNumber: UInt16, red: UInt8, green: UInt8, blue: UInt8)
}
