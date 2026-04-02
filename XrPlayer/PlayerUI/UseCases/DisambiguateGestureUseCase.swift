import Foundation
import CoreGraphics
import Observation

@MainActor
@Observable
public final class DisambiguateGestureUseCase {
    public enum GestureState {
        case idle
        case observing(startTime: Date)
        case awaitingSecondPinch(firstPinchAt: Date)
        case confirmed(GestureType)
    }
    
    public var state: GestureState = .idle
    public var onGestureResolved: ((GestureType) -> Void)?
    public var onLongPressBegan: (() -> Void)?
    public var onLongPressEnded: (() -> Void)?
    public var onDragUpdate: ((CGSize) -> Void)?
    public var onDragEnded: (() -> Void)?
    private var isLongPressing = false

    private let observationWindow: TimeInterval = 0.4 // 400ms
    private let longPressThreshold: TimeInterval = 0.2 // 200ms
    private let dragDistanceThreshold: CGFloat = 8

    private var activePinchStartTime: Date?
    private var isDragging = false
    private var singlePinchTask: Task<Void, Never>?
    private var longPressTask: Task<Void, Never>?
    
    public init() {}
    
    // Backward-compatible entry for existing callers that only emit tap-like pinch events.
    public func handlePinch() {
        handlePinchBegan()
        handlePinchEnded()
    }

    public func handlePinchBegan(at time: Date = Date()) {
        cancelLongPressTask()
        if case let .awaitingSecondPinch(firstPinchAt) = state,
           time.timeIntervalSince(firstPinchAt) <= observationWindow {
            cancelSinglePinchTask()
            emit(.doublePinch)
            activePinchStartTime = nil
            isDragging = false
            return
        }

        activePinchStartTime = time
        isDragging = false
        state = .observing(startTime: time)
        scheduleLongPressCheck(startTime: time)
    }

    public func handlePinchChanged(translation: CGSize, at time: Date = Date()) {
        if isDragging {
            onDragUpdate?(translation)
            return
        }
        guard activePinchStartTime != nil else { return }
        let distance = hypot(translation.width, translation.height)
        guard distance >= dragDistanceThreshold else { return }

        isDragging = true
        cancelLongPressTask()
        cancelSinglePinchTask()
        emit(.drag)
    }

    public func handlePinchEnded(at time: Date = Date()) {
        if isLongPressing {
            isLongPressing = false
            activePinchStartTime = nil
            cancelLongPressTask()
            isDragging = false
            onLongPressEnded?()
            state = .idle
            return
        }

        if isDragging {
            isDragging = false
            activePinchStartTime = nil
            cancelLongPressTask()
            onDragEnded?()
            state = .idle
            return
        }

        guard let startTime = activePinchStartTime else { return }
        activePinchStartTime = nil
        cancelLongPressTask()

        let duration = time.timeIntervalSince(startTime)
        if duration >= longPressThreshold {
            emit(.longPress)
            return
        }

        state = .awaitingSecondPinch(firstPinchAt: time)
        scheduleSinglePinchConfirmation(firstPinchAt: time)
    }

    private func scheduleSinglePinchConfirmation(firstPinchAt: Date) {
        cancelSinglePinchTask()
        singlePinchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self else { return }
            guard case let .awaitingSecondPinch(observedTime) = self.state,
                  observedTime == firstPinchAt else {
                return
            }
            self.emit(.singlePinch)
        }
    }

    private func scheduleLongPressCheck(startTime: Date) {
        longPressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self else { return }
            guard let activeStart = self.activePinchStartTime,
                  activeStart == startTime,
                  self.isDragging == false else {
                return
            }
            self.isLongPressing = true
            self.onLongPressBegan?()
        }
    }

    private func emit(_ gesture: GestureType) {
        cancelSinglePinchTask()
        cancelLongPressTask()
        state = .confirmed(gesture)
        onGestureResolved?(gesture)
        resetAfterDelay()
    }

    private func cancelSinglePinchTask() {
        singlePinchTask?.cancel()
        singlePinchTask = nil
    }

    private func cancelLongPressTask() {
        longPressTask?.cancel()
        longPressTask = nil
    }

    private func resetAfterDelay() {
        cancelSinglePinchTask()
        cancelLongPressTask()
        switch state {
        case .confirmed:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.state = .idle
            }
        case .idle, .observing, .awaitingSecondPinch:
            break
        }
    }
}
