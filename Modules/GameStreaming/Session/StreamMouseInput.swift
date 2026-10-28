import Foundation
import GameController

public struct StreamMouseMotion: Equatable, Sendable {
    private static let speedDivisor: Float = 1.25

    private var pendingX: Float = 0
    private var pendingY: Float = 0

    public init() {}

    public mutating func screenDelta(rawX: Float, rawY: Float) -> (x: Int32, y: Int32) {
        pendingX += rawX / Self.speedDivisor
        pendingY += -rawY / Self.speedDivisor
        let x = pendingX.rounded(.towardZero)
        let y = pendingY.rounded(.towardZero)
        guard x != 0 || y != 0 else { return (0, 0) }
        pendingX -= x
        pendingY -= y
        return (Int32(clamping: Int(x)), Int32(clamping: Int(y)))
    }
}

/// Accumulates raw scroll axis values into the high resolution wheel units the
/// host expects: one whole unit of axis travel becomes one wheel notch, which is
/// twenty high resolution units.
public struct StreamHighResScrollAccumulator: Equatable, Sendable {
    private var pending: Float = 0

    public init() {}

    public mutating func units(for axisValue: Float) -> Int32 {
        pending += axisValue
        let whole = pending.rounded(.towardZero)
        guard whole != 0 else { return 0 }
        pending -= whole
        return Int32(clamping: Int(whole) * 20)
    }
}

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

/// Turns device deltas into a position on the host picture. The device reports
/// movement only, so the client keeps the cursor itself: whole points move the
/// position by one stream pixel and the remainder carries to the next event, so
/// small movements are not dropped. The position is normalized to the stream
/// picture and clamped to it.
public struct StreamAbsoluteCursor: Equatable, Sendable {
    private static let speedDivisor: Float = 1.25

    private var pendingX: Float = 0
    private var pendingY: Float = 0
    private var x: Float = 0.5
    private var y: Float = 0.5

    public init() {}

    public mutating func reset() {
        pendingX = 0
        pendingY = 0
        x = 0.5
        y = 0.5
    }

    public mutating func position(
        rawDeltaX: Float,
        rawDeltaY: Float,
        width: Int,
        height: Int
    ) -> (x: Float, y: Float)? {
        guard width > 0, height > 0 else { return nil }
        pendingX += rawDeltaX / Self.speedDivisor
        pendingY += rawDeltaY / Self.speedDivisor
        let wholeX = pendingX.rounded(.towardZero)
        let wholeY = pendingY.rounded(.towardZero)
        guard wholeX != 0 || wholeY != 0 else { return nil }
        pendingX -= wholeX
        pendingY -= wholeY
        x = min(max(x + wholeX / Float(width), 0), 1)
        y = min(max(y + wholeY / Float(height), 0), 1)
        return (x, y)
    }
}

/// Owns the external mouse while a session is active.
///
/// A connected mouse normally drives the system pointer, so the window never
/// sees it as a pointer position. GameController still delivers the raw deltas
/// and button states, and those are what the host needs: the session forwards
/// movement, buttons and the wheel from here.
///
/// The relative mode sends the deltas themselves. The absolute mode integrates
/// them into a position on the stream picture, because that mode asks the host
/// for a pointer position rather than movement.
///
/// GameController delivers these callbacks on the main queue, so start and stop
/// are main-thread calls and this owner needs no cross-thread lock.
public final class StreamMouseInput: NSObject {
    public static let leftButtonCode: Int32 = 0x01
    public static let middleButtonCode: Int32 = 0x02
    public static let rightButtonCode: Int32 = 0x03
    public static let x1ButtonCode: Int32 = 0x04
    public static let x2ButtonCode: Int32 = 0x05

    private var mouse: GCMouse?
    private var motion = StreamMouseMotion()
    private var absoluteCursor = StreamAbsoluteCursor()
    private var trackingMode: StreamMouseTrackingMode = .relative
    private var streamWidth = 1920
    private var streamHeight = 1080
    private var verticalScroll = StreamHighResScrollAccumulator()
    private var horizontalScroll = StreamHighResScrollAccumulator()
    private var lastDeltaProbe = Date.distantPast
    private var onMove: (@Sendable (Int32, Int32) -> Void)?
    private var onPosition: (@Sendable (Float, Float) -> Void)?
    private var onButton: (@Sendable (Int32, Bool) -> Void)?
    private var onHighResScroll: (@Sendable (Int32, Int32) -> Void)?
    private var onPresence: (@Sendable (Bool) -> Void)?

