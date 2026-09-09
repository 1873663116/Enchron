import Foundation
import Observation
import QuartzCore
import AVFoundation
import CoreVideo
import IOSurface
import RealityKit

public struct DeveloperProcessMetrics: Equatable, Sendable {
    public var footprintBytes: UInt64
    public var availableBytes: Int
    public var mediaFootprintBytes: Int64?
    public var mediaUnchargedBytes: Int64?
    public var graphicsFootprintBytes: Int64?
    public var graphicsUnchargedBytes: Int64?

    public var refreshHz: Double?

    public var limitIsReported: Bool { availableBytes > 0 }

    public var limitBytes: UInt64 {
        footprintBytes + UInt64(max(availableBytes, 0))
    }

    public var longestStallSeconds: Double
    public var missedBeatCount: Int

    public init(
        footprintBytes: UInt64 = 0,
        availableBytes: Int = 0,
        mediaFootprintBytes: Int64? = nil,
        mediaUnchargedBytes: Int64? = nil,
        graphicsFootprintBytes: Int64? = nil,
        graphicsUnchargedBytes: Int64? = nil,
        refreshHz: Double? = nil,
        longestStallSeconds: Double = 0,
        missedBeatCount: Int = 0
    ) {
        self.footprintBytes = footprintBytes
        self.availableBytes = availableBytes
        self.mediaFootprintBytes = mediaFootprintBytes
        self.mediaUnchargedBytes = mediaUnchargedBytes
        self.graphicsFootprintBytes = graphicsFootprintBytes
        self.graphicsUnchargedBytes = graphicsUnchargedBytes
        self.refreshHz = refreshHz
        self.longestStallSeconds = longestStallSeconds
        self.missedBeatCount = missedBeatCount
    }
}

@MainActor
final class MainThreadCadenceMonitor {
    static let heartbeatInterval: CFTimeInterval = 1.0 / 60

    private final class Proxy: NSObject {
        weak var monitor: MainThreadCadenceMonitor?

        @objc func step(_ link: CADisplayLink) {
            MainActor.assumeIsolated { monitor?.readRefreshInterval(from: link) }
        }
    }

    private var link: CADisplayLink?
    private let proxy = Proxy()
    private var heartbeat: Timer?
    private var nextBeatDue: CFTimeInterval?
    private var refreshInterval: CFTimeInterval?
    private var longestStall: CFTimeInterval = 0
    private var missedBeats = 0

