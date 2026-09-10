import AudioToolbox
import AVFoundation
import CoreMedia
import Foundation
import PlaybackFFmpegBridge
import Testing
import VideoToolbox
@testable import PlaybackCore

private let playbackTestMedia = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("TestMedia")

private struct TestMediaStreamInformation {
    let raw: PBFFmpegMediaStreamInfo
    let codecName: String
    let language: String
    let title: String
}

private func mediaStreams(in fixture: URL) -> [TestMediaStreamInformation] {
    var error = [CChar](repeating: 0, count: 512)
    let information = fixture.path.withCString {
        PBFFmpegMediaSourceInformationCreate($0, &error, error.count)
    }
    guard let information else {
        Issue.record("\(fixture.lastPathComponent): \(cString(error))")
        return []
    }
    defer { PBFFmpegMediaSourceInformationDestroy(information) }
    return (0..<PBFFmpegMediaSourceInformationGetStreamCount(information)).compactMap {
        ordinal in
        var raw = PBFFmpegMediaStreamInfo()
        var codecName = [CChar](repeating: 0, count: 64)
        var language = [CChar](repeating: 0, count: 64)
        var title = [CChar](repeating: 0, count: 256)
        guard PBFFmpegMediaSourceInformationCopyStream(
            information,
            ordinal,
            &raw,
            &codecName, codecName.count,
            &language, language.count,
            &title, title.count,
            nil, 0,
            nil, 0,
            nil, 0,
            nil, 0,
            nil, 0
        ) else { return nil }
        return TestMediaStreamInformation(
            raw: raw,
            codecName: cString(codecName),
            language: cString(language),
            title: cString(title)
        )
    }
}

@Test func theVendoredBuildCarriesEveryComponentThisEngineReadsMediaThrough() throws {
    // The build decides what a source can be at all, and a component that was
    // configured away is missing at runtime with no error of its own: the
    // compressed Matroska subtitle track simply produced no picture. The
    // configure line is what was asked for; this is what is in the binary.
    // Anything listed here is on a path the product takes, so a name that
    // stops matching is either a real loss or a list that needs correcting -
    // never something to delete to make the test pass.
    for demuxer in ["matroska", "mov"] {
        #expect(
            PBFFmpegHasDemuxer(demuxer),
            Comment(rawValue: "demuxer \(demuxer)")
        )
    }
    for protocolName in ["file", "http", "https", "tcp", "tls"] {
        #expect(
            PBFFmpegHasInputProtocol(protocolName),
            Comment(rawValue: "protocol \(protocolName)")
        )
    }
    // Subtitles and audio are decoded here; video is handed to VideoToolbox
    // as compressed samples and has no FFmpeg decoder on its path.
    for decoder in [
        "pgssub", "dvdsub", "ass", "srt", "subrip", "mov_text", "webvtt",
        // DTS is "dca" here, after the codec family rather than the brand.
        "aac", "ac3", "eac3", "dca", "truehd", "flac", "mp3", "opus", "vorbis",
        "pcm_s16le",
    ] {
        #expect(
            PBFFmpegHasDecoder(decoder),
            Comment(rawValue: "decoder \(decoder)")
        )
    }
}

@Test func theVendoredBuildCanUncompressMatroskaTrackContents() throws {
    // Matroska may store a track's frames compressed, and mkvmerge does this
    // to Blu-ray bitmap subtitles by default. The demuxer uncompresses them
    // only in a build that has zlib; without it the compressed bytes reach the
    // codec, which reads them as its own format, finds nothing it knows and
    // produces no picture - no error anywhere along the way. The configure
    // line is what decides this, so it is asserted rather than described.
    let configuration = String(cString: PBFFmpegBuildConfiguration())
    #expect(
        configuration.contains("--enable-zlib"),
        Comment(rawValue: "vendored FFmpeg configure line: \(configuration)")
    )
}

@Test func nonSquarePixelStereoFixtureCarriesItsDisplayGeometryThroughTheBridge() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/Spatial/Stereo180/180_3D_TB.mp4"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    let result = PBFFmpegReaderCopyNextSample(
        activeReader,
        &sample,
        &error,
        error.count
    )
    #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let encoded = CMVideoFormatDescriptionGetDimensions(format)
    let presented = CMVideoFormatDescriptionGetPresentationDimensions(
        format,
        usePixelAspectRatio: true,
        useCleanAperture: false
    )
    let extensions = try #require(
        CMFormatDescriptionGetExtensions(format) as? [String: Any]
    )
    let pixelAspectRatio = try #require(
        extensions[kCMFormatDescriptionExtension_PixelAspectRatio as String]
            as? [String: Any]
    )

    #expect(encoded.width == 8_192)
    #expect(encoded.height == 4_096)
    #expect(
        pixelAspectRatio[
            kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String
        ] as? Int == 1
    )
    #expect(
        pixelAspectRatio[
            kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String
        ] as? Int == 4
    )
    #expect(presented.width == 2_048)
    #expect(presented.height == 4_096)
    #expect(
        PlaybackVideoGeometry(formatDescription: format) == .init(
            encodedDimensions: .init(width: 8_192, height: 4_096),
            sampleAspectRatio: .init(horizontalSpacing: 1, verticalSpacing: 4)
        )
    )
}

@Test func vrAndDolbyFixturesCreateCompressedSamplesThroughFFmpegBridge() throws {
    silenceFFmpegDiagnostics()
    let fixtures = [
        "Samples/Spatial/Panorama/360.mp4",
        "Samples/Spatial/Stereo180/180_3D.mp4",
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4",
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
    ]

    for relativePath in fixtures {
        let fixture = playbackTestMedia.appendingPathComponent(relativePath)
        var error = [CChar](repeating: 0, count: 512)
        let reader = fixture.path.withCString { path in
            PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
        }
        let activeReader = try #require(reader, Comment(rawValue: "\(relativePath): \(cString(error))"))
        defer { PBFFmpegReaderDestroy(activeReader) }

        var sample: Unmanaged<CMSampleBuffer>?
        let result = PBFFmpegReaderCopyNextSample(activeReader, &sample, &error, error.count)
        #expect(result == PBFFmpegReadResultSample, Comment(rawValue: "\(relativePath): \(cString(error))"))
        #expect(sample?.takeRetainedValue().formatDescription != nil)
    }
}

@Test func equirectangularSourceFormatIncludesItsKnownHorizontalFieldOfView() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Enchron/Calibration/Derived/APMP/equirect_grid_hevc_mono_apmp.mov"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    let result = PBFFmpegReaderCopyNextSample(
        activeReader,
        &sample,
        &error,
        error.count
    )
    #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any]

    #expect(
        extensions?[kCMFormatDescriptionExtension_ProjectionKind as String] as? String
            == kCMFormatDescriptionProjectionKind_Equirectangular as String
    )
    #expect(
        extensions?[kCMFormatDescriptionExtension_HorizontalFieldOfView as String] as? Int
            == 360_000
    )
}

@Test(arguments: [
    ("TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-avsync-30s.mp4", 1.5, 2),
    ("TestVectors/Enchron/Calibration/Sources/equirect_grid.mp4", 1.5, 2),
    ("Samples/Spatial/Stereo180/180_3D.mp4", 1.5, 2),
    (
        "Samples/CameraOriginals/Sony-A7SIII/"
            + "a7s III 4K 60p 600Mbps 10 bit 422 Slog3 SGamut3 .MP4",
        1.5,
        0
    ),
])
func skippingTheProbeStillDescribesWhatAFrameCosts(
    relativePath: String,
    expectedBytesPerPixel: Double,
    expectedReorderDepth: Int
) async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(relativePath)
    try #require(FileManager.default.fileExists(atPath: fixture.path))
    let information = try await SystemMediaSourceInformationLoader().load(from: fixture)
    let video = try #require(information.streams.compactMap { $0.video }.first)
    #expect(video.decodedBytesPerPixel == expectedBytesPerPixel)
    #expect(video.reorderDepth == expectedReorderDepth)
}

@Test(arguments: [
    (
        "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-avsync-30s.mp4",
        kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String?,
        kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String?,
        kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String?,
        false as Bool?
    ),
    (
        "TestVectors/Enchron/Calibration/Sources/equirect_grid.mp4",
        String?.none,
        String?.none,
        String?.none,
        false as Bool?
    ),
    (
        "Samples/CameraOriginals/Sony-A7SIII/a7s III 4K 60p 600Mbps 10 bit 422 Slog3 SGamut3 .MP4",
        String?.none,
        String?.none,
        String?.none,
        true as Bool?
    ),
])
func avcCH264FixturesCarryTheColorDeclarationOfTheirParameterSets(
    relativePath: String,
    declaredPrimaries: String?,
    declaredTransfer: String?,
    declaredMatrix: String?,
    declaresFullRange: Bool?
) async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(relativePath)
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(
        reader,
        Comment(rawValue: "\(relativePath): \(cString(error))")
    )
    defer { PBFFmpegReaderDestroy(activeReader) }
    var sampleReference: Unmanaged<CMSampleBuffer>?
    #expect(
        PBFFmpegReaderCopyNextSample(
            activeReader,
            &sampleReference,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: "\(relativePath): \(cString(error))")
    )
    let sample = try #require(sampleReference?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(sample))
    #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264)
    let bridgeExtensions =
        CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
    let sourceFormat = try await firstVideoFormatDescription(in: AVURLAsset(url: fixture))
    let sourceExtensions =
        CMFormatDescriptionGetExtensions(sourceFormat) as? [String: Any] ?? [:]

    for (key, declared) in [
        (kCMFormatDescriptionExtension_ColorPrimaries as String, declaredPrimaries),
        (kCMFormatDescriptionExtension_TransferFunction as String, declaredTransfer),
        (kCMFormatDescriptionExtension_YCbCrMatrix as String, declaredMatrix),
    ] {
        #expect(
            bridgeExtensions[key] as? String == declared,
            Comment(rawValue: "\(relativePath) bridge \(key)")
        )
        #expect(
            sourceExtensions[key] as? String == declared,
            Comment(rawValue: "\(relativePath) source \(key)")
        )
    }
    let rangeKey = kCMFormatDescriptionExtension_FullRangeVideo as String
    #expect(
        bridgeExtensions[rangeKey] as? Bool == declaresFullRange,
        Comment(rawValue: "\(relativePath) bridge \(rangeKey)")
    )
    #expect(
        sourceExtensions[rangeKey] as? Bool == declaresFullRange,
        Comment(rawValue: "\(relativePath) source \(rangeKey)")
    )
}

@Test(arguments: [
    (
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4",
        true,
        false,
        kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
    ),
    (
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
        false,
        true,
        kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
    ),
    (
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
        false,
        true,
        kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
    ),
])
func dolbyVisionFixturesPreserveConfigurationAtomsAndCompressedSamples(
    relativePath: String,
    expectsDvcC: Bool,
    expectsDvvC: Bool,
    expectedBaseLayerTransferFunction: String?
) throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(relativePath)
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(
        reader,
        Comment(rawValue: "\(relativePath): \(cString(error))")
    )
    defer { PBFFmpegReaderDestroy(activeReader) }

    #expect(PBFFmpegReaderFormatHasHvcC(activeReader))
    #expect(PBFFmpegReaderFormatHasDvcC(activeReader) == expectsDvcC)
    #expect(PBFFmpegReaderFormatHasDvvC(activeReader) == expectsDvvC)

    for _ in 0..<12 {
        var sample: Unmanaged<CMSampleBuffer>?
        let result = PBFFmpegReaderCopyNextSample(
            activeReader,
            &sample,
            &error,
            error.count
        )
        #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
        let buffer = try #require(sample?.takeRetainedValue())
        let format = try #require(CMSampleBufferGetFormatDescription(buffer))
        let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any]
        #expect(CMSampleBufferDataIsReady(buffer))
        #expect(CMBlockBufferGetDataLength(try #require(CMSampleBufferGetDataBuffer(buffer))) > 0)
        #expect(
            extensions?[kCMFormatDescriptionExtension_TransferFunction as String] as? String
                == expectedBaseLayerTransferFunction
        )
    }
}

