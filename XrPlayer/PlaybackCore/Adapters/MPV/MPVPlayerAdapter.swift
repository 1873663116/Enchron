import CoreVideo
import Foundation
import Libmpv

// Integration paths:
// 1) Primary: Swift Package Manager dependency on MPVKit (module: Libmpv).
// 2) Fallback: Manual libmpv integration using local stub headers/libs in Libraries/mpv.

public enum MPVPlayerAdapterError: Error {
    case createFailed
    case optionFailed(name: String, code: Int32)
    case initializeFailed(Int32)
    case commandFailed([String], Int32)
    case propertyFailed(name: String, Int32)
    case renderContextCreationFailed(Int32)
}

public final class MPVPlayerAdapter: PlaybackControlling, PlaybackRuntimeManaging {
    public weak var frameOutput: FrameOutput?

    private let configuration: MPVConfiguration
    private let videoToolboxBridge: VideoToolboxBridge

    private var handle: OpaquePointer?
    private var renderContext: OpaquePointer?

    private let stateQueue = DispatchQueue(label: "xrplayer.mpv.state")
    private let eventQueue = DispatchQueue(label: "xrplayer.mpv.events", qos: .userInitiated)
    private let renderQueue = DispatchQueue(label: "xrplayer.mpv.render", qos: .userInitiated)

    private var isEventLoopRunning = false
    private var shouldStopEventLoop = false
    private var internalQueueDepth = 0

    private var internalState: PlaybackCoreDomain.PlaybackState = .idle
    private var internalPosition: PlaybackCoreDomain.PlaybackPosition = .init(seconds: 0, duration: 0)
    private var internalAudioTracks: [PlaybackCoreDomain.AudioTrack] = []
    private var internalSubtitleTracks: [PlaybackCoreDomain.SubtitleTrack] = []

    private var currentTimeSeconds: Double = 0
    private var currentDurationSeconds: Double = 0
    private var renderWidth: Int = 1920
    private var renderHeight: Int = 1080

    private static let renderUpdateCallback: mpv_render_update_fn = { context in
        guard let context else { return }
        let adapter = Unmanaged<MPVPlayerAdapter>.fromOpaque(context).takeUnretainedValue()
        adapter.scheduleRender()
    }

    public init(configuration: MPVConfiguration = MPVConfiguration()) {
        self.configuration = configuration
        self.videoToolboxBridge = VideoToolboxBridge()
    }

    deinit {
        teardownMPV()
    }

    public func play(url: URL) async throws {
        try ensureMPVReady()

        updateState(.loading)
        try command(["loadfile", url.path, "replace"])
        updateState(.playing)
        startEventLoop()
    }

    public func pause() {
        setFlagProperty(name: "pause", value: true)
        updateState(.paused)
    }

    public func resume() {
        setFlagProperty(name: "pause", value: false)
        updateState(.playing)
    }

    public func stop() {
        _ = try? command(["stop"])
        updateState(.stopped)
    }

    public func cancelPendingLoad() {
        _ = try? command(["stop"])
        updateState(.idle)
    }

