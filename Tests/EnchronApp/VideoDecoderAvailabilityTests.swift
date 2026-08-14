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
