import CoreVideo
import Foundation
import Libmpv
import QuartzCore

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
    case fileNotFound(URL)
    case fileNotReadable(URL)
}

extension MPVPlayerAdapterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .createFailed:
            return "Failed to create mpv context."
        case let .optionFailed(name, code):
            return "mpv option failed: \(name) (\(code))."
        case let .initializeFailed(code):
            return "mpv initialization failed (\(code))."
        case let .commandFailed(args, code):
            return "mpv command failed: \(args.joined(separator: " ")) (\(code))."
        case let .propertyFailed(name, code):
            return "mpv property failed: \(name) (\(code))."
        case let .renderContextCreationFailed(code):
            return "mpv render context creation failed (\(code))."
        case let .fileNotFound(url):
            return "File not found: \(url.lastPathComponent)"
        case let .fileNotReadable(url):
            return "File is not readable: \(url.lastPathComponent)"
        }
    }
}

public final class MPVPlayerAdapter: PlaybackControlling, PlaybackRuntimeManaging {
    public weak var frameOutput: FrameOutput?
    public var onRuntimeError: ((String) -> Void)?
    public var usesNativeGPUOutput: Bool { configuration.useNativeGPUOutput }

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
    private var activeSecurityScopedURL: URL?
    private var pixelBufferPool: CVPixelBufferPool?
    private var pooledWidth: Int = 0
    private var pooledHeight: Int = 0
    private weak var videoLayer: CAMetalLayer?
    private var activeNativeGPUOutput: Bool = false
    private var didLogPipelineForCurrentFile = false

    private static let renderUpdateCallback: mpv_render_update_fn = { context in
        guard let context else { return }
        let adapter = Unmanaged<MPVPlayerAdapter>.fromOpaque(context).takeUnretainedValue()
        adapter.scheduleRender()
    }

    public init(configuration: MPVConfiguration = MPVConfiguration()) {
        self.configuration = configuration
        self.videoToolboxBridge = VideoToolboxBridge()
    }

    public func attachVideoLayer(_ layer: CAMetalLayer?) {
        stateQueue.sync {
            videoLayer = layer
        }
    }

    deinit {
        teardownMPV()
    }

    public func play(url: URL) async throws {
        do {
            await waitForVideoLayerIfNeeded()
            try ensureMPVReady()
            startEventLoop()

            let normalizedURL = url.standardizedFileURL
            let path = normalizedURL.path

            guard FileManager.default.fileExists(atPath: path) else {
                throw MPVPlayerAdapterError.fileNotFound(normalizedURL)
            }

            guard FileManager.default.isReadableFile(atPath: path) else {
                throw MPVPlayerAdapterError.fileNotReadable(normalizedURL)
            }

            var acquiredScope = false
            if normalizedURL.startAccessingSecurityScopedResource() {
                acquiredScope = true
                activeSecurityScopedURL = normalizedURL
            }

            do {
                updateState(.loading)
                // Force playback-related defaults on every new load. This avoids
                // inheriting a paused/muted/no-track state from previous sessions.
                setFlagProperty(name: "pause", value: false)
                setFlagProperty(name: "mute", value: false)
                _ = try? command(["set", "vid", "auto"])
                _ = try? command(["set", "aid", "auto"])
                try command(["loadfile", path, "replace"])
                setFlagProperty(name: "pause", value: false)
                setFlagProperty(name: "mute", value: false)
                _ = try? command(["set", "vid", "auto"])
                _ = try? command(["set", "aid", "auto"])
            } catch {
                if acquiredScope {
                    normalizedURL.stopAccessingSecurityScopedResource()
                    activeSecurityScopedURL = nil
                }
                throw error
            }
        } catch {
            notifyRuntimeError(error.localizedDescription)
            throw error
        }
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
        releaseSecurityScopedAccess()
    }

    public func cancelPendingLoad() {
        _ = try? command(["stop"])
        updateState(.idle)
        releaseSecurityScopedAccess()
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
            let wantsNativeGPUOutput = stateQueue.sync {
                configuration.useNativeGPUOutput && videoLayer != nil
            }

            try applyConfiguration(to: created, useNativeGPUOutput: wantsNativeGPUOutput)
            observeCoreProperties(on: created)

            if wantsNativeGPUOutput {
                try setWindowLayerOption(on: created)
            }

            let initCode = mpv_initialize(created)
            guard initCode >= 0 else {
                throw MPVPlayerAdapterError.initializeFailed(initCode)
            }

            _ = mpv_request_log_messages(created, "warn")

            handle = created
            activeNativeGPUOutput = wantsNativeGPUOutput
            print("[MPV] output-route=\(activeNativeGPUOutput ? "native-gpu" : "sw-render-fallback")")

            if activeNativeGPUOutput == false {
                try createRenderContext()
            }
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

        activeNativeGPUOutput = false

        releaseSecurityScopedAccess()

        stateQueue.sync {
            isEventLoopRunning = false
            shouldStopEventLoop = true
            internalQueueDepth = 0
            internalState = .stopped
        }
    }