@Test(arguments: [
    "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4",
    "Samples/DynamicRange/DolbyVision/UHD/Patterns_Of_Nature_DoVi_24_P5_UHD_HEVC-10mbps_DD+JOC-768kbps_iOS.mp4",
    "Samples/DynamicRange/DolbyVision/Dolby Vision Profile 5_8.1 Test/CM4_L3L8_Test_with_CM29_fallback_IPT_P5.mp4",
])
func profile5BridgeMatchesAVFoundationDolbyVisionDecoderConfiguration(
    relativePath: String
) async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(relativePath)
    let sourceFormat = try await firstVideoFormatDescription(in: AVURLAsset(url: fixture))
    let sourceAtoms = try sampleDescriptionAtoms(in: sourceFormat)
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(
        reader,
        Comment(rawValue: "\(relativePath): \(cString(error))")
    )
    defer { PBFFmpegReaderDestroy(activeReader) }
    var sampleReference: Unmanaged<CMSampleBuffer>?
    #expect(
        PBFFmpegReaderCopyNextSample(
            activeReader,
            &sampleReference,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: "\(relativePath): \(cString(error))")
    )
    let sample = try #require(sampleReference?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(sample))
    let atoms = try sampleDescriptionAtoms(in: format)
    let sourceExtensions = try #require(
        CMFormatDescriptionGetExtensions(sourceFormat) as? [String: Any]
    )
    let bridgeExtensions = try #require(
        CMFormatDescriptionGetExtensions(format) as? [String: Any]
    )

    #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_DolbyVisionHEVC)
    #expect(atoms["dvcC"]?.isEmpty == false)
    #expect(atoms["hvcC"] == sourceAtoms["hvcC"])
    #expect(atoms["dvcC"] == sourceAtoms["dvcC"])
    #expect(
        bridgeExtensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
            == kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String
    )
    #expect(
        bridgeExtensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
            == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
    )
    #expect(bridgeExtensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] == nil)
    #expect(
        bridgeExtensions[kCMFormatDescriptionExtension_FullRangeVideo as String] as? Bool
            == true
    )
    #expect(
        sourceExtensions[kCMFormatDescriptionExtension_VerbatimISOSampleEntry as String]
            != nil
    )
    #expect(
        bridgeExtensions[kCMFormatDescriptionExtension_VerbatimISOSampleEntry as String]
            != nil
    )
    #expect(
        bridgeExtensions[kCMFormatDescriptionExtension_VerbatimSampleDescription as String]
            == nil
    )
    #expect(CMSampleBufferDataIsReady(sample))
}

@Test(arguments: [
    (
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
        kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
    ),
    (
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
        kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
    ),
])
func compatibleDolbyVisionFallbackRemovesOnlyDolbyVisionInterpretation(
    relativePath: String,
    expectedTransfer: String
) throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(relativePath)
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString {
        PBFFmpegReaderCreate($0, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegReaderDestroy(activeReader) }
    var sampleReference: Unmanaged<CMSampleBuffer>?
    #expect(
        PBFFmpegReaderCopyNextSample(
            activeReader,
            &sampleReference,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let sourceSample = try #require(sampleReference?.takeRetainedValue())
    let sourceFormat = try #require(CMSampleBufferGetFormatDescription(sourceSample))
    let sourceAtoms = try sampleDescriptionAtoms(in: sourceFormat)
    let rewritten = try VideoSampleFormatOverride().rewrite(
        sourceSample,
        stereoLayout: nil,
        projection: nil,
        dynamicRange: .dolbyVisionFallback
    )
    let rewrittenFormat = try #require(CMSampleBufferGetFormatDescription(rewritten))
    let rewrittenExtensions = try #require(
        CMFormatDescriptionGetExtensions(rewrittenFormat) as? [String: Any]
    )
    let rewrittenAtoms = try sampleDescriptionAtoms(in: rewrittenFormat)

    #expect(sourceAtoms["dvvC"]?.isEmpty == false)
    #expect(try sampleDescriptionAtoms(in: sourceFormat)["dvvC"] == sourceAtoms["dvvC"])
    #expect(rewrittenAtoms["dvcC"] == nil)
    #expect(rewrittenAtoms["dvvC"] == nil)
    #expect(rewrittenAtoms["hvcC"] == sourceAtoms["hvcC"])
    #expect(CMFormatDescriptionGetMediaSubType(rewrittenFormat) == kCMVideoCodecType_HEVC)
    #expect(
        rewrittenExtensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
            == kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String
    )
    #expect(
        rewrittenExtensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
            == expectedTransfer
    )
    #expect(
        rewrittenExtensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
            == kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String
    )
    #expect(
        rewrittenExtensions[kCMFormatDescriptionExtension_FullRangeVideo as String] as? Bool
            == false
    )
}

@Test func profileFiveRejectsAUserSelectableHDRFallback() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString {
        PBFFmpegReaderCreate($0, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegReaderDestroy(activeReader) }
    var sampleReference: Unmanaged<CMSampleBuffer>?
    #expect(
        PBFFmpegReaderCopyNextSample(
            activeReader,
            &sampleReference,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let sample = try #require(sampleReference?.takeRetainedValue())

    #expect(
        throws: VideoSampleFormatOverrideError
            .dolbyVisionFallbackUnavailable(compatibilityID: 0)
    ) {
        try VideoSampleFormatOverride().rewrite(
            sample,
            stereoLayout: nil,
            projection: nil,
            dynamicRange: .dolbyVisionFallback
        )
    }
}

@Test func profile10Dav1FixtureCreatesCompressedAV1SamplesWithDolbyVisionConfiguration() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/DynamicRange/DolbyVision/Profile10/OfficialDolby/P10.0/media-video-dav1-dav1-1.mp4"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegReaderDestroy(activeReader) }

    #expect(String(cString: PBFFmpegReaderGetCodecName(activeReader)) == "av1")
    #expect(String(cString: PBFFmpegReaderGetCodecTag(activeReader)) == "dav1")
    #expect(PBFFmpegReaderFormatHasDvvC(activeReader))

    var previousPresentationTime: CMTime?
    for _ in 0..<12 {
        var sample: Unmanaged<CMSampleBuffer>?
        let result = PBFFmpegReaderCopyNextSample(
            activeReader,
            &sample,
            &error,
            error.count
        )
        #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
        let buffer = try #require(sample?.takeRetainedValue())
        let format = try #require(CMSampleBufferGetFormatDescription(buffer))
        let atoms = CMFormatDescriptionGetExtension(
            format,
            extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms
        ) as? [String: Data]
        let doviConfiguration = try #require(atoms?["dvvC"])
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(buffer)

        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_AV1)
        #expect(atoms?["av1C"]?.isEmpty == false)
        #expect(doviConfiguration.count >= 5)
        #expect(doviConfiguration[2] >> 1 == 10)
        #expect(doviConfiguration[4] >> 4 == 0)
        #expect(CMSampleBufferDataIsReady(buffer))
        #expect(CMBlockBufferGetDataLength(try #require(CMSampleBufferGetDataBuffer(buffer))) > 0)
        #expect(presentationTime.isNumeric)
        if let previousPresentationTime {
            #expect(CMTimeCompare(presentationTime, previousPresentationTime) > 0)
        }
        previousPresentationTime = presentationTime
    }
}

@Test func profile10Dav1ProviderKeepsAV1SampleSubtypeCompatible() async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/DynamicRange/DolbyVision/Profile10/OfficialDolby/P10.0/media-video-dav1-dav1-1.mp4"
    )
    let provider = FFmpegSampleProvider()
    defer { provider.cancel() }

    try await provider.prepare(url: fixture, asset: nil, startTime: .zero)
    for _ in 0..<12 {
        let event = try await provider.nextEvent()
        guard case .sample(let sample) = event else {
            Issue.record("Expected a compressed Profile 10 AV1 sample.")
            return
        }
        let format = try #require(CMSampleBufferGetFormatDescription(sample))
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_AV1)
        #expect(CMSampleBufferDataIsReady(sample))
    }
}

@Test func profile10PointOnePreservesStaticHDRMetadataInItsFormatDescription() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/DynamicRange/DolbyVision/Profile10/OfficialDolby/P10.1/media-video-av01-dav1-db1p-1.mp4"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    #expect(
        PBFFmpegReaderCopyNextSample(
            activeReader,
            &sample,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let extensions = try #require(
        CMFormatDescriptionGetExtensions(format) as? [String: Any]
    )

    let masteringDisplay = try #require(
        extensions[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String]
            as? Data
    )
    let contentLightLevel = try #require(
        extensions[kCMFormatDescriptionExtension_ContentLightLevelInfo as String]
            as? Data
    )
    #expect(
        masteringDisplay == Data([
            0x21, 0x33, 0x9b, 0xa9,
            0x19, 0x95, 0x08, 0xfc,
            0x8a, 0x47, 0x39, 0x08,
            0x3d, 0x12, 0x40, 0x41,
            0x01, 0x31, 0x2d, 0x00,
            0x00, 0x00, 0x00, 0x01,
        ])
    )
    #expect(contentLightLevel == Data([0x06, 0x10, 0x02, 0x86]))
}

@Test(arguments: [
    ("Sequence_1-Apple_ProRes_422_Proxy.mov", kCMVideoCodecType_AppleProRes422Proxy),
    ("Sequence_1-Apple_ProRes_422_LT.mov", kCMVideoCodecType_AppleProRes422LT),
    ("Sequence_1-Apple_ProRes_422.mov", kCMVideoCodecType_AppleProRes422),
    ("Sequence_1-Apple_ProRes_422_HQ.mov", kCMVideoCodecType_AppleProRes422HQ),
    ("Sequence_1-Apple_ProRes_with_Alpha.mov", kCMVideoCodecType_AppleProRes4444),
    ("prores4444_with_transparency.mov", kCMVideoCodecType_AppleProRes4444),
])
func proRes422And4444FixturesCreateCompressedSamples(
    fileName: String,
    expectedMediaSubtype: CMVideoCodecType
) throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia
        .appendingPathComponent("TestVectors/Upstream/FATE/ProRes")
        .appendingPathComponent(fileName)
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(
        reader,
        Comment(rawValue: "\(fileName): \(cString(error))")
    )
    defer { PBFFmpegReaderDestroy(activeReader) }

    #expect(String(cString: PBFFmpegReaderGetCodecName(activeReader)) == "prores")
    var sample: Unmanaged<CMSampleBuffer>?
    let result = PBFFmpegReaderCopyNextSample(
        activeReader,
        &sample,
        &error,
        error.count
    )
    #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))

    #expect(CMFormatDescriptionGetMediaSubType(format) == expectedMediaSubtype)
    #expect(CMSampleBufferDataIsReady(buffer))
    #expect(CMBlockBufferGetDataLength(try #require(CMSampleBufferGetDataBuffer(buffer))) > 0)
}

@Test(arguments: [
    (
        "Samples/Professional/ProRes/ARRI-AMIRA/B001C001_140702_R3VJ.mov",
        kCMVideoCodecType_AppleProRes422
    ),
    (
        "Samples/Professional/ProRes/ARRI-ALEXA-Mini/M001C001_161207_R00H.mov",
        kCMVideoCodecType_AppleProRes4444XQ
    ),
])
func officialProResCameraOriginalsDoNotRequireCodecExtradata(
    relativePath: String,
    expectedMediaSubtype: CMVideoCodecType
) throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(relativePath)
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(
        reader,
        Comment(rawValue: "\(relativePath): \(cString(error))")
    )
    defer { PBFFmpegReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    #expect(
        PBFFmpegReaderCopyNextSample(
            activeReader,
            &sample,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    #expect(CMFormatDescriptionGetMediaSubType(format) == expectedMediaSubtype)
    #expect(CMSampleBufferDataIsReady(buffer))
}

@Test func appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC() throws {
    silenceFFmpegDiagnostics()
    let fixtures = [
        (
            "Samples/Spatial/MVHEVC-Apple-Official/spatial_lighthouse_flowers_waves_short.mov",
            true
        ),
        (
            "Samples/Spatial/Apple-Immersive/Apple-Streaming-Examples/Immersive-Video-example.f99766.mp4",
            true
        ),
        (
            "Samples/DynamicRange/HDR10/HDR10.MP4",
            false
        ),
    ]

    for (relativePath, expectedMVHEVC) in fixtures {
        let fixture = playbackTestMedia.appendingPathComponent(relativePath)
        var error = [CChar](repeating: 0, count: 512)
        let reader = fixture.path.withCString { path in
            PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
        }
        let activeReader = try #require(
            reader,
            Comment(rawValue: "\(relativePath): \(cString(error))")
        )
        defer { PBFFmpegReaderDestroy(activeReader) }

        #expect(PBFFmpegReaderIsMVHEVC(activeReader) == expectedMVHEVC)
    }
}

