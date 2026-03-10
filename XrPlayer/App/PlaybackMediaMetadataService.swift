import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

public actor PlaybackMediaMetadataStore {
    private let defaults: UserDefaults
    private static let keyPrefix = "xrplayer.mediaMetadata."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadMetadata(for key: String) -> PlaybackMediaMetadata? {
        guard let data = defaults.data(forKey: Self.keyPrefix + key) else {
            return nil
        }
        return try? JSONDecoder().decode(PlaybackMediaMetadata.self, from: data)
    }

    func saveMetadata(_ metadata: PlaybackMediaMetadata, for key: String) {
        guard let data = try? JSONEncoder().encode(metadata) else {
            return
        }
        defaults.set(data, forKey: Self.keyPrefix + key)
    }
}

public actor PlaybackMediaMetadataService {
    private let store: PlaybackMediaMetadataStore

    public init(store: PlaybackMediaMetadataStore = PlaybackMediaMetadataStore()) {
        self.store = store
    }

    func prepareMetadata(for request: PlaybackLaunchRequest) async -> PlaybackMediaMetadata? {
        var resolvedMetadata = request.initialMetadata

        if let key = request.fileIdentifier?.rawValue,
           let cachedMetadata = await store.loadMetadata(for: key) {
            resolvedMetadata = resolvedMetadata?.merging(with: cachedMetadata) ?? cachedMetadata
        }

        guard request.url.isFileURL else {
            return resolvedMetadata
        }

        if let probedMetadata = await probeLocalMetadata(
            at: request.url,
            fallbackFileSizeInBytes: resolvedMetadata?.fileSizeInBytes
        ) {
            resolvedMetadata = resolvedMetadata?.merging(with: probedMetadata) ?? probedMetadata
            if let key = request.fileIdentifier?.rawValue, let resolvedMetadata {
                await store.saveMetadata(resolvedMetadata, for: key)
            }
        }

        return resolvedMetadata
    }

    func recordDetectedProfile(
        _ profile: PlaybackCoreDomain.MediaProfile,
        for request: PlaybackLaunchRequest
    ) async -> PlaybackMediaMetadata {
        let metadata = request.initialMetadata?.updating(mediaProfile: profile)
            ?? PlaybackMediaMetadata(mediaProfile: profile)

        if let key = request.fileIdentifier?.rawValue {
            let merged = (await store.loadMetadata(for: key))?.merging(with: metadata) ?? metadata
            await store.saveMetadata(merged, for: key)
            return merged
        }

        return metadata
    }

    func persist(_ metadata: PlaybackMediaMetadata, for request: PlaybackLaunchRequest) async {
        guard let key = request.fileIdentifier?.rawValue else {
            return
        }
        let merged = (await store.loadMetadata(for: key))?.merging(with: metadata) ?? metadata
        await store.saveMetadata(merged, for: key)
    }

    private func probeLocalMetadata(
        at url: URL,
        fallbackFileSizeInBytes: Int64?
    ) async -> PlaybackMediaMetadata? {
        let asset = AVURLAsset(url: url)

        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                return fallbackFileSizeInBytes.map {
                    PlaybackMediaMetadata(fileSizeInBytes: $0)
                }
            }

            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            let width = Int(abs(transformedSize.width.rounded()))
            let height = Int(abs(transformedSize.height.rounded()))
            let frameRate = Double(try await videoTrack.load(.nominalFrameRate))
            let formatDescriptions = try await videoTrack.load(.formatDescriptions)
            let hdrType = inferHDRType(from: formatDescriptions)

            let profile = PlaybackCoreDomain.MediaProfile(
                projectionType: .flat,
                hdrType: hdrType,
                resolution: .init(width: width, height: height),
                frameRate: frameRate
            )

            return PlaybackMediaMetadata(
                mediaProfile: profile,
                fileSizeInBytes: fallbackFileSizeInBytes,
                lastUpdatedAt: Date()
            )
        } catch {
            return fallbackFileSizeInBytes.map {
                PlaybackMediaMetadata(fileSizeInBytes: $0)
            }
        }
    }

    private func inferHDRType(from descriptions: [Any]) -> PlaybackCoreDomain.HDRType {
        for case let formatDescription as CMFormatDescription in descriptions {
            let extensions = (CMFormatDescriptionGetExtensions(formatDescription) as NSDictionary?) ?? [:]
            let formatName = (extensions[kCMFormatDescriptionExtension_FormatName as String] as? String)?
                .lowercased() ?? ""
            let transferFunction = (extensions[kCVImageBufferTransferFunctionKey as String] as? String)?
                .lowercased() ?? ""
            let primaries = (extensions[kCVImageBufferColorPrimariesKey as String] as? String)?
                .lowercased() ?? ""

            if formatName.contains("dovi") || formatName.contains("dolby") {
                return .dolbyVision
            }
            if transferFunction.contains("hlg") || transferFunction.contains("arib") {
                return .hlg
            }
            if transferFunction.contains("2084") || transferFunction.contains("pq") || primaries.contains("2020") {
                return .hdr10
            }
        }

        return .sdr
    }
}