    private func applyConfiguration(to handle: OpaquePointer, useNativeGPUOutput: Bool) throws {
        for (name, value) in configuration.options(useNativeGPUOutput: useNativeGPUOutput) {
            let result = mpv_set_option_string(handle, name, value)
            if result < 0 {
                // Some packaged libmpv builds (especially on visionOS) omit
                // non-critical options. Skip unsupported options so playback
                // can continue with defaults instead of failing startup.
                print("[MPV] skip unsupported option \(name)=\(value), code=\(result)")
            }
        }
    }

    private func observeCoreProperties(on handle: OpaquePointer) {
        _ = mpv_observe_property(handle, 2, "duration", MPV_FORMAT_DOUBLE)
        _ = mpv_observe_property(handle, 3, "pause", MPV_FORMAT_FLAG)
        _ = mpv_observe_property(handle, 4, "eof-reached", MPV_FORMAT_FLAG)
        _ = mpv_observe_property(handle, 5, "track-list", MPV_FORMAT_NONE)
        _ = mpv_observe_property(handle, 6, "dwidth", MPV_FORMAT_INT64)
        _ = mpv_observe_property(handle, 7, "dheight", MPV_FORMAT_INT64)
        _ = mpv_observe_property(handle, 8, "playback-time", MPV_FORMAT_DOUBLE)
    }

    private func setWindowLayerOption(on handle: OpaquePointer) throws {
        guard let layer = stateQueue.sync(execute: { videoLayer }) else {
            return
        }

        let pointer = Unmanaged.passUnretained(layer).toOpaque()
        var wid = Int64(bitPattern: UInt64(UInt(bitPattern: pointer)))
        let result = withUnsafeMutablePointer(to: &wid) { widPtr in
            mpv_set_option(handle, "wid", MPV_FORMAT_INT64, widPtr)
        }

        if result < 0 {
            throw MPVPlayerAdapterError.optionFailed(name: "wid", code: result)
        }
    }

    private func createRenderContext() throws {
        guard let handle else { return }

        var context: OpaquePointer?
        let code = MPV_RENDER_API_TYPE_SW.withCString { apiTypeCString in
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiTypeCString)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
            ]

            return params.withUnsafeMutableBufferPointer { buffer in
                mpv_render_context_create(&context, handle, buffer.baseAddress)
            }
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