@Test func mediaSourceInformationCarriesContainerDolbyAndStereoFacts() async throws {
    let loader = SystemMediaSourceInformationLoader()
    let profile7 = try await loader.load(
        from: playbackTestMedia.appendingPathComponent(
            "Samples/DynamicRange/DolbyVision/Profile7.6/FEL_test_for_AVS.mkv"
        )
    )
    #expect(profile7.containerSupportsSourceFormatDescription == false)
    #expect(profile7.dolbyVisionProfile == 7)
    #expect(profile7.dolbyVisionHasEnhancementLayer)

    let mvhevc = try await loader.load(
        from: playbackTestMedia.appendingPathComponent(
            "Samples/CameraOriginals/Apple/applle.MOV"
        )
    )
    #expect(mvhevc.containerSupportsSourceFormatDescription)
    #expect(mvhevc.hasStereoVideoEnhancementLayer)
}

@Test func appleImmersiveProviderPreservesExactPayloadAndMultiviewMetadata() async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/Spatial/Apple-Immersive/Apple-Streaming-Examples/Immersive-Video-example.f99766.mp4"
    )
    let provider = FFmpegSampleProvider()
    defer { provider.cancel() }

    try await provider.prepare(url: fixture, asset: nil, startTime: .zero)
    let event = try await provider.nextEvent()
    guard case .sample(let sample) = event else {
        Issue.record("Expected the first provider event to be a compressed video sample.")
        return
    }

    let format = try #require(CMSampleBufferGetFormatDescription(sample))
    let extensions = try #require(
        CMFormatDescriptionGetExtensions(format) as? [String: Any]
    )
    let atoms = try #require(
        extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String]
            as? [String: Data]
    )
    let sourceFormat = try await firstVideoFormatDescription(in: AVURLAsset(url: fixture))
    let sourceAtoms = try sampleDescriptionAtoms(in: sourceFormat)
    let assetReaderSample = try await firstCompressedVideoSample(
        in: AVURLAsset(url: fixture)
    )

    #expect(atoms["hvcC"] == sourceAtoms["hvcC"])
    #expect(atoms["lhvC"] == sourceAtoms["lhvC"])
    #expect(atoms["lhvC"]?.isEmpty == false)
    #expect(
        extensions[kCMFormatDescriptionExtension_ProjectionKind as String] as? String
            == "AppleImmersiveVideo"
    )
    #expect(
        extensions[kCMFormatDescriptionExtension_HasLeftStereoEyeView as String] as? Bool
            == true
    )
    #expect(
        extensions[kCMFormatDescriptionExtension_HasRightStereoEyeView as String] as? Bool
            == true
    )
    #expect(try compressedPayload(in: sample) == compressedPayload(in: assetReaderSample))
    #expect(try compressedPayload(in: sample).count == 1_361_070)
    #expect(provider.info.isMVHEVC)
    #expect(provider.info.codecConfigurationSummary.value == "hvcC,lhvC")
    #expect(provider.info.formatSignaling.provenance == "AVAssetTrack.sourceFormatDescription")
    #expect(provider.info.formatSignaling.projectionKind.value == "AppleImmersiveVideo")
    #expect(provider.info.formatSignaling.hasLeftStereoEyeView.value == true)
    #expect(provider.info.formatSignaling.hasRightStereoEyeView.value == true)
    #expect(provider.info.formatSignaling.lhvC.value == true)
}

@Test func appleImmersiveProviderRejectsBaseEyeDelivery() async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/Spatial/Apple-Immersive/Apple-Streaming-Examples/Immersive-Video-example.f99766.mp4"
    )
    let sourceFormat = try await firstVideoFormatDescription(in: AVURLAsset(url: fixture))
    let baseEyeFormat = try videoFormatDescription(
        byRemovingSampleDescriptionAtom: "lhvC",
        from: sourceFormat
    )
    let baseEyeSample = try compressedVideoSample(formatDescription: baseEyeFormat)
    let dimensions = CMVideoFormatDescriptionGetDimensions(baseEyeFormat)
    let operations = FixedFormatVideoReaderOperations(
        formatDescription: baseEyeFormat,
        sample: baseEyeSample,
        info: VideoSampleProviderInfo(
            providerKind: "FixedBaseEyeVideoTest",
            containerFormat: "mov,mp4,m4a,3gp,3g2,mj2",
            codecName: "hevc",
            codecTag: "hvc1",
            isMVHEVC: false,
            dimensions: "\(dimensions.width)x\(dimensions.height)",
            codecConfigurationSummary: .init(known: "hvcC"),
            formatSignaling: VideoFormatSignalingSummary(
                provenance: "FFmpeg.codecParameters",
                hvcC: .init(known: true),
                lhvC: .init(.none)
            )
        )
    )
    let provider = FFmpegSampleProvider(operations: operations)
    defer { provider.cancel() }
    let sourceInformation = MediaSourceInformation(
        containerFormat: "mov,mp4,m4a,3gp,3g2,mj2",
        durationSeconds: 29.355_733,
        streams: [],
        containerSupportsSourceFormatDescription: true
    )

    do {
        try await provider.prepare(
            url: fixture,
            asset: nil,
            sourceInformation: sourceInformation,
            startTime: .zero
        )
        Issue.record("Apple Immersive Video must not deliver a flat base-eye sample.")
    } catch let error as PlaybackProviderError {
        guard case .appleImmersivePayloadMismatch = error else {
            Issue.record("Expected an Apple Immersive payload mismatch, got \(error).")
            return
        }
    }
}

@Test func officialAppleProjectedMediaKeepsItsSourceProjectionKind() async throws {
    silenceFFmpegDiagnostics()
    let fixtures = [
        (
            "Samples/Spatial/Panorama/Apple-Streaming-Examples/APMP-wide-FOV-example.mp4",
            "ParametricImmersive"
        ),
        (
            "Samples/Spatial/Stereo180/Apple-Streaming-Examples/APMP-180-example.mp4",
            "HalfEquirectangular"
        ),
        (
            "Samples/Spatial/Panorama/Apple-Streaming-Examples/APMP-360-example.mp4",
            "Equirectangular"
        ),
    ]

    for (relativePath, expectedProjectionKind) in fixtures {
        let provider = FFmpegSampleProvider()
        defer { provider.cancel() }
        let fixture = playbackTestMedia.appendingPathComponent(relativePath)
        try await provider.prepare(url: fixture, asset: nil, startTime: .zero)
        let event = try await provider.nextEvent()
        guard case .sample(let sample) = event else {
            Issue.record("Expected a compressed sample for \(relativePath).")
            continue
        }
        let format = try #require(CMSampleBufferGetFormatDescription(sample))
        let extensions = try #require(
            CMFormatDescriptionGetExtensions(format) as? [String: Any]
        )
        #expect(
            extensions[kCMFormatDescriptionExtension_ProjectionKind as String] as? String
                == expectedProjectionKind
        )
    }
}

@Test func apmpWideProviderPreservesUniqueSourcePayloadAndLensMetadata() async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/Spatial/Panorama/Apple-Streaming-Examples/APMP-wide-FOV-example.mp4"
    )
    let sourceFormat = try await firstVideoFormatDescription(in: AVURLAsset(url: fixture))
    let sourceAtoms = try sampleDescriptionAtoms(in: sourceFormat)
    let provider = FFmpegSampleProvider()
    defer { provider.cancel() }

    try await provider.prepare(url: fixture, asset: nil, startTime: .zero)
    let event = try await provider.nextEvent()
    guard case .sample(let sample) = event else {
        Issue.record("Expected a compressed APMP Wide video sample.")
        return
    }
    let format = try #require(CMSampleBufferGetFormatDescription(sample))
    let extensions = try #require(
        CMFormatDescriptionGetExtensions(format) as? [String: Any]
    )
    let outputAtoms = try sampleDescriptionAtoms(in: format)

    #expect(outputAtoms["hvcC"] == sourceAtoms["hvcC"])
    #expect(
        extensions[kCMFormatDescriptionExtension_ProjectionKind as String] as? String
            == "ParametricImmersive"
    )
    #expect(extensions["CameraCalibrationDataLensCollection"] != nil)
    #expect(
        extensions[kCMFormatDescriptionExtension_AmbientViewingEnvironment as String] != nil
    )
    #expect(provider.info.formatSignaling.provenance == "AVAssetTrack.sourceFormatDescription")
}

@Test func mvhevcProviderPreservesUniqueSourceOnlyLhvCPayloadAndStereoMetadata() async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/Spatial/MVHEVC-Apple-Official/spatial_lighthouse_flowers_waves_short.mov"
    )
    let sourceFormat = try await firstVideoFormatDescription(in: AVURLAsset(url: fixture))
    let sourceAtoms = try sampleDescriptionAtoms(in: sourceFormat)
    let provider = FFmpegSampleProvider()
    defer { provider.cancel() }

    try await provider.prepare(url: fixture, asset: nil, startTime: .zero)
    let event = try await provider.nextEvent()
    guard case .sample(let sample) = event else {
        Issue.record("Expected a compressed MV-HEVC video sample.")
        return
    }
    let format = try #require(CMSampleBufferGetFormatDescription(sample))
    let extensions = try #require(
        CMFormatDescriptionGetExtensions(format) as? [String: Any]
    )
    let outputAtoms = try sampleDescriptionAtoms(in: format)

    #expect(provider.info.isMVHEVC)
    #expect(outputAtoms["hvcC"] == sourceAtoms["hvcC"])
    #expect(outputAtoms["lhvC"] == sourceAtoms["lhvC"])
    #expect(outputAtoms["lhvC"]?.isEmpty == false)
    #expect(
        extensions[kCMFormatDescriptionExtension_ProjectionKind as String] as? String
            == kCMFormatDescriptionProjectionKind_Rectilinear as String
    )
    #expect(
        extensions[kCMFormatDescriptionExtension_HorizontalFieldOfView as String] as? Int
            == 46_900
    )
    #expect(
        extensions[kCMFormatDescriptionExtension_HasLeftStereoEyeView as String] as? Bool
            == true
    )
    #expect(
        extensions[kCMFormatDescriptionExtension_HasRightStereoEyeView as String] as? Bool
            == true
    )
    #expect(provider.info.formatSignaling.provenance == "AVAssetTrack.sourceFormatDescription")
}

@Test func cameraOriginalMVHEVCPreservesItsCompleteSourceDecoderConfiguration() async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/CameraOriginals/Apple/applle.MOV"
    )
    let sourceFormat = try await firstVideoFormatDescription(in: AVURLAsset(url: fixture))
    let sourceAtoms = try sampleDescriptionAtoms(in: sourceFormat)
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegReaderDestroy(activeReader) }
    var bridgeSample: Unmanaged<CMSampleBuffer>?
    #expect(
        PBFFmpegReaderCopyNextSample(
            activeReader,
            &bridgeSample,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let bridgeBuffer = try #require(bridgeSample?.takeRetainedValue())
    let bridgeFormat = try #require(CMSampleBufferGetFormatDescription(bridgeBuffer))
    let bridgeAtoms = try sampleDescriptionAtoms(in: bridgeFormat)
    #expect(sourceAtoms["hvcC"] != bridgeAtoms["hvcC"])
    #expect(sourceAtoms["lhvC"]?.isEmpty == false)
    #expect(bridgeAtoms["lhvC"] == nil)

    let provider = FFmpegSampleProvider()
    defer { provider.cancel() }
    try await provider.prepare(url: fixture, asset: nil, startTime: .zero)
    let event = try await provider.nextEvent()
    guard case .sample(let sample) = event else {
        Issue.record("Expected a compressed MV-HEVC camera-original sample.")
        return
    }
    let outputFormat = try #require(CMSampleBufferGetFormatDescription(sample))
    let outputAtoms = try sampleDescriptionAtoms(in: outputFormat)

    #expect(outputAtoms["hvcC"] == sourceAtoms["hvcC"])
    #expect(outputAtoms["lhvC"] == sourceAtoms["lhvC"])
    #expect(provider.info.codecConfigurationSummary.value == "hvcC,lhvC")
    #expect(provider.info.isMVHEVC)
    #expect(provider.info.formatSignaling.provenance == "AVAssetTrack.sourceFormatDescription")
}

