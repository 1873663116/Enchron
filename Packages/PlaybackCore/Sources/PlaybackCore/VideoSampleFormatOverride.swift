import CoreMedia
import Foundation
import PlaybackFFmpegBridge

public enum VideoStereoLayout: String, CaseIterable, Codable, Sendable {
    case mono
    case sideBySide
    case overUnder
}

public enum VideoProjectionOverride: Hashable, Codable, Sendable {
    case rectilinear
    case equirectangular
    case halfEquirectangular
    case customEquirectangular(horizontalFieldOfViewDegrees: Int)

    public var diagnosticLabel: String {
        switch self {
        case .rectilinear: "rectilinear"
        case .equirectangular: "equirectangular"
        case .halfEquirectangular: "halfEquirectangular"
        case .customEquirectangular(let degrees): "customEquirectangular-\(degrees)"
        }
    }
}

public enum VideoDynamicRangeOverride: String, Codable, Sendable {
    case dolbyVisionFallback
}

public enum VideoSampleFormatOverrideError: Error, Equatable, Sendable {
    case missingFormatDescription
    case nonVideoFormat
    case missingCompressedData
    case dataNotReady
    case dolbyVisionFallbackUnavailable(compatibilityID: Int?)
    case formatDescriptionCreationFailed(OSStatus)
    case timingReadFailed(OSStatus)
    case sampleSizeReadFailed(OSStatus)
    case sampleBufferCreationFailed(OSStatus)
}

public final class VideoSampleFormatOverride: @unchecked Sendable {
    private struct CacheKey: Hashable {
        let sourceIdentity: ObjectIdentifier
        let stereoLayout: VideoStereoLayout?
        let projection: VideoProjectionOverride?
        let dynamicRange: VideoDynamicRangeOverride?
    }

    private struct CachedFormat {
        let source: CMFormatDescription
        let rewritten: CMFormatDescription
    }

    private let cacheLock = NSLock()
    private var formatCache: [CacheKey: CachedFormat] = [:]

    public init() {}

    public func rewrite(
        _ sampleBuffer: CMSampleBuffer,
        layout: VideoStereoLayout
    ) throws -> CMSampleBuffer {
        try rewrite(sampleBuffer, stereoLayout: layout, projection: nil)
    }

