@preconcurrency import AVFoundation
import Foundation
import PlaybackFFmpegBridge

enum FFmpegSourceLocator {
    static func argument(for url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }
}

struct VideoSampleProviderInfo: Sendable {
    var providerKind = "unknown"
    var containerFormat = "unknown"
    var durationSeconds = 0.0
    var nominalFrameRate = 0.0
    var codecName = "unknown"
    var codecTag = "unknown"
    var isMVHEVC = false
    var dimensions = "unknown"
    var colorPrimaries = "unknown"
    var transferFunction = "unknown"
    var yCbCrMatrix = "unknown"
    var range = "unknown"
    var seekability = ObservedStringFact(.unknown)
    var selectedRawTrackMapping = ObservedStringFact(.notExposed)
    var timebase = ObservedStringFact(.notExposed)
    var codecConfigurationSummary = ObservedStringFact(.notExposed)
    var formatSignaling = VideoFormatSignalingSummary(provenance: "providerOpen")
    var trackFormatHasMasteringDisplayMetadata = false
    var trackFormatHasContentLightLevelMetadata = false
}

protocol VideoSampleProvider: AnyObject {
    var info: VideoSampleProviderInfo { get }

    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        sourceInformation: MediaSourceInformation?,
        startTime: CMTime
    ) async throws
    func start() throws
    func nextEvent() async throws -> VideoSampleProviderEvent
    func cancel()
}

extension VideoSampleProvider {
    func prepare(url: URL, asset: PlaybackAsset?, startTime: CMTime) async throws {
        try await prepare(
            url: url,
            asset: asset,
            sourceInformation: nil,
            startTime: startTime
        )
    }
}

enum VideoSampleProviderEvent {
    case sample(CMSampleBuffer)
    case formatChanged
    case flush
    case end
}

struct SendableSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer
}

struct SendableVideoFormatDescription: @unchecked Sendable {
    let value: CMVideoFormatDescription
}

struct FFmpegVideoReaderHandle: @unchecked Sendable {
    let pointer: OpaquePointer
}

enum FFmpegVideoReadOutcome: @unchecked Sendable {
    case sample(SendableSampleBuffer)
    case end
    case cancelled
}

protocol FFmpegVideoReaderOperations: Sendable {
    func allocate() -> FFmpegVideoReaderHandle?
    func open(
        _ reader: FFmpegVideoReaderHandle,
        source: String,
        startSeconds: Double
    ) throws -> VideoSampleProviderInfo
    func copyNextSample(from reader: FFmpegVideoReaderHandle) throws -> FFmpegVideoReadOutcome
    func copyCompressedFormatDescription(
        from reader: FFmpegVideoReaderHandle
    ) -> SendableVideoFormatDescription?
    func copyMediaSourceInformation(
        from reader: FFmpegVideoReaderHandle
    ) -> MediaSourceInformation?
    func cancel(_ reader: FFmpegVideoReaderHandle)
    func destroy(_ reader: FFmpegVideoReaderHandle)
}

extension FFmpegVideoReaderOperations {
    func copyCompressedFormatDescription(
        from reader: FFmpegVideoReaderHandle
    ) -> SendableVideoFormatDescription? {
        nil
    }

    func copyMediaSourceInformation(
        from reader: FFmpegVideoReaderHandle
    ) -> MediaSourceInformation? {
        nil
    }
}

struct SystemFFmpegVideoReaderOperations: FFmpegVideoReaderOperations {
    private let sourceReadMeter: PlaybackSourceReadMeter
    private let demuxSession: FFmpegDemuxSession?

    init(
        sourceReadMeter: PlaybackSourceReadMeter = PlaybackSourceReadMeter(),
        demuxSession: FFmpegDemuxSession? = nil
    ) {
        self.sourceReadMeter = sourceReadMeter
        self.demuxSession = demuxSession
    }

    func allocate() -> FFmpegVideoReaderHandle? {
        PBFFmpegReaderAllocate().map(FFmpegVideoReaderHandle.init(pointer:))
    }