@Test func mvhevcClassificationFallsBackToMonoWhenDeliveredDescriptionHasNoLhvC() async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/CameraOriginals/Apple/applle.MOV"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegReaderDestroy(activeReader) }
    var bridgeSampleReference: Unmanaged<CMSampleBuffer>?
    #expect(
        PBFFmpegReaderCopyNextSample(
            activeReader,
            &bridgeSampleReference,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let bridgeSample = try #require(bridgeSampleReference?.takeRetainedValue())
    let bridgeFormat = try #require(CMSampleBufferGetFormatDescription(bridgeSample))
    #expect(try sampleDescriptionAtoms(in: bridgeFormat)["lhvC"] == nil)
    let dimensions = CMVideoFormatDescriptionGetDimensions(bridgeFormat)
    let operations = FixedFormatVideoReaderOperations(
        formatDescription: bridgeFormat,
        sample: bridgeSample,
        info: VideoSampleProviderInfo(
            providerKind: "FixedFormatVideoTest",
            containerFormat: "mov,mp4,m4a,3gp,3g2,mj2",
            codecName: "hevc",
            codecTag: "hvc1",
            isMVHEVC: true,
            dimensions: "\(dimensions.width)x\(dimensions.height)",
            codecConfigurationSummary: .init(known: "hvcC"),
            formatSignaling: VideoFormatSignalingSummary(
                provenance: "FFmpeg.codecParameters",
                hvcC: .init(known: true)
            )
        )
    )
    let provider = FFmpegSampleProvider(operations: operations)
    defer { provider.cancel() }

    try await provider.prepare(
        url: fixture,
        asset: PlaybackAsset(AVMutableComposition()),
        startTime: .zero
    )
    let event = try await provider.nextEvent()
    guard case .sample(let outputSample) = event else {
        Issue.record("Expected the bridge sample with its hvcC-only description.")
        return
    }
    let outputFormat = try #require(CMSampleBufferGetFormatDescription(outputSample))

    #expect(try sampleDescriptionAtoms(in: outputFormat)["lhvC"] == nil)
    #expect(provider.info.isMVHEVC == false)
    #expect(provider.info.formatSignaling.provenance == "FFmpeg.codecParameters")
}

@Test func suppliedAssetWithDifferentDecoderConfigurationKeepsBridgeFormat() async throws {
    silenceFFmpegDiagnostics()
    let pqFixture = playbackTestMedia.appendingPathComponent(
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
    )
    let hlgFixture = playbackTestMedia.appendingPathComponent(
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
    )
    let pqSourceFormat = try await firstVideoFormatDescription(in: AVURLAsset(url: pqFixture))
    let hlgSourceFormat = try await firstVideoFormatDescription(in: AVURLAsset(url: hlgFixture))
    let pqAtoms = try sampleDescriptionAtoms(in: pqSourceFormat)
    let hlgAtoms = try sampleDescriptionAtoms(in: hlgSourceFormat)
    #expect(pqAtoms["dvvC"] != hlgAtoms["dvvC"])

    let provider = FFmpegSampleProvider()
    defer { provider.cancel() }
    try await provider.prepare(
        url: pqFixture,
        asset: PlaybackAsset(AVURLAsset(url: hlgFixture)),
        startTime: .zero
    )
    let event = try await provider.nextEvent()
    guard case .sample(let sample) = event else {
        Issue.record("Expected a compressed PQ video sample.")
        return
    }
    let format = try #require(CMSampleBufferGetFormatDescription(sample))
    let extensions = try #require(
        CMFormatDescriptionGetExtensions(format) as? [String: Any]
    )
    let outputAtoms = try sampleDescriptionAtoms(in: format)

    #expect(
        extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
            == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
    )
    #expect(outputAtoms["hvcC"] == pqAtoms["hvcC"])
    #expect(outputAtoms["dvvC"] == pqAtoms["dvvC"])
    #expect(provider.info.formatSignaling.provenance == "FFmpeg.codecParameters")
}

@Test func sourceOnlyDolbyConfigurationDoesNotReplaceBridgeFormat() async throws {
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
    )
    let asset = AVURLAsset(url: fixture)
    let sourceFormat = try await firstVideoFormatDescription(in: asset)
    let sourceAtoms = try sampleDescriptionAtoms(in: sourceFormat)
    let bridgeFormat = try videoFormatDescription(
        byRemovingSampleDescriptionAtom: "dvvC",
        from: sourceFormat
    )
    let bridgeAtoms = try sampleDescriptionAtoms(in: bridgeFormat)
    let bridgeSample = try compressedVideoSample(formatDescription: bridgeFormat)
    let dimensions = CMVideoFormatDescriptionGetDimensions(bridgeFormat)
    let operations = FixedFormatVideoReaderOperations(
        formatDescription: bridgeFormat,
        sample: bridgeSample,
        info: VideoSampleProviderInfo(
            providerKind: "FixedFormatVideoTest",
            containerFormat: "mov,mp4,m4a,3gp,3g2,mj2",
            codecName: "hevc",
            codecTag: "hvc1",
            dimensions: "\(dimensions.width)x\(dimensions.height)",
            formatSignaling: VideoFormatSignalingSummary(
                provenance: "FFmpeg.codecParameters",
                hvcC: .init(known: true),
                dvvC: .init(.none)
            )
        )
    )
    #expect(sourceAtoms["dvvC"]?.isEmpty == false)
    #expect(bridgeAtoms["hvcC"] == sourceAtoms["hvcC"])
    #expect(bridgeAtoms["dvvC"] == nil)

    let provider = FFmpegSampleProvider(operations: operations)
    defer { provider.cancel() }
    try await provider.prepare(
        url: fixture,
        asset: PlaybackAsset(asset),
        startTime: .zero
    )
    let event = try await provider.nextEvent()
    guard case .sample(let sample) = event else {
        Issue.record("Expected the fixed compressed HEVC sample.")
        return
    }
    let outputFormat = try #require(CMSampleBufferGetFormatDescription(sample))
    let outputAtoms = try sampleDescriptionAtoms(in: outputFormat)

    #expect(outputAtoms["hvcC"] == bridgeAtoms["hvcC"])
    #expect(outputAtoms["dvvC"] == nil)
    #expect(provider.info.formatSignaling.provenance == "FFmpeg.codecParameters")
}

@Test func formatDescriptionOwnerFillsOnlyMissingDecoderConfigurationAtoms() async throws {
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
    )
    let bridgeFormat = try await firstVideoFormatDescription(in: AVURLAsset(url: fixture))
    let sourceFormat = try videoFormatDescription(
        byRemovingSampleDescriptionAtom: "dvvC",
        from: bridgeFormat
    )
    let sourceAtoms = try sampleDescriptionAtoms(in: sourceFormat)
    let bridgeAtoms = try sampleDescriptionAtoms(in: bridgeFormat)
    var mergedReference: Unmanaged<CMVideoFormatDescription>?

    let status = PBFFmpegVideoFormatDescriptionCreate(
        nil,
        sourceFormat,
        bridgeFormat,
        nil,
        &mergedReference
    )
    #expect(status == noErr)
    let merged = try #require(mergedReference?.takeRetainedValue())
    let mergedAtoms = try sampleDescriptionAtoms(in: merged)

    #expect(mergedAtoms["hvcC"] == sourceAtoms["hvcC"])
    #expect(mergedAtoms["dvvC"] == bridgeAtoms["dvvC"])
}

@Test func suppliedAssetWithMultipleMatchingVideoFormatsKeepsBridgeFormat() async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-avsync-30s.mp4"
    )
    let sourceAsset = AVURLAsset(url: fixture)
    let sourceTrack = try #require(
        try await sourceAsset.loadTracks(withMediaType: .video).first
    )
    let duration = try await sourceAsset.load(.duration)
    let composition = AVMutableComposition()
    for _ in 0..<2 {
        let track = try #require(
            composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        )
        try track.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceTrack,
            at: .zero
        )
    }
    var candidateFormats: [CMFormatDescription] = []
    for track in try await composition.loadTracks(withMediaType: .video) {
        candidateFormats.append(contentsOf: try await track.load(.formatDescriptions))
    }
    #expect(candidateFormats.count == 2)
    let sourceFormat = try await firstVideoFormatDescription(in: sourceAsset)
    let sourceAtoms = try sampleDescriptionAtoms(in: sourceFormat)
    for candidate in candidateFormats {
        #expect(
            CMFormatDescriptionGetMediaSubType(candidate)
                == CMFormatDescriptionGetMediaSubType(sourceFormat)
        )
        #expect(try sampleDescriptionAtoms(in: candidate)["avcC"] == sourceAtoms["avcC"])
    }

    let provider = FFmpegSampleProvider()
    defer { provider.cancel() }
    try await provider.prepare(
        url: fixture,
        asset: PlaybackAsset(composition),
        startTime: .zero
    )
    let event = try await provider.nextEvent()
    guard case .sample = event else {
        Issue.record("Expected a compressed H.264 video sample.")
        return
    }
    #expect(provider.info.formatSignaling.provenance == "FFmpeg.codecParameters")
}

@Test func profile20KeepsDolbyVisionAndMultiviewHEVCSignalsTogether() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/DynamicRange/DolbyVision/Profile20/Apple-Historic-Planet-HLS/DoVi_P20_09180_t1080p/prog_index.m3u8"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegReaderDestroy(activeReader) }

    #expect(PBFFmpegReaderFormatHasHvcC(activeReader))
    #expect(PBFFmpegReaderFormatHasDvcC(activeReader))
    #expect(PBFFmpegReaderIsMVHEVC(activeReader))

    var sample: Unmanaged<CMSampleBuffer>?
    #expect(
        PBFFmpegReaderCopyNextSample(
            activeReader,
            &sample,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let extensions = try #require(
        CMFormatDescriptionGetExtensions(format) as? [String: Any]
    )
    let atoms = try #require(
        extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String]
            as? [String: Data]
    )
    let doviConfiguration = try #require(atoms["dvcC"])

    #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_DolbyVisionHEVC)
    #expect(atoms["hvcC"]?.isEmpty == false)
    #expect(doviConfiguration.count >= 5)
    #expect(doviConfiguration[2] >> 1 == 20)
    #expect(CMSampleBufferDataIsReady(buffer))
}

@Test func dvh1WithoutDolbyVisionConfigurationUsesHEVCAndKeepsMultiviewSignals() async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/DynamicRange/DolbyVision/Profile20/Apple-Streaming-Examples/3D-example.mp4"
    )
    let sourceFormat = try await firstVideoFormatDescription(in: AVURLAsset(url: fixture))
    let sourceAtoms = try sampleDescriptionAtoms(in: sourceFormat)
    let provider = FFmpegSampleProvider()
    defer { provider.cancel() }

    try await provider.prepare(url: fixture, asset: nil, startTime: .zero)
    let event = try await provider.nextEvent()
    guard case .sample(let buffer) = event else {
        Issue.record("Expected a compressed multiview HEVC video sample.")
        return
    }
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let atoms = try sampleDescriptionAtoms(in: format)

    #expect(provider.info.codecTag == "dvh1")
    #expect(provider.info.formatSignaling.dvcC.availability == .none)
    #expect(provider.info.isMVHEVC)
    #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC)
    #expect(atoms["hvcC"] == sourceAtoms["hvcC"])
    #expect(atoms["lhvC"] == sourceAtoms["lhvC"])
    #expect(atoms["lhvC"]?.isEmpty == false)
    #expect(CMSampleBufferDataIsReady(buffer))
}

@Test func missingHEVCExtradataIsBootstrappedFromAnnexBBitstream() throws {
    let fixture = try decodedFixture(resource: "video-hevc-annexb", fileExtension: "h265")
    defer { try? FileManager.default.removeItem(at: fixture) }
    try requireBitstreamExtradataBootstrap(fixture: fixture, expectsHvcC: true)
}

@Test func missingAV1ExtradataIsBootstrappedFromSphericalFixtureBitstream() throws {
    let fixture = playbackTestMedia.appendingPathComponent("Samples/Spatial/Panorama/360.mp4")
    try requireBitstreamExtradataBootstrap(fixture: fixture, expectsHvcC: false)
}

private func requireBitstreamExtradataBootstrap(
    fixture: URL,
    expectsHvcC: Bool
) throws {
    silenceFFmpegDiagnostics()
    var error = [CChar](repeating: 0, count: 512)
    let reader = try #require(PBFFmpegReaderAllocate())
    defer { PBFFmpegReaderDestroy(reader) }
    PBFFmpegReaderForceBitstreamExtradataBootstrap(reader)

    let opened = fixture.path.withCString { path in
        PBFFmpegReaderOpen(
            reader,
            path,
            PBFFmpegModeCompressed,
            0,
            &error,
            error.count
        )
    }
    try #require(opened, Comment(rawValue: "\(fixture.lastPathComponent): \(cString(error))"))
    #expect(PBFFmpegReaderUsedBitstreamExtradataBootstrap(reader))
    if expectsHvcC {
        #expect(PBFFmpegReaderFormatHasHvcC(reader))
    }

    var sample: Unmanaged<CMSampleBuffer>?
    let result = PBFFmpegReaderCopyNextSample(reader, &sample, &error, error.count)
    #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
    let buffer = try #require(sample?.takeRetainedValue())
    #expect(CMSampleBufferGetFormatDescription(buffer) != nil)
    #expect(CMBlockBufferGetDataLength(try #require(CMSampleBufferGetDataBuffer(buffer))) > 0)
}

