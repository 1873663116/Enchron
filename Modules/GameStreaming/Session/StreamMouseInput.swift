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

public final class StreamMouseInput: @unchecked Sendable {
    private static let middleButtonCode: Int32 = 0x02
    private static let rightButtonCode: Int32 = 0x03

    private var observers: [NSObjectProtocol] = []
    private var mouse: GCMouse?
    private var accumulator = StreamScrollAccumulator()
    private var onScrollClicks: (@Sendable (Int32) -> Void)?
    private var onButton: (@Sendable (Int32, Bool) -> Void)?

    public init() {}

    public func start(
        onScrollClicks: @escaping @Sendable (Int32) -> Void,
        onButton: @escaping @Sendable (Int32, Bool) -> Void
    ) {
        self.onScrollClicks = onScrollClicks
        self.onButton = onButton
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.installObservers()
            if let mouse = GCMouse.mice().first {
                self.attach(mouse)
            }
        }
    }

    public func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.removeObservers()
            self.detach()
            self.onScrollClicks = nil
            self.onButton = nil
        }
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: .GCMouseDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self, let mouse = note.object as? GCMouse else { return }
                self.attach(mouse)
            },
            center.addObserver(
                forName: .GCMouseDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self, let mouse = note.object as? GCMouse else { return }
                if self.mouse === mouse {
                    self.detach()
                }
            }
        ]
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private func attach(_ mouse: GCMouse) {
        guard self.mouse == nil else { return }
        guard let input = mouse.mouseInput else {
            return
        }
        self.mouse = mouse
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
