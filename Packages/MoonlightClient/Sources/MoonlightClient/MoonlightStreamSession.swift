import CMoonlightCore
import CoreMedia
import Foundation
import MoonlightBridge

public final class MoonlightStreamSession: NSObject, @unchecked Sendable {
    public var onVideoSample: (@Sendable (CMSampleBuffer) -> Void)?
    public var onAudioFrame: (@Sendable (MoonlightAudioFrame) -> Void)?
    public var onEvent: (@Sendable (MoonlightSessionEvent) -> Void)?

    private var connection: MLCConnection!
    private let fallbackWidth: Int
    private let fallbackHeight: Int
    private let frameRate: Int
    private let requestedCodec: MoonlightVideoCodec

    private let lock = NSLock()
    private var negotiatedWidth = 0
    private var negotiatedHeight = 0
    private var configuredReported = false

    init(
        config: MLCStreamConfiguration,
        codec: MoonlightVideoCodec,
        fallbackWidth: Int,
        fallbackHeight: Int,
        frameRate: Int
    ) {
        self.fallbackWidth = fallbackWidth
        self.fallbackHeight = fallbackHeight
        self.frameRate = frameRate
        self.requestedCodec = codec
        super.init()

        connection = MLCConnection(config: config, delegate: self)
        connection.videoConsumer = self
        connection.audioFrameHandler = { [weak self] pcm, channelCount, sampleRate, frameCount in
            guard let self, let pcm else { return }
            self.onAudioFrame?(MoonlightAudioFrame(
                pcm: pcm as Data,
                channelCount: channelCount,
                sampleRate: sampleRate,
                frameCount: frameCount
            ))
        }
        connection.audioStarted = { [weak self] channelCount, sampleRate, samplesPerFrame in
            self?.onEvent?(.audioStarted(
                channelCount: channelCount,
                sampleRate: sampleRate,
                samplesPerFrame: samplesPerFrame
            ))
        }
        connection.audioStopped = { [weak self] in
            self?.onEvent?(.audioStopped)
        }
    }

    public var streamWidth: Int {
        lock.withLock { negotiatedWidth > 0 ? negotiatedWidth : fallbackWidth }
    }

    public var streamHeight: Int {
        lock.withLock { negotiatedHeight > 0 ? negotiatedHeight : fallbackHeight }
    }

    public var streamFrameRate: Int { frameRate }

    public var activeCodecName: String? {
        connection.getActiveCodecName()
    }

    public func start() {
        guard let connection = self.connection else { return }
        let thread = Thread {
            connection.start()
        }
        thread.name = "MoonlightConnection"
        thread.start()
    }

    public func stop() {
        connection.terminate()
    }

    public func sendMousePosition(normalizedX: Float, normalizedY: Float) {
        let width = streamWidth
        let height = streamHeight
        MLCInputSender.sendMousePositionNormalizedX(
            normalizedX,
            y: normalizedY,
            referenceWidth: Int16(clamping: width),
            referenceHeight: Int16(clamping: height)
        )
    }

    public func sendMouseMove(dx: Int32, dy: Int32) {
        MLCInputSender.sendMouseMoveDeltaX(
            Int16(clamping: dx),
            deltaY: Int16(clamping: dy)
        )
    }

    public func sendMouseButton(code: Int32, down: Bool) {
        guard let button = MLCInputMouseButton(rawValue: code) else { return }
        MLCInputSender.send(button, pressed: down)
    }

    public func sendScroll(amount: Int32) {
        MLCInputSender.sendScrollVerticalClicks(Int8(clamping: amount))
    }

    public func sendKey(hidUsage: UInt32, down: Bool, modifierFlags: UInt32) {
        MLCInputSender.sendKey(
            withHIDUsage: Int(hidUsage),
            down: down,
            modifierFlags: Int(modifierFlags)
        )
    }

    public func sendControllerState(
        buttonFlags: Int32,
        leftTrigger: UInt8,
        rightTrigger: UInt8,
        leftStickX: Int16,
        leftStickY: Int16,
        rightStickX: Int16,
        rightStickY: Int16
    ) {
        MLCInputSender.sendControllerState(
            withButtonFlags: Int32(buttonFlags),
            leftTrigger: leftTrigger,
            rightTrigger: rightTrigger,
            leftStickX: leftStickX,
            leftStickY: leftStickY,
            rightStickX: rightStickX,
            rightStickY: rightStickY
        )
    }

    public func sendControllerPresence(connected: Bool) {
        MLCInputSender.sendControllerPresenceArrived(connected)
    }

    public func releaseAllInput() {
        MLCInputSender.releaseAllPressedKeysAndButtons()
    }

    public func requestIdrFrame() {
        MLCInputSender.requestIdrFrame()
    }

