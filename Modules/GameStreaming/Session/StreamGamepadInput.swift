import Foundation
import GameController

public enum StreamGamepadButton: String, CaseIterable, Sendable {
    case a
    case b
    case x
    case y
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case leftShoulder
    case rightShoulder
    case leftThumbstickButton
    case rightThumbstickButton
    case menu
    case options
}

public struct StreamGamepadSticks: Equatable, Sendable {
    public var leftX: Int16
    public var leftY: Int16
    public var rightX: Int16
    public var rightY: Int16

    public init(leftX: Int16 = 0, leftY: Int16 = 0, rightX: Int16 = 0, rightY: Int16 = 0) {
        self.leftX = leftX
        self.leftY = leftY
        self.rightX = rightX
        self.rightY = rightY
    }

    public static let neutral = StreamGamepadSticks()
}

public struct StreamGamepadState: Equatable, Sendable {
    public var buttons: Set<StreamGamepadButton>
    public var leftTrigger: UInt8
    public var rightTrigger: UInt8
    public var sticks: StreamGamepadSticks

    public init(
        buttons: Set<StreamGamepadButton> = [],
        leftTrigger: UInt8 = 0,
        rightTrigger: UInt8 = 0,
        sticks: StreamGamepadSticks = .neutral
    ) {
        self.buttons = buttons
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
        self.sticks = sticks
    }

    public static let neutral = StreamGamepadState()
}

public enum StreamGamepadMapping {
    public static let aFlag: Int32 = 0x1000
    public static let bFlag: Int32 = 0x2000
    public static let xFlag: Int32 = 0x4000
    public static let yFlag: Int32 = 0x8000
    public static let dpadUpFlag: Int32 = 0x0001
    public static let dpadDownFlag: Int32 = 0x0002
    public static let dpadLeftFlag: Int32 = 0x0004
    public static let dpadRightFlag: Int32 = 0x0008
    public static let leftShoulderFlag: Int32 = 0x0100
    public static let rightShoulderFlag: Int32 = 0x0200
    public static let menuFlag: Int32 = 0x0010
    public static let optionsFlag: Int32 = 0x0020
    public static let leftThumbstickButtonFlag: Int32 = 0x0040
    public static let rightThumbstickButtonFlag: Int32 = 0x0080

    public static func buttonFlags(
        _ buttons: Set<StreamGamepadButton>,
        swapABXYButtons: Bool
    ) -> Int32 {
        var flags: Int32 = 0
        for button in buttons {
            flags |= flag(for: button, swapABXYButtons: swapABXYButtons)
        }
        return flags
    }

    private static func flag(for button: StreamGamepadButton, swapABXYButtons: Bool) -> Int32 {
        switch button {
        case .a: swapABXYButtons ? bFlag : aFlag
        case .b: swapABXYButtons ? aFlag : bFlag
        case .x: swapABXYButtons ? yFlag : xFlag
        case .y: swapABXYButtons ? xFlag : yFlag
        case .dpadUp: dpadUpFlag
        case .dpadDown: dpadDownFlag
        case .dpadLeft: dpadLeftFlag
        case .dpadRight: dpadRightFlag
        case .leftShoulder: leftShoulderFlag
        case .rightShoulder: rightShoulderFlag
        case .leftThumbstickButton: leftThumbstickButtonFlag
        case .rightThumbstickButton: rightThumbstickButtonFlag
        case .menu: menuFlag
        case .options: optionsFlag
        }
    }
}

/// GameController delivers input and connection callbacks on the main queue, so
/// start and stop are main-thread calls and this owner needs no cross-thread lock.
public final class StreamGamepadInput: NSObject {
    private var controller: GCController?
    private var onState: (@Sendable (StreamGamepadState) -> Void)?
    private var onPresence: (@Sendable (Bool) -> Void)?

    public override init() {
        super.init()
    }

    public static func connectedMask() -> Int {
        GCController.controllers().contains { $0.extendedGamepad != nil } ? 1 : 0
    }

