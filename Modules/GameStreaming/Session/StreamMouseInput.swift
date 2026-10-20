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

/// GameController delivers mouse callbacks on the main queue. The window gesture
/// path keeps movement and the primary click, so this owner forwards only the
/// scroll wheel and the secondary buttons that path cannot carry.
public final class StreamMouseInput: NSObject {
    private static let middleButtonCode: Int32 = 0x02
    private static let rightButtonCode: Int32 = 0x03

    private var mouse: GCMouse?
    private var accumulator = StreamScrollAccumulator()
    private var onScrollClicks: (@Sendable (Int32) -> Void)?
    private var onButton: (@Sendable (Int32, Bool) -> Void)?

    public override init() {
        super.init()
    }

    public func start(
        onScrollClicks: @escaping @Sendable (Int32) -> Void,
        onButton: @escaping @Sendable (Int32, Bool) -> Void
    ) {
        stop()
        self.onScrollClicks = onScrollClicks
        self.onButton = onButton
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
        attachCurrentMouse()
    }

    public func stop() {
        NotificationCenter.default.removeObserver(self, name: .GCMouseDidConnect, object: nil)
        NotificationCenter.default.removeObserver(self, name: .GCMouseDidDisconnect, object: nil)
        detach()
        onScrollClicks = nil
        onButton = nil
    }

    @objc private func mouseDidConnect(_ notification: Notification) {
        guard mouse == nil, let connected = notification.object as? GCMouse else { return }
        attach(connected)
    }

    @objc private func mouseDidDisconnect(_ notification: Notification) {
        guard let departing = notification.object as? GCMouse, departing === mouse else { return }
        detach()
        attachCurrentMouse()
    }

    private func attachCurrentMouse() {
        guard mouse == nil, let candidate = GCMouse.mice().first(where: { $0.mouseInput != nil }) else {
            return
        }
        attach(candidate)
    }

    private func attach(_ candidate: GCMouse) {
        guard let input = candidate.mouseInput else { return }
        mouse = candidate
        accumulator = StreamScrollAccumulator()
        input.scroll.valueChangedHandler = { [weak self] _, _, yValue in
            self?.handleScroll(yValue)
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.onButton?(Self.rightButtonCode, pressed)
        }
        input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.onButton?(Self.middleButtonCode, pressed)
        }
    }

    private func detach() {
        if let input = mouse?.mouseInput {
            input.scroll.valueChangedHandler = nil
            input.rightButton?.pressedChangedHandler = nil
            input.middleButton?.pressedChangedHandler = nil
        }
        mouse = nil
        accumulator = StreamScrollAccumulator()
    }

    private func handleScroll(_ yValue: Float) {
        let clicks = accumulator.clicks(for: yValue)
        guard clicks != 0 else { return }
        onScrollClicks?(clicks)
    }
}
