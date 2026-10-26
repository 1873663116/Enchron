import Foundation
import GameController
import SwiftUI
import UIKit

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
    case special
    case paddle1
    case paddle2
    case paddle3
    case paddle4
    case share
    case touchpad
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
    public static let specialFlag: Int32 = 0x0400
    public static let paddle1Flag: Int32 = 0x010000
    public static let paddle2Flag: Int32 = 0x020000
    public static let paddle3Flag: Int32 = 0x040000
    public static let paddle4Flag: Int32 = 0x080000
    public static let touchpadFlag: Int32 = 0x100000
    public static let miscFlag: Int32 = 0x200000

    public static let baseButtonFlags: Int32 =
        aFlag | bFlag | xFlag | yFlag
        | dpadUpFlag | dpadDownFlag | dpadLeftFlag | dpadRightFlag
        | leftShoulderFlag | rightShoulderFlag
        | leftThumbstickButtonFlag | rightThumbstickButtonFlag
        | menuFlag | optionsFlag

    /// Two base buttons a controller may lack are synthesized from combinations
    /// so every host still sees a complete pad: LB plus Start sends Options when
    /// no Options button exists, and RB plus Start (or Start plus Options when
    /// Options is physical) sends Home when no Home button exists. The
    /// combination consumes the buttons it uses, and releasing either one drops
    /// the synthesized button because the whole state is rebuilt per call.
    public static func combinedButtons(
        _ buttons: Set<StreamGamepadButton>,
        hasPhysicalOptions: Bool,
        hasPhysicalHome: Bool
    ) -> Set<StreamGamepadButton> {
        guard buttons.contains(.menu) else { return buttons }
        var combined = buttons
        if !hasPhysicalOptions, combined.contains(.leftShoulder) {
            combined.insert(.options)
            combined.remove(.menu)
            combined.remove(.leftShoulder)
            return combined
        }
        guard !hasPhysicalHome else { return combined }
        if !hasPhysicalOptions, combined.contains(.rightShoulder) {
            combined.insert(.special)
            combined.remove(.menu)
            combined.remove(.rightShoulder)
        } else if hasPhysicalOptions, combined.contains(.options) {
            combined.insert(.special)
            combined.remove(.menu)
            combined.remove(.options)
        }
        return combined
    }

    /// Triggers travel as one byte and sticks as a signed sixteen bit value. The
    /// host expects the upstream ranges, which the scaling below reproduces.
    public static func triggerByte(_ value: Float) -> UInt8 {
        UInt8(clamping: Int(value * 255))
    }

    public static func axisValue(_ value: Float) -> Int16 {
        Int16(clamping: Int(value * 32_766))
    }

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
        case .special: specialFlag
        case .paddle1: paddle1Flag
        case .paddle2: paddle2Flag
        case .paddle3: paddle3Flag
        case .paddle4: paddle4Flag
        case .share: miscFlag
        case .touchpad: touchpadFlag
        }
    }
}

/// GameController delivers input and connection callbacks on the main queue, so
/// start and stop are main-thread calls and this owner needs no cross-thread lock.
public final class StreamGamepadInput: NSObject, @unchecked Sendable {
    private var controller: GCController?
    private var controllerProfile: StreamControllerArrival?
    private var onState: (@Sendable (StreamGamepadState) -> Void)?
    private var onProfile: (@Sendable (StreamControllerArrival?) -> Void)?
    private var onTouch: (@Sendable (UInt8, UInt32, Float, Float, Float) -> Void)?
    private let feedback = StreamControllerFeedbackRouter()
    private struct TouchState {
        var x: Float = 0
        var y: Float = 0
    }

    private var primaryTouch = TouchState()
    private var secondaryTouch = TouchState()
    private var legacyPauseActive = false
#if DEBUG
    private let rateProbe = StreamGamepadRateProbe()
#endif

    public override init() {
        super.init()
    }

    public func resendProfile() {
        guard let controllerProfile else { return }
        onProfile?(controllerProfile)
    }

    public func configureFeedback(
        sendMotion: @escaping @Sendable (UInt8, UInt8, Float, Float, Float) -> Void,
        sendBattery: @escaping @Sendable (UInt8, UInt8, UInt8) -> Void
    ) {
        feedback.sendMotion = sendMotion
        feedback.sendBattery = sendBattery
    }

    public func reportCurrentBattery() {
        feedback.reportCurrentBattery()
    }

