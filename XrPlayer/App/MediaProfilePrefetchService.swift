import AVFoundation
import Foundation

/// Background prefetch service for folder-level MediaProfile cache warming.
///
/// When the file browser loads a folder, this service queues all video files
/// for background profile detection using AVFoundation. Detected profiles are
/// written to `PlaybackMediaMetadataService` so the detail page can read them
/// from cache without waiting for mpv to detect them at open time.
///
/// Concurrency model:
/// - max 3 concurrent prefetch tasks per folder load (TaskGroup)
/// - 3-second timeout per file (matches Unit 2 preparePlayback timeout)
/// - Fast-switch: when a new folder load starts, the previous prefetch Task is cancelled
/// - Session-level dedup: tracks (fileIdentifier, modifiedAt) to skip already-prefetched files
public actor MediaProfilePrefetchService {
    private let metadataService: PlaybackMediaMetadataService
    private static let maxConcurrency = 3
    private static let timeoutSeconds: Duration = .seconds(3)

    /// Tracks recently prefetched files within this session to avoid redundant work.
    /// Key: fileIdentifier.rawValue, Value: modifiedAt at time of prefetch.
    private var sessionCache: [String: Date] = [:]

    /// The Task running the current folder's batch prefetch.
    /// Cancelling this cancels all in-flight sub-tasks for the previous folder.
    private var activeBatchTask: Task<Void, Never>?

    public init(metadataService: PlaybackMediaMetadataService = PlaybackMediaMetadataService()) {
        self.metadataService = metadataService
    }

    /// Cancels any in-flight batch and starts prefetching the given files.
    /// Safe to call from @MainActor context (FileBrowsingViewModel).
    public func prefetchProfiles(
        for requests: [(request: PlaybackLaunchRequest, modifiedAt: Date)]
    ) {
        activeBatchTask?.cancel()

        guard !requests.isEmpty else { return }

        activeBatchTask = Task { [weak self] in
            guard let self else { return }
            await self.runBatch(requests: requests)
        }
    }

    // MARK: - Internal

    private func runBatch(requests: [(request: PlaybackLaunchRequest, modifiedAt: Date)]) async {
        await withTaskGroup(of: Void.self) { group in
            var running = 0

            for item in requests {
                guard !Task.isCancelled else { break }

                // Session-level dedup: skip if already prefetched with same modifiedAt
                if let key = item.request.fileIdentifier?.rawValue,
                   sessionCache[key] == item.modifiedAt {
                    print("[Prefetch] skip (cached) \(item.request.displayName)")
                    continue
                }

                // Throttle to maxConcurrency
                if running >= Self.maxConcurrency {
                    await group.next()
                    running -= 1
                }

                guard !Task.isCancelled else { break }

                let request = item.request
                let modifiedAt = item.modifiedAt
                running += 1

                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.prefetchOne(request: request, modifiedAt: modifiedAt)
                }
            }

            // Wait for remaining tasks
            for await _ in group { }
        }
    }

    private func prefetchOne(request: PlaybackLaunchRequest, modifiedAt: Date) async {
        guard let fileIdentifier = request.fileIdentifier else { return }

        // Check persistent cache — if we already have a profile stored, skip detection
        if let existing = await metadataService.cachedProfile(for: fileIdentifier),
           existing.mediaProfile != nil {
            // Mark in session cache so we don't check again this session
            sessionCache[fileIdentifier.rawValue] = modifiedAt
            print("[Prefetch] hit (persistent) \(request.displayName)")
            return
        }

        print("[Prefetch] detecting \(request.displayName)")

        do {
            let profile = try await withThrowingTaskGroup(of: PlaybackCoreDomain.MediaProfile.self) { group in
                group.addTask {
                    try await Self.detectProfile(url: request.url)
                }
                group.addTask {
                    try await Task.sleep(for: Self.timeoutSeconds)
                    throw CancellationError()
                }
                // Return first result (either detection or timeout error)
                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            guard !Task.isCancelled else { return }

            _ = await metadataService.recordDetectedProfile(profile, for: request)
            sessionCache[fileIdentifier.rawValue] = modifiedAt
            print("[Prefetch] done \(request.displayName) hdr=\(profile.hdrType.rawValue) proj=\(profile.projectionType.rawValue)")
        } catch is CancellationError {
            print("[Prefetch] timeout/cancelled \(request.displayName)")
        } catch {
            print("[Prefetch] error \(request.displayName): \(error.localizedDescription)")
        }
    }

    // MARK: - AVFoundation Profile Detection

    /// Detects a `MediaProfile` from a local or remote URL using AVFoundation.
    /// This is much lighter than spawning mpv — AVFoundation reads container
    /// metadata directly without decoding frames.
    ///
    /// Limitation: projection type detection (360°/180°/fisheye) relies on
    /// container metadata tags (GSpherical). If those are absent, projection
    /// defaults to `.flat`. mpv will correct this at actual playback time.
    private static func detectProfile(url: URL) async throws -> PlaybackCoreDomain.MediaProfile {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])

        // Always cancel AVURLAsset loading on exit to release HTTP connections promptly.
        // cancelLoading() is safe to call on a completed asset (Apple-documented).
        // Without this, ARC-delayed release causes connections to accumulate.
        defer {
            asset.cancelLoading()
        }

        // Load essential properties concurrently
        async let tracksResult = asset.loadTracks(withMediaType: .video)
        async let durationResult = asset.load(.duration)

        let videoTracks = try await tracksResult
        let duration = try await durationResult

        let durationSeconds = duration == .invalid ? nil : duration.seconds

        guard let videoTrack = videoTracks.first else {
            // Audio-only or unreadable file — return minimal SDR flat profile
            return PlaybackCoreDomain.MediaProfile(
                projectionType: .flat,
                stereoLayout: .mono,
                hdrType: .sdr,
                resolution: .init(width: 0, height: 0),
                durationSeconds: durationSeconds
            )
        }

        // Load video track properties
        async let naturalSizeResult = videoTrack.load(.naturalSize)
        async let formatDescriptionsResult = videoTrack.load(.formatDescriptions)
        async let nominalFrameRateResult = videoTrack.load(.nominalFrameRate)

        let naturalSize = try await naturalSizeResult
        let formatDescriptions = try await formatDescriptionsResult
        let nominalFrameRate = try await nominalFrameRateResult

        let width = Int(naturalSize.width)
        let height = Int(naturalSize.height)
        let frameRate = Double(nominalFrameRate)

        let hdrType = detectHDRType(from: formatDescriptions)
        let stereoLayout = detectStereoLayout(from: formatDescriptions)
        let projectionType = detectProjectionType(from: formatDescriptions, asset: asset)

        let videoCodec = detectVideoCodec(from: formatDescriptions)

        return PlaybackCoreDomain.MediaProfile(
            projectionType: projectionType,
            stereoLayout: stereoLayout,
            hdrType: hdrType,
            resolution: .init(width: width, height: height),
            frameRate: frameRate,
            videoCodec: videoCodec,
            durationSeconds: durationSeconds
        )
    }

    private static func detectHDRType(
        from formatDescriptions: [CMFormatDescription]
    ) -> PlaybackCoreDomain.HDRType {
        guard let desc = formatDescriptions.first else { return .sdr }

        // Check Dolby Vision via format description extensions.
        // Note: kCMFormatDescriptionExtension_DolbyVisionConfiguration is not available on visionOS,
        // so we use the raw string key which CoreMedia recognizes internally.
        if let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] {
            if let dvInfo = extensions["DolbyVisionConfiguration"] {
                _ = dvInfo
                return .dolbyVision
            }
        }

        // Check color primaries and transfer function
        let primaries = CMFormatDescriptionGetExtension(
            desc,
            extensionKey: kCMFormatDescriptionExtension_ColorPrimaries
        ) as? String ?? ""

        let transferFunction = CMFormatDescriptionGetExtension(
            desc,
            extensionKey: kCMFormatDescriptionExtension_TransferFunction
        ) as? String ?? ""

        // HLG detection
        if transferFunction == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String) {
            return .hlg
        }

        // HDR10 / HDR10+ detection via BT.2020 primaries + PQ transfer
        let isBT2020 = primaries == (kCVImageBufferColorPrimaries_ITU_R_2020 as String)
        let isPQ = transferFunction == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)

        if isBT2020 && isPQ {
            // Check for HDR10+ (dynamic metadata)
            if let mastering = CMFormatDescriptionGetExtension(
                desc,
                extensionKey: kCMFormatDescriptionExtension_MasteringDisplayColorVolume
            ) {
                _ = mastering
                return .hdr10
            }
            return .hdr10
        }

        return .sdr
    }

    private static func detectStereoLayout(
        from formatDescriptions: [CMFormatDescription]
    ) -> PlaybackCoreDomain.StereoLayout {
        guard let desc = formatDescriptions.first else { return .mono }
        guard let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] else {
            return .mono
        }

        // Check for stereo video format extensions
        if let stereoMode = extensions["VideoStereoMode" as String] as? String {
            switch stereoMode.lowercased() {
            case "sbs", "side-by-side", "leftright":
                return .sideBySide
            case "tb", "top-bottom", "topbottom", "overunder":
                return .topBottom
            default:
                return .mono
            }
        }

        return .mono
    }

    private static func detectProjectionType(
        from formatDescriptions: [CMFormatDescription],
        asset: AVURLAsset
    ) -> PlaybackCoreDomain.ProjectionType {
        guard let desc = formatDescriptions.first else { return .flat }
        guard let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] else {
            return .flat
        }

        // Check for spherical video projection extension
        if let projectionKind = extensions["ProjectionType" as String] as? String {
            switch projectionKind.lowercased() {
            case "equirectangular":
                return .equirectangular360
            case "half-equirectangular":
                return .equirectangular180
            case "fisheye":
                return .fisheye
            default:
                break
            }
        }

        return .flat
    }

    private static func detectVideoCodec(
        from formatDescriptions: [CMFormatDescription]
    ) -> String? {
        guard let desc = formatDescriptions.first else { return nil }
        let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
        // Convert FourCC to string
        var fourCC = mediaSubType.bigEndian
        return withUnsafeBytes(of: &fourCC) { bytes in
            let chars = bytes.map { Character(UnicodeScalar($0)) }
            return String(chars).trimmingCharacters(in: .whitespaces)
        }
    }
}
