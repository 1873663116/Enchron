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
        case .optionFailed(let name, let code):
            return "mpv option failed: \(name) (\(code))."
        case .initializeFailed(let code):
            return "mpv initialization failed (\(code))."
        case .commandFailed(let args, let code):
            return "mpv command failed: \(args.joined(separator: " ")) (\(code))."
        case .propertyFailed(let name, let code):
            return "mpv property failed: \(name) (\(code))."
        case .renderContextCreationFailed(let code):
            return "mpv render context creation failed (\(code))."
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .fileNotReadable(let url):
            return "File is not readable: \(url.lastPathComponent)"
        }
    }
}

struct MPVLoadRequest: Equatable {
    let url: URL
    let loadArgument: String
    let requiresSecurityScopedAccess: Bool
}

struct MPVHDRMetadataSnapshot: Equatable {
    let dolbyVisionProfile: Int64?
    let hdrFormat: String
    let primaries: String
    let gamma: String
    let colormatrix: String
    let colorlevels: String
    let signalPeak: Double?
    let sceneMaxR: Double?
    let sceneMaxG: Double?
    let sceneMaxB: Double?
}

public final class MPVPlayerAdapter: PlaybackControlling, PlaybackRuntimeManaging {
    public weak var frameOutput: FrameOutput?
    public var onRuntimeError: ((String) -> Void)?
    public var onMediaProfileDetected: ((PlaybackCoreDomain.MediaProfile) -> Void)?
    public var onPlaybackEnded: (() -> Void)?
    public var usesNativeGPUOutput: Bool { configuration.useNativeGPUOutput }
    public private(set) var isHDROutputEnabled: Bool = true
    public private(set) var isHDRContent: Bool = false

    /// Computed HDR output mode based on content detection, native GPU path, and configuration.
    public var hdrOutputMode: PlaybackCoreDomain.HDROutputMode {
        guard isHDRContent else { return .unsupported }

        if hasVerifiedHDRSurface {
            return isHDROutputEnabled ? .passthroughHDR : .toneMappedSDR
        }

        // Fallback renderer or a native route without a verified HDR surface:
        // keep the UI honest and present it as an SDR preview only.
        return .previewSDR
    }
    private var lastPlayedURL: URL?

    private let configuration: MPVConfiguration
    private let videoToolboxBridge: VideoToolboxBridge

    private var handle: OpaquePointer?
    private var renderContext: OpaquePointer?

    private let stateQueue = DispatchQueue(label: "xrplayer.mpv.state")
    private let eventQueue = DispatchQueue(label: "xrplayer.mpv.events", qos: .userInitiated)
    private let controlQueue = DispatchQueue(label: "xrplayer.mpv.control", qos: .userInitiated)
    private let renderQueue = DispatchQueue(label: "xrplayer.mpv.render", qos: .userInitiated)
    private let initializationLock = NSLock()

    private var isEventLoopRunning = false
    private var shouldStopEventLoop = false
    private var internalQueueDepth = 0

    private var internalState: PlaybackCoreDomain.PlaybackState = .idle
    private var internalPosition: PlaybackCoreDomain.PlaybackPosition = .init(
        seconds: 0, duration: 0)
    private var internalAudioTracks: [PlaybackCoreDomain.AudioTrack] = []
    private var internalSubtitleTracks: [PlaybackCoreDomain.SubtitleTrack] = []
    // Cached current track IDs — updated from event thread to avoid main-thread mpv_get_property calls.
    private var internalCurrentAudioTrackID: String? = nil
    private var internalCurrentSubtitleTrackID: String? = nil

    // Protected by stateQueue
    private var currentTimeSeconds: Double = 0
    private var currentDurationSeconds: Double = 0
    private var renderWidth: Int = 1920
    private var renderHeight: Int = 1080
    private var activeSecurityScopedURL: URL?
    private var pixelBufferPool: CVPixelBufferPool?
    private var pooledWidth: Int = 0
    private var pooledHeight: Int = 0
    private weak var videoLayer: CAMetalLayer?

    /// The native CAMetalLayer used by gpu-next rendering. Exposed read-only
    /// for the panorama bridge to read rendered drawables.
    public var nativeVideoLayer: CAMetalLayer? {
        stateQueue.sync { videoLayer }
    }
    private var activeNativeGPUOutput: Bool = false
    private var didLogPipelineForCurrentFile = false
    // Protected by stateQueue — written from event thread, read from public setHDREnabled.
    private var cachedHDRType: PlaybackCoreDomain.HDRType = .sdr
    private var cachedSignalPeak: Double?

    // Used to signal waitForVideoLayerIfNeeded() without polling.
    // Protected by stateQueue.
    private var videoLayerContinuation: CheckedContinuation<Void, Never>?
    private var shouldWarmupWhenLayerArrives = false
    private var isAwaitingVisualPlaybackStart = false
    /// When true, MPV_EVENT_FILE_LOADED will NOT unpause — used by loadPaused(url:) for track enumeration without rendering frames.
    private var isPrepareOnlyLoad = false