    func start() {
        guard link == nil else { return }
        proxy.monitor = self
        let link = CADisplayLink(target: proxy, selector: #selector(Proxy.step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link

        let heartbeat = Timer(
            timeInterval: Self.heartbeatInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
        heartbeat.tolerance = 0
        RunLoop.main.add(heartbeat, forMode: .common)
        self.heartbeat = heartbeat
        nextBeatDue = CACurrentMediaTime() + Self.heartbeatInterval
    }

    func stop() {
        link?.invalidate()
        link = nil
        heartbeat?.invalidate()
        heartbeat = nil
        nextBeatDue = nil
        refreshInterval = nil
        longestStall = 0
        missedBeats = 0
    }

    func drain() -> (longestStallSeconds: Double, missedBeatCount: Int, refreshHz: Double?) {
        defer {
            longestStall = 0
            missedBeats = 0
        }
        let hz = refreshInterval.flatMap { $0 > 0 ? 1 / $0 : nil }
        return (longestStall, missedBeats, hz)
    }

    private func readRefreshInterval(from link: CADisplayLink) {
        let interval = link.targetTimestamp - link.timestamp
        guard interval > 0 else { return }
        refreshInterval = interval
    }

    private func beat() {
        let now = CACurrentMediaTime()
        defer { nextBeatDue = now + Self.heartbeatInterval }
        guard let nextBeatDue else { return }
        let lateness = now - nextBeatDue
        guard lateness > 0 else { return }
        longestStall = max(longestStall, lateness)
        if lateness >= Self.heartbeatInterval {
            missedBeats += 1
        }
    }
}

@MainActor
public func presentedSurfaceIdentity(of renderer: AVSampleBufferVideoRenderer?) -> UInt64? {
    guard let pixelBuffer = renderer?.displayedPixelBuffer() else { return nil }
    if let surface = CVPixelBufferGetIOSurface(pixelBuffer) {
        return UInt64(IOSurfaceGetID(surface.takeUnretainedValue()))
    }
    return UInt64(CFHash(pixelBuffer))
}

@MainActor
public final class SceneTickSubscriber {
    private var subscription: EventSubscription?

    public init() {}

    public func subscribe(_ make: () -> EventSubscription) {
        guard subscription == nil else { return }
        subscription = make()
    }

    public func cancel() {
        subscription?.cancel()
        subscription = nil
    }

    public var isSubscribed: Bool { subscription != nil }
}

@MainActor
@Observable
public final class DeveloperMetricsModel {
    public enum SceneKey: String, Sendable {
        case window
        case immersive
    }

    public private(set) var metrics = DeveloperProcessMetrics()
    public private(set) var isRunning = false
    public private(set) var sceneUpdatesPerSecond: [SceneKey: Double] = [:]
    public private(set) var presentedFramesPerSecond: Double?

    public private(set) var enqueuedSamplesPerSecond: Double?

    @ObservationIgnored public var enqueuedSampleCountSource: (@MainActor () -> Int?)?

    public private(set) var droppedFramesPerSecond: Double?

    @ObservationIgnored public var droppedFrameCountSource: (@MainActor () -> Int?)?

    @ObservationIgnored private let cadence = MainThreadCadenceMonitor()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var sceneTicks: [SceneKey: Int] = [:]
    @ObservationIgnored private var sceneWindowStart = CACurrentMediaTime()
    @ObservationIgnored private var presentedFrameCount = 0
    @ObservationIgnored private var lastPresentedSurfaceIdentity: UInt64?
    @ObservationIgnored private var lastEnqueuedSampleCount: Int?
    @ObservationIgnored private var lastEnqueuedSampleAt: CFTimeInterval?
    @ObservationIgnored private var lastDroppedFrameCount: Int?
    @ObservationIgnored private var lastDroppedSampleAt: CFTimeInterval?

    public init() {}

    public func recordSceneTick(_ key: SceneKey) {
        guard isRunning else { return }
        sceneTicks[key, default: 0] += 1
    }

    public func recordPresentedSurface(_ identity: UInt64?) {
        guard isRunning, let identity else { return }
        guard identity != lastPresentedSurfaceIdentity else { return }
        lastPresentedSurfaceIdentity = identity
        presentedFrameCount += 1
    }

    public func start() {
        guard isRunning == false else { return }
        isRunning = true
        cadence.start()
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        cadence.stop()
        metrics = DeveloperProcessMetrics()
        sceneTicks = [:]
        sceneUpdatesPerSecond = [:]
        droppedFramesPerSecond = nil
        lastDroppedFrameCount = nil
        lastDroppedSampleAt = nil
        presentedFramesPerSecond = nil
        presentedFrameCount = 0
        lastPresentedSurfaceIdentity = nil
        enqueuedSamplesPerSecond = nil
        lastEnqueuedSampleCount = nil
        lastEnqueuedSampleAt = nil
    }

    private func drainEnqueuedSamples() {
        guard let count = enqueuedSampleCountSource?() else {
            enqueuedSamplesPerSecond = nil
            lastEnqueuedSampleCount = nil
            lastEnqueuedSampleAt = nil
            return
        }
        let now = CACurrentMediaTime()
        defer {
            lastEnqueuedSampleCount = count
            lastEnqueuedSampleAt = now
        }
        guard let previous = lastEnqueuedSampleCount, let at = lastEnqueuedSampleAt else { return }
        let elapsed = now - at
        guard elapsed > 0, count >= previous else {
            enqueuedSamplesPerSecond = nil
            return
        }
        enqueuedSamplesPerSecond = Double(count - previous) / elapsed
    }

    private func drainDroppedFrames() {
        guard let count = droppedFrameCountSource?() else {
            droppedFramesPerSecond = nil
            lastDroppedFrameCount = nil
            lastDroppedSampleAt = nil
            return
        }
        let now = CACurrentMediaTime()
        defer {
            lastDroppedFrameCount = count
            lastDroppedSampleAt = now
        }
        guard let previous = lastDroppedFrameCount, let at = lastDroppedSampleAt else { return }
        let elapsed = now - at
        guard elapsed > 0, count >= previous else {
            droppedFramesPerSecond = nil
            return
        }
        droppedFramesPerSecond = Double(count - previous) / elapsed
    }

    private func drainSceneTicks() {
        let now = CACurrentMediaTime()
        let elapsed = now - sceneWindowStart
        sceneWindowStart = now
        guard elapsed > 0 else { return }
        sceneUpdatesPerSecond = sceneTicks.mapValues { Double($0) / elapsed }
        sceneTicks = [:]
        presentedFramesPerSecond = Double(presentedFrameCount) / elapsed
        presentedFrameCount = 0
    }

    private func sample() {
        drainSceneTicks()
        drainEnqueuedSamples()
        drainDroppedFrames()
        let cadenceReading = cadence.drain()
        guard let memory = ProcessMemoryFootprint.read() else {
            metrics = DeveloperProcessMetrics(
                refreshHz: cadenceReading.refreshHz,
                longestStallSeconds: cadenceReading.longestStallSeconds,
                missedBeatCount: cadenceReading.missedBeatCount
            )
            return
        }
        metrics = DeveloperProcessMetrics(
            footprintBytes: memory.footprintBytes,
            availableBytes: memory.availableBytes,
            mediaFootprintBytes: memory.mediaFootprintBytes,
            mediaUnchargedBytes: memory.mediaUnchargedBytes,
            graphicsFootprintBytes: memory.graphicsFootprintBytes,
            graphicsUnchargedBytes: memory.graphicsUnchargedBytes,
            refreshHz: cadenceReading.refreshHz,
            longestStallSeconds: cadenceReading.longestStallSeconds,
            missedBeatCount: cadenceReading.missedBeatCount
        )
    }
}
