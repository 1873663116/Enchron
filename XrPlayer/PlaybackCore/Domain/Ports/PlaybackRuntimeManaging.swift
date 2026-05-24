import Foundation

public nonisolated protocol PlaybackRuntimeManaging: AnyObject {
    func startEventLoop()
    func stopEventLoop()
    var eventQueueDepth: Int { get }
}
