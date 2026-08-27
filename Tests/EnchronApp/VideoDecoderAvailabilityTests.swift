import CoreMedia
import Testing
import VideoToolbox

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
        kCMVideoCodecType_AppleProRes4444XQ
    ]
    let report = try (proRes + [kCMVideoCodecType_H264]).map { codec in
        "\(fourCharacterCode(codec))=\(try decoderStatus(for: codec))"
    }.joined(separator: "\n")
    try? report.write(
        to: URL.documentsDirectory.appending(path: "decoder-availability.txt"),
        atomically: true,
        encoding: .utf8
    )

    #expect(try decoderStatus(for: kCMVideoCodecType_H264) == noErr)
    for codec in proRes {
        #expect(
            try decoderStatus(for: codec) == kVTCouldNotFindVideoDecoderErr,
            Comment(rawValue: report)
        )
    }
}

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
        ("ProRes 4444 XQ", kCMVideoCodecType_AppleProRes4444XQ)
    ]
    let rows = try codecs.map { name, codec -> String in
        let status = try decoderStatus(for: codec)
        let verdict = status == kVTCouldNotFindVideoDecoderErr ? "absent" : "present"
        return "\(name)\t\(fourCharacterCode(codec))\t\(status)\t\(verdict)"
    }
    let report = rows.joined(separator: "\n")
    try? report.write(
        to: URL.documentsDirectory.appending(path: "video-decoder-matrix.tsv"),
        atomically: true,
        encoding: .utf8
    )

    #expect(try decoderStatus(for: kCMVideoCodecType_H264) == noErr, Comment(rawValue: report))
}