    public func estimatedRTT() -> (milliseconds: UInt32, variance: UInt32)? {
        var rtt: UInt32 = 0
        var variance: UInt32 = 0
        guard MLCInputSender.estimatedRttMs(&rtt, variance: &variance) else {
            return nil
        }
        return (rtt, variance)
    }

    public func audioDecodeStats() -> (skipped: Int, pendingPeakMs: Int) {
        var skipped: Int32 = 0
        var pendingPeakMs: Int32 = 0
        connection.takeAudioDecodeSkips(&skipped, pendingPeakMs: &pendingPeakMs)
        return (Int(skipped), Int(pendingPeakMs))
    }

    public func videoStats() -> MoonlightVideoStats? {
        var stats = video_stats_t()
        guard connection.getVideoStats(&stats) else {
            return nil
        }
        let interval = stats.endTime - stats.startTime
        let averageLatency: Double? = stats.framesWithHostProcessingLatency > 0
            ? Double(stats.totalHostProcessingLatency) / Double(stats.framesWithHostProcessingLatency) / 10.0
            : nil
        return MoonlightVideoStats(
            receivedFrames: Int(stats.receivedFrames),
            networkDroppedFrames: Int(stats.networkDroppedFrames),
            totalFrames: Int(stats.totalFrames),
            framesWithHostProcessingLatency: Int(stats.framesWithHostProcessingLatency),
            averageHostProcessingLatencyMs: averageLatency,
            measuredIntervalSeconds: interval,
            submitGapCount: Int(stats.submitGapCount),
            submitGapMaxMs: Int(stats.submitGapMaxMs),
            zeroCopyFrames: Int(stats.zeroCopyFrames),
            zeroCopyFallbacks: Int(stats.zeroCopyFallbacks),
            assembleMaxMs: Int(stats.assembleMaxMs),
            queueWaitMaxMs: Int(stats.queueWaitMaxMs),
            callbackMaxMs: Int(stats.callbackMaxMs),
            pendingMax: Int(stats.pendingMax),
            decoderQos: Int(stats.decoderQos)
        )
    }
}

extension MoonlightStreamSession: MLCVideoSampleBuilderDelegate {
    public func videoSampleBuilder(
        _ builder: MLCVideoSampleBuilder,
        didProduceSample sampleBuffer: CMSampleBuffer,
        frameType: Int32,
        presentationTimeUs: UInt64
    ) {
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            var report: (Int, Int)?
            lock.withLock {
                if !configuredReported, dimensions.width > 0, dimensions.height > 0 {
                    configuredReported = true
                    negotiatedWidth = Int(dimensions.width)
                    negotiatedHeight = Int(dimensions.height)
                    report = (Int(dimensions.width), Int(dimensions.height))
                }
            }
            if let report {
                onEvent?(.decoderConfigured(
                    width: report.0,
                    height: report.1,
                    frameRate: frameRate,
                    codec: Self.codec(fromDisplayName: connection.getActiveCodecName()) ?? requestedCodec
                ))
            }
        }
        onVideoSample?(sampleBuffer)
    }

    private static func codec(fromDisplayName name: String?) -> MoonlightVideoCodec? {
        guard let name else { return nil }
        if name.contains("AV1") { return .av1 }
        if name.contains("HEVC") || name.contains("H.265") { return .hevc }
        if name.contains("H.264") || name.contains("AVC") { return .h264 }
        return nil
    }
}

extension MoonlightStreamSession: MLCConnectionDelegate {
    public func connectionStarted() {
        onEvent?(.connected)
    }

    public func connectionTerminated(_ errorCode: Int32) {
        onEvent?(.terminated(errorCode: errorCode))
    }

    public func stageStarting(_ stageName: UnsafePointer<CChar>?) {
        onEvent?(.stage(name: stageName.map(String.init(cString:)) ?? "", phase: .starting))
    }

    public func stageComplete(_ stageName: UnsafePointer<CChar>?) {
        onEvent?(.stage(name: stageName.map(String.init(cString:)) ?? "", phase: .complete))
    }

    public func stageFailed(_ stageName: UnsafePointer<CChar>?, withError errorCode: Int32, portTestFlags: Int32) {
        onEvent?(.stage(
            name: stageName.map(String.init(cString:)) ?? "",
            phase: .failed(errorCode: errorCode, portTestFlags: portTestFlags)
        ))
    }

    public func connectionStatusUpdate(_ status: Int32) {
        onEvent?(.statusUpdate(status))
    }

    public func setHdrMode(_ enabled: Bool) {
        onEvent?(.hdrMode(enabled))
    }

    public func videoContentShown() {
        onEvent?(.firstFramePresented)
    }
}