    private var hasVerifiedHDRSurface: Bool {
        stateQueue.sync {
            guard activeNativeGPUOutput, let videoLayer else { return false }
            return videoLayer.wantsExtendedDynamicRangeContent
        }
    }

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
        let (continuation, shouldRecreateNativeContext): (CheckedContinuation<Void, Never>?, Bool) =
            stateQueue.sync {
                let previousLayer = videoLayer
                videoLayer = layer

                let continuation: CheckedContinuation<Void, Never>?
                if layer != nil {
                    continuation = videoLayerContinuation
                    videoLayerContinuation = nil
                } else {
                    continuation = nil
                }

                let shouldRecreateNativeContext =
                    activeNativeGPUOutput && previousLayer != nil && previousLayer !== layer

                return (continuation, shouldRecreateNativeContext)
            }

        if shouldRecreateNativeContext {
            // The native gpu-next path stores the CAMetalLayer pointer via `wid`.
            // When SwiftUI destroys or replaces the hosting view, that pointer
            // becomes stale. Recreate libmpv so MoltenVK binds to the new layer.
            teardownMPV()
        }

        // Resume outside stateQueue to avoid priority inversion.
        continuation?.resume()
        if layer != nil {
            scheduleDeferredWarmupIfNeeded()
        }
    }

    /// Pre-initialise the MPV context to reduce first-play latency.
    /// In software-rendering mode (simulator) this fully initialises the mpv context.
    /// In native GPU mode the Metal layer must be present before mpv_initialize(),
    /// so this starts the event loop infrastructure but defers the mpv context
    /// creation until the layer is attached and play() is called.
    public func warmup() {
        print("[MPV] warmup_requested native=\(configuration.useNativeGPUOutput)")
        if configuration.useNativeGPUOutput {
            let shouldScheduleImmediately = stateQueue.sync { () -> Bool in
                shouldWarmupWhenLayerArrives = true
                return videoLayer != nil
            }
            if shouldScheduleImmediately == false {
                print("[MPV] warmup_waiting_for_layer")
            }
            if shouldScheduleImmediately {
                scheduleDeferredWarmupIfNeeded()
            }
            return
        }
        print("[MPV] warmup_started mode=software")
        try? ensureMPVReady()
        print("[MPV] warmup_ready mode=software")
        startEventLoop()
    }

    deinit {
        teardownMPV()
    }

    public func play(url: URL) async throws {
        do {
            print("[MPV] request_started url=\(url.lastPathComponent)")
            await waitForVideoLayerIfNeeded()
            print("[MPV] layer_attached url=\(url.lastPathComponent)")
            try await performLoadStart(for: url)
        } catch {
            print(
                "[MPV] playback_failed url=\(url.lastPathComponent) error=\(error.localizedDescription)"
            )
            notifyRuntimeError(error.localizedDescription)
            throw error
        }
    }

    /// Loads a file into mpv without starting playback.
    /// Used for track enumeration in the prepare/confirm flow.
    /// mpv parses the container and populates track lists but never decodes or renders frames.
    /// Call `resume()` after confirmation to begin actual playback.
    public func loadPaused(url: URL) async throws {
        do {
            print("[MPV] load_paused_started url=\(url.lastPathComponent)")
            stateQueue.sync { isPrepareOnlyLoad = true }
            setFlagProperty(name: "pause", value: true)
            await waitForVideoLayerIfNeeded()
            try await performLoadStart(for: url)
        } catch {
            stateQueue.sync { isPrepareOnlyLoad = false }
            print("[MPV] load_paused_failed url=\(url.lastPathComponent) error=\(error.localizedDescription)")
            notifyRuntimeError(error.localizedDescription)
            throw error
        }
    }

    public func pause() {
        setFlagProperty(name: "pause", value: true)
        updateState(.paused)
    }

    public func resume() {
        stateQueue.sync { isPrepareOnlyLoad = false }
        setFlagProperty(name: "pause", value: false)
        setFlagProperty(name: "mute", value: false)
        let shouldShowPlaying = stateQueue.sync { isAwaitingVisualPlaybackStart == false }
        if shouldShowPlaying {
            updateState(.playing)
        }
    }

    public func stop() {
        _ = try? command(["stop"])
        stateQueue.sync {
            isAwaitingVisualPlaybackStart = false
            isPrepareOnlyLoad = false
        }
        updateState(.stopped)
        releaseSecurityScopedAccess()
    }

    public func cancelPendingLoad() {
        _ = try? command(["stop"])
        stateQueue.sync { isAwaitingVisualPlaybackStart = false }
        updateState(.idle)
        releaseSecurityScopedAccess()
    }

    public func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        guard (try? command(["seek", String(clamped), "absolute+exact"])) != nil else {
            return
        }

        let actual = doubleProperty("playback-time") ?? clamped
        let time = max(0, actual)
        let dur = stateQueue.sync {
            currentTimeSeconds = time
            return currentDurationSeconds
        }
        updatePosition(seconds: time, duration: dur)
    }

    public func skip(by seconds: Double) {
        guard seconds != 0 else { return }
        guard (try? command(["seek", String(seconds), "relative+exact"])) != nil else {
            return
        }

        if let actual = doubleProperty("playback-time") {
            let time = max(0, actual)
            let dur = stateQueue.sync {
                currentTimeSeconds = time
                return currentDurationSeconds
            }
            updatePosition(seconds: time, duration: dur)
        }
    }

    public func setSpeed(_ speed: PlaybackCoreDomain.PlaybackSpeed) {
        setDoubleProperty(name: "speed", value: speed.value)
    }

    public func selectAudioTrack(_ track: PlaybackCoreDomain.AudioTrack) {
        _ = try? command(["set", "aid", track.id])
        // Optimistic update — keeps UI responsive without a main-thread mpv_get_property call.
        stateQueue.sync { internalCurrentAudioTrackID = track.id }
    }

    public func selectSubtitleTrack(_ track: PlaybackCoreDomain.SubtitleTrack?) {
        if let track {
            _ = try? command(["set", "sid", track.id])
            stateQueue.sync { internalCurrentSubtitleTrackID = track.id }
        } else {
            _ = try? command(["set", "sid", "no"])
            stateQueue.sync { internalCurrentSubtitleTrackID = nil }
        }
    }

    public func replay() {
        guard let url = lastPlayedURL else { return }
        _ = try? command(["seek", "0", "absolute"])
        setFlagProperty(name: "pause", value: false)
        updateState(.playing)
    }

    public func setHDREnabled(_ enabled: Bool) {
        let commands = manualHDROutputCommands(enabled: enabled)
        for args in commands {
            _ = try? command(args)
        }
        stateQueue.sync {
            videoLayer?.wantsExtendedDynamicRangeContent = enabled
        }
        isHDROutputEnabled = enabled
        if enabled && isHDRContent {
            applyEDRMetadataToLayer()
        } else {
            stateQueue.sync {
                guard let layer = videoLayer else { return }
                if #available(visionOS 1.0, *) {
                    layer.edrMetadata = nil
                }
            }
            print("[MPV] edr_metadata cleared reason=hdr_disabled")
        }
        logHDRPipelineState(reason: "manual_toggle")
    }

    public func frameStepForward() {
        _ = try? command(["frame-step"])
    }

    public func frameStepBackward() {
        _ = try? command(["frame-back-step"])
    }

    public func debugSubtitleState() -> String {
        let sid = stringProperty("sid") ?? "nil"
        let visibility = stringProperty("sub-visibility") ?? "nil"
        let text = stringProperty("sub-text") ?? ""
        let assText = stringProperty("sub-text/ass") ?? ""
        let start = stringProperty("sub-start/full") ?? "nil"
        let end = stringProperty("sub-end/full") ?? "nil"
        let vo = stringProperty("current-vo") ?? "nil"
        return
            "sid=\(sid) vis=\(visibility) start=\(start) end=\(end) vo=\(vo) text=\(text) ass=\(assText)"
    }

    public func captureScreenshot(to url: URL, flags: String = "subtitles") {
        _ = try? command(["screenshot-to-file", url.path, flags])
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

    public var currentAudioTrackID: String? {
        // Read from cache — safe to call from any thread including the main thread.
        stateQueue.sync { internalCurrentAudioTrackID }
    }

    public var currentSubtitleTrackID: String? {
        // Read from cache — safe to call from any thread including the main thread.
        stateQueue.sync { internalCurrentSubtitleTrackID }
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
        initializationLock.lock()
        defer { initializationLock.unlock() }

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
            print(
                "[MPV] output-route=\(activeNativeGPUOutput ? "native-gpu" : "sw-render-fallback")")

            if activeNativeGPUOutput == false {
                try createRenderContext()
            }
        } catch {
            mpv_terminate_destroy(created)
            throw error
        }
    }

    private func teardownMPV() {
        initializationLock.lock()
        defer { initializationLock.unlock() }

        // Cancel any in-flight waitForVideoLayerIfNeeded so callers don't hang.
        let pendingContinuation: CheckedContinuation<Void, Never>? = stateQueue.sync {
            let c = videoLayerContinuation
            videoLayerContinuation = nil
            return c
        }
        pendingContinuation?.resume()

        stopEventLoop()

        if let renderContext {
            mpv_render_context_set_update_callback(renderContext, nil, nil)
            renderQueue.sync {}  // drain in-flight render callbacks before freeing
            mpv_render_context_free(renderContext)
            self.renderContext = nil
        }

        if let handle {
            mpv_terminate_destroy(handle)
            self.handle = nil
        }

        activeNativeGPUOutput = false
        pixelBufferPool = nil
        pooledWidth = 0
        pooledHeight = 0

        releaseSecurityScopedAccess()

        stateQueue.sync {
            isEventLoopRunning = false
            shouldStopEventLoop = true
            internalQueueDepth = 0
            internalState = .stopped
            isAwaitingVisualPlaybackStart = false
            shouldWarmupWhenLayerArrives = false
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
        _ = mpv_observe_property(handle, 9, "paused-for-cache", MPV_FORMAT_FLAG)
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
                mpv_render_param(
                    type: MPV_RENDER_PARAM_API_TYPE,
                    data: UnsafeMutableRawPointer(mutating: apiTypeCString)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
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
            stateQueue.sync { isAwaitingVisualPlaybackStart = true }
            updateState(.loading)
        case MPV_EVENT_FILE_LOADED:
            let prepareOnly = stateQueue.sync { isPrepareOnlyLoad }
            stateQueue.sync { isAwaitingVisualPlaybackStart = !prepareOnly }
            if !prepareOnly {
                updateState(.loading)
            }
            didLogPipelineForCurrentFile = false
            if !prepareOnly {
                setFlagProperty(name: "pause", value: false)
                setFlagProperty(name: "mute", value: false)
            }
            _ = try? command(["set", "vid", "auto"])
            _ = try? command(["set", "aid", "auto"])
            _ = try? command(["set", "sid", "no"])
            // Reset cached IDs before refreshTrackCache re-populates them from actual MPV state.
            stateQueue.sync {
                internalCurrentAudioTrackID = nil
                internalCurrentSubtitleTrackID = nil
            }
            refreshTrackCache()
            detectAndNotifyMediaProfile()
            logPipelineIfNeeded()
            let hasVideoTrack =
                (stringProperty("video-codec")?.isEmpty == false)
                || ((int64Property("vid") ?? 0) > 0)
            if hasVideoTrack == false {
                markPlaybackReadyIfNeeded()
            }
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
            detectAndNotifyMediaProfile()
            markPlaybackReadyIfNeeded()
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
            let time = data.pointee
            stateQueue.sync { currentTimeSeconds = time }
            let dur = stateQueue.sync { currentDurationSeconds }
            updatePosition(seconds: time, duration: dur)
            markPlaybackReadyIfNeeded()

        case "duration":
            guard property.format == MPV_FORMAT_DOUBLE,
                let data = property.data?.assumingMemoryBound(to: Double.self)
            else { return }
            let dur = data.pointee
            stateQueue.sync { currentDurationSeconds = dur }
            let time = stateQueue.sync { currentTimeSeconds }
            updatePosition(seconds: time, duration: dur)

        case "pause":
            guard property.format == MPV_FORMAT_FLAG,
                let data = property.data?.assumingMemoryBound(to: Int32.self)
            else { return }
            let shouldIgnorePauseChange = stateQueue.sync { isAwaitingVisualPlaybackStart }
            if shouldIgnorePauseChange {
                return
            }
            let currentState = stateQueue.sync { internalState }
            if currentState != .ended {
                updateState(data.pointee != 0 ? .paused : .playing)
            }

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
            stateQueue.sync { renderWidth = max(1, Int(data.pointee)) }

        case "dheight":
            guard property.format == MPV_FORMAT_INT64,
                let data = property.data?.assumingMemoryBound(to: Int64.self)
            else { return }
            stateQueue.sync { renderHeight = max(1, Int(data.pointee)) }

        case "track-list":
            refreshTrackCache()

        case "paused-for-cache":
            handlePausedForCacheChange(property)

        default:
            break
        }
    }

    private func handlePausedForCacheChange(_ property: mpv_event_property) {
        guard property.format == MPV_FORMAT_FLAG,
            let data = property.data?.assumingMemoryBound(to: Int32.self)
        else { return }
        let shouldIgnore = stateQueue.sync { isAwaitingVisualPlaybackStart }
        if shouldIgnore { return }
        if data.pointee != 0 {
            updateState(.buffering)
        } else {
            let isPaused = flagProperty("pause") ?? false
            updateState(isPaused ? .paused : .playing)
        }
    }

    private func refreshTrackCache() {
        guard let handle else { return }

        let activeAudioID = stringProperty("aid")
        let activeSubtitleID = stringProperty("sid")

        var count: Int64 = 0
        let countCode = withUnsafeMutablePointer(to: &count) { countPtr in
            mpv_get_property(handle, "track-list/count", MPV_FORMAT_INT64, countPtr)
        }
        guard countCode >= 0, count > 0 else {
            stateQueue.sync {
                internalAudioTracks = []
                internalSubtitleTracks = []
            }
            return
        }

        var audio: [PlaybackCoreDomain.AudioTrack] = []
        var subtitles: [PlaybackCoreDomain.SubtitleTrack] = []

        for index in 0..<Int(count) {
            let basePath = "track-list/\(index)"
            guard let type = stringProperty("\(basePath)/type")?.lowercased() else {
                continue
            }

            let id: String
            if let idInt = int64Property("\(basePath)/id") {
                id = String(idInt)
            } else if let idString = stringProperty("\(basePath)/id"), idString.isEmpty == false {
                id = idString
            } else {
                continue
            }

            let lang = normalizeTrackMetadata(stringProperty("\(basePath)/lang"))
            let title = normalizeTrackMetadata(stringProperty("\(basePath)/title"))
            let displayName = title ?? "\(type.capitalized) \(id)"
            let isDefaultTrack = flagProperty("\(basePath)/default") ?? false

            switch type {
            case "audio":
                let isCurrent = activeAudioID == id
                audio.append(
                    .init(
                        id: id,
                        languageCode: lang,
                        displayName: displayName,
                        isDefault: isDefaultTrack || isCurrent
                    )
                )
            case "sub":
                let isCurrent = activeSubtitleID == id
                subtitles.append(
                    .init(
                        id: id,
                        languageCode: lang,
                        displayName: displayName,
                        isDefault: isDefaultTrack || isCurrent
                    )
                )
            default:
                continue
            }
        }

        // Normalise "no" to nil so cached IDs are consistent with the public API contract.
        let newAudioID: String? =
            (activeAudioID == "no" || activeAudioID == nil) ? nil : activeAudioID
        let newSubtitleID: String? =
            (activeSubtitleID == "no" || activeSubtitleID == nil) ? nil : activeSubtitleID

        stateQueue.sync {
            internalAudioTracks = audio
            internalSubtitleTracks = subtitles
            internalCurrentAudioTrackID = newAudioID
            internalCurrentSubtitleTrackID = newSubtitleID
        }
    }

    private func handleEndFileEvent(_ data: UnsafeMutableRawPointer?) {
        stateQueue.sync { isAwaitingVisualPlaybackStart = false }
        guard let pointer = data?.assumingMemoryBound(to: mpv_event_end_file.self) else {
            updateState(.ended)
            releaseSecurityScopedAccess()
            return
        }

        let payload = pointer.pointee
        if payload.reason == MPV_END_FILE_REASON_ERROR {
            updateState(.failed)
            let message =
                "Playback ended with error: \(mpvErrorString(payload.error)) (\(payload.error))"
            print("[MPV] \(message)")
            notifyRuntimeError(message)
        } else {
            updateState(.ended)
            DispatchQueue.main.async { [weak self] in
                self?.onPlaybackEnded?()
            }
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
        let text =
            payload.text.map(String.init(cString:))?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
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

    static func makeLoadRequest(for url: URL) throws -> MPVLoadRequest {
        if url.isFileURL {
            let normalizedURL = url.standardizedFileURL
            let path = normalizedURL.path

            guard FileManager.default.fileExists(atPath: path) else {
                throw MPVPlayerAdapterError.fileNotFound(normalizedURL)
            }

            guard FileManager.default.isReadableFile(atPath: path) else {
                throw MPVPlayerAdapterError.fileNotReadable(normalizedURL)
            }

            return MPVLoadRequest(
                url: normalizedURL,
                loadArgument: path,
                requiresSecurityScopedAccess: true
            )
        }

        return MPVLoadRequest(
            url: url,
            loadArgument: url.absoluteString,
            requiresSecurityScopedAccess: false
        )
    }

    private func setFlagProperty(name: String, value: Bool) {
        guard let handle else { return }
        var flag: Int32 = value ? 1 : 0
        _ = mpv_set_property(handle, name, MPV_FORMAT_FLAG, &flag)
    }

    private func setIntProperty(name: String, value: Int64) {
        guard let handle else { return }
        var v = value
        _ = mpv_set_property(handle, name, MPV_FORMAT_INT64, &v)
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
        stateQueue.sync { isAwaitingVisualPlaybackStart = false }
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

        let (width, height) = stateQueue.sync { (max(1, renderWidth), max(1, renderHeight)) }

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
                        mpv_render_param(
                            type: MPV_RENDER_PARAM_SW_SIZE, data: UnsafeMutableRawPointer(sizePtr)),
                        mpv_render_param(
                            type: MPV_RENDER_PARAM_SW_FORMAT,
                            data: UnsafeMutableRawPointer(mutating: softwareFormat)),
                        mpv_render_param(
                            type: MPV_RENDER_PARAM_SW_STRIDE,
                            data: UnsafeMutableRawPointer(rowStridePtr)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: destination),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
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

        let isAlreadyReady = stateQueue.sync { videoLayer != nil }
        if isAlreadyReady { return }

        // Use a continuation so we resume the instant attachVideoLayer() is called,
        // rather than burning CPU cycles polling every 5 ms.
        await withCheckedContinuation { continuation in
            let alreadyReady = stateQueue.sync { () -> Bool in
                if videoLayer != nil { return true }
                // Another call may have stored a continuation concurrently — cancel
                // the old one by resuming it so it doesn't leak.
                videoLayerContinuation?.resume()
                videoLayerContinuation = continuation
                return false
            }
            if alreadyReady {
                continuation.resume()
            }
        }
    }

    private func performLoadStart(for url: URL) async throws {
        try await runOnControlQueue { [self] in
            try ensureMPVReady()
            print("[MPV] mpv_ready url=\(url.lastPathComponent)")
            logHDRPipelineState(reason: "mpv_ready")
            startEventLoop()

            let loadRequest = try Self.makeLoadRequest(for: url)
            lastPlayedURL = loadRequest.url

            var acquiredScope = false
            if loadRequest.requiresSecurityScopedAccess,
                loadRequest.url.startAccessingSecurityScopedResource()
            {
                acquiredScope = true
                activeSecurityScopedURL = loadRequest.url
            }

            do {
                updateState(.loading)
                isHDRContent = false
                isHDROutputEnabled = true
                if url.scheme == "smb" || url.scheme == "http" || url.scheme == "https" {
                    print("[MPV] remote_prepare_started url=\(url.lastPathComponent)")
                }
                try command(["loadfile", loadRequest.loadArgument, "replace"])
                print("[MPV] loadfile_sent url=\(url.lastPathComponent)")
            } catch {
                if acquiredScope {
                    loadRequest.url.stopAccessingSecurityScopedResource()
                    activeSecurityScopedURL = nil
                }
                throw error
            }
        }
    }

    private func runOnControlQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T)
        async throws -> T
    {
        try await withCheckedThrowingContinuation { continuation in
            controlQueue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func scheduleDeferredWarmupIfNeeded() {
        let shouldWarmup = stateQueue.sync { () -> Bool in
            guard configuration.useNativeGPUOutput, shouldWarmupWhenLayerArrives, videoLayer != nil
            else {
                return false
            }
            shouldWarmupWhenLayerArrives = false
            return true
        }
        guard shouldWarmup else { return }

        controlQueue.async { [weak self] in
            guard let self else { return }
            do {
                print("[MPV] warmup_started mode=native")
                try self.ensureMPVReady()
                print("[MPV] warmup_ready mode=native")
                self.startEventLoop()
            } catch {
                self.notifyRuntimeError(error.localizedDescription)
            }
        }
    }

    private func markPlaybackReadyIfNeeded() {
        let shouldTransition = stateQueue.sync { () -> Bool in
            guard isAwaitingVisualPlaybackStart else { return false }
            isAwaitingVisualPlaybackStart = false
            return true
        }
        guard shouldTransition else { return }

        if let url = lastPlayedURL {
            print("[MPV] first_frame_visible url=\(url.lastPathComponent)")
        }
        let isPaused = flagProperty("pause") ?? false
        updateState(isPaused ? .paused : .playing)
    }

    private func stringProperty(_ name: String) -> String? {
        guard let handle else { return nil }
        var raw: UnsafeMutablePointer<CChar>?
        let code = mpv_get_property(handle, name, MPV_FORMAT_STRING, &raw)
        guard code >= 0, let raw else { return nil }
        defer { mpv_free(raw) }
        return String(cString: raw)
    }

    private func int64Property(_ name: String) -> Int64? {
        guard let handle else { return nil }
        var value: Int64 = 0
        let code = withUnsafeMutablePointer(to: &value) { pointer in
            mpv_get_property(handle, name, MPV_FORMAT_INT64, pointer)
        }
        guard code >= 0 else { return nil }
        return value
    }

    private func doubleProperty(_ name: String) -> Double? {
        guard let handle else { return nil }
        var value: Double = 0
        let code = withUnsafeMutablePointer(to: &value) { pointer in
            mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, pointer)
        }
        guard code >= 0 else { return nil }
        return value
    }

    private func flagProperty(_ name: String) -> Bool? {
        guard let handle else { return nil }
        var value: Int32 = 0
        let code = withUnsafeMutablePointer(to: &value) { pointer in
            mpv_get_property(handle, name, MPV_FORMAT_FLAG, pointer)
        }
        guard code >= 0 else { return nil }
        return value != 0
    }

    private func normalizeTrackMetadata(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            value.isEmpty == false
        else {
            return nil
        }
        return value
    }

    private func detectAndNotifyMediaProfile() {
        let hdrMetadata = currentHDRMetadata()
        let hdrType = Self.inferHDRType(from: hdrMetadata)
        stateQueue.sync {
            cachedHDRType = hdrType
            cachedSignalPeak = hdrMetadata.signalPeak
        }
        isHDRContent = hdrType != .sdr
        if isHDRContent {
            isHDROutputEnabled = true
            applyHDRRuntimeConfiguration()
        } else {
            // SDR content: clear any leftover EDR metadata from previous HDR content
            applyEDRMetadataToLayer()
        }

        let width = Int(int64Property("video-params/w") ?? 0)
        let height = Int(int64Property("video-params/h") ?? 0)
        let frameRate = max(0, doubleProperty("container-fps") ?? 0)

        // Compute horizontal FOV to distinguish equirectangular180 vs equirectangular360.
        // Priority: direct HFOV tag → CroppedAreaImageWidthPixels / FullPanoWidthPixels × 360.
        let gSphericalDirectFOV = stringProperty("metadata/by-key/GSpherical:InitialHorizontalFOVDegrees")
            .flatMap { Double($0) }
        let gSphericalFullPanoWidth = stringProperty("metadata/by-key/GSpherical:FullPanoWidthPixels")
            .flatMap { Double($0) }
        let gSphericalCroppedWidth = stringProperty("metadata/by-key/GSpherical:CroppedAreaImageWidthPixels")
            .flatMap { Double($0) }
        let computedFOV: Double?
        if let directFOV = gSphericalDirectFOV, directFOV > 0 {
            computedFOV = directFOV
        } else if let fullW = gSphericalFullPanoWidth, let croppedW = gSphericalCroppedWidth, fullW > 0 {
            computedFOV = (croppedW / fullW) * 360.0
        } else {
            computedFOV = nil
        }

        let projectionInput = ProjectionDetectionInput(
            stereo3dIn: stringProperty("video-params/stereo-in")
                ?? stringProperty("video-params/stereo3d-in")
                ?? "",
            gSphericalSpherical: stringProperty("metadata/by-key/GSpherical:Spherical"),
            gSphericalProjectionType: stringProperty("metadata/by-key/GSpherical:ProjectionType"),
            horizontalFOVDegrees: computedFOV,
            aspectRatio: (width > 0 && height > 0) ? Double(width) / Double(height) : nil
        )
        let projectionType = ProjectionDetection.detect(from: projectionInput)

        print(
            "[MPV] media-profile hdr=\(hdrType.rawValue) projection=\(projectionType.rawValue) dovi=\(hdrMetadata.dolbyVisionProfile.map(String.init) ?? "nil") hdr-format=\(hdrMetadata.hdrFormat.ifEmpty("nil")) colormatrix=\(hdrMetadata.colormatrix.ifEmpty("nil")) gamma=\(hdrMetadata.gamma.ifEmpty("nil")) primaries=\(hdrMetadata.primaries.ifEmpty("nil")) colorlevels=\(hdrMetadata.colorlevels.ifEmpty("nil")) sig-peak=\(hdrMetadata.signalPeak.map { String(format: "%.2f", $0) } ?? "nil") stereo3d=\(projectionInput.stereo3dIn.ifEmpty("nil")) gspherical=\(projectionInput.gSphericalSpherical ?? "nil")"
        )
        logHDRPipelineState(reason: "media_profile_detected")

        let videoCodec = stringProperty("video-codec")
        let durationSecs = doubleProperty("duration")

        let profile = PlaybackCoreDomain.MediaProfile(
            projectionType: projectionType,
            hdrType: hdrType,
            resolution: .init(width: width, height: height),
            frameRate: frameRate,
            videoCodec: videoCodec,
            durationSeconds: durationSecs
        )

        DispatchQueue.main.async { [weak self] in
            self?.onMediaProfileDetected?(profile)
        }
    }

    private func inferHDRType() -> PlaybackCoreDomain.HDRType {
        Self.inferHDRType(from: currentHDRMetadata())
    }

    static func inferHDRType(from metadata: MPVHDRMetadataSnapshot) -> PlaybackCoreDomain.HDRType {
        let hdrFormat = metadata.hdrFormat.lowercased()
        let primaries = metadata.primaries.lowercased()
        let gamma = metadata.gamma.lowercased()
        let colormatrix = metadata.colormatrix.lowercased()
        let scenePeak =
            [
                metadata.sceneMaxR,
                metadata.sceneMaxG,
                metadata.sceneMaxB,
            ]
            .compactMap { $0 }
            .max() ?? 0
        let hasBT2020Markers =
            primaries.contains("bt.2020") || primaries.contains("bt2020")
            || colormatrix.contains("bt.2020") || colormatrix.contains("bt2020")
        let hasDolbyVisionMarkers =
            metadata.dolbyVisionProfile != nil || hdrFormat.contains("dolby")
            || hdrFormat.contains("dovi") || colormatrix.contains("dolby")
            || colormatrix.contains("dovi")

        if hasDolbyVisionMarkers {
            return .dolbyVision
        }
        if hdrFormat.contains("hdr10+") || hdrFormat.contains("hdr10plus") {
            return .hdr10Plus
        }
        if gamma.contains("arib-std-b67") || gamma.contains("hlg") {
            return .hlg
        }
        if hdrFormat.contains("hdr10") {
            return .hdr10
        }
        if gamma.contains("smpte2084") || gamma.contains("pq") {
            return .hdr10
        }
        // Trust peak-based fallback only when the stream also carries BT.2020-era gamut markers.
        // Primaries alone are not a sufficient HDR signal, but combined with extended peak data
        // they are a safer fallback than the previous "BT.2020 means HDR" heuristic.
        if let signalPeak = metadata.signalPeak, signalPeak > 1.05, hasBT2020Markers {
            return .hdr10
        }
        if scenePeak > 1.0, hasBT2020Markers {
            return .hdr10
        }
        return .sdr
    }

    private func currentHDRMetadata() -> MPVHDRMetadataSnapshot {
        MPVHDRMetadataSnapshot(
            dolbyVisionProfile: dolbyVisionProfile(),
            hdrFormat: stringProperty("video-params/hdr-format") ?? "",
            primaries: stringProperty("video-params/primaries") ?? "",
            gamma: stringProperty("video-params/gamma")
                ?? stringProperty("video-params/transfer-characteristics")
                ?? "",
            colormatrix: stringProperty("video-params/colormatrix")
                ?? stringProperty("video-params/colorspace")
                ?? "",
            colorlevels: stringProperty("video-params/colorlevels") ?? "",
            signalPeak: doubleProperty("video-params/sig-peak"),
            sceneMaxR: doubleProperty("video-params/scene-max-r"),
            sceneMaxG: doubleProperty("video-params/scene-max-g"),
            sceneMaxB: doubleProperty("video-params/scene-max-b")
        )
    }

    private func dolbyVisionProfile() -> Int64? {
        for propertyName in [
            "video-params/dovi-profile",
            "video-params/dolby-vision-profile",
        ] {
            if let numericValue = int64Property(propertyName), numericValue > 0 {
                return numericValue
            }

            if let stringValue = stringProperty(propertyName)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                let parsedValue = Int64(stringValue),
                parsedValue > 0
            {
                return parsedValue
            }
        }

        return nil
    }

    private func applyHDRRuntimeConfiguration() {
        for args in configuration.hdrRuntimeCommands() {
            _ = try? command(args)
        }
        stateQueue.sync {
            videoLayer?.wantsExtendedDynamicRangeContent = true
        }
        applyEDRMetadataToLayer()
        logHDRPipelineState(reason: "auto_runtime_config")
    }

    private func applyEDRMetadataToLayer() {
        // Read cached values and apply to layer atomically under stateQueue
        let (descriptor, logType, logPeak): (EDRMetadataDescriptor?, String, String) = stateQueue.sync {
            let desc = EDRMetadataSelection.descriptor(
                for: cachedHDRType,
                signalPeak: cachedSignalPeak
            )
            let typeStr = cachedHDRType.rawValue
            let peakStr = cachedSignalPeak.map { String(format: "%.2f", $0) } ?? "nil"

            guard let layer = videoLayer else { return (desc, typeStr, peakStr) }
            switch desc {
            case .hdr10(let minLuminance, let maxLuminance, let opticalOutputScale):
                if #available(visionOS 1.0, *) {
                    layer.edrMetadata = CAEDRMetadata.hdr10(
                        minLuminance: minLuminance,
                        maxLuminance: maxLuminance,
                        opticalOutputScale: opticalOutputScale
                    )
                }
            case .hlg:
                if #available(visionOS 1.0, *) {
                    layer.edrMetadata = CAEDRMetadata.hlg
                }
            case nil:
                if #available(visionOS 1.0, *) {
                    layer.edrMetadata = nil
                }
            }
            return (desc, typeStr, peakStr)
        }
        print("[MPV] edr_metadata applied type=\(logType) sig-peak=\(logPeak) descriptor=\(descriptor.map { "\($0)" } ?? "nil")")
    }

    private func manualHDROutputCommands(enabled: Bool) -> [[String]] {
        if enabled {
            return [
                ["set", "target-colorspace-hint", "auto"]
            ] + configuration.hdrRuntimeCommands()
        }

        return [
            ["set", "target-colorspace-hint", "no"]
        ] + configuration.sdrRuntimeCommands()
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

    private func logHDRPipelineState(reason: String) {
        let outputMode = hdrOutputMode.rawValue
        let targetTRC = stringProperty("target-trc") ?? "unknown"
        let targetPrimaries = stringProperty("target-prim") ?? "unknown"
        let colorspaceHint = stringProperty("target-colorspace-hint") ?? "unknown"
        let currentVO = stringProperty("current-vo") ?? "unknown"
        print(
            "[MPV] hdr_state reason=\(reason) content=\(isHDRContent) enabled=\(isHDROutputEnabled) verified_surface=\(hasVerifiedHDRSurface) output=\(outputMode) vo=\(currentVO) target-trc=\(targetTRC) target-prim=\(targetPrimaries) colorspace-hint=\(colorspaceHint)"
        )
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
                kCVPixelBufferMetalCompatibilityKey: true,
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

extension String {
    fileprivate func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