            // Defensive throttle: if libmpv returns MPV_EVENT_NONE immediately
            // (e.g. accidental stub linkage), avoid a CPU spin-loop that can
            // make the app unresponsive.
            if event.pointee.event_id == MPV_EVENT_NONE {
                Thread.sleep(forTimeInterval: 0.01)
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
            didLogPipelineForCurrentFile = false
            setFlagProperty(name: "pause", value: false)
            setFlagProperty(name: "mute", value: false)
            _ = try? command(["set", "vid", "auto"])
            _ = try? command(["set", "aid", "auto"])
            refreshTrackCache()
            logPipelineIfNeeded()
        case MPV_EVENT_END_FILE:
            handleEndFileEvent(event.data)
        case MPV_EVENT_LOG_MESSAGE:
            handleLogMessageEvent(event.data)
        case MPV_EVENT_SHUTDOWN:
            stopEventLoop()
        case MPV_EVENT_PROPERTY_CHANGE:
            if let propertyPointer = event.data?.assumingMemoryBound(to: mpv_event_property.self) {
                handlePropertyChange(propertyPointer.pointee)
            }
        case MPV_EVENT_VIDEO_RECONFIG:
            if activeNativeGPUOutput == false {
                scheduleRender(forceFrame: true)
            }
        default:
            break
        }
    }

    private func handlePropertyChange(_ property: mpv_event_property) {
        guard let rawName = property.name else { return }
        let name = String(cString: rawName)

        switch name {
        case "playback-time":
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

    private func handleEndFileEvent(_ data: UnsafeMutableRawPointer?) {
        guard let pointer = data?.assumingMemoryBound(to: mpv_event_end_file.self) else {
            updateState(.ended)
            releaseSecurityScopedAccess()
            return
        }

        let payload = pointer.pointee
        if payload.reason == MPV_END_FILE_REASON_ERROR {
            updateState(.failed)
            let message = "Playback ended with error: \(mpvErrorString(payload.error)) (\(payload.error))"
            print("[MPV] \(message)")
            notifyRuntimeError(message)
        } else {
            updateState(.ended)
        }

        releaseSecurityScopedAccess()
    }

    private func handleLogMessageEvent(_ data: UnsafeMutableRawPointer?) {
        guard let pointer = data?.assumingMemoryBound(to: mpv_event_log_message.self) else {
            return
        }

        let payload = pointer.pointee
        let level = payload.level.map(String.init(cString:)) ?? "unknown"
        let prefix = payload.prefix.map(String.init(cString:)) ?? "mpv"
        let text = payload.text.map(String.init(cString:))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.isEmpty == false else { return }

        print("[MPV][\(level)][\(prefix)] \(text)")
    }

    private func command(_ args: [String]) throws {
        guard let handle else { return }

        let duplicated = args.map { strdup($0) }
        defer {
            for item in duplicated where item != nil {
                free(item)
            }
        }

        var cArgs: [UnsafePointer<CChar>?] = duplicated.map { ptr in
            ptr.map { UnsafePointer<CChar>($0) }
        }
        cArgs.append(nil)

        let code = cArgs.withUnsafeMutableBufferPointer { buffer -> Int32 in
            mpv_command(handle, buffer.baseAddress)
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

    private func releaseSecurityScopedAccess() {
        guard let url = activeSecurityScopedURL else { return }
        url.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
    }

    private func mpvErrorString(_ code: Int32) -> String {
        guard let cString = mpv_error_string(code) else {
            return "unknown"
        }
        return String(cString: cString)
    }

    private func notifyRuntimeError(_ message: String) {
        guard message.isEmpty == false else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onRuntimeError?(message)
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

        guard let pixelBuffer = makePooledPixelBuffer(width: width, height: height) else {
            return
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let destination = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        var size = [Int32(width), Int32(height)]
        var rowStride = Int32(CVPixelBufferGetBytesPerRow(pixelBuffer))

        let result: Int32 = "bgr0".withCString { softwareFormat in
            size.withUnsafeMutableBufferPointer { sizeBuffer -> Int32 in
                guard let sizePtr = sizeBuffer.baseAddress else { return -1 }

                return withUnsafeMutablePointer(to: &rowStride) { rowStridePtr in
                    var params: [mpv_render_param] = [
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: UnsafeMutableRawPointer(sizePtr)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: softwareFormat)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: UnsafeMutableRawPointer(rowStridePtr)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: destination),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                    ]

                    _ = params.withUnsafeMutableBufferPointer { buffer in
                        mpv_render_context_render(renderContext, buffer.baseAddress)
                    }
                    return 0
                }
            }
        }

        guard result >= 0 else { return }
        frameOutput?.didOutputFrame(pixelBuffer)
    }

    private func waitForVideoLayerIfNeeded() async {
        guard configuration.useNativeGPUOutput else { return }

        for _ in 0..<240 {
            let isReady = stateQueue.sync { videoLayer != nil }
            if isReady { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func stringProperty(_ name: String) -> String? {
        guard let handle else { return nil }
        var raw: UnsafeMutablePointer<CChar>?
        let code = mpv_get_property(handle, name, MPV_FORMAT_STRING, &raw)
        guard code >= 0, let raw else { return nil }
        defer { mpv_free(raw) }
        return String(cString: raw)
    }

    private func logPipelineIfNeeded() {
        guard didLogPipelineForCurrentFile == false else { return }
        didLogPipelineForCurrentFile = true

        let voName = stringProperty("current-vo") ?? "unknown"
        let hwdecName = stringProperty("hwdec-current") ?? "unknown"
        let vCodec = stringProperty("video-codec") ?? "unknown"
        let aCodec = stringProperty("audio-codec-name") ?? "unknown"
        print("[MPV] pipeline vo=\(voName) hwdec=\(hwdecName) vcodec=\(vCodec) acodec=\(aCodec)")
    }

    private func makePooledPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pixelBufferPool == nil || pooledWidth != width || pooledHeight != height {
            pooledWidth = width
            pooledHeight = height

            let poolAttributes: [CFString: Any] = [
                kCVPixelBufferPoolMinimumBufferCountKey: 6
            ]
            let pixelBufferAttributes: [CFString: Any] = [
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferMetalCompatibilityKey: true
            ]

            var pool: CVPixelBufferPool?
            let createStatus = CVPixelBufferPoolCreate(
                nil,
                poolAttributes as CFDictionary,
                pixelBufferAttributes as CFDictionary,
                &pool
            )
            guard createStatus == kCVReturnSuccess else {
                pixelBufferPool = nil
                return nil
            }
            pixelBufferPool = pool
        }

        guard let pixelBufferPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }
        return pixelBuffer
    }
}
