import CoreMedia
import CoreVideo
import Foundation
import PlaybackFFmpegBridge
import Testing
import VideoToolbox

private let profile7TestMedia = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("TestMedia")

private final class Profile7DecodeObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStatuses: [OSStatus] = []
    private var storedImageCount = 0

    var statuses: [OSStatus] { lock.withLock { storedStatuses } }
    var imageCount: Int { lock.withLock { storedImageCount } }

    func record(status: OSStatus, imageBuffer: CVImageBuffer?) {
        lock.withLock {
            storedStatuses.append(status)
            if imageBuffer != nil { storedImageCount += 1 }
        }
    }
}

@Test
func profile7SourcesDeliverDecodableBaseLayerSamples() throws {
    for relativePath in [
        "Samples/DynamicRange/DolbyVision/Profile7.6/FEL_test_for_AVS.mp4",
        "Samples/DynamicRange/DolbyVision/Profile7.6/FEL_test_for_AVS.mkv",
        "Samples/DynamicRange/DolbyVision/Profile7.6/FEL_test_for_AVS.m2ts",
    ] {
        try verifyProfile7Source(relativePath)
    }
}

private func verifyProfile7Source(_ relativePath: String) throws {
    let verifiesEntireSource =
        ProcessInfo.processInfo.environment["PLAYBACKCORE_PROFILE7_FULL_DECODE"] == "1"
    let fixture = profile7TestMedia.appendingPathComponent(
        relativePath
    )
    var error = [CChar](repeating: 0, count: 512)
    let source = fixture.path.withCString {
        PBFFmpegDemuxSourceCreate($0, false, nil, &error, error.count)
    }
    let activeSource = try #require(
        source,
        Comment(rawValue: profile7ErrorString(error))
    )
    defer { PBFFmpegDemuxSourceDestroy(activeSource) }
    let information = try #require(
        PBFFmpegDemuxSourceCopyInformation(activeSource, &error, error.count),
        Comment(rawValue: profile7ErrorString(error))
    )
    defer { PBFFmpegMediaSourceInformationDestroy(information) }
    #expect(PBFFmpegMediaSourceInformationGetDolbyVisionProfile(information) == 7)
    #expect(
        PBFFmpegMediaSourceInformationGetDolbyVisionCrossCompatibilityID(information) == 6
    )
    #expect(PBFFmpegMediaSourceInformationDolbyVisionHasEnhancementLayer(information))
    let activeReader = try #require(PBFFmpegReaderAllocate())
    defer { PBFFmpegReaderDestroy(activeReader) }
    try #require(PBFFmpegReaderOpenWithDemuxSource(
        activeReader,
        activeSource,
        PBFFmpegModeCompressed,
        &error,
        error.count
    ), Comment(rawValue: profile7ErrorString(error)))

    #expect(PBFFmpegReaderFormatHasHvcC(activeReader))
    #expect(!PBFFmpegReaderFormatHasDvcC(activeReader))
    #expect(!PBFFmpegReaderFormatHasDvvC(activeReader))

    var formatReference: Unmanaged<CMVideoFormatDescription>?
    let formatStatus = PBFFmpegVideoFormatDescriptionCreate(
        activeReader,
        nil,
        nil,
        nil,
        &formatReference
    )
    #expect(formatStatus == noErr)
    let activeFormat = try #require(formatReference?.takeRetainedValue())
    #expect(CMFormatDescriptionGetMediaSubType(activeFormat) == kCMVideoCodecType_HEVC)

    let atoms = try profile7SampleDescriptionAtoms(activeFormat)
    let hvcC = try #require(atoms["hvcC"])
    try #require(hvcC.count > 21)
    let nalLengthSize = Int(hvcC[21] & 0x03) + 1

    let observation = Profile7DecodeObservation()
    var session: VTDecompressionSession?
    let sessionStatus = VTDecompressionSessionCreate(
        allocator: kCFAllocatorDefault,
        formatDescription: activeFormat,
        decoderSpecification: nil,
        imageBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey: true,
        ] as CFDictionary,
        outputCallback: nil,
        decompressionSessionOut: &session
    )
    try #require(sessionStatus == noErr)
    let activeSession = try #require(session)
    defer { VTDecompressionSessionInvalidate(activeSession) }

    var submittedSampleCount = 0
    var sawRelocatedParameterSets = !relativePath.hasSuffix(".mp4")
    while true {
        var sampleReference: Unmanaged<CMSampleBuffer>?
        let readResult = PBFFmpegReaderCopyNextSample(
            activeReader,
            &sampleReference,
            &error,
            error.count
        )
        if readResult == PBFFmpegReadResultEnd { break }
        try #require(readResult == PBFFmpegReadResultSample, Comment(
            rawValue: "\(relativePath): \(profile7ErrorString(error))"
        ))
        let sample = try #require(sampleReference?.takeRetainedValue())
        let nalTypes = try profile7NALUnitTypes(
            in: sample,
            lengthSize: nalLengthSize
        )
        #expect(!nalTypes.contains(62))
        #expect(!nalTypes.contains(63))
        if submittedSampleCount > 0,
           let firstVCL = nalTypes.firstIndex(where: { $0 <= 31 }),
           nalTypes[..<firstVCL].contains(32),
           nalTypes[..<firstVCL].contains(33),
           nalTypes[..<firstVCL].contains(34),
           nalTypes[firstVCL] >= 16,
           nalTypes[firstVCL] <= 23 {
            sawRelocatedParameterSets = true
        }

        var flags = VTDecodeInfoFlags()
        let submitStatus = VTDecompressionSessionDecodeFrame(
            activeSession,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: &flags
        ) { status, _, imageBuffer, _, _, _ in
            observation.record(status: status, imageBuffer: imageBuffer)
        }
        #expect(submitStatus == noErr)
        submittedSampleCount += 1
        if !verifiesEntireSource {
            #expect(VTDecompressionSessionWaitForAsynchronousFrames(activeSession) == noErr)
            if sawRelocatedParameterSets && observation.imageCount > 0 { break }
        }
    }

    if verifiesEntireSource {
        #expect(VTDecompressionSessionFinishDelayedFrames(activeSession) == noErr)
    }
    #expect(VTDecompressionSessionWaitForAsynchronousFrames(activeSession) == noErr)
    let failedCallbacks = observation.statuses.enumerated().compactMap { index, status in
        status == noErr ? nil : "\(index):\(status)"
    }
    let statusComment = Comment(rawValue:
        "\(relativePath): submitted=\(submittedSampleCount), " +
        "callbacks=\(observation.statuses.count), images=\(observation.imageCount), " +
        "failures=\(failedCallbacks)"
    )
    #expect(submittedSampleCount > 0)
    #expect(sawRelocatedParameterSets)
    #expect(observation.statuses.count == submittedSampleCount, statusComment)
    #expect(observation.statuses.allSatisfy { $0 == noErr }, statusComment)
    if verifiesEntireSource {
        #expect(observation.imageCount == submittedSampleCount, statusComment)
    } else {
        #expect(observation.imageCount > 0, statusComment)
    }
}

