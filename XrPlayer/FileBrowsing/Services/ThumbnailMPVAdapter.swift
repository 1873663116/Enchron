import CoreGraphics
import Foundation
import ImageIO
import Libmpv

/// Lightweight mpv instance dedicated to thumbnail extraction.
///
/// Uses `vo=libmpv` (offscreen, no display output), `pause=yes`, `cache=no`.
/// Does NOT share state with the main `MPVPlayerAdapter`.
///
/// Extraction strategy (priority order):
///   Phase B — embedded cover art (track-list/N/image == true)
///   Phase A — video frame at ~10% of duration
///
/// Security-scoped resource access mirrors MPVPlayerAdapter.performLoadStart().
/// Call `extract(from:)` and then `cleanup()` when done with the instance.
nonisolated final class ThumbnailMPVAdapter: @unchecked Sendable {

    // MARK: - Configuration

    private static let targetWidth = 320
    private static let targetHeight = 180
    private static let seekFraction = 0.10  // 10% into the file
    private static let loadTimeoutSeconds = 10.0
    private static let frameWaitTimeoutSeconds = 5.0

    // MARK: - State

    private var handle: OpaquePointer?
    private var renderContext: OpaquePointer?

    private let controlQueue = DispatchQueue(label: "xrplayer.thumbnail.mpv.control", qos: .utility)
    private let renderQueue = DispatchQueue(label: "xrplayer.thumbnail.mpv.render", qos: .utility)
    private let eventQueue = DispatchQueue(label: "xrplayer.thumbnail.mpv.events", qos: .utility)

    private var renderUpdateAvailable = false
    private let renderLock = NSLock()

    private var activeSecurityScopedURL: URL?

    /// Flag to signal the event loop to exit.
    private var shouldStopEventLoop = false
    private let eventStateLock = NSLock()
    /// Semaphore to wait for the event loop to finish draining.
    private let eventLoopDone = DispatchSemaphore(value: 0)

    // MARK: - Init / Cleanup

    init() {}

    deinit {
        cleanup()
    }

    func cleanup() {
        releaseSecurityScope()

        // Signal the event loop to stop, then wait for it to exit
        // before destroying the handle.
        if isEventLoopActive {
            requestEventLoopStop()
            eventLoopDone.wait()
            markEventLoopStopped()
        }

        if let rc = renderContext {
            mpv_render_context_set_update_callback(rc, nil, nil)
            renderQueue.sync {}  // drain in-flight callbacks
            mpv_render_context_free(rc)
            renderContext = nil
        }
        if let h = handle {
            mpv_terminate_destroy(h)
            handle = nil
        }
    }

    // MARK: - Extraction

    /// Extract a thumbnail CGImage for the given file.
    /// Returns nil on any error (file not found, timeout, corrupt).
    func extract(from file: FileBrowsingDomain.MediaFile) async -> CGImage? {
        do {
            return try await _extract(from: file)
        } catch {
            print("[Thumbnail] extraction failed for \(file.name): \(error)")
            return nil
        }
    }

    // MARK: - Private Implementation

    private func _extract(from file: FileBrowsingDomain.MediaFile) async throws -> CGImage? {
        // Set up mpv
        try setupMPV()

        // Acquire security scope for local files
        let url = file.url
        if url.isFileURL {
            let normalizedURL = url.standardizedFileURL
            if normalizedURL.startAccessingSecurityScopedResource() {
                activeSecurityScopedURL = normalizedURL
            }
        }

        // Load the file paused
        let loadArg: String
        if url.isFileURL {
            loadArg = url.standardizedFileURL.path
        } else {
            loadArg = url.absoluteString
        }

        resetFileLoadedState()
        try command(["loadfile", loadArg, "replace"])

        // Wait for FILE_LOADED event
        let fileLoaded = await waitForEvent(
            matching: { $0 == MPV_EVENT_FILE_LOADED },
            timeout: Self.loadTimeoutSeconds
        )
        guard fileLoaded else {
            print("[Thumbnail] timeout waiting for FILE_LOADED: \(file.name)")
            return nil
        }

        // Phase B: try embedded cover art first
        if let coverImage = try extractCoverArt() {
            return coverImage
        }

        // Phase A: frame at 10% duration
        return try await extractFrame()
    }

    // MARK: - Phase B: Cover Art

    private func extractCoverArt() throws -> CGImage? {
        guard let h = handle else { return nil }

        var trackCount: Int64 = 0
        let countCode = withUnsafeMutablePointer(to: &trackCount) { ptr in
            mpv_get_property(h, "track-list/count", MPV_FORMAT_INT64, ptr)
        }
        guard countCode >= 0, trackCount > 0 else { return nil }

        for index in 0..<Int(trackCount) {
            let basePath = "track-list/\(index)"

            // Only video tracks can be cover art
            guard let type = stringProperty("\(basePath)/type"), type.lowercased() == "video" else {
                continue
            }

            // image == true means embedded still (cover art / attached picture)
            guard let isImage = flagProperty("\(basePath)/image"), isImage else {
                continue
            }

            // Get the track ID
            guard let trackID = int64Property("\(basePath)/id") else { continue }

            // Switch to the cover track and screenshot
            try command(["set", "vid", String(trackID)])

            // Brief delay to let mpv decode the image track
            try awaitAsync(seconds: 0.15)

            let image = try captureToTempFile()
            // Restore default video selection (no-op if no real video tracks)
            _ = try? command(["set", "vid", "auto"])
            return image
        }

        return nil
    }

    // MARK: - Phase A: Video Frame

    private func extractFrame() async throws -> CGImage? {
        guard let h = handle else { return nil }

        // Get duration
        var duration: Double = 0
        let durationCode = withUnsafeMutablePointer(to: &duration) { ptr in
            mpv_get_property(h, "duration", MPV_FORMAT_DOUBLE, ptr)
        }

        let seekTarget: Double
        if durationCode >= 0 && duration > 0 {
            seekTarget = duration * Self.seekFraction
        } else {
            seekTarget = 5.0  // fallback: 5 seconds in
        }

        // Keyframe seek (faster than exact for thumbnails)
        try command(["seek", String(seekTarget), "absolute+keyframes"])

        // Wait for the render update callback to fire (frame available)
        let frameReady = await waitForRenderUpdate(timeout: Self.frameWaitTimeoutSeconds)
        guard frameReady else {
            print("[Thumbnail] timeout waiting for frame render update")
            return nil
        }

        return try captureToTempFile()
    }

    // MARK: - Screenshot via temp file

    private func captureToTempFile() throws -> CGImage? {
        let tempPath = NSTemporaryDirectory() + "enchron_thumb_\(UUID().uuidString).png"
        let result = try command(["screenshot-to-file", tempPath, "video"])
        _ = result

        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        guard FileManager.default.fileExists(atPath: tempPath),
            let data = try? Data(contentsOf: URL(fileURLWithPath: tempPath)),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        return downscale(cgImage, maxWidth: Self.targetWidth, maxHeight: Self.targetHeight)
    }

    // MARK: - MPV Setup

    private func setupMPV() throws {
        guard handle == nil else { return }

        guard let h = mpv_create() else {
            throw ThumbnailMPVError.createFailed
        }

        // Minimal thumbnail configuration
        let options: [(String, String)] = [
            ("vo", "libmpv"),
            ("pause", "yes"),
            ("cache", "no"),
            ("demuxer-readahead-secs", "0"),
            ("demuxer-max-bytes", "4MiB"),
            ("hwdec", "no"),     // CPU decode for isolated instances
            ("aid", "no"),       // disable audio — not needed
            ("sid", "no"),       // disable subtitles
            ("keep-open", "yes"),
            ("video-latency-hacks", "yes"),
            ("hr-seek", "no"),   // keyframe seek is faster for thumbnails
            ("msg-level", "all=error"),
            ("sub-font-provider", "none"),
            ("screenshot-format", "png"),
        ]

        for (name, value) in options {
            let code = mpv_set_option_string(h, name, value)
            if code < 0 {
                print("[Thumbnail] skip unsupported option \(name)=\(value), code=\(code)")
            }
        }

        let initCode = mpv_initialize(h)
        guard initCode >= 0 else {
            mpv_terminate_destroy(h)
            throw ThumbnailMPVError.initFailed(initCode)
        }

        handle = h

        // Create software render context for offscreen rendering
        try createRenderContext(h)

        // Start a minimal event loop to handle FILE_LOADED
        startEventLoop()
    }

    private func createRenderContext(_ h: OpaquePointer) throws {
        var context: OpaquePointer?
        let code = MPV_RENDER_API_TYPE_SW.withCString { apiType in
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                                 data: UnsafeMutableRawPointer(mutating: apiType)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return params.withUnsafeMutableBufferPointer { buf in
                mpv_render_context_create(&context, h, buf.baseAddress)
            }
        }
        guard code >= 0, let context else {
            throw ThumbnailMPVError.renderContextFailed(code)
        }
        renderContext = context

        // Set update callback so we can signal when a frame is ready
        mpv_render_context_set_update_callback(
            context,
            { ctx in
                guard let ctx else { return }
                let adapter = Unmanaged<ThumbnailMPVAdapter>.fromOpaque(ctx).takeUnretainedValue()
                adapter.markRenderUpdateAvailable()
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    // MARK: - Event Loop

    private var fileLoadedContinuation: CheckedContinuation<Bool, Never>?
    private var fileLoadedResult = false
    private var isEventLoopRunning = false

    private func startEventLoop() {
        guard markEventLoopStarted() else { return }
        eventQueue.async {
            self.runEventLoop()
        }
    }

    private func runEventLoop() {
        guard let h = handle else {
            eventLoopDone.signal()
            return
        }
        while !isEventLoopStopRequested {
            guard let event = mpv_wait_event(h, 0.05) else { continue }
            let id = event.pointee.event_id
            if id == MPV_EVENT_SHUTDOWN { break }
            if id == MPV_EVENT_FILE_LOADED {
                completeFileLoaded()
            }
            if id == MPV_EVENT_NONE { continue }
        }
        eventLoopDone.signal()
    }

    private func waitForEvent(
        matching predicate: @escaping (mpv_event_id) -> Bool,
        timeout: Double
    ) async -> Bool {
        // We specifically need FILE_LOADED here
        await withCheckedContinuation { continuation in
            let deadline = Date().addingTimeInterval(timeout)
            controlQueue.async { [weak self] in
                guard let self else { continuation.resume(returning: false); return }
                if self.fileLoadedResult {
                    continuation.resume(returning: true)
                } else {
                    // Store continuation — event loop will resume it
                    self.fileLoadedContinuation = continuation
                }
            }

            // Timeout watcher
            Task {
                let remaining = max(0, deadline.timeIntervalSinceNow)
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
                self.controlQueue.async {
                    if let cont = self.fileLoadedContinuation {
                        self.fileLoadedContinuation = nil
                        cont.resume(returning: false)
                    }
                }
            }
        }
    }

    private func waitForRenderUpdate(timeout: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            if takeRenderUpdateAvailable() { return true }
        }
        return false
    }

    private var isEventLoopActive: Bool {
        eventStateLock.withLock { isEventLoopRunning }
    }

    private var isEventLoopStopRequested: Bool {
        eventStateLock.withLock { shouldStopEventLoop }
    }

    private func markEventLoopStarted() -> Bool {
        eventStateLock.withLock {
            guard !isEventLoopRunning else { return false }
            shouldStopEventLoop = false
            isEventLoopRunning = true
            return true
        }
    }

    private func requestEventLoopStop() {
        eventStateLock.withLock {
            shouldStopEventLoop = true
        }
    }

    private func markEventLoopStopped() {
        eventStateLock.withLock {
            shouldStopEventLoop = false
            isEventLoopRunning = false
        }
    }

    private func resetFileLoadedState() {
        controlQueue.sync {
            fileLoadedResult = false
            fileLoadedContinuation = nil
        }
    }

    private func completeFileLoaded() {
        controlQueue.async {
            self.fileLoadedResult = true
            self.fileLoadedContinuation?.resume(returning: true)
            self.fileLoadedContinuation = nil
        }
    }

    private func markRenderUpdateAvailable() {
        renderLock.withLock {
            renderUpdateAvailable = true
        }
    }

    private func takeRenderUpdateAvailable() -> Bool {
        renderLock.withLock {
            let available = renderUpdateAvailable
            if available {
                renderUpdateAvailable = false
            }
            return available
        }
    }

    // MARK: - MPV Commands and Properties

    @discardableResult
    private func command(_ args: [String]) throws -> Int32 {
        guard let h = handle else { throw ThumbnailMPVError.noHandle }
        var cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cStrings.append(nil)
        defer { cStrings.dropLast().forEach { free($0) } }

        let code = cStrings.withUnsafeMutableBufferPointer { buf in
            buf.withMemoryRebound(to: UnsafePointer<CChar>?.self) { constBuf in
                mpv_command(h, constBuf.baseAddress)
            }
        }
        if code < 0 {
            print("[Thumbnail] command failed: \(args.first ?? "?") code=\(code)")
        }
        return code
    }

    private func stringProperty(_ name: String) -> String? {
        guard let h = handle else { return nil }
        var raw: UnsafeMutablePointer<CChar>?
        let code = mpv_get_property(h, name, MPV_FORMAT_STRING, &raw)
        guard code >= 0, let raw else { return nil }
        defer { mpv_free(raw) }
        return String(cString: raw)
    }

    private func int64Property(_ name: String) -> Int64? {
        guard let h = handle else { return nil }
        var value: Int64 = 0
        let code = withUnsafeMutablePointer(to: &value) { ptr in
            mpv_get_property(h, name, MPV_FORMAT_INT64, ptr)
        }
        guard code >= 0 else { return nil }
        return value
    }

    private func flagProperty(_ name: String) -> Bool? {
        guard let h = handle else { return nil }
        var value: Int32 = 0
        let code = withUnsafeMutablePointer(to: &value) { ptr in
            mpv_get_property(h, name, MPV_FORMAT_FLAG, ptr)
        }
        guard code >= 0 else { return nil }
        return value != 0
    }

    // MARK: - Helpers

    private func awaitAsync(seconds: Double) throws {
        let sema = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { sema.signal() }
        sema.wait()
    }

    private func releaseSecurityScope() {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
    }

    // MARK: - Downscale

    private func downscale(_ image: CGImage, maxWidth: Int, maxHeight: Int) -> CGImage {
        let srcW = image.width
        let srcH = image.height
        guard srcW > maxWidth || srcH > maxHeight else { return image }

        let scale = min(Double(maxWidth) / Double(srcW), Double(maxHeight) / Double(srcH))
        let dstW = max(1, Int(Double(srcW) * scale))
        let dstH = max(1, Int(Double(srcH) * scale))

        guard
            let ctx = CGContext(
                data: nil,
                width: dstW, height: dstH,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return image }

        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
        return ctx.makeImage() ?? image
    }
}

// MARK: - Errors

enum ThumbnailMPVError: Error {
    case createFailed
    case initFailed(Int32)
    case renderContextFailed(Int32)
    case noHandle
}