    public func rewrite(
        _ sampleBuffer: CMSampleBuffer,
        stereoLayout: VideoStereoLayout?,
        projection: VideoProjectionOverride?,
        dynamicRange: VideoDynamicRangeOverride? = nil
    ) throws -> CMSampleBuffer {
        guard let sourceFormat = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw VideoSampleFormatOverrideError.missingFormatDescription
        }
        guard CMFormatDescriptionGetMediaType(sourceFormat) == kCMMediaType_Video else {
            throw VideoSampleFormatOverrideError.nonVideoFormat
        }
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw VideoSampleFormatOverrideError.missingCompressedData
        }
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            throw VideoSampleFormatOverrideError.dataNotReady
        }

        let targetFormat = try rewrittenFormat(
            from: sourceFormat,
            stereoLayout: stereoLayout,
            projection: projection,
            dynamicRange: dynamicRange
        )
        let timings = try sampleTimings(of: sampleBuffer)
        let sampleSizes = try sampleSizes(of: sampleBuffer)
        var rewritten: CMSampleBuffer?
        let status = timings.withUnsafeBufferPointer { timingBuffer in
            sampleSizes.withUnsafeBufferPointer { sizeBuffer in
                CMSampleBufferCreateReady(
                    allocator: kCFAllocatorDefault,
                    dataBuffer: dataBuffer,
                    formatDescription: targetFormat,
                    sampleCount: CMSampleBufferGetNumSamples(sampleBuffer),
                    sampleTimingEntryCount: timingBuffer.count,
                    sampleTimingArray: timingBuffer.baseAddress,
                    sampleSizeEntryCount: sizeBuffer.count,
                    sampleSizeArray: sizeBuffer.baseAddress,
                    sampleBufferOut: &rewritten
                )
            }
        }
        guard status == noErr, let rewritten else {
            throw VideoSampleFormatOverrideError.sampleBufferCreationFailed(status)
        }

        copyBufferAttachments(from: sampleBuffer, to: rewritten)
        copySampleAttachments(from: sampleBuffer, to: rewritten)
        return rewritten
    }

    func replacingFormatDescription(
        of sampleBuffer: CMSampleBuffer,
        with targetFormat: CMFormatDescription
    ) throws -> CMSampleBuffer {
        guard let sourceFormat = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw VideoSampleFormatOverrideError.missingFormatDescription
        }
        guard CMFormatDescriptionGetMediaType(sourceFormat) == kCMMediaType_Video,
              CMFormatDescriptionGetMediaType(targetFormat) == kCMMediaType_Video else {
            throw VideoSampleFormatOverrideError.nonVideoFormat
        }
        let sourceDimensions = CMVideoFormatDescriptionGetDimensions(sourceFormat)
        let targetDimensions = CMVideoFormatDescriptionGetDimensions(targetFormat)
        guard CMFormatDescriptionGetMediaSubType(sourceFormat)
                == CMFormatDescriptionGetMediaSubType(targetFormat),
              sourceDimensions.width == targetDimensions.width,
              sourceDimensions.height == targetDimensions.height else {
            throw VideoSampleFormatOverrideError.formatDescriptionCreationFailed(
                kCMFormatDescriptionError_InvalidParameter
            )
        }
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw VideoSampleFormatOverrideError.missingCompressedData
        }
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            throw VideoSampleFormatOverrideError.dataNotReady
        }

        let timings = try sampleTimings(of: sampleBuffer)
        let sampleSizes = try sampleSizes(of: sampleBuffer)
        var replaced: CMSampleBuffer?
        let status = timings.withUnsafeBufferPointer { timingBuffer in
            sampleSizes.withUnsafeBufferPointer { sizeBuffer in
                CMSampleBufferCreateReady(
                    allocator: kCFAllocatorDefault,
                    dataBuffer: dataBuffer,
                    formatDescription: targetFormat,
                    sampleCount: CMSampleBufferGetNumSamples(sampleBuffer),
                    sampleTimingEntryCount: timingBuffer.count,
                    sampleTimingArray: timingBuffer.baseAddress,
                    sampleSizeEntryCount: sizeBuffer.count,
                    sampleSizeArray: sizeBuffer.baseAddress,
                    sampleBufferOut: &replaced
                )
            }
        }
        guard status == noErr, let replaced else {
            throw VideoSampleFormatOverrideError.sampleBufferCreationFailed(status)
        }

        copyBufferAttachments(from: sampleBuffer, to: replaced)
        copySampleAttachments(from: sampleBuffer, to: replaced)
        return replaced
    }

    func taggedPresentationSample(
        _ sampleBuffer: CMSampleBuffer,
        stereoLayout: VideoStereoLayout?,
        projection: VideoProjectionOverride?
    ) -> CMSampleBuffer {
        // Compressed SBS/OU remains one codec sample whose packing and
        // projection live in its CMVideoFormatDescription. RealityKit's
        // tagged-buffer contract describes decoded pixel buffers; wrapping a
        // compressed sample in a CMTaggedBufferGroup can make the renderer
        // reject or crash on otherwise valid high-resolution HEVC input.
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
            return sampleBuffer
        }
        let usesPackedStereo = stereoLayout == .sideBySide
            || stereoLayout == .overUnder
        guard usesPackedStereo else { return sampleBuffer }

        var tags: [CMTag] = [.mediaType(.video)]
        if let projection {
            let projectionType: CMProjectionType = switch projection {
            case .rectilinear: .rectangular
            case .equirectangular: .equirectangular
            case .halfEquirectangular: .halfEquirectangular
            case .customEquirectangular: .equirectangular
            }
            tags.append(.projectionType(projectionType))
        }
        switch stereoLayout {
        case .sideBySide:
            tags.append(.packingType(.sideBySide))
            tags.append(.stereoView([.leftEye, .rightEye]))
        case .overUnder:
            tags.append(.packingType(.overUnder))
            tags.append(.stereoView([.leftEye, .rightEye]))
        case .mono, nil:
            break
        }

        let taggedBuffer = CMTaggedBuffer(tags: tags, sampleBuffer: sampleBuffer)
        let format = CMTaggedBufferGroupFormatDescription(
            taggedBuffers: [taggedBuffer]
        )
        let taggedSample = CMSampleBuffer(
            taggedBuffers: [taggedBuffer],
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            duration: CMSampleBufferGetDuration(sampleBuffer),
            formatDescription: format
        )
        copyBufferAttachments(from: sampleBuffer, to: taggedSample)
        return taggedSample
    }

    private func rewrittenFormat(
        from source: CMFormatDescription,
        stereoLayout: VideoStereoLayout?,
        projection: VideoProjectionOverride?,
        dynamicRange: VideoDynamicRangeOverride?
    ) throws -> CMFormatDescription {
        let key = CacheKey(
            sourceIdentity: ObjectIdentifier(source),
            stereoLayout: stereoLayout,
            projection: projection,
            dynamicRange: dynamicRange
        )
        cacheLock.lock()
        if let cached = formatCache[key] {
            cacheLock.unlock()
            return cached.rewritten
        }
        cacheLock.unlock()

        var extensions = CMFormatDescriptionGetExtensions(source) as? [String: Any] ?? [:]
        let packingKey = kCMFormatDescriptionExtension_ViewPackingKind as String
        let leftEyeKey = kCMFormatDescriptionExtension_HasLeftStereoEyeView as String
        let rightEyeKey = kCMFormatDescriptionExtension_HasRightStereoEyeView as String
        if let stereoLayout {
            switch stereoLayout {
            case .mono:
                extensions.removeValue(forKey: packingKey)
                extensions[leftEyeKey] = false
                extensions[rightEyeKey] = false
            case .sideBySide:
                extensions[packingKey] = kCMFormatDescriptionViewPackingKind_SideBySide
                extensions[leftEyeKey] = true
                extensions[rightEyeKey] = true
            case .overUnder:
                extensions[packingKey] = kCMFormatDescriptionViewPackingKind_OverUnder
                extensions[leftEyeKey] = true
                extensions[rightEyeKey] = true
            }
        }

        if let projection {
            let projectionKind: CFString = switch projection {
            case .rectilinear:
                kCMFormatDescriptionProjectionKind_Rectilinear
            case .equirectangular:
                kCMFormatDescriptionProjectionKind_Equirectangular
            case .halfEquirectangular:
                kCMFormatDescriptionProjectionKind_HalfEquirectangular
            case .customEquirectangular:
                kCMFormatDescriptionProjectionKind_Equirectangular
            }
            extensions[kCMFormatDescriptionExtension_ProjectionKind as String] = projectionKind
            let horizontalFieldOfView: Int? = switch projection {
            case .equirectangular:
                360_000
            case .halfEquirectangular:
                180_000
            case .customEquirectangular(let degrees):
                min(max(degrees, 180), 360) * 1_000
            case .rectilinear:
                nil
            }
            if let horizontalFieldOfView {
                extensions[
                    kCMFormatDescriptionExtension_HorizontalFieldOfView as String
                ] = horizontalFieldOfView
            }
        }
        if projection == .rectilinear {
            extensions.removeValue(
                forKey: kCMFormatDescriptionExtension_HorizontalFieldOfView as String
            )
        }

        if dynamicRange == .dolbyVisionFallback {
            try applyDolbyVisionFallback(to: &extensions)
        }

        var target: Unmanaged<CMVideoFormatDescription>?
        let status = PBFFmpegVideoFormatDescriptionCreate(
            nil,
            source,
            nil,
            extensions as CFDictionary,
            &target
        )
        guard status == noErr, let target else {
            throw VideoSampleFormatOverrideError.formatDescriptionCreationFailed(status)
        }
        let rewritten = target.takeRetainedValue()

        cacheLock.lock()
        formatCache[key] = CachedFormat(source: source, rewritten: rewritten)
        cacheLock.unlock()
        return rewritten
    }

    private func applyDolbyVisionFallback(
        to extensions: inout [String: Any]
    ) throws {
        let atomsKey =
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String
        var atoms = extensions[atomsKey] as? [String: Data] ?? [:]
        let configuration = atoms["dvvC"] ?? atoms["dvcC"]
        let compatibilityID = configuration.flatMap { data in
            data.count > 4 ? Int(data[4] >> 4) : nil
        }
        guard let compatibilityID, compatibilityID != 0 else {
            throw VideoSampleFormatOverrideError.dolbyVisionFallbackUnavailable(
                compatibilityID: compatibilityID
            )
        }
        atoms.removeValue(forKey: "dvcC")
        atoms.removeValue(forKey: "dvvC")
        extensions[atomsKey] = atoms

        switch compatibilityID {
        case 1, 6:
            extensions[kCMFormatDescriptionExtension_ColorPrimaries as String]
                = kCMFormatDescriptionColorPrimaries_ITU_R_2020
            extensions[kCMFormatDescriptionExtension_TransferFunction as String]
                = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
            extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String]
                = kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
            extensions[kCMFormatDescriptionExtension_FullRangeVideo as String] = false
        case 4:
            extensions[kCMFormatDescriptionExtension_ColorPrimaries as String]
                = kCMFormatDescriptionColorPrimaries_ITU_R_2020
            extensions[kCMFormatDescriptionExtension_TransferFunction as String]
                = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG
            extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String]
                = kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
            extensions[kCMFormatDescriptionExtension_FullRangeVideo as String] = false
        default:
            break
        }
    }

    private func sampleTimings(of sampleBuffer: CMSampleBuffer) throws -> [CMSampleTimingInfo] {
        var count = 0
        var status = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &count
        )
        guard status == noErr else {
            throw VideoSampleFormatOverrideError.timingReadFailed(status)
        }
        var timings = Array(repeating: CMSampleTimingInfo(), count: count)
        status = timings.withUnsafeMutableBufferPointer { buffer in
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: buffer.count,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: &count
            )
        }
        guard status == noErr else {
            throw VideoSampleFormatOverrideError.timingReadFailed(status)
        }
        return timings
    }

    private func sampleSizes(of sampleBuffer: CMSampleBuffer) throws -> [Int] {
        var count = 0
        var status = CMSampleBufferGetSampleSizeArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &count
        )
        guard status == noErr else {
            throw VideoSampleFormatOverrideError.sampleSizeReadFailed(status)
        }
        var sizes = Array(repeating: 0, count: count)
        status = sizes.withUnsafeMutableBufferPointer { buffer in
            CMSampleBufferGetSampleSizeArray(
                sampleBuffer,
                entryCount: buffer.count,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: &count
            )
        }
        guard status == noErr else {
            throw VideoSampleFormatOverrideError.sampleSizeReadFailed(status)
        }
        return sizes
    }

    private func copyBufferAttachments(
        from source: CMSampleBuffer,
        to destination: CMSampleBuffer
    ) {
        for mode in [kCMAttachmentMode_ShouldNotPropagate, kCMAttachmentMode_ShouldPropagate] {
            guard let attachments = CMCopyDictionaryOfAttachments(
                allocator: kCFAllocatorDefault,
                target: source,
                attachmentMode: mode
            ) else { continue }
            CMSetAttachments(destination, attachments: attachments, attachmentMode: mode)
        }
    }

    private func copySampleAttachments(
        from source: CMSampleBuffer,
        to destination: CMSampleBuffer
    ) {
        guard let sourceArray = CMSampleBufferGetSampleAttachmentsArray(
            source,
            createIfNecessary: false
        ),
        let destinationArray = CMSampleBufferGetSampleAttachmentsArray(
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
            let entryCount = CFDictionaryGetCount(sourceDictionary)
            var keys = [UnsafeRawPointer?](repeating: nil, count: entryCount)
            var values = [UnsafeRawPointer?](repeating: nil, count: entryCount)
            keys.withUnsafeMutableBufferPointer { keyBuffer in
                values.withUnsafeMutableBufferPointer { valueBuffer in
                    CFDictionaryGetKeysAndValues(
                        sourceDictionary,
                        keyBuffer.baseAddress,
                        valueBuffer.baseAddress
                    )
                }
            }
            for entryIndex in 0..<entryCount {
                if let key = keys[entryIndex], let value = values[entryIndex] {
                    CFDictionarySetValue(destinationDictionary, key, value)
                }
            }
        }
    }
}