    public func handle(_ event: StreamControllerFeedback) {
        feedback.handle(event)
    }

    private func registerTouchpadHandlers(for candidate: GCController) {
        if let dualShock = candidate.extendedGamepad as? GCDualShockGamepad {
            dualShock.touchpadPrimary.valueChangedHandler = { [weak self] _, x, y in
                self?.handleTouch(index: 0, x: x, y: y)
            }
            dualShock.touchpadSecondary.valueChangedHandler = { [weak self] _, x, y in
                self?.handleTouch(index: 1, x: x, y: y)
            }
        }
        if let dualSense = candidate.extendedGamepad as? GCDualSenseGamepad {
            dualSense.touchpadPrimary.valueChangedHandler = { [weak self] _, x, y in
                self?.handleTouch(index: 0, x: x, y: y)
            }
            dualSense.touchpadSecondary.valueChangedHandler = { [weak self] _, x, y in
                self?.handleTouch(index: 1, x: x, y: y)
            }
        }
    }

    /// Old MFi pads have no Options button and deliver Start as an instant press
    /// through the legacy pause handler, too short for the host to register.
    /// Holding it for a hundred milliseconds turns that into a usable press.
    private func registerLegacyPauseHandler(for candidate: GCController) {
        guard let gamepad = candidate.extendedGamepad, gamepad.buttonOptions == nil else { return }
        candidate.controllerPausedHandler = { [weak self] _ in
            guard let self else { return }
            self.legacyPauseActive = true
            self.emit(self.controller?.extendedGamepad)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                self.legacyPauseActive = false
                self.emit(self.controller?.extendedGamepad)
            }
        }
    }

    private func handleTouch(index: Int, x: Float, y: Float) {
        let normalizedX = (1 + x) * 0.5
        let normalizedY = 1 - (1 + y) * 0.5
        var state = index == 0 ? primaryTouch : secondaryTouch
        let pointerId = UInt32(index)
        if (state.x != 0 || state.y != 0) && x == 0 && y == 0 {
            onTouch?(Self.touchEventUp, pointerId, normalizedX, normalizedY, 1)
            StreamSessionProbes.record(
                "gamepad touchpad index=\(index) event=up",
                retention: .evidence
            )
        } else if x != 0 || y != 0 {
            if state.x == 0 && state.y == 0 {
                onTouch?(Self.touchEventDown, pointerId, normalizedX, normalizedY, 1)
                StreamSessionProbes.record(
                    "gamepad touchpad index=\(index) event=down",
                    retention: .evidence
                )
            } else if state.x != x || state.y != y {
                onTouch?(Self.touchEventMove, pointerId, normalizedX, normalizedY, 1)
            }
        }
        state.x = x
        state.y = y
        if index == 0 {
            primaryTouch = state
        } else {
            secondaryTouch = state
        }
    }

    private static let touchEventDown: UInt8 = 0x01
    private static let touchEventUp: UInt8 = 0x02
    private static let touchEventMove: UInt8 = 0x03

    private static func arrival(for controller: GCController) -> StreamControllerArrival {
        var capabilities: StreamControllerCapabilities = [.analogTriggers]
        if let haptics = controller.haptics {
            if haptics.supportedLocalities.contains(.handles) {
                capabilities.insert(.rumble)
            }
            if haptics.supportedLocalities.contains(.triggers) {
                capabilities.insert(.triggerRumble)
            }
        }
        if let motion = controller.motion {
            if motion.hasGravityAndUserAcceleration {
                capabilities.insert(.accelerometer)
            }
            if motion.hasRotationRate {
                capabilities.insert(.gyroscope)
            }
        }
        if controller.light != nil {
            capabilities.insert(.indicatorLight)
        }
        if controller.battery != nil {
            capabilities.insert(.battery)
        }
        if controller.physicalInputProfile.dpads[GCInputDualShockTouchpadOne] != nil {
            capabilities.insert(.touchpad)
        }

        var kind: StreamControllerKind = .unknown
        if controller.extendedGamepad is GCXboxGamepad {
            kind = .xbox
        }
        if controller.extendedGamepad is GCDualShockGamepad {
            kind = .playStation
        }
        if controller.extendedGamepad is GCDualSenseGamepad {
            kind = .playStation
        }

        var supportedButtons = StreamGamepadMapping.baseButtonFlags
        let profile = controller.physicalInputProfile
        if controller.extendedGamepad?.buttonHome != nil {
            supportedButtons |= StreamGamepadMapping.specialFlag
        }
        if profile.buttons[GCInputXboxPaddleOne] != nil {
            supportedButtons |= StreamGamepadMapping.paddle1Flag
        }
        if profile.buttons[GCInputXboxPaddleTwo] != nil {
            supportedButtons |= StreamGamepadMapping.paddle2Flag
        }
        if profile.buttons[GCInputXboxPaddleThree] != nil {
            supportedButtons |= StreamGamepadMapping.paddle3Flag
        }
        if profile.buttons[GCInputXboxPaddleFour] != nil {
            supportedButtons |= StreamGamepadMapping.paddle4Flag
        }
        if profile.buttons[GCInputButtonShare] != nil {
            supportedButtons |= StreamGamepadMapping.miscFlag
        }
        if profile.buttons[GCInputDualShockTouchpadButton] != nil {
            supportedButtons |= StreamGamepadMapping.touchpadFlag
        }

        return StreamControllerArrival(
            controllerNumber: 0,
            activeGamepadMask: 1,
            kind: kind,
            supportedButtons: supportedButtons,
            capabilities: capabilities
        )
    }

    public static func connectedMask() -> Int {
        GCController.controllers().contains { $0.extendedGamepad != nil } ? 1 : 0
    }

    public func start(
        onState: @escaping @Sendable (StreamGamepadState) -> Void,
        onProfile: @escaping @Sendable (StreamControllerArrival?) -> Void,
        onTouch: @escaping @Sendable (UInt8, UInt32, Float, Float, Float) -> Void
    ) {
        stop()
        self.onState = onState
        self.onProfile = onProfile
        self.onTouch = onTouch
#if DEBUG
        rateProbe.start()
#endif
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
        onProfile = nil
        onTouch = nil
#if DEBUG
        rateProbe.stop()
#endif
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
        controllerProfile = Self.arrival(for: candidate)
        feedback.attach(to: candidate)
        claimSystemGestures(from: candidate)
        gamepad.valueChangedHandler = { [weak self] gamepad, element in
#if DEBUG
            self?.rateProbe.record(element)
#endif
            if element is GCControllerButtonInput {
                StreamSessionProbes.record(
                    "gamepad button event t=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime))"
                        + " element=\(element.localizedName ?? "unknown")",
                    retention: .evidence
                )
            }
            self?.emit(gamepad)
        }
        registerTouchpadHandlers(for: candidate)
        registerLegacyPauseHandler(for: candidate)
        if reportPresence, let controllerProfile {
            onProfile?(controllerProfile)
        }
        emit(gamepad)
    }

    private func claimSystemGestures(from candidate: GCController) {
        for element in candidate.physicalInputProfile.allElements {
            element.preferredSystemGestureState = .disabled
        }
    }

    private func restoreSystemGestures(_ candidate: GCController) {
        for element in candidate.physicalInputProfile.allElements {
            element.preferredSystemGestureState = .enabled
        }
    }

    private func detachController(reportPresence: Bool) {
        guard let controller else { return }
        restoreSystemGestures(controller)
        controller.extendedGamepad?.valueChangedHandler = nil
        if let dualShock = controller.extendedGamepad as? GCDualShockGamepad {
            dualShock.touchpadPrimary.valueChangedHandler = nil
            dualShock.touchpadSecondary.valueChangedHandler = nil
        }
        if let dualSense = controller.extendedGamepad as? GCDualSenseGamepad {
            dualSense.touchpadPrimary.valueChangedHandler = nil
            dualSense.touchpadSecondary.valueChangedHandler = nil
        }
        controller.controllerPausedHandler = nil
        primaryTouch = TouchState()
        secondaryTouch = TouchState()
        legacyPauseActive = false
        controller.playerIndex = .indexUnset
        feedback.detach()
        self.controller = nil
        self.controllerProfile = nil
        if reportPresence {
            onProfile?(nil)
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
        if gamepad.buttonOptions != nil, gamepad.buttonMenu.isPressed {
            buttons.insert(.menu)
        }
        if legacyPauseActive {
            buttons.insert(.menu)
        }
        if gamepad.buttonOptions?.isPressed == true { buttons.insert(.options) }
        if gamepad.buttonHome?.isPressed == true { buttons.insert(.special) }
        let profile = gamepad.controller?.physicalInputProfile
        if profile?.buttons[GCInputXboxPaddleOne]?.isPressed == true { buttons.insert(.paddle1) }
        if profile?.buttons[GCInputXboxPaddleTwo]?.isPressed == true { buttons.insert(.paddle2) }
        if profile?.buttons[GCInputXboxPaddleThree]?.isPressed == true { buttons.insert(.paddle3) }
        if profile?.buttons[GCInputXboxPaddleFour]?.isPressed == true { buttons.insert(.paddle4) }
        if profile?.buttons[GCInputButtonShare]?.isPressed == true { buttons.insert(.share) }
        if profile?.buttons[GCInputDualShockTouchpadButton]?.isPressed == true {
            buttons.insert(.touchpad)
        }
        buttons = StreamGamepadMapping.combinedButtons(
            buttons,
            hasPhysicalOptions: gamepad.buttonOptions != nil,
            hasPhysicalHome: gamepad.buttonHome != nil
        )

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
        StreamGamepadMapping.triggerByte(value)
    }

    private static func axisValue(_ value: Float) -> Int16 {
        StreamGamepadMapping.axisValue(value)
    }
}