@Test func embeddedSubRipTracksExposeStableMetadata() throws {
    silenceFFmpegDiagnostics()
    let fixture = try #require(
        Bundle.module.url(
            forResource: "subtitle-subrip",
            withExtension: "mkv",
            subdirectory: "Fixtures"
        )
    )

    let tracks = mediaStreams(in: fixture).filter {
        $0.raw.category == PBFFmpegMediaStreamCategorySubtitle
    }
    #expect(tracks.count == 2)
    #expect(tracks.first?.raw.streamIndex == 1)
    #expect(tracks.first?.codecName == "subrip")
    #expect(tracks.first?.language == "zho")
    #expect(tracks.first?.title == "简体中文")
}

@Test func anInterruptedSourceReadMonitorAbortsSubtitleOpensOnAStalledSource() throws {
    silenceFFmpegDiagnostics()
    let fixture = try #require(
        Bundle.module.url(
            forResource: "subtitle-subrip",
            withExtension: "mkv",
            subdirectory: "Fixtures"
        )
    )
    let payload = try Data(contentsOf: fixture)
    let opens: [(String, @Sendable (UnsafePointer<CChar>, OpaquePointer, inout [CChar]) -> Bool)] = [
        ("subtitle reader", { path, monitor, error in
            let reader = PBFFmpegSubtitleReaderCreateWithSourceReadMonitor(
                path, 1, &error, error.count, monitor, nil
            )
            PBFFmpegSubtitleReaderDestroy(reader)
            return reader != nil
        }),
        ("subtitle document renderer", { path, monitor, error in
            let renderer = PBSubtitleFrameRendererCreate(
                path, 1, monitor, nil, &error, error.count
            )
            PBSubtitleFrameRendererDestroy(renderer)
            return renderer != nil
        }),
    ]
    for (name, open) in opens {
        let server = try RecordingRangeServer(serving: payload)
        defer { server.stop() }
        nonisolated(unsafe) let monitor = try #require(PBFFmpegSourceReadMonitorCreate())
        defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
        server.stallNextRangeResponse()
        let finished = DispatchSemaphore(value: 0)
        let opened = OpenOutcome()
        let url = server.url.absoluteString
        Thread.detachNewThread {
            var error = [CChar](repeating: 0, count: 512)
            let succeeded = url.withCString { open($0, monitor, &error) }
            opened.record(succeeded: succeeded, message: cString(error))
            finished.signal()
        }
        #expect(
            server.waitForStalledResponse(timeout: .now() + .seconds(3)),
            "\(name): the open never reached the stalled range request"
        )
        PBFFmpegSourceReadMonitorInterrupt(monitor)
        let returnedAfterInterrupt = finished.wait(timeout: .now() + .seconds(2)) == .success
        if !returnedAfterInterrupt {
            server.stop()
            finished.wait()
        }
        #expect(
            returnedAfterInterrupt,
            "\(name): the open kept waiting on the stalled source after the interrupt"
        )
        #expect(opened.succeeded == false, "\(name): an interrupted open returned a reader")
        #expect(!opened.message.isEmpty, "\(name): an interrupted open reported no error")
    }
}

private final class OpenOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSuccess = true
    private var recordedMessage = ""

    var succeeded: Bool { lock.withLock { recordedSuccess } }
    var message: String { lock.withLock { recordedMessage } }

    func record(succeeded: Bool, message: String) {
        lock.withLock {
            recordedSuccess = succeeded
            recordedMessage = message
        }
    }
}

@Test func aSubtitleDocumentCutOffMidReadFailsInsteadOfReturningAShorterTrack() throws {
    silenceFFmpegDiagnostics()
    let fixture = try #require(
        Bundle.module.url(
            forResource: "subtitle-subrip",
            withExtension: "mkv",
            subdirectory: "Fixtures"
        )
    )
    let server = try RecordingRangeServer(
        serving: try Data(contentsOf: fixture),
        responseChunkSize: 512
    )
    defer { server.stop() }
    nonisolated(unsafe) let monitor = try #require(PBFFmpegSourceReadMonitorCreate())
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
    server.disconnectOnce(afterSendingAdditionalBytes: 2_048)
    var error = [CChar](repeating: 0, count: 512)
    let renderer = server.url.absoluteString.withCString { path in
        PBSubtitleFrameRendererCreate(path, 1, monitor, nil, &error, error.count)
    }
    defer { PBSubtitleFrameRendererDestroy(renderer) }
    #expect(renderer == nil, "a document whose read failed mid-way produced a renderer")
    #expect(!cString(error).isEmpty)
}

@Test func embeddedSubRipCuesPreserveTimingUTF8AndLineBreaks() throws {
    silenceFFmpegDiagnostics()
    let fixture = try #require(
        Bundle.module.url(
            forResource: "subtitle-subrip",
            withExtension: "mkv",
            subdirectory: "Fixtures"
        )
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegSubtitleReaderCreateWithSourceReadMonitor(
            path, 1, &error, error.count, nil, nil
        )
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegSubtitleReaderDestroy(activeReader) }

    var startSeconds = 0.0
    var durationSeconds = 0.0
    var text: Unmanaged<CFString>?
    let result = PBFFmpegSubtitleReaderCopyNextCue(
        activeReader,
        &startSeconds,
        &durationSeconds,
        &text,
        &error,
        error.count
    )
    #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
    let cueText = try #require(text?.takeRetainedValue()) as String

    #expect(abs(startSeconds - 0.5) < 0.001)
    #expect(abs(durationSeconds - 1.5) < 0.001)
    #expect(cueText == "第一行\n第二行")
}

@Test func delayedAudioParametersAreDiscovered() throws {
    silenceFFmpegDiagnostics()
    let fixture = try delayedAACTransportStream()
    defer { try? FileManager.default.removeItem(at: fixture) }

    let trackCount = mediaStreams(in: fixture).count {
        $0.raw.category == PBFFmpegMediaStreamCategoryAudio
    }

    #expect(trackCount == 1)
}

@Test func declaredAudioWithoutParametersIsNotReportedAsNoAudio() throws {
    silenceFFmpegDiagnostics()
    let fixture = try delayedAACTransportStream(includeAudioPackets: false)
    defer { try? FileManager.default.removeItem(at: fixture) }
    var error = [CChar](repeating: 0, count: 512)

    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }

    #expect(reader == nil)
    let message = String(
        decoding: error.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
    #expect(message == "Audio stream parameters are unavailable after extended probe")
}

@Test func delayedAudioParametersProduceDecodedAACSample() throws {
    silenceFFmpegDiagnostics()
    let fixture = try delayedAACTransportStream()
    defer { try? FileManager.default.removeItem(at: fixture) }
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(reader)
    defer { PBFFmpegAudioReaderDestroy(activeReader) }
    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()

    let result = PBFFmpegAudioReaderCopyNextSample(
        activeReader,
        &sample,
        &metadata,
        &error,
        error.count
    )
    let message = String(
        decoding: error.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
    #expect(result == PBFFmpegReadResultSample, Comment(rawValue: message))
    let buffer = try #require(sample?.takeRetainedValue())

    #expect(PBFFmpegAudioReaderGetSampleRate(activeReader) == 48_000)
    #expect(PBFFmpegAudioReaderGetChannelCount(activeReader) == 1)
    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader))
    #expect(CMSampleBufferGetNumSamples(buffer) > 0)
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let streamDescription = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(format))
    #expect(streamDescription.pointee.mFormatID == kAudioFormatLinearPCM)
    #expect(streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0)
    var magicCookieSize = 0
    let magicCookie = CMAudioFormatDescriptionGetMagicCookie(
        format,
        sizeOut: &magicCookieSize
    )
    #expect(magicCookie == nil)
    #expect(magicCookieSize == 0)
    #expect(metadata.payloadByteCount > 0)
    #expect(metadata.timeBaseNumerator > 0)
    #expect(metadata.timeBaseDenominator > 0)
    #expect(metadata.cookieSource == PBFFmpegAudioCookieSourceUnavailable)
}

@Test(arguments: [
    ("audio-dts-5.1", "mka", "dts", 48_000, 6, kAudioChannelLayoutTag_WAVE_5_1_A),
    (
        "audio-truehd-5.1",
        "mka",
        "truehd",
        48_000,
        6,
        kAudioChannelLayoutTag_WAVE_5_1_A
    ),
    ("audio-vorbis-stereo", "ogg", "vorbis", 44_100, 2, kAudioChannelLayoutTag_Stereo),
])
func ffmpegDecodedAudioProducesInterleavedFloatPCMWithDeclaredLayout(
    resource: String,
    fileExtension: String,
    expectedCodec: String,
    expectedSampleRate: Int,
    expectedChannelCount: Int,
    expectedLayoutTag: AudioChannelLayoutTag
) throws {
    silenceFFmpegDiagnostics()
    let fixture = try #require(
        Bundle.module.url(forResource: resource, withExtension: fileExtension)
            ?? Bundle.module.url(
                forResource: resource,
                withExtension: fileExtension,
                subdirectory: "Fixtures"
            )
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(
        reader,
        Comment(rawValue: "\(resource): \(cString(error))")
    )
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader))
    #expect(String(cString: PBFFmpegAudioReaderGetCodecName(activeReader)) == expectedCodec)
    #expect(PBFFmpegAudioReaderGetSampleRate(activeReader) == expectedSampleRate)
    #expect(PBFFmpegAudioReaderGetChannelCount(activeReader) == expectedChannelCount)

    var previousPresentationTime: CMTime?
    var sampleCount = 0
    while sampleCount < 64 {
        var sample: Unmanaged<CMSampleBuffer>?
        var metadata = PBFFmpegAudioSampleMetadata()
        let result = PBFFmpegAudioReaderCopyNextSample(
            activeReader,
            &sample,
            &metadata,
            &error,
            error.count
        )
        if result == PBFFmpegReadResultEnd { break }
        #expect(
            result == PBFFmpegReadResultSample,
            Comment(rawValue: "\(resource): \(cString(error))")
        )
        let buffer = try #require(sample?.takeRetainedValue())
        let format = try #require(CMSampleBufferGetFormatDescription(buffer))
        let description = try #require(
            CMAudioFormatDescriptionGetStreamBasicDescription(format)
        ).pointee
        var layoutSize = 0
        let layout = try #require(
            CMAudioFormatDescriptionGetChannelLayout(format, sizeOut: &layoutSize)
        )
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(buffer)

        #expect(description.mFormatID == kAudioFormatLinearPCM)
        #expect(description.mFormatFlags & kAudioFormatFlagIsFloat != 0)
        #expect(description.mFormatFlags & kAudioFormatFlagIsPacked != 0)
        #expect(description.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0)
        #expect(description.mSampleRate == Double(expectedSampleRate))
        #expect(description.mChannelsPerFrame == expectedChannelCount)
        #expect(description.mBytesPerFrame == expectedChannelCount * 4)
        #expect(layoutSize >= MemoryLayout<AudioChannelLayout>.size)
        #expect(layout.pointee.mChannelLayoutTag == expectedLayoutTag)
        #expect(CMSampleBufferGetNumSamples(buffer) > 0)
        #expect(CMSampleBufferGetDuration(buffer).isNumeric)
        #expect(presentationTime.isNumeric)
        if let previousPresentationTime {
            #expect(CMTimeCompare(presentationTime, previousPresentationTime) > 0)
        }
        previousPresentationTime = presentationTime
        sampleCount += 1
    }
    #expect(sampleCount > 1)
}