    public override init() {
        super.init()
    }

    public static func connected() -> Bool {
        GCMouse.mice().contains { $0.mouseInput != nil }
    }

    public func start(
        trackingMode: StreamMouseTrackingMode,
        streamWidth: Int,
        streamHeight: Int,
        onMove: @escaping @Sendable (Int32, Int32) -> Void,
        onPosition: @escaping @Sendable (Float, Float) -> Void,
        onButton: @escaping @Sendable (Int32, Bool) -> Void,
        onHighResScroll: @escaping @Sendable (Int32, Int32) -> Void,
        onPresence: @escaping @Sendable (Bool) -> Void
    ) {
        stop()
        self.trackingMode = trackingMode
        self.streamWidth = streamWidth
        self.streamHeight = streamHeight
        self.onMove = onMove
        self.onPosition = onPosition
        self.onButton = onButton
        self.onHighResScroll = onHighResScroll
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
        onPosition = nil
        onButton = nil
        onHighResScroll = nil
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
        verticalScroll = StreamHighResScrollAccumulator()
        horizontalScroll = StreamHighResScrollAccumulator()
        motion = StreamMouseMotion()
        absoluteCursor.reset()
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
        if let auxiliary = input.auxiliaryButtons {
            if auxiliary.count >= 1 {
                auxiliary[0].pressedChangedHandler = { [weak self] _, _, pressed in
                    self?.onButton?(Self.x1ButtonCode, pressed)
                }
            }
            if auxiliary.count >= 2 {
                auxiliary[1].pressedChangedHandler = { [weak self] _, _, pressed in
                    self?.onButton?(Self.x2ButtonCode, pressed)
                }
            }
        }
        input.scroll.yAxis.valueChangedHandler = { [weak self] _, value in
            self?.handleScroll(vertical: value)
        }
        input.scroll.xAxis.valueChangedHandler = { [weak self] _, value in
            self?.handleScroll(horizontal: value)
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
            for button in input.auxiliaryButtons ?? [] {
                button.pressedChangedHandler = nil
            }
            input.scroll.yAxis.valueChangedHandler = nil
            input.scroll.xAxis.valueChangedHandler = nil
        }
        let wasAttached = mouse != nil
        mouse = nil
        verticalScroll = StreamHighResScrollAccumulator()
        horizontalScroll = StreamHighResScrollAccumulator()
        if reportPresence, wasAttached {
            onPresence?(false)
        }
    }

    private func handleMove(deltaX: Float, deltaY: Float) {
        switch trackingMode {
        case .relative:
            let delta = motion.screenDelta(rawX: deltaX, rawY: deltaY)
            recordDeltaProbe(rawX: deltaX, rawY: deltaY, sent: "\(delta.x),\(delta.y)")
            guard delta.x != 0 || delta.y != 0 else { return }
            onMove?(delta.x, delta.y)
        case .absolute:
            guard let position = absoluteCursor.position(
                rawDeltaX: deltaX,
                rawDeltaY: deltaY,
                width: streamWidth,
                height: streamHeight
            ) else {
                return
            }
            recordDeltaProbe(
                rawX: deltaX,
                rawY: deltaY,
                sent: String(format: "%.4f,%.4f", position.x, position.y)
            )
            onPosition?(position.x, position.y)
        }
    }

    private func recordDeltaProbe(rawX: Float, rawY: Float, sent: String) {
        let now = Date()
        guard now.timeIntervalSince(lastDeltaProbe) >= 0.25 else { return }
        lastDeltaProbe = now
        StreamSessionProbes.record(
            "mouse delta raw=\(String(format: "%.2f", rawX)),\(String(format: "%.2f", rawY))"
                + " sent=\(sent) mode=\(trackingMode.rawValue)",
            retention: .evidence
        )
    }

    private func handleScroll(vertical: Float) {
        let units = verticalScroll.units(for: vertical)
        guard units != 0 else { return }
        onHighResScroll?(units, 0)
    }

    private func handleScroll(horizontal: Float) {
        let units = horizontalScroll.units(for: -horizontal)
        guard units != 0 else { return }
        onHighResScroll?(0, units)
    }
}
