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

@Test("the codecs playback claims to render have decoders on this device")
func rendererCodecsHaveDecoders() throws {
    let codecs: [CMVideoCodecType] = [
        kCMVideoCodecType_H264,
        kCMVideoCodecType_HEVC,
        kCMVideoCodecType_DolbyVisionHEVC,
        kCMVideoCodecType_AV1,
        kCMVideoCodecType_AppleProRes422Proxy,
        kCMVideoCodecType_AppleProRes422LT,
        kCMVideoCodecType_AppleProRes422,
        kCMVideoCodecType_AppleProRes422HQ,
        kCMVideoCodecType_AppleProRes4444,
        kCMVideoCodecType_AppleProRes4444XQ,
    ]
    let report = try codecs.map { codec in
        "\(fourCharacterCode(codec))=\(try decoderStatus(for: codec))"
    }.joined(separator: " ")

    let proResStatus = try decoderStatus(for: kCMVideoCodecType_AppleProRes422)
    #expect(proResStatus == noErr, Comment(rawValue: report))
}