@Test func trueHDSubframesAreAggregatedBeforeTheyReachCoreMedia() throws {
    silenceFFmpegDiagnostics()
    let fixture = try #require(
        Bundle.module.url(forResource: "audio-truehd-5.1", withExtension: "mka")
            ?? Bundle.module.url(
                forResource: "audio-truehd-5.1",
                withExtension: "mka",
                subdirectory: "Fixtures"
            )
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    var frameCounts: [Int] = []
    var observations: [PBFFmpegAudioSampleMetadata] = []
    while true {
        var sample: Unmanaged<CMSampleBuffer>?
        var metadata = PBFFmpegAudioSampleMetadata()
        let result = PBFFmpegAudioReaderCopyNextSample(
            activeReader,
            &sample,
            &metadata,
            &error,
            error.count
        )
        if result == PBFFmpegReadResultEnd { break }
        #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
        let buffer = try #require(sample?.takeRetainedValue())
        frameCounts.append(CMSampleBufferGetNumSamples(buffer))
        observations.append(metadata)
    }

    #expect(frameCounts == [4_800, 4_800, 2_400])
    #expect(frameCounts.reduce(0, +) == 12_000)
    let finalObservation = try #require(observations.last)
    #expect(finalObservation.trueHDDecoderInputPacketCount > 0)
    #expect(finalObservation.trueHDDecoderBatchCount > 0)
    #expect(
        finalObservation.trueHDDecoderInputPacketCount
            > finalObservation.trueHDDecoderBatchCount
    )
    #expect(finalObservation.trueHDAggregatedDecoderBatchCount > 0)
    #expect(finalObservation.trueHDOutputSampleBufferCount == observations.count)
    #expect(finalObservation.trueHDLastDecoderBatchInputPacketCount > 0)
}

@Test func ffmpegUndecodableAudioNamesTheCodecInsteadOfGuessing() throws {
    silenceFFmpegDiagnostics()
    let fixture = FileManager.default.temporaryDirectory
        .appendingPathComponent("playbackcore-unsupported-\(UUID().uuidString).ac4")
    let probeableAC4Frame: [UInt8] = [0xAC, 0x40, 0x00, 0x04, 0, 0, 0, 0]
    try Data((0..<32).flatMap { _ in probeableAC4Frame }).write(
        to: fixture,
        options: .atomic
    )
    defer { try? FileManager.default.removeItem(at: fixture) }
    var error = [CChar](repeating: 0, count: 512)

    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }

    #expect(reader == nil)
    #expect(cString(error) == "Audio codec ac4 is unsupported because FFmpeg has no decoder")
}

@Test func flacPacketsDecodeToInterleavedFloatPCM() throws {
    silenceFFmpegDiagnostics()
    let fixture = try decodedFixture(
        resource: "audio-flac-stereo.mka",
        fileExtension: "mka"
    )
    defer { try? FileManager.default.removeItem(at: fixture) }
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader))
    #expect(PBFFmpegAudioReaderGetSampleRate(activeReader) == 48_000)
    #expect(PBFFmpegAudioReaderGetChannelCount(activeReader) == 2)
    #expect(String(cString: PBFFmpegAudioReaderGetCodecName(activeReader)) == "flac")

    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    let result = PBFFmpegAudioReaderCopyNextSample(
        activeReader,
        &sample,
        &metadata,
        &error,
        error.count
    )
    #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let streamDescription = try #require(
        CMAudioFormatDescriptionGetStreamBasicDescription(format)
    ).pointee

    #expect(streamDescription.mFormatID == kAudioFormatLinearPCM)
    #expect(streamDescription.mFormatFlags & kAudioFormatFlagIsFloat != 0)
    #expect(streamDescription.mSampleRate == 48_000)
    #expect(streamDescription.mChannelsPerFrame == 2)
    #expect(streamDescription.mFramesPerPacket == 1)
    #expect(CMSampleBufferGetNumSamples(buffer) > 1)
    #expect(CMSampleBufferGetDuration(buffer).seconds > 0)
    #expect(metadata.payloadByteCount > 0)
    let dataBuffer = try #require(CMSampleBufferGetDataBuffer(buffer))
    #expect(CMBlockBufferGetDataLength(dataBuffer) == metadata.payloadByteCount)

    var magicCookieSize = 0
    #expect(CMAudioFormatDescriptionGetMagicCookie(format, sizeOut: &magicCookieSize) == nil)
    #expect(magicCookieSize == 0)
}

@Test func proResCameraOriginalNormalizesFiveChannelPCMToFloat() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/Professional/ProRes/ARRI-AMIRA/B001C001_140702_R3VJ.mov"
    )
    #expect(mediaStreams(in: fixture).count {
        $0.raw.category == PBFFmpegMediaStreamCategoryAudio
    } == 1)

    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    #expect(String(cString: PBFFmpegAudioReaderGetCodecName(activeReader)) == "pcm_s24le")
    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader))
    #expect(PBFFmpegAudioReaderGetSampleRate(activeReader) == 48_000)
    #expect(PBFFmpegAudioReaderGetChannelCount(activeReader) == 5)

    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    let result = PBFFmpegAudioReaderCopyNextSample(
        activeReader,
        &sample,
        &metadata,
        &error,
        error.count
    )
    #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let description = try #require(
        CMAudioFormatDescriptionGetStreamBasicDescription(format)
    ).pointee

    #expect(description.mFormatID == kAudioFormatLinearPCM)
    #expect(description.mBitsPerChannel == 32)
    #expect(description.mBytesPerFrame == 20)
    #expect(description.mFormatFlags & kAudioFormatFlagIsFloat != 0)
    #expect(description.mChannelsPerFrame == 5)
    #expect(CMSampleBufferGetNumSamples(buffer) == 1_024)
    #expect(CMSampleBufferGetDuration(buffer) == CMTime(value: 1_024, timescale: 48_000))
    #expect(metadata.payloadByteCount == 20_480)
    #expect(metadata.cookieSource == PBFFmpegAudioCookieSourceUnavailable)
    #expect(CMBlockBufferGetDataLength(try #require(CMSampleBufferGetDataBuffer(buffer))) == 20_480)

    var channelLayoutSize = 0
    let channelLayout = CMAudioFormatDescriptionGetChannelLayout(
        format,
        sizeOut: &channelLayoutSize
    )
    #expect(channelLayout != nil)
    #expect(channelLayoutSize >= MemoryLayout<AudioChannelLayout>.size)
}

@Test func proResTransparencyPCM16LEProducesLinearPCMSamples() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Upstream/FATE/ProRes/prores4444_with_transparency.mov"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    #expect(String(cString: PBFFmpegAudioReaderGetCodecName(activeReader)) == "pcm_s16le")
    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader))

    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    #expect(
        PBFFmpegAudioReaderCopyNextSample(
            activeReader,
            &sample,
            &metadata,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let description = try #require(
        CMAudioFormatDescriptionGetStreamBasicDescription(format)
    ).pointee

    #expect(description.mFormatID == kAudioFormatLinearPCM)
    #expect(description.mBitsPerChannel == 32)
    #expect(description.mBytesPerFrame == description.mChannelsPerFrame * 4)
    #expect(description.mFormatFlags & kAudioFormatFlagIsFloat != 0)
    #expect(description.mFormatFlags & kAudioFormatFlagIsPacked != 0)
    #expect(CMSampleBufferGetNumSamples(buffer) > 0)
    #expect(metadata.payloadByteCount > 0)
}

@Test func damagedTransportStreamAACSkipsInvalidPacketsAndProducesAudio() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/DynamicRange/HLG/LG_Cymatic_Jazz_HLG_Astra_teststream.ts"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    #expect(
        PBFFmpegAudioReaderCopyNextSample(
            activeReader,
            &sample,
            &metadata,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let description = try #require(
        CMAudioFormatDescriptionGetStreamBasicDescription(format)
    ).pointee

    #expect(description.mFormatID == kAudioFormatLinearPCM)
    #expect(CMSampleBufferDataIsReady(buffer))
    #expect(metadata.payloadByteCount > 0)
}

@Test func sourcePCMUsesTheUnifiedFFmpegDecodePath() throws {
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/Professional/ProRes/ARRI-AMIRA/B001C001_140702_R3VJ.mov"
    )
    let operations = SystemFFmpegAudioReaderOperations()
    let reader = try #require(operations.allocate())
    defer { operations.destroy(reader) }

    let info = try operations.open(
        reader,
        source: fixture.path,
        startSeconds: 0,
        streamIndex: nil
    )
    #expect(info.providerKind == "FFmpegDecodedPCM")
    #expect(info.codecName == "pcm_s24le")
}

@Test(arguments: [
    (
        "TestVectors/Enchron/CodecContainer/Audio/he-aac-v1-apple-audio-toolbox.m4a",
        kAudioFormatMPEG4AAC_HE,
        48_000
    ),
    (
        "TestVectors/Enchron/CodecContainer/Audio/he-aac-v2-apple-audio-toolbox.m4a",
        kAudioFormatMPEG4AAC_HE_V2,
        48_000
    ),
    (
        "TestVectors/Upstream/Fraunhofer/Audio/HE-AAC/SBRtestStereoAot5Sig1.mp4",
        kAudioFormatMPEG4AAC_HE,
        44_100
    ),
    (
        "TestVectors/Upstream/Fraunhofer/Audio/HE-AAC/SBRtestStereoAot29Sig1.mp4",
        kAudioFormatMPEG4AAC_HE_V2,
        44_100
    ),
])
func highEfficiencyAACProfilesDecodeToPCM(
    relativePath: String,
    _: AudioFormatID,
    expectedSampleRate: Int
) throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(relativePath)
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(
        reader,
        Comment(rawValue: "\(relativePath): \(cString(error))")
    )
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    let result = PBFFmpegAudioReaderCopyNextSample(
        activeReader,
        &sample,
        &metadata,
        &error,
        error.count
    )
    #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let description = try #require(
        CMAudioFormatDescriptionGetStreamBasicDescription(format)
    ).pointee

    #expect(description.mFormatID == kAudioFormatLinearPCM)
    #expect(description.mFramesPerPacket == 1)
    #expect(description.mChannelsPerFrame == 2)
    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader))
    #expect(CMSampleBufferGetNumSamples(buffer) > 1)
    #expect(
        CMSampleBufferGetDuration(buffer)
            == CMTime(
                value: CMTimeValue(CMSampleBufferGetNumSamples(buffer)),
                timescale: CMTimeScale(expectedSampleRate)
            )
    )
    #expect(metadata.payloadByteCount > 0)
}

@Test func undecodableXHEAACFailsWithTheDeclaredCodecName() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Upstream/Fraunhofer/Audio/xHE-AAC/Sintel_24kbps_rap5s.mp4"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    let result = PBFFmpegAudioReaderCopyNextSample(
        activeReader,
        &sample,
        &metadata,
        &error,
        error.count
    )
    #expect(result == PBFFmpegReadResultError)
    #expect(sample == nil)
    #expect(String(cString: PBFFmpegAudioReaderGetCodecName(activeReader)) == "aac")
    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader))
    #expect(cString(error).contains("audio codec aac"))
}

@Test func decodableXHEAACUsesPCM() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Upstream/Fraunhofer/Audio/xHE-AAC/xHEchID.mp4"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    #expect(
        PBFFmpegAudioReaderCopyNextSample(
            activeReader,
            &sample,
            &metadata,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let description = try #require(
        CMAudioFormatDescriptionGetStreamBasicDescription(format)
    ).pointee

    #expect(description.mFormatID == kAudioFormatLinearPCM)
    #expect(description.mFramesPerPacket == 1)
    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader))
    #expect(metadata.payloadByteCount > 0)
}

@Test func appleAPACHLSPassesCompressedPacketsToCoreMedia() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Upstream/Apple/Audio/APAC-HLS/playlist.m3u8"
    )

    #expect(mediaStreams(in: fixture).count {
        $0.raw.category == PBFFmpegMediaStreamCategoryAudio
    } == 1)
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    #expect(
        PBFFmpegAudioReaderCopyNextSample(
            activeReader,
            &sample,
            &metadata,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let buffer = try #require(sample?.takeRetainedValue())
    let bridgeFormat = try #require(CMSampleBufferGetFormatDescription(buffer))
    let bridgeDescription = try #require(
        CMAudioFormatDescriptionGetStreamBasicDescription(bridgeFormat)
    ).pointee

    #expect(String(cString: PBFFmpegAudioReaderGetCodecName(activeReader)) == "apac")
    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader) == false)
    #expect(bridgeDescription.mFormatID == kAudioFormatAPAC)
    #expect(bridgeDescription.mSampleRate == 48_000)
    #expect(bridgeDescription.mFormatFlags == 0)
    #expect(bridgeDescription.mBytesPerPacket == 0)
    #expect(bridgeDescription.mFramesPerPacket == 1_024)
    #expect(bridgeDescription.mBytesPerFrame == 0)
    #expect(bridgeDescription.mChannelsPerFrame == 2)
    #expect(bridgeDescription.mBitsPerChannel == 0)
    #expect(CMSampleBufferGetNumSamples(buffer) == 1)
    #expect(CMSampleBufferGetDuration(buffer) == CMTime(value: 1_024, timescale: 48_000))
    #expect(CMSampleBufferGetTotalSampleSize(buffer) == metadata.payloadByteCount)
    #expect(metadata.payloadByteCount > 0)
    #expect(metadata.cookieSource == PBFFmpegAudioCookieSourceExtradata)

    let initializationSegment = fixture.deletingLastPathComponent()
        .appendingPathComponent("fileSequence0.mp4")
    let expectedMagicCookie = try isoBaseMediaBox(
        named: "dapa",
        in: initializationSegment
    )
    #expect(magicCookieData(bridgeFormat) == expectedMagicCookie)
}

