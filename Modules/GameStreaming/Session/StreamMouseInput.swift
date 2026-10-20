import Foundation
import GameController

public struct StreamScrollAccumulator: Equatable, Sendable {
    private var pending: Float = 0

    public init() {}

    public mutating func clicks(for axisValue: Float) -> Int32 {
        pending += axisValue
        let whole = pending.rounded(.towardZero)
        guard whole != 0 else { return 0 }
        pending -= whole
        return Int32(clamping: Int(whole))
    }
}

/// Owns the external mouse while a session is active.
///
/// A connected mouse normally drives the system pointer, so the window's gaze
/// layer never sees it as a pointer position. GameController still delivers the
/// raw deltas and button states, and those are what the host needs: the session
/// forwards movement, buttons and the wheel from here instead of asking the
/// gesture layer for an absolute position.
///
/// GameController delivers these callbacks on the main queue, so start and stop
/// are main-thread calls and this owner needs no cross-thread lock.
public final class StreamMouseInput: NSObject {
    public static let leftButtonCode: Int32 = 0x01
    public static let middleButtonCode: Int32 = 0x02
    public static let rightButtonCode: Int32 = 0x03

    private var mouse: GCMouse?
    private var accumulator = StreamScrollAccumulator()
    private var onMove: (@Sendable (Int32, Int32) -> Void)?
    private var onButton: (@Sendable (Int32, Bool) -> Void)?
    private var onScrollClicks: (@Sendable (Int32) -> Void)?
    private var onPresence: (@Sendable (Bool) -> Void)?

    public override init() {
        super.init()
    }

    public static func connected() -> Bool {
        GCMouse.mice().contains { $0.mouseInput != nil }
    }

    public func start(
        onMove: @escaping @Sendable (Int32, Int32) -> Void,
        onButton: @escaping @Sendable (Int32, Bool) -> Void,
        onScrollClicks: @escaping @Sendable (Int32) -> Void,
        onPresence: @escaping @Sendable (Bool) -> Void
    ) {
        stop()
        self.onMove = onMove
        self.onButton = onButton
        self.onScrollClicks = onScrollClicks
        self.onPresence = onPresence
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mouseDidConnect(_:)),
            name: .GCMouseDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mouseDidDisconnect(_:)),
            name: .GCMouseDidDisconnect,
            object: nil
        )
        attachCurrentMouse(reportPresence: true)
    }

    public func stop() {
        NotificationCenter.default.removeObserver(self, name: .GCMouseDidConnect, object: nil)
        NotificationCenter.default.removeObserver(self, name: .GCMouseDidDisconnect, object: nil)
        detach(reportPresence: false)
        onMove = nil
        onButton = nil
        onScrollClicks = nil
        onPresence = nil
    }

    @objc private func mouseDidConnect(_ notification: Notification) {
        guard mouse == nil, let connected = notification.object as? GCMouse else { return }
        attach(connected)
    }

    @objc private func mouseDidDisconnect(_ notification: Notification) {
        guard let departing = notification.object as? GCMouse, departing === mouse else { return }
        detach(reportPresence: true)
        attachCurrentMouse(reportPresence: true)
    }

    private func attachCurrentMouse(reportPresence: Bool) {
        guard mouse == nil, let candidate = GCMouse.mice().first(where: { $0.mouseInput != nil }) else {
            return
        }
        attach(candidate, reportPresence: reportPresence)
    }

    private func attach(_ candidate: GCMouse, reportPresence: Bool = true) {
        guard let input = candidate.mouseInput else { return }
        mouse = candidate
        accumulator = StreamScrollAccumulator()
        input.mouseMovedHandler = { [weak self] _, deltaX, deltaY in
            self?.handleMove(deltaX: deltaX, deltaY: deltaY)
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.onButton?(Self.leftButtonCode, pressed)
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.onButton?(Self.rightButtonCode, pressed)
        }
        input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.onButton?(Self.middleButtonCode, pressed)
        }
        input.scroll.valueChangedHandler = { [weak self] _, _, yValue in
            self?.handleScroll(yValue)
        }
        if reportPresence {
            onPresence?(true)
        }
    }

    private func detach(reportPresence: Bool) {
        if let input = mouse?.mouseInput {
            input.mouseMovedHandler = nil
            input.leftButton.pressedChangedHandler = nil
            input.rightButton?.pressedChangedHandler = nil
            input.middleButton?.pressedChangedHandler = nil
            input.scroll.valueChangedHandler = nil
        }
        let wasAttached = mouse != nil
        mouse = nil
        accumulator = StreamScrollAccumulator()
        if reportPresence, wasAttached {
            onPresence?(false)
        }
    }

    private func handleMove(deltaX: Float, deltaY: Float) {
        let dx = Int32(deltaX.rounded())
        let dy = Int32(deltaY.rounded())
        guard dx != 0 || dy != 0 else { return }
        onMove?(dx, dy)
    }

    private func handleScroll(_ yValue: Float) {
        let clicks = accumulator.clicks(for: yValue)
        guard clicks != 0 else { return }
        onScrollClicks?(clicks)
    }
}