private func profile7SampleDescriptionAtoms(
    _ format: CMVideoFormatDescription
) throws -> [String: Data] {
    let extensions = try #require(
        CMFormatDescriptionGetExtensions(format) as? [String: Any]
    )
    return try #require(
        extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String]
            as? [String: Data]
    )
}

private func profile7NALUnitTypes(
    in sample: CMSampleBuffer,
    lengthSize: Int
) throws -> [UInt8] {
    let block = try #require(CMSampleBufferGetDataBuffer(sample))
    let byteCount = CMBlockBufferGetDataLength(block)
    var data = Data(repeating: 0, count: byteCount)
    let copyStatus = data.withUnsafeMutableBytes { bytes in
        CMBlockBufferCopyDataBytes(
            block,
            atOffset: 0,
            dataLength: byteCount,
            destination: bytes.baseAddress!
        )
    }
    try #require(copyStatus == noErr)

    var types: [UInt8] = []
    var offset = 0
    while offset + lengthSize <= data.count {
        var nalSize = 0
        for byte in data[offset..<(offset + lengthSize)] {
            nalSize = nalSize << 8 | Int(byte)
        }
        offset += lengthSize
        try #require(nalSize > 0 && offset + nalSize <= data.count)
        types.append((data[offset] >> 1) & 0x3f)
        offset += nalSize
    }
    try #require(offset == data.count)
    return types
}

private func profile7ErrorString(_ buffer: [CChar]) -> String {
    String(
        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
}
