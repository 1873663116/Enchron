import CoreMedia
import Foundation

@main
struct VideoSampleFormatOverrideTests {
    static func main() throws {
        expect(
            Set(VideoStereoLayout.allCases) == Set([.mono, .sideBySide, .overUnder]),
            "stereo layout has exactly the accepted three values"
        )
        try sideBySideRewritesOnlyStereoFormatSignaling()
        try overUnderWritesOverUnderStereoSignaling()
        try monoRemovesStereoPackingAndClearsEyeFlags()
        try rectilinearProjectionOverridePreservesStereoAndPayload()
        try panoramicProjectionOverridesPreservePayloadAndTiming()
        print("GREEN video sample format override")
    }

    private static func sideBySideRewritesOnlyStereoFormatSignaling() throws {
        let input = try makeCompressedH264Sample()
        let output = try VideoSampleFormatOverride().rewrite(input, layout: .sideBySide)

        let inputFormat = try require(CMSampleBufferGetFormatDescription(input), "input format")
        let outputFormat = try require(CMSampleBufferGetFormatDescription(output), "output format")
        let outputExtensions = extensions(of: outputFormat)

        expect(
            CMFormatDescriptionGetMediaSubType(outputFormat)
                == CMFormatDescriptionGetMediaSubType(inputFormat),
            "codec subtype is preserved"
        )
        let inputDimensions = CMVideoFormatDescriptionGetDimensions(inputFormat)
        let outputDimensions = CMVideoFormatDescriptionGetDimensions(outputFormat)
        expect(
            outputDimensions.width == inputDimensions.width
                && outputDimensions.height == inputDimensions.height,
            "coded dimensions are preserved"
        )
        expect(
            outputExtensions["PlaybackCore.TestMarker"] as? String == "preserve-me",
            "unrelated format extensions are preserved"
        )
        expectNonStereoExtensionsPreserved(from: inputFormat, to: outputFormat)
        expect(
            outputExtensions[kCMFormatDescriptionExtension_ViewPackingKind as String] as? String
                == kCMFormatDescriptionViewPackingKind_SideBySide as String,
            "side-by-side view packing is written"
        )
        expect(
            outputExtensions[kCMFormatDescriptionExtension_HasLeftStereoEyeView as String] as? Bool == true,
            "left-eye presence is written"
        )
        expect(
            outputExtensions[kCMFormatDescriptionExtension_HasRightStereoEyeView as String] as? Bool == true,
            "right-eye presence is written"
        )

        try expectSamplePayloadContractPreserved(from: input, to: output)
    }

    private static func overUnderWritesOverUnderStereoSignaling() throws {
        let input = try makeCompressedH264Sample()
        let output = try VideoSampleFormatOverride().rewrite(input, layout: .overUnder)
        let outputFormat = try require(CMSampleBufferGetFormatDescription(output), "output format")
        let outputExtensions = extensions(of: outputFormat)

        expect(
            outputExtensions[kCMFormatDescriptionExtension_ViewPackingKind as String] as? String
                == kCMFormatDescriptionViewPackingKind_OverUnder as String,
            "over-under view packing is written"
        )
        expect(
            outputExtensions[kCMFormatDescriptionExtension_HasLeftStereoEyeView as String] as? Bool == true,
            "over-under exposes the left eye"
        )
        expect(
            outputExtensions[kCMFormatDescriptionExtension_HasRightStereoEyeView as String] as? Bool == true,
            "over-under exposes the right eye"
        )
        try expectSamplePayloadContractPreserved(from: input, to: output)
    }

    private static func monoRemovesStereoPackingAndClearsEyeFlags() throws {
        let rewriter = VideoSampleFormatOverride()
        let input = try makeCompressedH264Sample()
        let stereo = try rewriter.rewrite(input, layout: .sideBySide)
        let mono = try rewriter.rewrite(stereo, layout: .mono)
        let monoFormat = try require(CMSampleBufferGetFormatDescription(mono), "mono format")
        let monoExtensions = extensions(of: monoFormat)

        expect(
            monoExtensions[kCMFormatDescriptionExtension_ViewPackingKind as String] == nil,
            "mono removes view packing"
        )
        expect(
            monoExtensions[kCMFormatDescriptionExtension_HasLeftStereoEyeView as String] as? Bool == false,
            "mono clears the left-eye flag"
        )
        expect(
            monoExtensions[kCMFormatDescriptionExtension_HasRightStereoEyeView as String] as? Bool == false,
            "mono clears the right-eye flag"
        )
        expectNonStereoExtensionsPreserved(
            from: try require(CMSampleBufferGetFormatDescription(stereo), "stereo format"),
            to: monoFormat
        )
        try expectSamplePayloadContractPreserved(from: stereo, to: mono)
    }

