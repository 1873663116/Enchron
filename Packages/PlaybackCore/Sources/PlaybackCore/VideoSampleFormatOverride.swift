import CoreMedia
import Foundation

public enum VideoStereoLayout: String, CaseIterable, Codable, Sendable {
    case mono
    case sideBySide
    case overUnder
}

public enum VideoProjectionOverride: String, Codable, Sendable {
    case rectilinear
    case equirectangular
    case halfEquirectangular
}

public enum VideoSampleFormatOverrideError: Error, Equatable, Sendable {
    case missingFormatDescription
    case nonVideoFormat
    case missingCompressedData
    case dataNotReady
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
        projection: VideoProjectionOverride?
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
            projection: projection
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

    private func rewrittenFormat(
        from source: CMFormatDescription,
        stereoLayout: VideoStereoLayout?,
        projection: VideoProjectionOverride?
    ) throws -> CMFormatDescription {
        let key = CacheKey(
            sourceIdentity: ObjectIdentifier(source),
            stereoLayout: stereoLayout,
            projection: projection
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
            }
            extensions[kCMFormatDescriptionExtension_ProjectionKind as String] = projectionKind
        }
        if projection == .rectilinear {
            extensions.removeValue(
                forKey: kCMFormatDescriptionExtension_HorizontalFieldOfView as String
            )
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(source)
        var target: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: CMFormatDescriptionGetMediaSubType(source),
            width: dimensions.width,
            height: dimensions.height,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &target
        )
        guard status == noErr, let target else {
            throw VideoSampleFormatOverrideError.formatDescriptionCreationFailed(status)
        }

        cacheLock.lock()
        formatCache[key] = CachedFormat(source: source, rewritten: target)
        cacheLock.unlock()
        return target
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