    func open(
        _ reader: FFmpegVideoReaderHandle,
        source: String,
        startSeconds: Double
    ) throws -> VideoSampleProviderInfo {
        PBFFmpegReaderSetSourceReadMonitor(
            reader.pointer,
            sourceReadMeter.bridgeMonitor
        )
        var error = [CChar](repeating: 0, count: 512)
        let opened = if let demuxSession {
            try demuxSession.withSource(argument: source) {
                PBFFmpegReaderOpenWithDemuxSource(
                    reader.pointer,
                    $0,
                    PBFFmpegModeCompressed,
                    &error,
                    error.count
                )
            }
        } else {
            source.withCString { path in
                PBFFmpegReaderOpen(
                    reader.pointer,
                    path,
                    PBFFmpegModeCompressed,
                    startSeconds,
                    &error,
                    error.count
                )
            }
        }
        guard opened else {
            if PBFFmpegReaderOpenFailedWithUnsupportedVideoCodec(reader.pointer) {
                throw PlaybackControlError.unsupportedVideoCodec(
                    codecName: String(cString: PBFFmpegReaderGetCodecName(reader.pointer))
                )
            }
            throw PlaybackProviderError.ffmpeg(ffmpegErrorMessage(error))
        }
        let configurationAtoms = [
            PBFFmpegReaderFormatHasHvcC(reader.pointer) ? "hvcC" : nil,
            PBFFmpegReaderFormatHasDvcC(reader.pointer) ? "dvcC" : nil,
            PBFFmpegReaderFormatHasDvvC(reader.pointer) ? "dvvC" : nil
        ].compactMap(\.self)
        return VideoSampleProviderInfo(
            providerKind: "FFmpegCompressed",
            containerFormat: String(cString: PBFFmpegReaderGetContainerFormat(reader.pointer)),
            durationSeconds: PBFFmpegReaderGetDurationSeconds(reader.pointer),
            nominalFrameRate: PBFFmpegReaderGetNominalFrameRate(reader.pointer),
            codecName: String(cString: PBFFmpegReaderGetCodecName(reader.pointer)),
            codecTag: String(cString: PBFFmpegReaderGetCodecTag(reader.pointer)),
            isMVHEVC: PBFFmpegReaderIsMVHEVC(reader.pointer),
            dimensions: "\(PBFFmpegReaderGetWidth(reader.pointer))x\(PBFFmpegReaderGetHeight(reader.pointer))",
            colorPrimaries: String(cString: PBFFmpegReaderGetColorPrimaries(reader.pointer)),
            transferFunction: String(cString: PBFFmpegReaderGetTransferFunction(reader.pointer)),
            yCbCrMatrix: String(cString: PBFFmpegReaderGetYCbCrMatrix(reader.pointer)),
            range: String(cString: PBFFmpegReaderGetColorRange(reader.pointer)),
            seekability: .init(known: "providerRebuild"),
            selectedRawTrackMapping: .init(
                known: "stream:\(PBFFmpegReaderGetVideoStreamIndex(reader.pointer))"
            ),
            timebase: .init(
                known: "\(PBFFmpegReaderGetTimeBaseNumerator(reader.pointer))/\(PBFFmpegReaderGetTimeBaseDenominator(reader.pointer))"
            ),
            codecConfigurationSummary: configurationAtoms.isEmpty
                ? .init(.none)
                : .init(known: configurationAtoms.joined(separator: ",")),
            formatSignaling: VideoFormatSignalingSummary(
                provenance: "FFmpeg.codecParameters",
                colorPrimaries: ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetColorPrimaries(reader.pointer))
                ),
                transferFunction: ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetTransferFunction(reader.pointer))
                ),
                yCbCrMatrix: ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetYCbCrMatrix(reader.pointer))
                ),
                range: ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetColorRange(reader.pointer))
                ),
                projectionKind: ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetProjectionKind(reader.pointer))
                ),
                viewPackingKind: ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetViewPackingKind(reader.pointer))
                ),
                hvcC: PBFFmpegReaderFormatHasHvcC(reader.pointer)
                    ? .init(known: true)
                    : .init(.none),
                dvcC: PBFFmpegReaderFormatHasDvcC(reader.pointer)
                    ? .init(known: true)
                    : .init(.none),
                dvvC: PBFFmpegReaderFormatHasDvvC(reader.pointer)
                    ? .init(known: true)
                    : .init(.none)
            )
        )
    }

    func copyNextSample(from reader: FFmpegVideoReaderHandle) throws -> FFmpegVideoReadOutcome {
        var sample: Unmanaged<CMSampleBuffer>?
        var error = [CChar](repeating: 0, count: 512)
        let result = PBFFmpegReaderCopyNextSample(
            reader.pointer,
            &sample,
            &error,
            error.count
        )
        switch result {
        case PBFFmpegReadResultSample:
            guard let sample else { return .end }
            return .sample(SendableSampleBuffer(value: sample.takeRetainedValue()))
        case PBFFmpegReadResultEnd:
            return .end
        case PBFFmpegReadResultCancelled:
            return .cancelled
        default:
            let message = ffmpegErrorMessage(error)
            throw PlaybackProviderError(
                bridgeCause: PBFFmpegReaderGetLastActiveFailureCause(reader.pointer),
                message: message
            ) ?? PlaybackProviderError.ffmpeg(message)
        }
    }

    func copyCompressedFormatDescription(
        from reader: FFmpegVideoReaderHandle
    ) -> SendableVideoFormatDescription? {
        var format: Unmanaged<CMVideoFormatDescription>?
        let status = PBFFmpegVideoFormatDescriptionCreate(
            reader.pointer,
            nil,
            nil,
            nil,
            &format
        )
        guard status == noErr, let format else {
            return nil
        }
        return SendableVideoFormatDescription(value: format.takeRetainedValue())
    }

    func copyMediaSourceInformation(
        from reader: FFmpegVideoReaderHandle
    ) -> MediaSourceInformation? {
        guard let handle = PBFFmpegReaderCopyMediaSourceInformation(reader.pointer) else {
            return nil
        }
        defer { PBFFmpegMediaSourceInformationDestroy(handle) }
        return try? SystemMediaSourceInformationLoader.copy(handle)
    }

    func cancel(_ reader: FFmpegVideoReaderHandle) {
        PBFFmpegReaderCancel(reader.pointer)
    }

    func destroy(_ reader: FFmpegVideoReaderHandle) {
        PBFFmpegReaderDestroy(reader.pointer)
    }

    private func ffmpegStringFact(_ value: String) -> ObservedStringFact {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "unknown", normalized != "unspecified" else {
            return .init(.unknown)
        }
        return .init(known: value)
    }
}