    private static func rectilinearProjectionOverridePreservesStereoAndPayload() throws {
        let input = try makeCompressedH264Sample()
        let output = try VideoSampleFormatOverride().rewrite(
            input,
            stereoLayout: .sideBySide,
            projection: .rectilinear
        )
        let outputFormat = try require(CMSampleBufferGetFormatDescription(output), "output format")
        let outputExtensions = extensions(of: outputFormat)

        expect(
            outputExtensions[kCMFormatDescriptionExtension_ProjectionKind as String] as? String
                == kCMFormatDescriptionProjectionKind_Rectilinear as String,
            "flat presentation writes an effective rectilinear projection"
        )
        expect(
            outputExtensions[kCMFormatDescriptionExtension_HorizontalFieldOfView as String] == nil,
            "flat presentation removes the source panoramic field of view"
        )
        expect(
            outputExtensions[kCMFormatDescriptionExtension_ViewPackingKind as String] as? String
                == kCMFormatDescriptionViewPackingKind_SideBySide as String,
            "projection and Stereo overrides compose"
        )
        expect(
            outputExtensions["PlaybackCore.TestMarker"] as? String == "preserve-me",
            "projection override preserves unrelated extensions"
        )
        try expectSamplePayloadContractPreserved(from: input, to: output)
    }

    private static func panoramicProjectionOverridesPreservePayloadAndTiming() throws {
        let input = try makeCompressedH264Sample()
        for (override, expected) in [
            (
                VideoProjectionOverride.equirectangular,
                kCMFormatDescriptionProjectionKind_Equirectangular
            ),
            (
                VideoProjectionOverride.halfEquirectangular,
                kCMFormatDescriptionProjectionKind_HalfEquirectangular
            ),
        ] {
            let output = try VideoSampleFormatOverride().rewrite(
                input,
                stereoLayout: nil,
                projection: override
            )
            let outputFormat = try require(
                CMSampleBufferGetFormatDescription(output),
                "panoramic output format"
            )
            let outputExtensions = extensions(of: outputFormat)
            expect(
                outputExtensions[kCMFormatDescriptionExtension_ProjectionKind as String]
                    as? String == expected as String,
                "panoramic override writes the requested effective projection"
            )
            expect(
                outputExtensions["PlaybackCore.TestMarker"] as? String == "preserve-me",
                "panoramic override preserves unrelated format extensions"
            )
            try expectSamplePayloadContractPreserved(from: input, to: output)
        }
    }

