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
    var route: PlaybackRoute { get }
    var info: VideoSampleProviderInfo { get }

    func prepare(url: URL, asset: PlaybackAsset?, startTime: CMTime) async throws
    func start() throws
    func nextEvent() async throws -> VideoSampleProviderEvent
    func cancel()
}

enum VideoSampleProviderEvent {
    case sample(CMSampleBuffer)
    case formatChanged
    case flush
    case end
}

private struct SendableSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer
}

final class AppleCompressedSampleProvider: VideoSampleProvider {
    let route = PlaybackRoute.appleCompressed
    private(set) var info = VideoSampleProviderInfo()

    private var reader: AVAssetReader?
    private var outputProvider: AVAssetReaderOutput.Provider<
        CMReadySampleBuffer<CMSampleBuffer.DynamicContent>
    >?

    func prepare(url: URL, asset suppliedAsset: PlaybackAsset?, startTime: CMTime) async throws {
        let asset = suppliedAsset?.value ?? AVURLAsset(
            url: url,
            options: [AVURLAssetShouldParseExternalSphericalTagsKey: true]
        )
        PlaybackTrace.event(
            "provider.asset kind=\(String(describing: type(of: asset))) supplied=\(suppliedAsset != nil)"
        )
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw PlaybackProviderError.noVideoTrack
        }
        let duration = try await asset.load(.duration)
        let naturalTimeScale = try await track.load(.naturalTimeScale)
        let formatDescriptions = try await track.load(.formatDescriptions)
        let formatExtensions = formatDescriptions
            .map { CMFormatDescriptionGetExtensions($0) as? [String: Any] ?? [:] }
        let firstFormat = formatDescriptions.first
        let firstExtensions = formatExtensions.first ?? [:]
        let projectionWasSynthesizedFromExternalTags =
            firstExtensions[
                kCMFormatDescriptionExtension_ConvertedFromExternalSphericalTags as String
            ] as? Bool == true
        let firstAtoms = firstExtensions[
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String
        ] as? [String: Any] ?? [:]
        let dimensions = firstFormat.map(CMVideoFormatDescriptionGetDimensions)
        let configurationAtoms = ["hvcC", "dvcC", "dvvC", "amve"].filter {
            firstAtoms[$0] != nil
        }
        info = VideoSampleProviderInfo(
            providerKind: "AVAssetReaderOutput.Provider",
            containerFormat: url.pathExtension.lowercased(),
            durationSeconds: duration.seconds,
            nominalFrameRate: Double(try await track.load(.nominalFrameRate)),
            codecName: firstFormat.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "unknown",
            codecTag: firstFormat.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "unknown",
            dimensions: dimensions.map { "\($0.width)x\($0.height)" } ?? "unknown",
            colorPrimaries: Self.extensionString(firstExtensions, key: kCMFormatDescriptionExtension_ColorPrimaries),
            transferFunction: Self.extensionString(firstExtensions, key: kCMFormatDescriptionExtension_TransferFunction),
            yCbCrMatrix: Self.extensionString(firstExtensions, key: kCMFormatDescriptionExtension_YCbCrMatrix),
            range: Self.rangeString(firstExtensions),
            seekability: .init(.known, value: "providerRebuild"),
            selectedRawTrackMapping: .init(.known, value: "primaryVideo"),
            timebase: .init(.known, value: "1/\(naturalTimeScale)"),
            codecConfigurationSummary: configurationAtoms.isEmpty
                ? .init(.none)
                : .init(.known, value: configurationAtoms.joined(separator: ",")),
            formatSignaling: VideoFormatSignalingSummary(
                provenance: projectionWasSynthesizedFromExternalTags
                    ? "AVAssetTrack.formatDescription.externalSphericalTagsSynthesis"
                    : "AVAssetTrack.formatDescription",
                colorPrimaries: Self.stringFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_ColorPrimaries
                ),
                transferFunction: Self.stringFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_TransferFunction
                ),
                yCbCrMatrix: Self.stringFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_YCbCrMatrix
                ),
                range: Self.rangeFact(firstExtensions),
                projectionKind: Self.stringFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_ProjectionKind
                ),
                viewPackingKind: Self.stringFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_ViewPackingKind
                ),
                hasLeftStereoEyeView: Self.booleanFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_HasLeftStereoEyeView
                ),
                hasRightStereoEyeView: Self.booleanFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_HasRightStereoEyeView
                ),
                masteringDisplayMetadata: Self.presenceFact(
                    firstExtensions[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String]
                ),
                contentLightLevelMetadata: Self.presenceFact(
                    firstExtensions[kCMFormatDescriptionExtension_ContentLightLevelInfo as String]
                ),
                hvcC: Self.presenceFact(firstAtoms["hvcC"]),
                dvcC: Self.presenceFact(firstAtoms["dvcC"]),
                dvvC: Self.presenceFact(firstAtoms["dvvC"]),
                ambientViewingEnvironment: Self.presenceFact(
                    firstExtensions[kCMFormatDescriptionExtension_AmbientViewingEnvironment as String]
                        ?? firstAtoms["amve"]
                )
            ),
            trackFormatHasMasteringDisplayMetadata: formatExtensions.contains {
                $0[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String] != nil
            },
            trackFormatHasContentLightLevelMetadata: formatExtensions.contains {
                $0[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] != nil
            }
        )

        let reader = try AVAssetReader(asset: asset)
        if startTime > .zero {
            reader.timeRange = CMTimeRange(start: startTime, end: duration)
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        let outputProvider = reader.outputProvider(for: output)
        self.reader = reader
        self.outputProvider = outputProvider
    }

    func start() throws {
        guard let reader else { throw PlaybackProviderError.readerDidNotStart }
        try reader.start()
    }

    func nextEvent() async throws -> VideoSampleProviderEvent {
        PlaybackTrace.event("provider.next.begin status=\(reader?.status.rawValue ?? -1)")
        guard let readySample = try await outputProvider?.next() else {
            let status = reader?.status ?? .unknown
            let message = reader?.error?.localizedDescription ?? "none"
            PlaybackTrace.event("provider.end status=\(status.rawValue) error=\(message)")
            return .end
        }
        PlaybackTrace.event(
            "provider.next.received count=\(readySample.sampleCount) " +
            "pts=\(readySample.presentationTimeStamp.seconds)"
        )
        let sample = try readySample.withUnsafeSampleBuffer { source in
            SendableSampleBuffer(value: try Self.independentCopy(of: source))
        }
        PlaybackTrace.event("provider.next.copied count=\(CMSampleBufferGetNumSamples(sample.value))")
        return .sample(sample.value)
    }

    func cancel() {
        reader?.cancelReading()
        reader = nil
        outputProvider = nil
    }

    private static func extensionString(_ extensions: [String: Any], key: CFString) -> String {
        extensions[key as String].map { String(describing: $0) } ?? "unknown"
    }

    static func independentCopy(of source: CMSampleBuffer) throws -> CMSampleBuffer {
        if CMSampleBufferGetNumSamples(source) == 0 {
            return try CMSampleBuffer(copying: source)
        }
        guard let sourceData = CMSampleBufferGetDataBuffer(source),
              let format = CMSampleBufferGetFormatDescription(source) else {
            throw PlaybackProviderError.readerFailed("Compressed sample has no data or format description")
        }

        var data: CMBlockBuffer?
        var status = CMBlockBufferCreateContiguous(
            allocator: kCFAllocatorDefault,
            sourceBuffer: sourceData,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: CMBlockBufferGetDataLength(sourceData),
            flags: 0,
            blockBufferOut: &data
        )
        guard status == kCMBlockBufferNoErr, let data else {
            throw PlaybackProviderError.readerFailed("CMBlockBufferCreateContiguous returned \(status)")
        }

        let timings = try sampleTimings(of: source)
        let sizes = try sampleSizes(of: source)
        var copy: CMSampleBuffer?
        status = timings.withUnsafeBufferPointer { timingBuffer in
            sizes.withUnsafeBufferPointer { sizeBuffer in
                CMSampleBufferCreateReady(
                    allocator: kCFAllocatorDefault,
                    dataBuffer: data,
                    formatDescription: format,
                    sampleCount: CMSampleBufferGetNumSamples(source),
                    sampleTimingEntryCount: timingBuffer.count,
                    sampleTimingArray: timingBuffer.baseAddress,
                    sampleSizeEntryCount: sizeBuffer.count,
                    sampleSizeArray: sizeBuffer.baseAddress,
                    sampleBufferOut: &copy
                )
            }
        }
        guard status == noErr, let copy else {
            throw PlaybackProviderError.readerFailed("CMSampleBufferCreateReady returned \(status)")
        }
        copyAttachments(from: source, to: copy)
        return copy
    }

    private static func sampleTimings(of sample: CMSampleBuffer) throws -> [CMSampleTimingInfo] {
        var count = 0
        var status = CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &count
        )
        guard status == noErr else {
            throw PlaybackProviderError.readerFailed("Reading sample timing returned \(status)")
        }
        var values = Array(repeating: CMSampleTimingInfo(), count: count)
        status = values.withUnsafeMutableBufferPointer { buffer in
            CMSampleBufferGetSampleTimingInfoArray(
                sample,
                entryCount: buffer.count,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: &count
            )
        }
        guard status == noErr else {
            throw PlaybackProviderError.readerFailed("Reading sample timing returned \(status)")
        }
        return values
    }

    private static func sampleSizes(of sample: CMSampleBuffer) throws -> [Int] {
        var count = 0
        var status = CMSampleBufferGetSampleSizeArray(
            sample,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &count
        )
        guard status == noErr else {
            throw PlaybackProviderError.readerFailed("Reading sample sizes returned \(status)")
        }
        var values = Array(repeating: 0, count: count)
        status = values.withUnsafeMutableBufferPointer { buffer in
            CMSampleBufferGetSampleSizeArray(
                sample,
                entryCount: buffer.count,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: &count
            )
        }
        guard status == noErr else {
            throw PlaybackProviderError.readerFailed("Reading sample sizes returned \(status)")
        }
        return values
    }

    private static func copyAttachments(from source: CMSampleBuffer, to destination: CMSampleBuffer) {
        for mode in [kCMAttachmentMode_ShouldNotPropagate, kCMAttachmentMode_ShouldPropagate] {
            if let attachments = CMCopyDictionaryOfAttachments(
                allocator: kCFAllocatorDefault,
                target: source,
                attachmentMode: mode
            ) {
                CMSetAttachments(destination, attachments: attachments, attachmentMode: mode)
            }
        }
        guard let sourceArray = CMSampleBufferGetSampleAttachmentsArray(
            source,
            createIfNecessary: false
        ), let destinationArray = CMSampleBufferGetSampleAttachmentsArray(
            destination,
            createIfNecessary: true
        ) else { return }
        let count = min(CFArrayGetCount(sourceArray), CFArrayGetCount(destinationArray))
        for index in 0..<count {
            let sourceDictionary = unsafeBitCast(
                CFArrayGetValueAtIndex(sourceArray, index),
                to: CFDictionary.self
            )
            let destinationDictionary = unsafeBitCast(
                CFArrayGetValueAtIndex(destinationArray, index),
                to: CFMutableDictionary.self
            )
            CFDictionaryRemoveAllValues(destinationDictionary)
            CFDictionaryApplyFunction(
                sourceDictionary,
                { key, value, context in
                    guard let key, let value, let context else { return }
                    let target = Unmanaged<CFMutableDictionary>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                    CFDictionarySetValue(target, key, value)
                },
                Unmanaged.passUnretained(destinationDictionary).toOpaque()
            )
        }
    }

    private static func stringFact(
        _ extensions: [String: Any],
        key: CFString
    ) -> ObservedStringFact {
        guard let value = extensions[key as String] else { return .init(.none) }
        return .init(.known, value: String(describing: value))
    }

    private static func presenceFact(_ value: Any?) -> ObservedBooleanFact {
        value == nil ? .init(.none, value: false) : .init(.known, value: true)
    }

    private static func booleanFact(
        _ extensions: [String: Any],
        key: CFString
    ) -> ObservedBooleanFact {
        guard let value = extensions[key as String] as? Bool else {
            return .init(.none)
        }
        return .init(.known, value: value)
    }

    private static func rangeString(_ extensions: [String: Any]) -> String {
        guard let fullRange = extensions[
            kCMFormatDescriptionExtension_FullRangeVideo as String
        ] as? Bool else { return "unknown" }
        return fullRange ? "full" : "video"
    }

    private static func rangeFact(_ extensions: [String: Any]) -> ObservedStringFact {
        let value = rangeString(extensions)
        return value == "unknown" ? .init(.unknown) : .init(.known, value: value)
    }
}