final class FFmpegSampleProvider: VideoSampleProvider, @unchecked Sendable {
    var info: VideoSampleProviderInfo {
        readerLock.withLock { storedInfo }
    }

    private let readerLock = NSLock()
    private let readerQueue: DispatchQueue
    private let operations: any FFmpegVideoReaderOperations
    private let formatSubstitution = VideoSampleFormatOverride()
    private var storedInfo = VideoSampleProviderInfo()
    private var bridgeFormatDescription: CMVideoFormatDescription?
    private var sourceFormatDescription: CMFormatDescription?
    private var reader: FFmpegVideoReaderHandle?
    private var generation: UInt64 = 0

    init(
        sourceReadMeter: PlaybackSourceReadMeter = PlaybackSourceReadMeter(),
        demuxSession: FFmpegDemuxSession? = nil,
        operations: (any FFmpegVideoReaderOperations)? = nil,
        readerQueue: DispatchQueue = DispatchQueue(
            label: "com.enchron.playbackcore.ffmpeg-video-reader"
        )
    ) {
        self.operations = operations
            ?? SystemFFmpegVideoReaderOperations(
                sourceReadMeter: sourceReadMeter,
                demuxSession: demuxSession
            )
        self.readerQueue = readerQueue
    }

    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        sourceInformation suppliedSourceInformation: MediaSourceInformation?,
        startTime: CMTime
    ) async throws {
        cancel()
        let operationGeneration = readerLock.withLock { generation }
        let source = FFmpegSourceLocator.argument(for: url)
        try await withTaskCancellationHandler {
            let openedSourceInformation = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<MediaSourceInformation?, any Error>) in
                readerQueue.async { [self] in
                    guard isCurrent(operationGeneration) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    guard let newReader = operations.allocate() else {
                        guard isCurrent(operationGeneration) else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        continuation.resume(
                            throwing: PlaybackProviderError.ffmpeg(
                                "Unable to allocate FFmpeg reader"
                            )
                        )
                        return
                    }
                    guard install(newReader, for: operationGeneration) else {
                        operations.destroy(newReader)
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        let newInfo = try operations.open(
                            newReader,
                            source: source,
                            startSeconds: startTime.seconds
                        )
                        let bridgeFormat = operations.copyCompressedFormatDescription(
                            from: newReader
                        )
                        let sourceInformation = operations.copyMediaSourceInformation(
                            from: newReader
                        )
                        guard accept(
                            newInfo,
                            bridgeFormatDescription: bridgeFormat?.value,
                            from: newReader,
                            generation: operationGeneration
                        ) else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        continuation.resume(returning: sourceInformation)
                    } catch {
                        guard removeIfCurrent(newReader, generation: operationGeneration) else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        operations.destroy(newReader)
                        continuation.resume(throwing: error)
                    }
                }
            }
            try Task.checkCancellation()
            let sourceInformation = suppliedSourceInformation ?? openedSourceInformation
            let (openedInfo, bridgeFormat) = readerLock.withLock {
                (storedInfo, bridgeFormatDescription)
            }
            if Self.shouldConsultAVFoundation(
                suppliedAsset: asset,
                sourceInformation: sourceInformation
            ), let bridgeFormat {
                let sourceAsset = asset?.value ?? AVURLAsset(
                    url: url,
                    options: Self.avFoundationAssetOptions(for: sourceInformation)
                )
                let sourceFormat: CMFormatDescription?
                do {
                    sourceFormat = try await Self.uniqueSourceVideoFormatDescription(
                        in: sourceAsset,
                        matching: bridgeFormat,
                        allowsSourceOnlyLhvC: openedInfo.isMVHEVC,
                        allowsSameFileHvcCReconstruction: asset == nil && openedInfo.isMVHEVC
                    )
                } catch {
                    if openedInfo.isMVHEVC { throw error }
                    sourceFormat = nil
                }
                let appleImmersiveClassificationFormat: CMFormatDescription?
                if sourceFormat == nil, asset == nil {
                    do {
                        appleImmersiveClassificationFormat = try await Self
                            .uniqueAppleImmersiveSourceFormatMetadata(
                                in: sourceAsset,
                                matching: bridgeFormat
                            )
                    } catch {
                        if openedInfo.isMVHEVC { throw error }
                        appleImmersiveClassificationFormat = nil
                    }
                } else {
                    appleImmersiveClassificationFormat = nil
                }
                if let sourceFormat {
                    let preservedFormat = try Self.formatByPreservingSourceSignals(
                        sourceFormat,
                        on: bridgeFormat
                    )
                    guard readerLock.withLock({
                        guard generation == operationGeneration else { return false }
                        sourceFormatDescription = preservedFormat
                        storedInfo = Self.infoByPreservingSourceFormat(
                            storedInfo,
                            sourceFormat: preservedFormat
                        )
                        return true
                    }) else {
                        throw CancellationError()
                    }
                } else {
                    if appleImmersiveClassificationFormat != nil {
                        throw PlaybackProviderError.appleImmersivePayloadMismatch
                    }
                    guard readerLock.withLock({
                        guard generation == operationGeneration else { return false }
                        storedInfo = Self.infoByClassifyingDeliveredDescription(
                            storedInfo,
                            format: bridgeFormat
                        )
                        return true
                    }) else {
                        throw CancellationError()
                    }
                }
            }
            try Task.checkCancellation()
        } onCancel: { [weak self] in
            self?.cancel(generation: operationGeneration)
        }
    }

    func start() throws {}

    func nextEvent() async throws -> VideoSampleProviderEvent {
        guard let operation = readerLock.withLock({ reader.map { ($0, generation) } }) else {
            return .end
        }
        let outcome: FFmpegVideoReadOutcome = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                readerQueue.async { [self] in
                    guard isCurrent(operation.1, reader: operation.0) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        let outcome = try operations.copyNextSample(from: operation.0)
                        guard isCurrent(operation.1, reader: operation.0) else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        if case .cancelled = outcome {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(returning: outcome)
                        }
                    } catch {
                        guard isCurrent(operation.1, reader: operation.0) else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { [weak self] in
            self?.cancel(generation: operation.1)
        }
        switch outcome {
        case .sample(let sample):
            let sourceFormat = readerLock.withLock { sourceFormatDescription }
            guard let sourceFormat else { return .sample(sample.value) }
            return .sample(
                try formatSubstitution.replacingFormatDescription(
                    of: sample.value,
                    with: sourceFormat
                )
            )
        case .end: return .end
        case .cancelled: throw CancellationError()
        }
    }

    func cancel() {
        cancel(generation: nil)
    }

    deinit {
        cancel()
    }

    private func cancel(generation expectedGeneration: UInt64?) {
        let cancelledReader: FFmpegVideoReaderHandle? = readerLock.withLock {
            if let expectedGeneration, generation != expectedGeneration { return nil }
            generation &+= 1
            let cancelledReader = reader
            reader = nil
            storedInfo = VideoSampleProviderInfo()
            bridgeFormatDescription = nil
            sourceFormatDescription = nil
            return cancelledReader
        }
        guard let cancelledReader else { return }
        operations.cancel(cancelledReader)
        readerQueue.async { [operations] in
            operations.destroy(cancelledReader)
        }
    }

    private func isCurrent(
        _ expectedGeneration: UInt64,
        reader expectedReader: FFmpegVideoReaderHandle? = nil
    ) -> Bool {
        readerLock.withLock {
            guard generation == expectedGeneration else { return false }
            guard let expectedReader else { return true }
            return reader?.pointer == expectedReader.pointer
        }
    }

    private func install(
        _ newReader: FFmpegVideoReaderHandle,
        for expectedGeneration: UInt64
    ) -> Bool {
        readerLock.withLock {
            guard generation == expectedGeneration, reader == nil else { return false }
            reader = newReader
            return true
        }
    }

    private func accept(
        _ newInfo: VideoSampleProviderInfo,
        bridgeFormatDescription newBridgeFormatDescription: CMVideoFormatDescription?,
        from openedReader: FFmpegVideoReaderHandle,
        generation expectedGeneration: UInt64
    ) -> Bool {
        readerLock.withLock {
            guard generation == expectedGeneration,
                  reader?.pointer == openedReader.pointer else { return false }
            storedInfo = newInfo
            bridgeFormatDescription = newBridgeFormatDescription
            return true
        }
    }

    private func removeIfCurrent(
        _ failedReader: FFmpegVideoReaderHandle,
        generation expectedGeneration: UInt64
    ) -> Bool {
        readerLock.withLock {
            guard generation == expectedGeneration,
                  reader?.pointer == failedReader.pointer else { return false }
            reader = nil
            return true
        }
    }

    private static func uniqueSourceVideoFormatDescription(
        in asset: AVAsset,
        matching bridgeFormat: CMVideoFormatDescription,
        allowsSourceOnlyLhvC: Bool,
        allowsSameFileHvcCReconstruction: Bool
    ) async throws -> CMFormatDescription? {
        var match: CMFormatDescription?
        for track in try await asset.loadTracks(withMediaType: .video) {
            for format in try await track.load(.formatDescriptions) {
                guard sourceVideoFormat(
                    format,
                    matches: bridgeFormat,
                    allowsSourceOnlyLhvC: allowsSourceOnlyLhvC,
                    allowsSameFileHvcCReconstruction: allowsSameFileHvcCReconstruction
                ) else { continue }
                guard match == nil else { return nil }
                match = format
            }
        }
        return match
    }

    private static func shouldConsultAVFoundation(
        suppliedAsset: PlaybackAsset?,
        sourceInformation: MediaSourceInformation?
    ) -> Bool {
        suppliedAsset != nil ||
            sourceInformation?.containerSupportsSourceFormatDescription == true
    }

    static func avFoundationAssetOptions(
        for sourceInformation: MediaSourceInformation?
    ) -> [String: Any] {
        guard sourceInformation?.containerSupportsSourceFormatDescription == true else {
            return [:]
        }
        return [AVURLAssetOverrideMIMETypeKey: "video/mp4"]
    }

    private static func uniqueAppleImmersiveSourceFormatMetadata(
        in asset: AVAsset,
        matching bridgeFormat: CMVideoFormatDescription
    ) async throws -> CMFormatDescription? {
        var match: CMFormatDescription?
        for track in try await asset.loadTracks(withMediaType: .video) {
            for format in try await track.load(.formatDescriptions) {
                guard sourceVideoFormatHasSameSubtypeAndDimensions(
                    format,
                    as: bridgeFormat
                ) else { continue }
                let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any]
                let projection = extensions?[
                    kCMFormatDescriptionExtension_ProjectionKind as String
                ] as? String
                guard projection?.localizedCaseInsensitiveContains(
                    "AppleImmersiveVideo"
                ) == true else { continue }
                guard match == nil else { return nil }
                match = format
            }
        }
        return match
    }

    private static func sourceVideoFormat(
        _ sourceFormat: CMVideoFormatDescription,
        matches bridgeFormat: CMVideoFormatDescription,
        allowsSourceOnlyLhvC: Bool,
        allowsSameFileHvcCReconstruction: Bool
    ) -> Bool {
        let sourceDimensions = CMVideoFormatDescriptionGetDimensions(sourceFormat)
        let bridgeDimensions = CMVideoFormatDescriptionGetDimensions(bridgeFormat)
        guard sourceDimensions.width == bridgeDimensions.width,
              sourceDimensions.height == bridgeDimensions.height else { return false }
        let sourceAtoms = decoderConfigurationAtoms(in: sourceFormat)
        let bridgeAtoms = decoderConfigurationAtoms(in: bridgeFormat)
        for atom in ["avcC", "av1C"] {
            guard sourceAtoms[atom] == bridgeAtoms[atom] else { return false }
        }
        let hvcCMatches = sourceAtoms["hvcC"] == bridgeAtoms["hvcC"]
        let sameFileMVHEVCReconstruction = allowsSameFileHvcCReconstruction
            && sourceAtoms["hvcC"]?.isEmpty == false
            && bridgeAtoms["hvcC"]?.isEmpty == false
            && sourceAtoms["lhvC"]?.isEmpty == false
            && bridgeAtoms["lhvC"] == nil
        guard hvcCMatches || sameFileMVHEVCReconstruction else { return false }
        let sourceSubtype = CMFormatDescriptionGetMediaSubType(sourceFormat)
        let bridgeSubtype = CMFormatDescriptionGetMediaSubType(bridgeFormat)
        if sourceSubtype != bridgeSubtype {
            guard allowsSourceOnlyLhvC,
                  sourceSubtype == kCMVideoCodecType_DolbyVisionHEVC,
                  bridgeSubtype == kCMVideoCodecType_HEVC,
                  sourceAtoms["dvcC"] == nil,
                  sourceAtoms["dvvC"] == nil,
                  sourceAtoms["lhvC"]?.isEmpty == false else {
                return false
            }
            return true
        }
        for atom in ["dvcC", "dvvC"] {
            guard sourceAtoms[atom] == bridgeAtoms[atom] else { return false }
        }
        if let bridgeLhvC = bridgeAtoms["lhvC"] {
            return sourceAtoms["lhvC"] == bridgeLhvC
        }
        return sourceAtoms["lhvC"] == nil || allowsSourceOnlyLhvC
    }

    private static func formatByPreservingSourceSignals(
        _ sourceFormat: CMVideoFormatDescription,
        on bridgeFormat: CMVideoFormatDescription
    ) throws -> CMVideoFormatDescription {
        var preserved: Unmanaged<CMVideoFormatDescription>?
        let status = PBFFmpegVideoFormatDescriptionCreate(
            nil,
            sourceFormat,
            bridgeFormat,
            nil,
            &preserved
        )
        guard status == noErr, let preserved else {
            throw VideoSampleFormatOverrideError.formatDescriptionCreationFailed(status)
        }
        return preserved.takeRetainedValue()
    }

    private static func sourceVideoFormatHasSameSubtypeAndDimensions(
        _ sourceFormat: CMVideoFormatDescription,
        as bridgeFormat: CMVideoFormatDescription
    ) -> Bool {
        let sourceDimensions = CMVideoFormatDescriptionGetDimensions(sourceFormat)
        let bridgeDimensions = CMVideoFormatDescriptionGetDimensions(bridgeFormat)
        return CMFormatDescriptionGetMediaSubType(sourceFormat)
                == CMFormatDescriptionGetMediaSubType(bridgeFormat)
            && sourceDimensions.width == bridgeDimensions.width
            && sourceDimensions.height == bridgeDimensions.height
    }

    private static func decoderConfigurationAtoms(
        in format: CMFormatDescription
    ) -> [String: Data] {
        let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any]
        return extensions?[
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String
        ] as? [String: Data] ?? [:]
    }

    private static func infoByPreservingSourceFormat(
        _ info: VideoSampleProviderInfo,
        sourceFormat: CMFormatDescription
    ) -> VideoSampleProviderInfo {
        var updated = info
        let extensions = CMFormatDescriptionGetExtensions(sourceFormat) as? [String: Any] ?? [:]
        let atoms = extensions[
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String
        ] as? [String: Data] ?? [:]
        updated.isMVHEVC = atoms["lhvC"]?.isEmpty == false
        let configurationAtoms = ["avcC", "hvcC", "lhvC", "dvcC", "dvvC", "av1C"]
            .filter { atoms[$0]?.isEmpty == false }
        if !configurationAtoms.isEmpty {
            updated.codecConfigurationSummary = .init(
                known: configurationAtoms.joined(separator: ",")
            )
        }
        updated.formatSignaling = VideoFormatSignalingSummary(
            provenance: "AVAssetTrack.sourceFormatDescription",
            colorPrimaries: updated.formatSignaling.colorPrimaries,
            transferFunction: updated.formatSignaling.transferFunction,
            yCbCrMatrix: updated.formatSignaling.yCbCrMatrix,
            range: updated.formatSignaling.range,
            projectionKind: stringFact(
                extensions[kCMFormatDescriptionExtension_ProjectionKind as String]
            ),
            viewPackingKind: stringFact(
                extensions[kCMFormatDescriptionExtension_ViewPackingKind as String]
            ),
            hasLeftStereoEyeView: boolFact(
                extensions[kCMFormatDescriptionExtension_HasLeftStereoEyeView as String]
            ),
            hasRightStereoEyeView: boolFact(
                extensions[kCMFormatDescriptionExtension_HasRightStereoEyeView as String]
            ),
            hvcC: atoms["hvcC"]?.isEmpty == false ? .init(known: true) : .init(.none),
            lhvC: atoms["lhvC"]?.isEmpty == false ? .init(known: true) : .init(.none),
            dvcC: atoms["dvcC"]?.isEmpty == false ? .init(known: true) : .init(.none),
            dvvC: atoms["dvvC"]?.isEmpty == false ? .init(known: true) : .init(.none)
        )
        return updated
    }

    private static func infoByClassifyingDeliveredDescription(
        _ info: VideoSampleProviderInfo,
        format: CMFormatDescription
    ) -> VideoSampleProviderInfo {
        var updated = info
        let atoms = decoderConfigurationAtoms(in: format)
        updated.isMVHEVC = atoms["lhvC"]?.isEmpty == false
        return updated
    }

    private static func stringFact(_ value: Any?) -> ObservedStringFact {
        if let string = value as? String { return .init(known: string) }
        return .init(.none)
    }

    private static func boolFact(_ value: Any?) -> ObservedBooleanFact {
        guard let value = value as? Bool else { return .init(.none) }
        return .init(known: value)
    }
}