/// Holds the session's claim on physical input.
///
/// visionOS turns game controller input into pinch events unless a view states
/// that it handles controller events itself. The claim only covers the scene the
/// wearer is using: a session that starts in the window and moves to an immersive
/// space needs the claim inside the immersive scene's own hierarchy, and the
/// immersive scene connects after the session starts.
///
/// The claim also hides the system pointer over the picture and asks UIKit for
/// the pointer lock. Without both, the host cursor and the system pointer are
/// drawn at once and the system keeps the edge gestures.
@MainActor
public final class StreamInputCapture {
    public static let shared = StreamInputCapture()

    @MainActor
    private final class Claim {
        let gamepad: GCEventInteraction
        let pointer: UIPointerInteraction
        weak var view: UIView?
        let origin: String

        init(view: UIView, origin: String) {
            self.view = view
            self.origin = origin
            gamepad = GCEventInteraction()
            gamepad.handledEventTypes = .gamepad
            gamepad.receivesEventsInView = false
            pointer = UIPointerInteraction(delegate: StreamInputCapture.hider)
        }
    }

    @MainActor
    private final class PointerHider: NSObject, UIPointerInteractionDelegate {
        func pointerInteraction(
            _ interaction: UIPointerInteraction,
            regionFor request: UIPointerRegionRequest,
            defaultRegion: UIPointerRegion
        ) -> UIPointerRegion? {
            guard let bounds = interaction.view?.bounds, bounds.isEmpty == false else {
                return defaultRegion
            }
            return UIPointerRegion(rect: bounds, identifier: nil)
        }

