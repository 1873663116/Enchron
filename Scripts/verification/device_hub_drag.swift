import AppKit
import CoreGraphics
import Foundation

enum PointerInputError: Error {
    case invalidArguments
    case eventUnavailable
    case targetNotFrontmost
}

let values = CommandLine.arguments.dropFirst().compactMap(Double.init)
guard CommandLine.arguments.count == 6, values.count == 5,
      values.allSatisfy(\.isFinite), values[4] >= 0 else {
    throw PointerInputError.invalidArguments
}
let start = CGPoint(x: values[0], y: values[1])
let destination = CGPoint(x: values[2], y: values[3])
let duration = values[4]

func post(_ type: CGEventType, point: CGPoint, delta: CGVector = .zero) throws {
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.dt.Devices" else {
        throw PointerInputError.targetNotFrontmost
    }
    guard let event = CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left
    ) else { throw PointerInputError.eventUnavailable }
    event.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.dx.rounded()))
    event.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.dy.rounded()))
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.post(tap: .cghidEventTap)
}

try post(.leftMouseDown, point: start)
if start != destination {
    Thread.sleep(forTimeInterval: 0.08)
    let steps = 24
    var previous = start
    for index in 1...steps {
        let fraction = Double(index) / Double(steps)
        let point = CGPoint(
            x: start.x + (destination.x - start.x) * fraction,
            y: start.y + (destination.y - start.y) * fraction
        )
        try post(
            .leftMouseDragged,
            point: point,
            delta: CGVector(dx: point.x - previous.x, dy: point.y - previous.y)
        )
        previous = point
        Thread.sleep(forTimeInterval: duration / Double(steps))
    }
}