@Test func appleAudioRendererAcceptsAPACPassthrough() throws {
    let buffer = try firstCompressedAudioSample(
        relativePath: "TestVectors/Upstream/Apple/Audio/APAC-HLS/playlist.m3u8"
    )
    let synchronizer = AVSampleBufferRenderSynchronizer()
    let renderer = AVSampleBufferAudioRenderer()
    let receiver = synchronizer.sampleBufferReceiver(adding: renderer)
    let readySample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
        unsafeBuffer: buffer
    )
    let outcome = receiver.enqueueImmediately(readySample)
    let accepted: Bool
    switch outcome {
    case .enqueued, .enqueuedWithSuggestedFlush:
        accepted = true
    case .cancelledDueToFlush, .cancelledDueToError:
        accepted = false
    @unknown default:
        accepted = false
    }
    #expect(accepted, Comment(rawValue: String(describing: outcome)))
}

@Test func appleAudioRendererAcceptsPrivilegedDolbyPassthrough() throws {
    silenceFFmpegDiagnostics()
    let fixtures = [
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4",
    ]

    for relativePath in fixtures {
        let buffer = try firstCompressedAudioSample(relativePath: relativePath)
        let synchronizer = AVSampleBufferRenderSynchronizer()
        let renderer = AVSampleBufferAudioRenderer()
        let receiver = synchronizer.sampleBufferReceiver(adding: renderer)
        let readySample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
            unsafeBuffer: buffer
        )
        let outcome = receiver.enqueueImmediately(readySample)
        let accepted: Bool
        switch outcome {
        case .enqueued, .enqueuedWithSuggestedFlush:
            accepted = true
        case .cancelledDueToFlush, .cancelledDueToError:
            accepted = false
        @unknown default:
            accepted = false
        }
        #expect(
            accepted,
            Comment(rawValue: "\(relativePath): \(String(describing: outcome))")
        )
    }
}

@Test func opusDecodesToTimestampedPCM() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-audio-codec-matrix-15s.mkv"
    )
    let audioStreams = mediaStreams(in: fixture).filter {
        $0.raw.category == PBFFmpegMediaStreamCategoryAudio
    }
    let opusStream = try #require(
        audioStreams.indices.contains(6) ? audioStreams[6] : nil
    )
    let streamIndex = opusStream.raw.streamIndex
    #expect(opusStream.codecName == "opus")

    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, streamIndex, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    #expect(
        PBFFmpegAudioReaderCopyNextSample(
            activeReader,
            &sample,
            &metadata,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let description = try #require(
        CMAudioFormatDescriptionGetStreamBasicDescription(format)
    ).pointee

    #expect(description.mFormatID == kAudioFormatLinearPCM)
    #expect(description.mFramesPerPacket == 1)
    #expect(
        CMSampleBufferGetDuration(buffer)
            == CMTime(
                value: CMTimeValue(CMSampleBufferGetNumSamples(buffer)),
                timescale: 48_000
            )
    )
    #expect(metadata.packetDuration > 0)
    #expect(metadata.timeBaseNumerator == 1)
    #expect(metadata.timeBaseDenominator == 1_000)
}

@Test func dolbyDigitalPlusAtmosKeepsItsSixChannelCompressedLayout() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    #expect(
        PBFFmpegAudioReaderCopyNextSample(
            activeReader,
            &sample,
            &metadata,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: cString(error))
    )
    let buffer = try #require(sample?.takeRetainedValue())
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let description = try #require(
        CMAudioFormatDescriptionGetStreamBasicDescription(format)
    ).pointee

    #expect(String(cString: PBFFmpegAudioReaderGetCodecName(activeReader)) == "eac3")
    #expect(description.mFormatID == kAudioFormatEnhancedAC3)
    #expect(description.mChannelsPerFrame == 6)
    #expect(description.mFramesPerPacket == 1_536)
    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader) == false)
    #expect(CMSampleBufferGetDuration(buffer) == CMTime(value: 1_536, timescale: 48_000))
    #expect(metadata.payloadByteCount == 3_072)

    var channelLayoutSize = 0
    let channelLayout = CMAudioFormatDescriptionGetChannelLayout(
        format,
        sizeOut: &channelLayoutSize
    )
    #expect(channelLayout != nil)
    #expect(channelLayoutSize >= MemoryLayout<AudioChannelLayout>.size)
}

@Test func generatedAudioCodecMatrixProducesEveryRegisteredAudioFormat() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-audio-codec-matrix-15s.mkv"
    )
    let expectedFormats: [(codec: String, formatID: AudioFormatID, outputsPCM: Bool)] = [
        ("aac", kAudioFormatLinearPCM, true),
        ("ac3", kAudioFormatAC3, false),
        ("eac3", kAudioFormatEnhancedAC3, false),
        ("mp2", kAudioFormatLinearPCM, true),
        ("mp3", kAudioFormatLinearPCM, true),
        ("alac", kAudioFormatLinearPCM, true),
        ("opus", kAudioFormatLinearPCM, true),
        ("flac", kAudioFormatLinearPCM, true),
    ]

    let audioStreams = mediaStreams(in: fixture).filter {
        $0.raw.category == PBFFmpegMediaStreamCategoryAudio
    }
    #expect(audioStreams.count == expectedFormats.count)
    for (ordinal, expected) in expectedFormats.enumerated() {
        let stream = try #require(
            audioStreams.indices.contains(ordinal) ? audioStreams[ordinal] : nil
        )
        #expect(stream.codecName == expected.codec)
        #expect(stream.raw.sampleRate == 48_000)
        #expect(stream.raw.channelCount == 2)

        var error = [CChar](repeating: 0, count: 512)
        let reader = fixture.path.withCString { path in
            PBFFmpegAudioReaderCreate(
                path,
                0,
                stream.raw.streamIndex,
                &error,
                error.count
            )
        }
        let activeReader = try #require(
            reader,
            Comment(rawValue: "\(expected.codec): \(cString(error))")
        )
        defer { PBFFmpegAudioReaderDestroy(activeReader) }
        #expect(String(cString: PBFFmpegAudioReaderGetCodecName(activeReader)) == expected.codec)
        #expect(PBFFmpegAudioReaderOutputsPCM(activeReader) == expected.outputsPCM)

        var sample: Unmanaged<CMSampleBuffer>?
        var metadata = PBFFmpegAudioSampleMetadata()
        let result = PBFFmpegAudioReaderCopyNextSample(
            activeReader,
            &sample,
            &metadata,
            &error,
            error.count
        )
        #expect(
            result == PBFFmpegReadResultSample,
            Comment(rawValue: "\(expected.codec): \(cString(error))")
        )
        let buffer = try #require(sample?.takeRetainedValue())
        let format = try #require(CMSampleBufferGetFormatDescription(buffer))
        let description = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(format))
        #expect(description.pointee.mFormatID == expected.formatID)
        #expect(CMSampleBufferDataIsReady(buffer))
    }
}

@Test func generatedAV1RemainsCompressedWhileFLACDecodesToPCM() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/av1-flac-avsync-10s.mkv"
    )
    var error = [CChar](repeating: 0, count: 512)
    let videoReader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeVideoReader = try #require(videoReader, Comment(rawValue: cString(error)))
    defer { PBFFmpegReaderDestroy(activeVideoReader) }
    #expect(String(cString: PBFFmpegReaderGetCodecName(activeVideoReader)) == "av1")

    var videoSample: Unmanaged<CMSampleBuffer>?
    #expect(
        PBFFmpegReaderCopyNextSample(
            activeVideoReader,
            &videoSample,
            &error,
            error.count
        ) == PBFFmpegReadResultSample
    )
    let retainedVideoSample = try #require(videoSample?.takeRetainedValue())
    let videoFormat = try #require(CMSampleBufferGetFormatDescription(retainedVideoSample))
    #expect(CMFormatDescriptionGetMediaSubType(videoFormat) == kCMVideoCodecType_AV1)

    let audioReader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeAudioReader = try #require(audioReader, Comment(rawValue: cString(error)))
    defer { PBFFmpegAudioReaderDestroy(activeAudioReader) }
    #expect(String(cString: PBFFmpegAudioReaderGetCodecName(activeAudioReader)) == "flac")
    #expect(PBFFmpegAudioReaderOutputsPCM(activeAudioReader))
}

@Test func generatedVideoOnlyFixtureHasNoAudioTracks() {
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-video-only-15s.mp4"
    )
    #expect(mediaStreams(in: fixture).contains {
        $0.raw.category == PBFFmpegMediaStreamCategoryAudio
    } == false)
}

@Test(arguments: [Int32(-1), Int32(1)])
func lateStartAudioOpensOnASharedDemuxSource(preferredStreamIndex: Int32) throws {
    silenceFFmpegDiagnostics()
    let fixture = try lateStartAudioTransportStream()
    var error = [CChar](repeating: 0, count: 512)
    let source = try #require(
        fixture.path.withCString {
            PBFFmpegDemuxSourceCreate(
                $0,
                false,
                PBFFmpegDemuxBufferConfigurationMake(PBFFmpegDemuxBufferModeNone, 0),
                nil,
                &error,
                error.count
            )
        },
        Comment(rawValue: cString(error))
    )
    defer { PBFFmpegDemuxSourceDestroy(source) }
    #expect(
        PBFFmpegDemuxSourceSeek(source, 6, &error, error.count),
        Comment(rawValue: cString(error))
    )
    let reader = try #require(PBFFmpegAudioReaderAllocate())
    defer { PBFFmpegAudioReaderDestroy(reader) }

    let opened = PBFFmpegAudioReaderOpenWithDemuxSource(
        reader,
        source,
        preferredStreamIndex,
        &error,
        error.count
    )

    #expect(opened, Comment(rawValue: cString(error)))
    #expect(PBFFmpegAudioReaderGetStreamIndex(reader) == 1)
    #expect(PBFFmpegAudioReaderGetSampleRate(reader) == 48_000)
    #expect(PBFFmpegAudioReaderGetChannelCount(reader) == 2)
    #expect(String(cString: PBFFmpegAudioReaderGetCodecName(reader)) == "eac3")
    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    let result = PBFFmpegAudioReaderCopyNextSample(
        reader,
        &sample,
        &metadata,
        &error,
        error.count
    )
    #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
    let buffer = try #require(sample?.takeRetainedValue())
    #expect(CMSampleBufferGetNumSamples(buffer) > 0)
}

@Test func ownedContextAndSharedDemuxSourceReachTheSameLateStartAudio() throws {
    silenceFFmpegDiagnostics()
    let fixture = try lateStartAudioTransportStream()
    var error = [CChar](repeating: 0, count: 512)
    let owned = try #require(
        fixture.path.withCString {
            PBFFmpegAudioReaderCreate($0, 6, 1, &error, error.count)
        },
        Comment(rawValue: cString(error))
    )
    defer { PBFFmpegAudioReaderDestroy(owned) }
    let source = try #require(
        fixture.path.withCString {
            PBFFmpegDemuxSourceCreate(
                $0,
                false,
                PBFFmpegDemuxBufferConfigurationMake(PBFFmpegDemuxBufferModeNone, 0),
                nil,
                &error,
                error.count
            )
        },
        Comment(rawValue: cString(error))
    )
    defer { PBFFmpegDemuxSourceDestroy(source) }
    let shared = try #require(PBFFmpegAudioReaderAllocate())
    defer { PBFFmpegAudioReaderDestroy(shared) }
    #expect(
        PBFFmpegAudioReaderOpenWithDemuxSource(shared, source, 1, &error, error.count),
        Comment(rawValue: cString(error))
    )

    #expect(
        PBFFmpegAudioReaderGetSampleRate(shared) == PBFFmpegAudioReaderGetSampleRate(owned)
    )
    #expect(
        PBFFmpegAudioReaderGetChannelCount(shared) == PBFFmpegAudioReaderGetChannelCount(owned)
    )
}