        func pointerInteraction(
            _ interaction: UIPointerInteraction,
            styleFor region: UIPointerRegion
        ) -> UIPointerStyle? {
            .hidden()
        }
    }

    private static let hider = PointerHider()

    private struct PendingClaim {
        weak var view: UIView?
        let origin: String
    }

    private var claims: [ObjectIdentifier: Claim] = [:]
    private var pending: [PendingClaim] = []
    private var observers: [NSObjectProtocol] = []
    private var immersivePresentation = false
    private var dockStateTimer: Timer?
    private(set) var isActive = false

    private init() {}

    public func start() {
        isActive = true
        Self.swizzlePointerLock()
        installObserversIfNeeded()
        let queued = pending
        pending = []
        for entry in queued {
            guard let view = entry.view else { continue }
            claim(view, origin: entry.origin)
        }
        refreshWindowClaims()
        logWindowInventory()
        requestPointerLock()
    }

    private func logWindowInventory() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for (index, window) in windowScene.windows.enumerated() {
                let root = window.rootViewController.map { String(describing: type(of: $0)) }
                StreamSessionProbes.record(
                    "gamepad window index=\(index)"
                        + " size=\(Int(window.bounds.width))x\(Int(window.bounds.height))"
                        + " hidden=\(window.isHidden)"
                        + " key=\(window.isKeyWindow)"
                        + " level=\(window.windowLevel.rawValue)"
                        + " root=\(root ?? "none")"
                        + " role=\(windowScene.session.role.rawValue)",
                    retention: .evidence
                )
            }
        }
    }

    public func stop() {
        isActive = false
        immersivePresentation = false
        stopDockStateProbe()
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = []
        for claim in claims.values {
            guard let view = claim.view else { continue }
            view.removeInteraction(claim.gamepad)
            view.removeInteraction(claim.pointer)
        }
        claims = [:]
        requestPointerLock()
    }

    public func prepareForImmersivePresentation() {
        guard immersivePresentation == false, isActive else { return }
        for claim in claims.values where claim.origin == "surface" {
            _ = claim.view?.resignFirstResponder()
        }
        releaseAllClaims()
        StreamSessionProbes.record(
            "gamepad presentation prepared claims=\(claims.count)",
            retention: .evidence
        )
    }

    public func enterImmersivePresentation() {
        guard immersivePresentation == false else { return }
        immersivePresentation = true
        guard isActive else { return }
        releaseAllClaims()
        StreamSessionProbes.record(
            "gamepad presentation immersive=true claims=\(claims.count)",
            retention: .evidence
        )
        startDockStateProbe()
        requestPointerLock()
    }

    public func leaveImmersivePresentation() {
        guard immersivePresentation else { return }
        immersivePresentation = false
        guard isActive else { return }
        stopDockStateProbe()
        refreshWindowClaims()
        StreamSessionProbes.record(
            "gamepad presentation immersive=false claims=\(claims.count)",
            retention: .evidence
        )
        requestPointerLock()
    }

    private func startDockStateProbe() {
        stopDockStateProbe()
        dockStateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                StreamInputCapture.shared.recordDockState()
            }
        }
    }

    private func stopDockStateProbe() {
        dockStateTimer?.invalidate()
        dockStateTimer = nil
    }

    private func recordDockState() {
        guard isActive, immersivePresentation else { return }
        var parts: [String] = []
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            let key = windowScene.windows.contains(where: { $0.isKeyWindow })
            parts.append(windowScene.session.role.rawValue + ":key=" + (key ? "1" : "0"))
        }
        StreamSessionProbes.record(
            "gamepad dock state scenes=\(parts.sorted().joined(separator: ","))"
                + " claims=\(claims.count)",
            retention: .evidence
        )
    }

    private func releaseAllClaims() {
        for claim in claims.values {
            guard let view = claim.view else { continue }
            view.removeInteraction(claim.gamepad)
            view.removeInteraction(claim.pointer)
        }
        claims = [:]
    }

    private func refreshWindowClaims() {
        guard isActive, immersivePresentation == false else { return }
        var roots: [UIView] = []
        for claim in claims.values where claim.origin == "surface" {
            guard let window = claim.view?.window,
                  let root = window.rootViewController?.view
            else { continue }
            roots.append(root)
        }
        for root in roots where claims[ObjectIdentifier(root)] == nil {
            claim(root, origin: "window")
        }
        var stale: [ObjectIdentifier] = []
        for (identity, claim) in claims where claim.origin == "window" {
            if roots.contains(where: { ObjectIdentifier($0) == identity }) { continue }
            claim.view?.removeInteraction(claim.gamepad)
            claim.view?.removeInteraction(claim.pointer)
            stale.append(identity)
        }
        for identity in stale {
            claims.removeValue(forKey: identity)
        }
    }

    /// Reports whether this view, or the window's root view, already carries the
    /// session's input claim. Pointer lock is only taken for those views, so the
    /// app's own panels keep the system pointer.
    public func holdsClaim(for view: UIView) -> Bool {
        if claims[ObjectIdentifier(view)] != nil { return true }
        if let root = view.window?.rootViewController?.view {
            return claims[ObjectIdentifier(root)] != nil
        }
        return false
    }

    /// Claims a view supplied by the scene that holds it. The immersive space
    /// renders its own scene without a window hierarchy the app can walk, so its
    /// content adds this claim through a hosted surface.
    public func claim(_ view: UIView, origin: String) {
        guard isActive else {
            if pending.contains(where: { $0.view === view }) == false {
                pending.append(PendingClaim(view: view, origin: origin))
            }
            return
        }
        let identity = ObjectIdentifier(view)
        if claims[identity] == nil {
            let claim = Claim(view: view, origin: origin)
            view.addInteraction(claim.gamepad)
            view.addInteraction(claim.pointer)
            claims[identity] = claim
            let window = view.window
            StreamSessionProbes.record(
                "gamepad claim origin=\(origin) claims=\(claims.count)"
                    + " role=\(window?.windowScene?.session.role.rawValue ?? "none")"
                    + " size=\(Int(window?.bounds.width ?? 0))x\(Int(window?.bounds.height ?? 0))"
                    + " hidden=\(window?.isHidden ?? true)"
                    + " level=\(window?.windowLevel.rawValue ?? 0)",
                retention: .evidence
            )
        }
        requestPointerLock()
        if origin == "surface" {
            refreshWindowClaims()
        }
    }

    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [
            UIScene.didActivateNotification,
            UIScene.willConnectNotification,
            UIScene.didDisconnectNotification,
            UIWindow.didBecomeKeyNotification,
            UIWindow.didBecomeVisibleNotification
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    StreamInputCapture.shared.refreshWindowClaims()
                }
            })
        }
        for name in [Notification.Name.GCControllerDidBecomeCurrent, .GCControllerDidStopBeingCurrent] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { notification in
                StreamSessionProbes.record(
                    "gamepad current \(notification.name.rawValue)"
                        + " t=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime))",
                    retention: .evidence
                )
            })
        }
        observers.append(center.addObserver(
            forName: .GCMouseDidConnect,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                StreamInputCapture.shared.requestPointerLock()
            }
        })
        observers.append(center.addObserver(
            forName: UIPointerLockState.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                StreamInputCapture.shared.requestPointerLock()
            }
        })
    }

    /// Only a full-screen scene can ever honor the lock, and on visionOS that
    /// means the immersive space. Window scenes are never asked, so the lock
    /// subsystem is left untouched while the wearer streams in a window.
    private func requestPointerLock() {
        var states: [String] = []
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            switch windowScene.session.role {
            case .immersiveSpaceApplication, .windowApplication:
                break
            default:
                continue
            }
            for window in windowScene.windows {
                window.rootViewController?.setNeedsUpdateOfPrefersPointerLocked()
            }
            let value: String
            if let state = windowScene.pointerLockState {
                value = state.isLocked ? "locked" : "unlocked"
            } else {
                value = "none"
            }
            states.append("\(windowScene.session.role.rawValue)=\(value)")
        }
        guard isActive, states.isEmpty == false else { return }
        StreamSessionProbes.record(
            "pointer lock requested \(states.joined(separator: ","))",
            retention: .evidence
        )
    }

    private static let swizzleOnce: Void = {
        let original = #selector(getter: UIViewController.prefersPointerLocked)
        let replacement = #selector(getter: UIViewController.enchron_prefersPointerLocked)
        guard let originalMethod = class_getInstanceMethod(UIViewController.self, original),
              let replacementMethod = class_getInstanceMethod(UIViewController.self, replacement)
        else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }()

    private static func swizzlePointerLock() {
        _ = swizzleOnce
    }
}