    public func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        _ = try? command(["seek", String(clamped), "absolute+exact"])
        updatePosition(seconds: clamped, duration: currentDurationSeconds)
    }

    public func skip(by seconds: Double) {
        _ = try? command(["seek", String(seconds), "relative+exact"])
    }

    public func setSpeed(_ speed: PlaybackCoreDomain.PlaybackSpeed) {
        setDoubleProperty(name: "speed", value: speed.value)
    }

    public func selectAudioTrack(_ track: PlaybackCoreDomain.AudioTrack) {
        _ = try? command(["set", "aid", track.id])
    }

    public func selectSubtitleTrack(_ track: PlaybackCoreDomain.SubtitleTrack?) {
        if let track {
            _ = try? command(["set", "sid", track.id])
        } else {
            _ = try? command(["set", "sid", "no"])
        }
    }

    public var currentState: PlaybackCoreDomain.PlaybackState {
        stateQueue.sync { internalState }
    }

    public var currentPosition: PlaybackCoreDomain.PlaybackPosition {
        stateQueue.sync { internalPosition }
    }

    public var availableAudioTracks: [PlaybackCoreDomain.AudioTrack] {
        stateQueue.sync { internalAudioTracks }
    }

    public var availableSubtitleTracks: [PlaybackCoreDomain.SubtitleTrack] {
        stateQueue.sync { internalSubtitleTracks }
    }

    public func startEventLoop() {
        let shouldStart = stateQueue.sync { () -> Bool in
            if isEventLoopRunning { return false }
            shouldStopEventLoop = false
            isEventLoopRunning = true
            return true
        }
        guard shouldStart else { return }

        eventQueue.async { [weak self] in
            self?.runEventLoop()
        }
    }

    public func stopEventLoop() {
        let shouldWake = stateQueue.sync { () -> Bool in
            shouldStopEventLoop = true
            return handle != nil
        }

        if shouldWake, let handle {
            mpv_wakeup(handle)
        }
    }

    public var eventQueueDepth: Int {
        stateQueue.sync { internalQueueDepth }
    }

    private func ensureMPVReady() throws {
        if handle != nil {
            return
        }

        guard let created = mpv_create() else {
            throw MPVPlayerAdapterError.createFailed
        }

        do {
            try applyConfiguration(to: created)
            observeCoreProperties(on: created)

            let initCode = mpv_initialize(created)
            guard initCode >= 0 else {
                throw MPVPlayerAdapterError.initializeFailed(initCode)
            }

            handle = created
            try createRenderContext()
        } catch {
            mpv_terminate_destroy(created)
            throw error
        }
    }

    private func teardownMPV() {
        stopEventLoop()

        if let renderContext {
            mpv_render_context_set_update_callback(renderContext, nil, nil)
            mpv_render_context_free(renderContext)
            self.renderContext = nil
        }

        if let handle {
            mpv_terminate_destroy(handle)
            self.handle = nil
        }

        stateQueue.sync {
            isEventLoopRunning = false
            shouldStopEventLoop = true
            internalQueueDepth = 0
            internalState = .stopped
        }
    }

    private func applyConfiguration(to handle: OpaquePointer) throws {
        for (name, value) in configuration.defaultOptions {
            let result = mpv_set_option_string(handle, name, value)
            guard result >= 0 else {
                throw MPVPlayerAdapterError.optionFailed(name: name, code: result)
            }
        }
    }

    private func observeCoreProperties(on handle: OpaquePointer) {
        _ = mpv_observe_property(handle, 1, "time-pos", MPV_FORMAT_DOUBLE)
        _ = mpv_observe_property(handle, 2, "duration", MPV_FORMAT_DOUBLE)
        _ = mpv_observe_property(handle, 3, "pause", MPV_FORMAT_FLAG)
        _ = mpv_observe_property(handle, 4, "eof-reached", MPV_FORMAT_FLAG)
        _ = mpv_observe_property(handle, 5, "track-list", MPV_FORMAT_NONE)
        _ = mpv_observe_property(handle, 6, "dwidth", MPV_FORMAT_INT64)
        _ = mpv_observe_property(handle, 7, "dheight", MPV_FORMAT_INT64)
    }

    private func createRenderContext() throws {
        guard let handle else { return }

        var context: OpaquePointer?
        let apiType = MPV_RENDER_API_TYPE_SW

        var params: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiType)),
            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
        ]

        let code = params.withUnsafeMutableBufferPointer { buffer in
            mpv_render_context_create(&context, handle, buffer.baseAddress)
        }

        guard code >= 0, let context else {
            throw MPVPlayerAdapterError.renderContextCreationFailed(code)
        }

        self.renderContext = context
        mpv_render_context_set_update_callback(
            context,
            Self.renderUpdateCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func runEventLoop() {
        while true {
            let shouldStop = stateQueue.sync { shouldStopEventLoop }
            if shouldStop {
                stateQueue.sync { isEventLoopRunning = false }
                return
            }

            guard let handle else {
                stateQueue.sync { isEventLoopRunning = false }
                return
            }

            guard let event = mpv_wait_event(handle, 0.10) else {
                continue
            }

            stateQueue.sync { internalQueueDepth += 1 }
            process(event: event.pointee)
            stateQueue.sync { internalQueueDepth = max(0, internalQueueDepth - 1) }
        }
    }

    private func process(event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_NONE:
            break
        case MPV_EVENT_START_FILE:
            updateState(.loading)
        case MPV_EVENT_FILE_LOADED:
            updateState(.playing)
            refreshTrackCache()
        case MPV_EVENT_END_FILE:
            updateState(.ended)
        case MPV_EVENT_SHUTDOWN:
            stopEventLoop()
        case MPV_EVENT_PROPERTY_CHANGE:
            if let propertyPointer = event.data?.assumingMemoryBound(to: mpv_event_property.self) {
                handlePropertyChange(propertyPointer.pointee)
            }
        case MPV_EVENT_VIDEO_RECONFIG:
            scheduleRender(forceFrame: true)
        default:
            break
        }
    }

    private func handlePropertyChange(_ property: mpv_event_property) {
        guard let rawName = property.name else { return }
        let name = String(cString: rawName)

        switch name {
        case "time-pos":
            guard property.format == MPV_FORMAT_DOUBLE,
                  let data = property.data?.assumingMemoryBound(to: Double.self)
            else { return }
            currentTimeSeconds = data.pointee
            updatePosition(seconds: currentTimeSeconds, duration: currentDurationSeconds)

        case "duration":
            guard property.format == MPV_FORMAT_DOUBLE,
                  let data = property.data?.assumingMemoryBound(to: Double.self)
            else { return }
            currentDurationSeconds = data.pointee
            updatePosition(seconds: currentTimeSeconds, duration: currentDurationSeconds)

        case "pause":
            guard property.format == MPV_FORMAT_FLAG,
                  let data = property.data?.assumingMemoryBound(to: Int32.self)
            else { return }
            updateState(data.pointee != 0 ? .paused : .playing)

        case "eof-reached":
            guard property.format == MPV_FORMAT_FLAG,
                  let data = property.data?.assumingMemoryBound(to: Int32.self)
            else { return }
            if data.pointee != 0 {
                updateState(.ended)
            }

        case "dwidth":
            guard property.format == MPV_FORMAT_INT64,
                  let data = property.data?.assumingMemoryBound(to: Int64.self)
            else { return }
            renderWidth = max(1, Int(data.pointee))

        case "dheight":
            guard property.format == MPV_FORMAT_INT64,
                  let data = property.data?.assumingMemoryBound(to: Int64.self)
            else { return }
            renderHeight = max(1, Int(data.pointee))

        case "track-list":
            refreshTrackCache()

        default:
            break
        }
    }

    private func refreshTrackCache() {
        // Keep this lightweight and resilient: if libmpv track metadata is unavailable,
        // preserve current lists instead of failing playback.
        guard let handle else { return }

        var aid: UnsafeMutablePointer<CChar>?
        var sid: UnsafeMutablePointer<CChar>?

        _ = mpv_get_property(handle, "aid", MPV_FORMAT_STRING, &aid)
        _ = mpv_get_property(handle, "sid", MPV_FORMAT_STRING, &sid)

        defer {
            if let aid { mpv_free(aid) }
            if let sid { mpv_free(sid) }
        }

        var audio: [PlaybackCoreDomain.AudioTrack] = []
        var subtitles: [PlaybackCoreDomain.SubtitleTrack] = []

        if let aid {
            let id = String(cString: aid)
            audio.append(.init(id: id, languageCode: nil, displayName: "Audio \(id)", isDefault: true))
        }

        if let sid {
            let id = String(cString: sid)
            if id != "no" {
                subtitles.append(.init(id: id, languageCode: nil, displayName: "Subtitle \(id)", isDefault: true))
            }
        }

        stateQueue.sync {
            internalAudioTracks = audio
            internalSubtitleTracks = subtitles
        }
    }

    private func command(_ args: [String]) throws {
        guard let handle else { return }

        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cArgs.append(nil)

        defer {
            for argument in cArgs where argument != nil {
                free(argument)
            }
        }

        let code = cArgs.withUnsafeMutableBufferPointer { buffer -> Int32 in
            let bound = UnsafeMutablePointer<UnsafePointer<CChar>?>(OpaquePointer(buffer.baseAddress))
            return mpv_command(handle, bound)
        }

        guard code >= 0 else {
            throw MPVPlayerAdapterError.commandFailed(args, code)
        }
    }

    private func setFlagProperty(name: String, value: Bool) {
        guard let handle else { return }
        var flag: Int32 = value ? 1 : 0
        _ = mpv_set_property(handle, name, MPV_FORMAT_FLAG, &flag)
    }

    private func setDoubleProperty(name: String, value: Double) {
        guard let handle else { return }
        var v = value
        _ = mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &v)
    }

    private func updateState(_ state: PlaybackCoreDomain.PlaybackState) {
        stateQueue.sync {
            internalState = state
        }
    }

    private func updatePosition(seconds: Double, duration: Double) {
        let position = PlaybackCoreDomain.PlaybackPosition(seconds: seconds, duration: duration)
        stateQueue.sync {
            internalPosition = position
        }
    }

    private func scheduleRender(forceFrame: Bool = false) {
        renderQueue.async { [weak self] in
            self?.renderNextFrame(forceFrame: forceFrame)
        }
    }

    private func renderNextFrame(forceFrame: Bool) {
        guard let renderContext else { return }

        let flags = mpv_render_context_update(renderContext)
        let hasFrameUpdate = (flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue)) != 0
        guard forceFrame || hasFrameUpdate else { return }

        let width = max(1, renderWidth)
        let height = max(1, renderHeight)
        let stride = width * 4
        var rawBytes = [UInt8](repeating: 0, count: stride * height)

        var size = [Int32(width), Int32(height)]
        var rowStride = stride
        var softwareFormat = strdup("bgr0")

        defer {
            if let softwareFormat {
                free(softwareFormat)
            }
        }

        let result: Int32 = rawBytes.withUnsafeMutableBytes { bytes -> Int32 in
            guard let pixelPointer = bytes.baseAddress else { return -1 }
            return size.withUnsafeMutableBufferPointer { sizeBuffer -> Int32 in
                guard let sizePtr = sizeBuffer.baseAddress else { return -1 }

                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: sizePtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: softwareFormat),
                    mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: &rowStride),
                    mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: pixelPointer),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]

                params.withUnsafeMutableBufferPointer { buffer in
                    mpv_render_context_render(renderContext, buffer.baseAddress)
                }
                return 0
            }
        }

        guard result >= 0 else { return }

        guard let pixelBuffer = try? makeBGRAFrame(width: width, height: height, bytes: rawBytes, bytesPerRow: stride) else {
            return
        }

        frameOutput?.didOutputFrame(pixelBuffer)
    }

    private func makeBGRAFrame(width: Int, height: Int, bytes: [UInt8], bytesPerRow: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        let status = CVPixelBufferCreate(
            nil,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            return try videoToolboxBridge.makePlaceholderPixelBuffer(width: width, height: height)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let destination = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return try videoToolboxBridge.makePlaceholderPixelBuffer(width: width, height: height)
        }

        bytes.withUnsafeBytes { source in
            if let sourceAddress = source.baseAddress {
                memcpy(destination, sourceAddress, bytesPerRow * height)
            }
        }

        return pixelBuffer
    }
}