@Test func audioWithoutPacketsStillFailsOnASharedDemuxSource() throws {
    silenceFFmpegDiagnostics()
    let fixture = try delayedAACTransportStream(includeAudioPackets: false)
    defer { try? FileManager.default.removeItem(at: fixture) }
    var error = [CChar](repeating: 0, count: 512)
    let source = try #require(
        fixture.path.withCString {
            PBFFmpegDemuxSourceCreate(
                $0,
                false,
                PBFFmpegDemuxBufferConfigurationMake(PBFFmpegDemuxBufferModeNone, 0),
                nil,
                &error,
                error.count
            )
        },
        Comment(rawValue: cString(error))
    )
    defer { PBFFmpegDemuxSourceDestroy(source) }
    let reader = try #require(PBFFmpegAudioReaderAllocate())
    defer { PBFFmpegAudioReaderDestroy(reader) }

    let opened = PBFFmpegAudioReaderOpenWithDemuxSource(reader, source, 1, &error, error.count)

    #expect(opened == false)
    #expect(cString(error) == "Audio stream parameters are unavailable after extended probe")
}

private func lateStartAudioTransportStream() throws -> URL {
    try #require(
        Bundle.module.url(
            forResource: "audio-eac3-late-start",
            withExtension: "ts",
            subdirectory: "Fixtures"
        )
    )
}

private func decodedFixture(resource: String, fileExtension: String) throws -> URL {
    let encodedURL = try #require(
        Bundle.module.url(
            forResource: resource,
            withExtension: "base64",
            subdirectory: "Fixtures"
        )
    )
    let encoded = try String(contentsOf: encodedURL, encoding: .utf8)
    let data = try #require(Data(base64Encoded: encoded, options: .ignoreUnknownCharacters))
    let output = FileManager.default.temporaryDirectory
        .appendingPathComponent("playbackcore-\(UUID().uuidString)")
        .appendingPathExtension(fileExtension)
    try data.write(to: output, options: .atomic)
    return output
}

private func delayedAACTransportStream(includeAudioPackets: Bool = true) throws -> URL {
    let encoded = "R0AREABC8CUAAcEAAP8B/wAB/IAUSBIBBkZGbXBlZwlTZXJ2aWNlMDF3fEPK//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HQAAQAACwDQABwQAAAAHwACqxBLL//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dQABAAArAXAAHBAADhAPAAAuEA8AAP4QHwAJdXh9D/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R0EAMAdQAAB7DH4AAAAB4AAAgMAKMQAH79ERAAfYYQAAAbMoAWg1///gGAAAAbUUigABAAAAAAG4AAgAQAAAAQAAD//4AAABtY//80GAAAABARP5wTEAC4A0AHQFAE4BfhnJobiEhgCssNJpNLJqSgwmEwhEIaGhob2UgMK6W37Nv5wCsAIAA4ADkEQAQAPwA4GAhf6AFYAdkslAB4AHTAB6AVuCIAKBgljAlhi7ogDsMJpCBBAlALwG4AdHAQARAFAHQIP9QFA0Ax5SA0MANCGAZhnIQDAmk0rqJQBazpLYmbti057qcCgCEEH9kEH+IAOQQgDgQwDgQf5ACwoAqADkEEBMANgA7ALHGAFQAcqAyCGAUNCAMtcAIAFgIAGoBkAIgDTlEwB38G8CmALSGQgzAOgA/DQExYaGFEL4oov8hhucNzhoaXiWoM5/vriw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"
    guard let base = Data(base64Encoded: encoded) else {
        throw FixtureError.invalidBase
    }
    let packetSize = 188
    let tablePacketCount = 3
    let videoPacketCount = 34
    let audioPacketCount = 3
    let tableBytes = packetSize * tablePacketCount
    let videoBytes = packetSize * videoPacketCount
    let audioBytes = packetSize * audioPacketCount
    let videoPackets = base[tableBytes..<(tableBytes + videoBytes)]
    let audioPackets = base.suffix(audioBytes)
    var fixture = Data(base.prefix(tableBytes))
    while fixture.count < 5_600_000 {
        fixture.append(videoPackets)
    }
    if includeAudioPackets {
        fixture.append(audioPackets)
    }

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("playbackcore-delayed-audio-\(UUID().uuidString).ts")
    try fixture.write(to: url, options: .atomic)
    return url
}

private enum FixtureError: Error {
    case invalidBase
}

@_silgen_name("av_log_set_level")
private func avLogSetLevel(_ level: Int32)

private func silenceFFmpegDiagnostics() {
    avLogSetLevel(-8)
}

private func cString(_ buffer: [CChar]) -> String {
    String(
        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
}

private func firstVideoFormatDescription(in asset: AVAsset) async throws -> CMFormatDescription {
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    return try #require(try await track.load(.formatDescriptions).first)
}

private func firstCompressedVideoSample(in asset: AVAsset) async throws -> CMSampleBuffer {
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    try #require(reader.canAdd(output))
    reader.add(output)
    try #require(reader.startReading())
    while let sample = output.copyNextSampleBuffer() {
        guard CMSampleBufferGetNumSamples(sample) > 0,
              let buffer = CMSampleBufferGetDataBuffer(sample),
              CMBlockBufferGetDataLength(buffer) > 0 else { continue }
        return sample
    }
    Issue.record("AVAssetReader did not publish a compressed video sample.")
    throw CancellationError()
}

private func compressedPayload(in sample: CMSampleBuffer) throws -> Data {
    let buffer = try #require(CMSampleBufferGetDataBuffer(sample))
    let length = CMBlockBufferGetDataLength(buffer)
    var data = Data(count: length)
    let status = data.withUnsafeMutableBytes { bytes in
        guard let baseAddress = bytes.baseAddress else {
            return kCMBlockBufferBadLengthParameterErr
        }
        return CMBlockBufferCopyDataBytes(
            buffer,
            atOffset: 0,
            dataLength: length,
            destination: baseAddress
        )
    }
    try #require(status == noErr)
    return data
}

private func sampleDescriptionAtoms(
    in format: CMFormatDescription
) throws -> [String: Data] {
    let extensions = try #require(
        CMFormatDescriptionGetExtensions(format) as? [String: Any]
    )
    return try #require(
        extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String]
            as? [String: Data]
    )
}

private func videoFormatDescription(
    byRemovingSampleDescriptionAtom atom: String,
    from sourceFormat: CMVideoFormatDescription
) throws -> CMVideoFormatDescription {
    var extensions = CMFormatDescriptionGetExtensions(sourceFormat) as? [String: Any] ?? [:]
    var atoms = try sampleDescriptionAtoms(in: sourceFormat)
    atoms.removeValue(forKey: atom)
    extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] = atoms
    let dimensions = CMVideoFormatDescriptionGetDimensions(sourceFormat)
    var result: CMVideoFormatDescription?
    let status = CMVideoFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        codecType: CMFormatDescriptionGetMediaSubType(sourceFormat),
        width: dimensions.width,
        height: dimensions.height,
        extensions: extensions as CFDictionary,
        formatDescriptionOut: &result
    )
    try #require(status == noErr)
    return try #require(result)
}

private func compressedVideoSample(
    formatDescription: CMVideoFormatDescription
) throws -> CMSampleBuffer {
    var blockBuffer: CMBlockBuffer?
    let byteCount = 4
    var status = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: byteCount,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: byteCount,
        flags: 0,
        blockBufferOut: &blockBuffer
    )
    try #require(status == noErr)
    let block = try #require(blockBuffer)
    var payload = [UInt8](repeating: 0, count: byteCount)
    status = payload.withUnsafeMutableBytes { bytes in
        CMBlockBufferReplaceDataBytes(
            with: bytes.baseAddress!,
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: byteCount
        )
    }
    try #require(status == noErr)
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 24),
        presentationTimeStamp: .zero,
        decodeTimeStamp: .invalid
    )
    var sampleSize = byteCount
    var sample: CMSampleBuffer?
    status = CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: block,
        formatDescription: formatDescription,
        sampleCount: 1,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 1,
        sampleSizeArray: &sampleSize,
        sampleBufferOut: &sample
    )
    try #require(status == noErr)
    return try #require(sample)
}

private final class FixedFormatVideoReaderOperations:
    FFmpegVideoReaderOperations,
    @unchecked Sendable
{
    private let formatDescription: CMVideoFormatDescription
    private let sample: CMSampleBuffer
    private let info: VideoSampleProviderInfo

    init(
        formatDescription: CMVideoFormatDescription,
        sample: CMSampleBuffer,
        info: VideoSampleProviderInfo
    ) {
        self.formatDescription = formatDescription
        self.sample = sample
        self.info = info
    }

    func allocate() -> FFmpegVideoReaderHandle? {
        FFmpegVideoReaderHandle(pointer: OpaquePointer(bitPattern: 0x401)!)
    }

    func open(
        _ reader: FFmpegVideoReaderHandle,
        source: String,
        startSeconds: Double
    ) throws -> VideoSampleProviderInfo {
        info
    }

    func copyCompressedFormatDescription(
        from reader: FFmpegVideoReaderHandle
    ) -> SendableVideoFormatDescription? {
        SendableVideoFormatDescription(value: formatDescription)
    }

    func copyNextSample(
        from reader: FFmpegVideoReaderHandle
    ) throws -> FFmpegVideoReadOutcome {
        .sample(SendableSampleBuffer(value: sample))
    }

    func cancel(_ reader: FFmpegVideoReaderHandle) {}
    func destroy(_ reader: FFmpegVideoReaderHandle) {}
}

private func magicCookieData(_ format: CMAudioFormatDescription) -> Data? {
    var size = 0
    guard let cookie = CMAudioFormatDescriptionGetMagicCookie(format, sizeOut: &size),
          size > 0 else {
        return nil
    }
    return Data(bytes: cookie, count: size)
}

private func isoBaseMediaBox(named type: String, in file: URL) throws -> Data {
    let data = try Data(contentsOf: file)
    let typeData = Data(type.utf8)
    let typeRange = try #require(data.range(of: typeData))
    try #require(typeRange.lowerBound >= MemoryLayout<UInt32>.size)
    let sizeOffset = typeRange.lowerBound - MemoryLayout<UInt32>.size
    let declaredSize = data[sizeOffset..<typeRange.lowerBound].reduce(UInt32(0)) {
        ($0 << 8) | UInt32($1)
    }
    let endOffset = sizeOffset + Int(declaredSize)
    try #require(declaredSize >= 8)
    try #require(endOffset <= data.endIndex)
    return data.subdata(in: sizeOffset..<endOffset)
}

private func decoderSpecificInfo(in cookie: Data?) -> Data? {
    guard let cookie,
          let descriptorIndex = cookie.firstIndex(of: 0x05),
          descriptorIndex + 1 < cookie.endIndex else {
        return nil
    }
    let byteCount = Int(cookie[descriptorIndex + 1])
    let payloadStart = descriptorIndex + 2
    guard byteCount < 0x80,
          payloadStart + byteCount <= cookie.endIndex else {
        return nil
    }
    return cookie[payloadStart..<(payloadStart + byteCount)]
}

private func firstCompressedAudioSample(relativePath: String) throws -> CMSampleBuffer {
    let fixture = playbackTestMedia.appendingPathComponent(relativePath)
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(
        reader,
        Comment(rawValue: "\(relativePath): \(cString(error))")
    )
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    #expect(
        PBFFmpegAudioReaderCopyNextSample(
            activeReader,
            &sample,
            &metadata,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: "\(relativePath): \(cString(error))")
    )
    return try #require(sample?.takeRetainedValue())
}

@Test func retiredVP9CodecIsRejectedByPlaybackCore() throws {
    silenceFFmpegDiagnostics()
    let fixture = try decodedFixture(
        resource: "video-vp9-no-vpcc.webm",
        fileExtension: "webm"
    )
    defer { try? FileManager.default.removeItem(at: fixture) }
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    #expect(reader == nil)
    #expect(cString(error).localizedCaseInsensitiveContains("unsupported codec"))
}

@Test func retiredMPEG4Part2CodecIsRejectedByPlaybackCore() {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Upstream/FATE/MPEG4-Part2/packed_bframes.avi"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    defer { PBFFmpegReaderDestroy(reader) }

    #expect(reader == nil)
    #expect(cString(error).localizedCaseInsensitiveContains("unsupported codec"))
}
