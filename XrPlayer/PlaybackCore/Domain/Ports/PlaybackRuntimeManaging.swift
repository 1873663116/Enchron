import Foundation

public protocol PlaybackRuntimeManaging: AnyObject {
    func startEventLoop()
    func stopEventLoop()
    var eventQueueDepth: Int { get }
}