    private static func makeCompressedH264Sample() throws -> CMSampleBuffer {
        let sequenceParameterSet: [UInt8] = [
            0x67, 0x64, 0x00, 0x1e, 0xac, 0xd9, 0x40, 0xa0,
            0x2f, 0xf9, 0x70, 0x11, 0x00, 0x00, 0x03, 0x00,
            0x01, 0x00, 0x00, 0x03, 0x00, 0x3c, 0x0f, 0x16,
            0x2d, 0x96,
        ]
        let pictureParameterSet: [UInt8] = [0x68, 0xeb, 0xe3, 0xcb, 0x22, 0xc0]
        var baseFormat: CMFormatDescription?
        var status = sequenceParameterSet.withUnsafeBufferPointer { sequencePointer in
            pictureParameterSet.withUnsafeBufferPointer { picturePointer in
                let pointers = [sequencePointer.baseAddress!, picturePointer.baseAddress!]
                let sizes = [sequencePointer.count, picturePointer.count]
                return pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: pointerBuffer.count,
                            parameterSetPointers: pointerBuffer.baseAddress!,
                            parameterSetSizes: sizeBuffer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &baseFormat
                        )
                    }
                }
            }
        }
        guard status == noErr, let baseFormat else {
            throw TestFailure("create base H.264 format: \(status)")
        }

        var formatExtensions = extensions(of: baseFormat)
        formatExtensions["PlaybackCore.TestMarker"] = "preserve-me"
        formatExtensions[kCMFormatDescriptionExtension_ColorPrimaries as String]
            = kCMFormatDescriptionColorPrimaries_ITU_R_709_2
        formatExtensions[kCMFormatDescriptionExtension_ProjectionKind as String]
            = kCMFormatDescriptionProjectionKind_Equirectangular
        formatExtensions[kCMFormatDescriptionExtension_HorizontalFieldOfView as String] = 360_000
        var format: CMFormatDescription?
        let dimensions = CMVideoFormatDescriptionGetDimensions(baseFormat)
        status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: CMFormatDescriptionGetMediaSubType(baseFormat),
            width: dimensions.width,
            height: dimensions.height,
            extensions: formatExtensions as CFDictionary,
            formatDescriptionOut: &format
        )
        guard status == noErr, let format else {
            throw TestFailure("create extended H.264 format: \(status)")
        }

        let payloads: [[UInt8]] = [
            [0, 0, 0, 4, 0x65, 0x88, 0x84, 0x00],
            [0, 0, 0, 4, 0x41, 0x9a, 0x20, 0x11],
        ]
        let payload = payloads.flatMap { $0 }
        var blockBuffer: CMBlockBuffer?
        status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: payload.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: payload.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else {
            throw TestFailure("create block buffer: \(status)")
        }
        status = payload.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: payload.count
            )
        }
        guard status == noErr else {
            throw TestFailure("fill block buffer: \(status)")
        }

        var timings = [
            CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 30),
                presentationTimeStamp: CMTime(value: 10, timescale: 30),
                decodeTimeStamp: CMTime(value: 9, timescale: 30)
            ),
            CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 30),
                presentationTimeStamp: CMTime(value: 11, timescale: 30),
                decodeTimeStamp: CMTime(value: 10, timescale: 30)
            ),
        ]
        var sampleSizes = payloads.map(\.count)
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: format,
            sampleCount: payloads.count,
            sampleTimingEntryCount: timings.count,
            sampleTimingArray: &timings,
            sampleSizeEntryCount: sampleSizes.count,
            sampleSizeArray: &sampleSizes,
            sampleBufferOut: &sample
        )
        guard status == noErr, let sample else {
            throw TestFailure("create sample buffer: \(status)")
        }

        let attachments = try require(
            CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
            "sample attachments"
        )
        for index in 0..<payloads.count {
            let dictionary = unsafeBitCast(
                CFArrayGetValueAtIndex(attachments, index),
                to: CFMutableDictionary.self
            )
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                Unmanaged.passUnretained(index == 0 ? kCFBooleanFalse : kCFBooleanTrue).toOpaque()
            )
        }
        CMSetAttachment(
            sample,
            key: "PlaybackCore.BufferAttachment" as CFString,
            value: "preserve-buffer-attachment" as CFString,
            attachmentMode: kCMAttachmentMode_ShouldPropagate
        )
        CMSetAttachment(
            sample,
            key: "PlaybackCore.NonPropagatingAttachment" as CFString,
            value: "preserve-non-propagating-attachment" as CFString,
            attachmentMode: kCMAttachmentMode_ShouldNotPropagate
        )
        return sample
    }

    private static func expectSamplePayloadContractPreserved(
        from input: CMSampleBuffer,
        to output: CMSampleBuffer
    ) throws {
        expect(CMSampleBufferGetNumSamples(output) == CMSampleBufferGetNumSamples(input), "sample count")
        expect(CMSampleBufferDataIsReady(output) == CMSampleBufferDataIsReady(input), "data readiness")
        let inputData = try require(CMSampleBufferGetDataBuffer(input), "input data buffer")
        let outputData = try require(CMSampleBufferGetDataBuffer(output), "output data buffer")
        expect(inputData === outputData, "the compressed data buffer is shared")
        let inputTimings = try timingInfo(of: input)
        let outputTimings = try timingInfo(of: output)
        expect(timingsEqual(outputTimings, inputTimings), "timing entries are preserved")
        let inputSizes = try sampleSizes(of: input)
        let outputSizes = try sampleSizes(of: output)
        expect(outputSizes == inputSizes, "sample sizes are preserved")

        let inputAttachments = try require(
            CMSampleBufferGetSampleAttachmentsArray(input, createIfNecessary: false),
            "input sample attachments"
        )
        let outputAttachments = try require(
            CMSampleBufferGetSampleAttachmentsArray(output, createIfNecessary: false),
            "output sample attachments"
        )
        expect(CFEqual(inputAttachments, outputAttachments), "per-sample attachments are preserved")

        var attachmentMode: CMAttachmentMode = 0
        let bufferAttachment = CMGetAttachment(
            output,
            key: "PlaybackCore.BufferAttachment" as CFString,
            attachmentModeOut: &attachmentMode
        )
        expect(bufferAttachment as? String == "preserve-buffer-attachment", "buffer attachment is preserved")
        expect(attachmentMode == kCMAttachmentMode_ShouldPropagate, "buffer attachment mode is preserved")

        let nonPropagatingAttachment = CMGetAttachment(
            output,
            key: "PlaybackCore.NonPropagatingAttachment" as CFString,
            attachmentModeOut: &attachmentMode
        )
        expect(
            nonPropagatingAttachment as? String == "preserve-non-propagating-attachment",
            "non-propagating buffer attachment is preserved"
        )
        expect(
            attachmentMode == kCMAttachmentMode_ShouldNotPropagate,
            "non-propagating buffer attachment mode is preserved"
        )
    }

    private static func timingInfo(of sample: CMSampleBuffer) throws -> [CMSampleTimingInfo] {
        var needed = 0
        var status = CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &needed
        )
        guard status == noErr else { throw TestFailure("timing count: \(status)") }
        var entries = Array(repeating: CMSampleTimingInfo(), count: needed)
        status = CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: entries.count,
            arrayToFill: &entries,
            entriesNeededOut: &needed
        )
        guard status == noErr else { throw TestFailure("timing entries: \(status)") }
        return entries
    }

    private static func sampleSizes(of sample: CMSampleBuffer) throws -> [Int] {
        var needed = 0
        var status = CMSampleBufferGetSampleSizeArray(
            sample,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &needed
        )
        guard status == noErr else { throw TestFailure("sample size count: \(status)") }
        var entries = Array(repeating: 0, count: needed)
        status = CMSampleBufferGetSampleSizeArray(
            sample,
            entryCount: entries.count,
            arrayToFill: &entries,
            entriesNeededOut: &needed
        )
        guard status == noErr else { throw TestFailure("sample sizes: \(status)") }
        return entries
    }

    private static func extensions(of format: CMFormatDescription) -> [String: Any] {
        CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
    }

    private static func expectNonStereoExtensionsPreserved(
        from input: CMFormatDescription,
        to output: CMFormatDescription
    ) {
        let stereoKeys: Set<String> = [
            kCMFormatDescriptionExtension_ViewPackingKind as String,
            kCMFormatDescriptionExtension_HasLeftStereoEyeView as String,
            kCMFormatDescriptionExtension_HasRightStereoEyeView as String,
        ]
        let inputExtensions = extensions(of: input)
        let outputExtensions = extensions(of: output)
        for (key, inputValue) in inputExtensions where !stereoKeys.contains(key) {
            guard let outputValue = outputExtensions[key] else {
                expect(false, "non-stereo extension \(key) exists")
                continue
            }
            expect(
                CFEqual(inputValue as CFTypeRef, outputValue as CFTypeRef),
                "non-stereo extension \(key) is unchanged"
            )
        }
    }

    private static func timingsEqual(
        _ lhs: [CMSampleTimingInfo],
        _ rhs: [CMSampleTimingInfo]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.duration == $1.duration
                && $0.presentationTimeStamp == $1.presentationTimeStamp
                && $0.decodeTimeStamp == $1.decodeTimeStamp
        }
    }

    private static func require<T>(_ value: T?, _ name: String) throws -> T {
        guard let value else { throw TestFailure("missing \(name)") }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("RED \(message)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