extension UIViewController {
    @objc dynamic var enchron_prefersPointerLocked: Bool {
        guard StreamInputCapture.shared.isActive, isViewLoaded else {
            return self.enchron_prefersPointerLocked
        }
        guard let scene = view.window?.windowScene else {
            return self.enchron_prefersPointerLocked
        }
        switch scene.session.role {
        case .immersiveSpaceApplication:
            return true
        case .windowApplication:
            return StreamInputCapture.shared.holdsClaim(for: view)
        default:
            return self.enchron_prefersPointerLocked
        }
    }
}

/// A hosted surface that puts the session's input claim inside the scene it is
/// placed in. The immersive space has no window the app can enumerate, so its
/// content carries the claim itself. The surface is placed over the stream
/// picture, takes every synthesized touch, and stays the first responder, so
/// gamepad events resolve to its claim instead of the system's pinch path.
public struct StreamInputSurface: UIViewRepresentable {
    private let wantsFocus: Bool

    public init(wantsFocus: Bool = false) {
        self.wantsFocus = wantsFocus
    }

    public func makeUIView(context: Context) -> StreamInputSurfaceView {
        StreamInputSurfaceView(wantsFocus: wantsFocus)
    }

    public func updateUIView(_ uiView: StreamInputSurfaceView, context: Context) {
        uiView.wantsFocus = wantsFocus
        uiView.refreshClaim()
    }
}

