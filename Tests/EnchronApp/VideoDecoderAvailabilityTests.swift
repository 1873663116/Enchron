import CoreMedia
import Testing
import VideoToolbox

/// What this device will actually decode, asked of VideoToolbox rather than inferred.
///
/// PlaybackCore decides a codec is renderable when its four character code maps to a
/// known CMVideoCodecType. That is a mapping check, not a capability check, so a codec
/// the device has no decoder for reaches the renderer and fails there as a silent black
/// window. These cases record the real answer per codec.
private func decoderStatus(
    for codecType: CMVideoCodecType,
    width: Int32 = 1920,
    height: Int32 = 1080
) throws -> OSStatus {
    var format: CMVideoFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        codecType: codecType,
        width: width,
        height: height,
        extensions: nil,
        formatDescriptionOut: &format
    )
    #expect(formatStatus == noErr)
    let description = try #require(format)

    var session: VTDecompressionSession?
    let status = VTDecompressionSessionCreate(
        allocator: kCFAllocatorDefault,
        formatDescription: description,
        decoderSpecification: nil,
        imageBufferAttributes: nil,
        outputCallback: nil,
        decompressionSessionOut: &session
    )
    if let session {
        VTDecompressionSessionInvalidate(session)
    }
    return status
}

private func fourCharacterCode(_ codecType: CMVideoCodecType) -> String {
    String(
        bytes: (0..<4).map { UInt8((codecType >> (8 * (3 - $0))) & 0xff) },
        encoding: .ascii
    ) ?? "????"
}

@Test("this device has a Dolby Vision decoder")
func dolbyVisionDecoderExistsOnThisDevice() throws {
    // HEVC carries its parameter sets in extradata, so a bare description cannot open
    // a session for either type and neither status is noErr. That still separates the
    // two failures that matter. A decoder that was never found reports
    // kVTCouldNotFindVideoDecoderErr, as all six ProRes types do. A decoder that was
    // found and then rejected the description reports something else. Requiring the
    // two types to return the same status would be the wrong bar, because different
    // decoders describe an incomplete description differently.
    let hevc = try decoderStatus(for: kCMVideoCodecType_HEVC)
    let dolbyVision = try decoderStatus(for: kCMVideoCodecType_DolbyVisionHEVC)
    let report = "hvc1=\(hevc)\ndvh1=\(dolbyVision)"
    try? report.write(
        to: URL.documentsDirectory.appending(path: "dolby-vision-availability.txt"),
        atomically: true,
        encoding: .utf8
    )
    #expect(dolbyVision != kVTCouldNotFindVideoDecoderErr, Comment(rawValue: report))
    #expect(hevc != kVTCouldNotFindVideoDecoderErr, Comment(rawValue: report))
}

@Test("this device has no ProRes decoder, and the probe that says so works")
func proResHasNoDecoderOnThisDevice() throws {
    let proRes: [CMVideoCodecType] = [
        kCMVideoCodecType_AppleProRes422Proxy,
        kCMVideoCodecType_AppleProRes422LT,
        kCMVideoCodecType_AppleProRes422,
        kCMVideoCodecType_AppleProRes422HQ,
        kCMVideoCodecType_AppleProRes4444,
        kCMVideoCodecType_AppleProRes4444XQ,
    ]
    let report = try (proRes + [kCMVideoCodecType_H264]).map { codec in
        "\(fourCharacterCode(codec))=\(try decoderStatus(for: codec))"
    }.joined(separator: "\n")
    // Test host stdout does not reach the xcodebuild log or the result bundle on
    // device. The app container does, through devicectl.
    try? report.write(
        to: URL.documentsDirectory.appending(path: "decoder-availability.txt"),
        atomically: true,
        encoding: .utf8
    )

    // H.264 is the control. It is the one codec here whose sample description is
    // complete without extradata, so a session that opens for it and not for
    // ProRes separates a missing decoder from an incomplete description.
    #expect(try decoderStatus(for: kCMVideoCodecType_H264) == noErr)
    for codec in proRes {
        #expect(
            try decoderStatus(for: codec) == kVTCouldNotFindVideoDecoderErr,
            Comment(rawValue: report)
        )
    }
}

/// Every codec PlaybackCore can hand a renderer, asked of this environment at once.
///
/// The axis is `codec_type()` in `PlaybackFFmpegBridge.c`, which is the one place
/// that decides what reaches the renderer: anything it maps to 0 fails
/// `compressed_codec_is_renderable` and never reaches VideoToolbox, so probing it
/// would measure the platform rather than this product.
///
/// The two cases above assert what one environment must be true of. This one
/// asserts nothing beyond the control and records the whole answer instead,
/// because the interesting use is the diff between a simulator run and a device
/// run, and a case that encodes one side's answer cannot produce that diff.
/// The report lands in the container as `video-decoder-matrix.tsv`.
@Test("this environment's video decoder matrix is recorded")
func videoDecoderMatrixIsRecorded() throws {
    let codecs: [(String, CMVideoCodecType)] = [
        ("H.264", kCMVideoCodecType_H264),
        ("HEVC", kCMVideoCodecType_HEVC),
        ("Dolby Vision HEVC", kCMVideoCodecType_DolbyVisionHEVC),
        ("AV1", kCMVideoCodecType_AV1),
        ("ProRes 422 Proxy", kCMVideoCodecType_AppleProRes422Proxy),
        ("ProRes 422 LT", kCMVideoCodecType_AppleProRes422LT),
        ("ProRes 422", kCMVideoCodecType_AppleProRes422),
        ("ProRes 422 HQ", kCMVideoCodecType_AppleProRes422HQ),
        ("ProRes 4444", kCMVideoCodecType_AppleProRes4444),
        ("ProRes 4444 XQ", kCMVideoCodecType_AppleProRes4444XQ),
    ]
    let rows = try codecs.map { name, codec -> String in
        let status = try decoderStatus(for: codec)
        // A codec whose sample description is incomplete without extradata
        // cannot open a session even where its decoder exists, so the only
        // sound reading is present versus never found.
        let verdict = status == kVTCouldNotFindVideoDecoderErr ? "absent" : "present"
        return "\(name)\t\(fourCharacterCode(codec))\t\(status)\t\(verdict)"
    }
    let report = rows.joined(separator: "\n")
    try? report.write(
        to: URL.documentsDirectory.appending(path: "video-decoder-matrix.tsv"),
        atomically: true,
        encoding: .utf8
    )

    // H.264 is the control: the one codec here whose description is complete
    // without extradata, so a run where even it cannot open a session measured
    // something other than decoder availability.
    #expect(try decoderStatus(for: kCMVideoCodecType_H264) == noErr, Comment(rawValue: report))
}
