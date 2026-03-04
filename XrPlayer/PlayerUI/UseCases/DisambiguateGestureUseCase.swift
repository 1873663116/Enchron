import Foundation
import Observation

@MainActor
@Observable
public final class DisambiguateGestureUseCase {
    public enum GestureState {
        case idle
        case observing(startTime: Date)
        case confirmed(GestureType)
    }
    
    public var state: GestureState = .idle
    private let observationWindow: TimeInterval = 0.1 // 100ms
    
    public init() {}
    
    public func handlePinch() {
        switch state {
        case .idle:
            state = .observing(startTime: Date())
            
            // Wait for potential second pinch
            DispatchQueue.main.asyncAfter(deadline: .now() + observationWindow) { [weak self] in
                self?.finalizeObservation()
            }
            
        case .observing:
            // Second pinch within window -> Double Pinch
            state = .confirmed(.doublePinch)
            resetAfterDelay()
            
        case .confirmed:
            break
        }
    }
    
    private func finalizeObservation() {
        if case .observing = state {
            state = .confirmed(.singlePinch)
            resetAfterDelay()
        }
    }
    
    private func resetAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.state = .idle
        }
    }
}