public final class StreamInputSurfaceView: UIView, UIKeyInput {
    var wantsFocus: Bool
    var onKey: ((UIKeyboardHIDUsage, Bool, UIKeyModifierFlags) -> Void)?
    private var focusReclaimTimer: Timer?
    private var hasFocusProbeRecorded = false

    public init(wantsFocus: Bool) {
        self.wantsFocus = wantsFocus
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    public required init?(coder: NSCoder) {
        nil
    }

    public override var canBecomeFocused: Bool { true }
    public override var canBecomeFirstResponder: Bool { wantsFocus }

    public override var inputView: UIView? { UIView() }

    public var hasText: Bool { true }

    public func insertText(_ text: String) {}

    public func deleteBackward() {}

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        self
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isFirstResponder == false {
            becomeFirstResponder()
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !forward(presses, down: true) {
            super.pressesBegan(presses, with: event)
        }
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !forward(presses, down: false) {
            super.pressesEnded(presses, with: event)
        }
    }

    public override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        _ = forward(presses, down: false)
        super.pressesCancelled(presses, with: event)
    }

    private func forward(_ presses: Set<UIPress>, down: Bool) -> Bool {
        guard let onKey else { return false }
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            onKey(key.keyCode, down, key.modifierFlags)
            handled = true
        }
        return handled
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopFocusReclaimTimer()
            return
        }
        refreshClaim()
        reclaimFocus()
        startFocusReclaimTimerIfNeeded()
    }

    func refreshClaim() {
        guard window != nil else { return }
        StreamInputCapture.shared.claim(self, origin: "surface")
    }

    private func reclaimFocus() {
        guard window != nil,
              UIApplication.shared.applicationState == .active,
              isFirstResponder == false
        else {
            recordFocusProbe()
            return
        }
        becomeFirstResponder()
        recordFocusProbe()
    }

    private func recordFocusProbe() {
        guard isFirstResponder, hasFocusProbeRecorded == false else { return }
        hasFocusProbeRecorded = true
        StreamSessionProbes.record(
            "input surface firstResponder",
            retention: .evidence
        )
    }

    private func startFocusReclaimTimerIfNeeded() {
        guard wantsFocus, focusReclaimTimer == nil else { return }
        focusReclaimTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reclaimFocus()
            }
        }
    }

    private func stopFocusReclaimTimer() {
        focusReclaimTimer?.invalidate()
        focusReclaimTimer = nil
    }
}