    public func start(
        onState: @escaping @Sendable (StreamGamepadState) -> Void,
        onPresence: @escaping @Sendable (Bool) -> Void
    ) {
        stop()
        self.onState = onState
        self.onPresence = onPresence
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidConnect(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidDisconnect(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        attachCurrentController(reportPresence: true)
    }

    public func stop() {
        NotificationCenter.default.removeObserver(self, name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.removeObserver(self, name: .GCControllerDidDisconnect, object: nil)
        detachController(reportPresence: false)
        onState = nil
        onPresence = nil
    }

    @objc private func controllerDidConnect(_ notification: Notification) {
        guard controller == nil, let connected = notification.object as? GCController else { return }
        attach(connected, reportPresence: true)
    }

    @objc private func controllerDidDisconnect(_ notification: Notification) {
        guard let departing = notification.object as? GCController,
              departing === controller else { return }
        detachController(reportPresence: true)
        attachCurrentController(reportPresence: true)
    }

    private func attachCurrentController(reportPresence: Bool) {
        guard controller == nil,
              let candidate = GCController.controllers().first(where: { $0.extendedGamepad != nil })
        else { return }
        attach(candidate, reportPresence: reportPresence)
    }

    private func attach(_ candidate: GCController, reportPresence: Bool) {
        guard let gamepad = candidate.extendedGamepad else { return }
        candidate.playerIndex = .index1
        controller = candidate
        gamepad.valueChangedHandler = { [weak self] gamepad, _ in
            self?.emit(gamepad)
        }
        if reportPresence {
            onPresence?(true)
        }
        emit(gamepad)
    }

    private func detachController(reportPresence: Bool) {
        guard let controller else { return }
        controller.extendedGamepad?.valueChangedHandler = nil
        controller.playerIndex = .indexUnset
        self.controller = nil
        if reportPresence {
            onPresence?(false)
            onState?(.neutral)
        }
    }

    private func emit(_ gamepad: GCExtendedGamepad?) {
        guard let gamepad, let onState else { return }
        var buttons: Set<StreamGamepadButton> = []
        if gamepad.buttonA.isPressed { buttons.insert(.a) }
        if gamepad.buttonB.isPressed { buttons.insert(.b) }
        if gamepad.buttonX.isPressed { buttons.insert(.x) }
        if gamepad.buttonY.isPressed { buttons.insert(.y) }
        if gamepad.dpad.up.isPressed { buttons.insert(.dpadUp) }
        if gamepad.dpad.down.isPressed { buttons.insert(.dpadDown) }
        if gamepad.dpad.left.isPressed { buttons.insert(.dpadLeft) }
        if gamepad.dpad.right.isPressed { buttons.insert(.dpadRight) }
        if gamepad.leftShoulder.isPressed { buttons.insert(.leftShoulder) }
        if gamepad.rightShoulder.isPressed { buttons.insert(.rightShoulder) }
        if gamepad.leftThumbstickButton?.isPressed == true { buttons.insert(.leftThumbstickButton) }
        if gamepad.rightThumbstickButton?.isPressed == true { buttons.insert(.rightThumbstickButton) }
        if gamepad.buttonMenu.isPressed { buttons.insert(.menu) }
        if gamepad.buttonOptions?.isPressed == true { buttons.insert(.options) }

        onState(StreamGamepadState(
            buttons: buttons,
            leftTrigger: Self.triggerValue(gamepad.leftTrigger.value),
            rightTrigger: Self.triggerValue(gamepad.rightTrigger.value),
            sticks: StreamGamepadSticks(
                leftX: Self.axisValue(gamepad.leftThumbstick.xAxis.value),
                leftY: Self.axisValue(gamepad.leftThumbstick.yAxis.value),
                rightX: Self.axisValue(gamepad.rightThumbstick.xAxis.value),
                rightY: Self.axisValue(gamepad.rightThumbstick.yAxis.value)
            )
        ))
    }

    private static func triggerValue(_ value: Float) -> UInt8 {
        UInt8(clamping: Int((value * 255).rounded()))
    }

    private static func axisValue(_ value: Float) -> Int16 {
        Int16(clamping: Int((value * 32_767).rounded()))
    }
}