func ffmpegErrorMessage(_ buffer: [CChar]) -> String {
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

enum PlaybackProviderError: LocalizedError {
    case noVideoTrack
    case readerDidNotStart
    case readerFailed(String)
    case ffmpeg(String)
    case appleImmersivePayloadMismatch
    case activeFailure(PlaybackCoreActiveFailureCause, String)

    init?(bridgeCause: PBFFmpegActiveFailureCause, message: String) {
        switch bridgeCause {
        case PBFFmpegActiveFailureCauseConnectionInterrupted:
            self = .activeFailure(.connectionInterrupted, message)
        case PBFFmpegActiveFailureCauseSourceFileMissing:
            self = .activeFailure(.sourceFileMissing, message)
        case PBFFmpegActiveFailureCauseSourceAccessDenied:
            self = .activeFailure(.sourceAccessDenied, message)
        case PBFFmpegActiveFailureCauseMediaDataCorrupt:
            self = .activeFailure(.mediaDataCorrupt, message)
        default:
            return nil
        }
    }

    var activeFailureCause: PlaybackCoreActiveFailureCause? {
        guard case .activeFailure(let cause, _) = self else { return nil }
        return cause
    }

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "The selected file has no video track."
        case .readerDidNotStart: "AVAssetReader could not start reading."
        case .readerFailed(let message): "AVAssetReader failed: \(message)"
        case .ffmpeg(let message): "FFmpeg: \(message)"
        case .appleImmersivePayloadMismatch:
            "Apple Immersive Video payload metadata could not be preserved."
        case .activeFailure(_, let message): "FFmpeg: \(message)"
        }
    }
}