/// The host of the input surface over the stream picture, in the window and in
/// the immersive space alike. visionOS hands the gamepad claim to the focused
/// first responder's chain: a GCEventViewController keeps controller events
/// decoupled from the UI while its view holds first responder, and the
/// GCEventInteraction on the same view carries the visionOS-specific claim.
public struct StreamFocusedInputCapture: View {
    @FocusState private var inputFocused: Bool
    private let onKey: ((UIKeyboardHIDUsage, Bool, UIKeyModifierFlags) -> Void)?

    public init(
        onKey: ((UIKeyboardHIDUsage, Bool, UIKeyModifierFlags) -> Void)? = nil
    ) {
        self.onKey = onKey
    }

    public var body: some View {
        StreamInputCaptureControllerHost(onKey: onKey)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .focused($inputFocused)
            .handlesGameControllerEvents(matching: .gamepad)
            .onAppear {
                StreamSessionProbes.record(
                    "input capture appeared",
                    retention: .evidence
                )
                inputFocused = true
            }
            .onChange(of: inputFocused) { _, focused in
                StreamSessionProbes.record(
                    "input capture focus=\(focused)",
                    retention: .evidence
                )
                if focused == false {
                    inputFocused = true
                }
            }
    }
}

struct StreamInputCaptureControllerHost: UIViewControllerRepresentable {
    let onKey: ((UIKeyboardHIDUsage, Bool, UIKeyModifierFlags) -> Void)?

    func makeUIViewController(context: Context) -> StreamInputCaptureController {
        let controller = StreamInputCaptureController()
        controller.captureView.onKey = onKey
        return controller
    }

    func updateUIViewController(_ controller: StreamInputCaptureController, context: Context) {
        controller.captureView.onKey = onKey
        controller.refreshClaim()
    }
}

@MainActor
public final class StreamInputCaptureController: GCEventViewController {
    let captureView: StreamInputSurfaceView

    public init() {
        captureView = StreamInputSurfaceView(wantsFocus: true)
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        nil
    }

    public override func loadView() {
        view = captureView
    }

    func refreshClaim() {
        captureView.refreshClaim()
    }
}