final class FFmpegSampleProvider: VideoSampleProvider {
    let route: PlaybackRoute
    var info: VideoSampleProviderInfo {
        readerLock.withLock { storedInfo }
    }

    private let readerLock = NSLock()
    private var storedInfo = VideoSampleProviderInfo()
    private var reader: OpaquePointer?

    init(route: PlaybackRoute) {
        precondition(route == .ffmpegCompressed)
        self.route = route
    }

    func prepare(url: URL, asset: PlaybackAsset?, startTime: CMTime) async throws {
        var error = [CChar](repeating: 0, count: 512)
        let newReader = FFmpegSourceLocator.argument(for: url).withCString { path in
            PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, startTime.seconds, &error, error.count)
        }
        guard let newReader else {
            throw PlaybackProviderError.ffmpeg(Self.errorMessage(error))
        }
        let configurationAtoms = [
            PBFFmpegReaderFormatHasHvcC(newReader) ? "hvcC" : nil,
            PBFFmpegReaderFormatHasDvcC(newReader) ? "dvcC" : nil,
            PBFFmpegReaderFormatHasDvvC(newReader) ? "dvvC" : nil,
        ].compactMap(\.self)
        let newInfo = VideoSampleProviderInfo(
            providerKind: "FFmpegCompressed",
            containerFormat: String(cString: PBFFmpegReaderGetContainerFormat(newReader)),
            durationSeconds: PBFFmpegReaderGetDurationSeconds(newReader),
            nominalFrameRate: PBFFmpegReaderGetNominalFrameRate(newReader),
            codecName: String(cString: PBFFmpegReaderGetCodecName(newReader)),
            codecTag: String(cString: PBFFmpegReaderGetCodecTag(newReader)),
            dimensions: "\(PBFFmpegReaderGetWidth(newReader))x\(PBFFmpegReaderGetHeight(newReader))",
            colorPrimaries: String(cString: PBFFmpegReaderGetColorPrimaries(newReader)),
            transferFunction: String(cString: PBFFmpegReaderGetTransferFunction(newReader)),
            yCbCrMatrix: String(cString: PBFFmpegReaderGetYCbCrMatrix(newReader)),
            range: String(cString: PBFFmpegReaderGetColorRange(newReader)),
            seekability: .init(.known, value: "providerRebuild"),
            selectedRawTrackMapping: .init(
                .known,
                value: "stream:\(PBFFmpegReaderGetVideoStreamIndex(newReader))"
            ),
            timebase: .init(
                .known,
                value: "\(PBFFmpegReaderGetTimeBaseNumerator(newReader))/\(PBFFmpegReaderGetTimeBaseDenominator(newReader))"
            ),
            codecConfigurationSummary: configurationAtoms.isEmpty
                ? .init(.none)
                : .init(.known, value: configurationAtoms.joined(separator: ",")),
            formatSignaling: VideoFormatSignalingSummary(
                provenance: "FFmpeg.codecParameters",
                colorPrimaries: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetColorPrimaries(newReader))
                ),
                transferFunction: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetTransferFunction(newReader))
                ),
                yCbCrMatrix: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetYCbCrMatrix(newReader))
                ),
                range: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetColorRange(newReader))
                ),
                projectionKind: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetProjectionKind(newReader))
                ),
                viewPackingKind: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetViewPackingKind(newReader))
                ),
                hvcC: PBFFmpegReaderFormatHasHvcC(newReader)
                    ? .init(.known, value: true)
                    : .init(.none, value: false),
                dvcC: PBFFmpegReaderFormatHasDvcC(newReader)
                    ? .init(.known, value: true)
                    : .init(.none, value: false),
                dvvC: PBFFmpegReaderFormatHasDvvC(newReader)
                    ? .init(.known, value: true)
                    : .init(.none, value: false)
            )
        )
        readerLock.withLock {
            if let reader { PBFFmpegReaderDestroy(reader) }
            reader = newReader
            storedInfo = newInfo
        }
    }

    func start() throws {}

    func nextEvent() async throws -> VideoSampleProviderEvent {
        try readerLock.withLock {
            guard let reader else { return .end }
            var sample: Unmanaged<CMSampleBuffer>?
            var error = [CChar](repeating: 0, count: 512)
            let result = PBFFmpegReaderCopyNextSample(reader, &sample, &error, error.count)
            switch result {
            case PBFFmpegReadResultSample:
                guard let sample else { return .end }
                return .sample(sample.takeRetainedValue())
            case PBFFmpegReadResultEnd:
                return .end
            default:
                throw PlaybackProviderError.ffmpeg(Self.errorMessage(error))
            }
        }
    }

    func cancel() {
        readerLock.withLock {
            if let reader {
                PBFFmpegReaderDestroy(reader)
                self.reader = nil
            }
        }
    }

    deinit {
        cancel()
    }

    private static func errorMessage(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func ffmpegStringFact(_ value: String) -> ObservedStringFact {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "unknown", normalized != "unspecified" else {
            return .init(.unknown)
        }
        return .init(.known, value: value)
    }
}

enum PlaybackProviderError: LocalizedError {
    case noVideoTrack
    case readerDidNotStart
    case readerFailed(String)
    case ffmpeg(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "The selected file has no video track."
        case .readerDidNotStart: "AVAssetReader could not start reading."
        case .readerFailed(let message): "AVAssetReader failed: \(message)"
        case .ffmpeg(let message): "FFmpeg: \(message)"
        }
    }
}
