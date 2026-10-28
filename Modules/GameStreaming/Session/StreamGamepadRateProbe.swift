#if DEBUG
import Foundation
import GameController
import UIKit

final class StreamGamepadRateProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var timer: Timer?
    private var deadline = Date()
    private var events = 0
    private var buttonEvents = 0
    private var stickEvents = 0
    private var maxMainThreadLag: TimeInterval = 0
    private var maxSourceLatency: TimeInterval = 0

    func start() {
        guard timer == nil else { return }
        deadline = Date().addingTimeInterval(1)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lock.lock()
        events = 0
        buttonEvents = 0
        stickEvents = 0
        maxMainThreadLag = 0
        maxSourceLatency = 0
        lock.unlock()
    }

    func record(_ element: GCControllerElement) {
        lock.lock()
        events += 1
        if element is GCControllerButtonInput {
            buttonEvents += 1
        } else {
            stickEvents += 1
        }
        if let axis = element as? GCAxisInput {
            maxSourceLatency = max(maxSourceLatency, axis.lastValueLatency)
        }
        lock.unlock()
    }

    private func tick() {
        let now = Date()
        lock.lock()
        maxMainThreadLag = max(maxMainThreadLag, now.timeIntervalSince(deadline))
        deadline = now.addingTimeInterval(1)
        let events = self.events
        let buttonEvents = self.buttonEvents
        let stickEvents = self.stickEvents
        let lag = maxMainThreadLag
        let sourceLatency = maxSourceLatency
        self.events = 0
        self.buttonEvents = 0
        self.stickEvents = 0
        maxMainThreadLag = 0
        maxSourceLatency = 0
        lock.unlock()
        let mode = MainActor.assumeIsolated { Self.mode }
        StreamSessionProbes.record(
            "gamepad rate mode=\(mode) events=\(events) button=\(buttonEvents)"
                + " stick=\(stickEvents) mainLagMs=\(Int((lag * 1000).rounded()))"
                + " sourceLatencyMs=\(Int((sourceLatency * 1000).rounded()))",
            retention: .evidence
        )
    }

    @MainActor
    private static var mode: String {
        var hasImmersive = false
        var hasWindow = false
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if windowScene.session.role == .immersiveSpaceApplication {
                hasImmersive = true
            }
            if windowScene.session.role == .windowApplication {
                hasWindow = true
            }
        }
        if hasImmersive { return "dock" }
        return hasWindow ? "window" : "none"
    }
}
#endif
