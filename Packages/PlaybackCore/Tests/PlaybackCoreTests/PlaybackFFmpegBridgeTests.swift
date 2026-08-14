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
    (
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4",
        true,
        false,
        nil
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

@Test func appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat() async throws {
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

    #expect(atoms["hvcC"] != sourceAtoms["hvcC"])
    #expect(atoms["lhvC"] == nil)
    #expect(extensions[kCMFormatDescriptionExtension_ProjectionKind as String] == nil)
    #expect(provider.info.formatSignaling.provenance == "FFmpeg.codecParameters")
    #expect(provider.info.formatSignaling.projectionKind.value == "AppleImmersiveVideo")
    #expect(provider.info.formatSignaling.hasLeftStereoEyeView.value == true)
    #expect(provider.info.formatSignaling.hasRightStereoEyeView.value == true)
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

    let count = fixture.path.withCString(PBFFmpegSubtitleTrackCount)
    #expect(count == 2)

    var streamIndex: Int32 = -1
    var codec = [CChar](repeating: 0, count: 64)
    var language = [CChar](repeating: 0, count: 64)
    var title = [CChar](repeating: 0, count: 256)
    let copied = fixture.path.withCString { path in
        PBFFmpegSubtitleTrackCopyInfo(
            path,
            0,
            &streamIndex,
            &codec,
            codec.count,
            &language,
            language.count,
            &title,
            title.count
        )
    }

    #expect(copied)
    #expect(streamIndex == 1)
    #expect(cString(codec) == "subrip")
    #expect(cString(language) == "zho")
    #expect(cString(title) == "简体中文")
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
        PBFFmpegSubtitleReaderCreate(path, 1, &error, error.count)
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

    let trackCount = fixture.path.withCString(PBFFmpegAudioTrackCount)

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

@Test func delayedAudioParametersProduceCompressedAACSample() throws {
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
    #expect(CMSampleBufferGetNumSamples(buffer) > 0)
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let streamDescription = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(format))
    #expect(streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC)
    #expect(streamDescription.pointee.mFormatID != kAudioFormatLinearPCM)
    var magicCookieSize = 0
    let magicCookie = CMAudioFormatDescriptionGetMagicCookie(
        format,
        sizeOut: &magicCookieSize
    )
    #expect(magicCookie != nil)
    #expect(magicCookieSize > 2)
    if let magicCookie {
        let bytes = UnsafeRawBufferPointer(start: magicCookie, count: magicCookieSize)
        #expect(bytes.first == 0x03)
    }
    #expect(metadata.payloadByteCount > 0)
    #expect(metadata.timeBaseNumerator > 0)
    #expect(metadata.timeBaseDenominator > 0)
    #expect(metadata.cookieSource == PBFFmpegAudioCookieSourceFilterOutput)
}

@Test func flacPacketsRemainCompressedForAVFoundationDecoding() throws {
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

    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader) == false)
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

    #expect(streamDescription.mFormatID == kAudioFormatFLAC)
    #expect(streamDescription.mSampleRate == 48_000)
    #expect(streamDescription.mChannelsPerFrame == 2)
    #expect(streamDescription.mFramesPerPacket > 0)
    #expect(CMSampleBufferGetNumSamples(buffer) == 1)
    #expect(CMSampleBufferGetDuration(buffer).seconds > 0)
    #expect(metadata.payloadByteCount > 0)
    let dataBuffer = try #require(CMSampleBufferGetDataBuffer(buffer))
    #expect(CMBlockBufferGetDataLength(dataBuffer) == metadata.payloadByteCount)

    var magicCookieSize = 0
    let magicCookie = CMAudioFormatDescriptionGetMagicCookie(
        format,
        sizeOut: &magicCookieSize
    )
    let cookieBytes = UnsafeRawBufferPointer(
        start: magicCookie,
        count: magicCookieSize
    )
    #expect(magicCookieSize >= 16)
    #expect(String(bytes: cookieBytes[4..<8], encoding: .ascii) == "dfLa")
}

@Test func proResCameraOriginalKeepsFiveChannelPCMAsSourcePCM() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "Samples/Professional/ProRes/ARRI-AMIRA/B001C001_140702_R3VJ.mov"
    )
    #expect(fixture.path.withCString(PBFFmpegAudioTrackCount) == 1)

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
    #expect(description.mBitsPerChannel == 24)
    #expect(description.mBytesPerFrame == 15)
    #expect(description.mChannelsPerFrame == 5)
    #expect(CMSampleBufferGetNumSamples(buffer) == 1_024)
    #expect(CMSampleBufferGetDuration(buffer) == CMTime(value: 1_024, timescale: 48_000))
    #expect(metadata.payloadByteCount == 15_360)
    #expect(metadata.cookieSource == PBFFmpegAudioCookieSourceUnavailable)
    #expect(CMBlockBufferGetDataLength(try #require(CMSampleBufferGetDataBuffer(buffer))) == 15_360)

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
    #expect(description.mBitsPerChannel == 16)
    #expect(description.mBytesPerFrame == description.mChannelsPerFrame * 2)
    #expect(description.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0)
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

    #expect(description.mFormatID == kAudioFormatMPEG4AAC)
    #expect(CMSampleBufferDataIsReady(buffer))
    #expect(metadata.payloadByteCount > 0)
}

@Test func sourcePCMIsNotReportedAsAnFFmpegDecodePath() throws {
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
    #expect(info.providerKind == "FFmpegSourcePCM")
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
func highEfficiencyAACProfilesKeepTheirCoreAudioFormat(
    relativePath: String,
    expectedFormatID: AudioFormatID,
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

    #expect(description.mFormatID == expectedFormatID)
    #expect(description.mFramesPerPacket == 2_048)
    #expect(description.mChannelsPerFrame == 2)
    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader) == false)
    #expect(CMSampleBufferGetNumSamples(buffer) == 1)
    #expect(
        CMSampleBufferGetDuration(buffer)
            == CMTime(value: 2_048, timescale: CMTimeScale(expectedSampleRate))
    )
    #expect(metadata.payloadByteCount > 0)
}

@Test func xHEAACMatchesAVFoundationsCompressedFormatDescription() async throws {
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

    let asset = AVURLAsset(url: fixture)
    let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
    let nativeFormat = try #require(try await track.load(.formatDescriptions).first)
    let nativeDescription = try #require(
        CMAudioFormatDescriptionGetStreamBasicDescription(nativeFormat)
    ).pointee

    #expect(String(cString: PBFFmpegAudioReaderGetCodecName(activeReader)) == "aac")
    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader) == false)
    #expect(bridgeDescription.mFormatID == kAudioFormatMPEGD_USAC)
    #expect(bridgeDescription.mFormatID == nativeDescription.mFormatID)
    #expect(bridgeDescription.mSampleRate == nativeDescription.mSampleRate)
    #expect(bridgeDescription.mChannelsPerFrame == nativeDescription.mChannelsPerFrame)
    #expect(bridgeDescription.mFramesPerPacket == nativeDescription.mFramesPerPacket)
    #expect(
        decoderSpecificInfo(in: magicCookieData(bridgeFormat))
            == decoderSpecificInfo(in: magicCookieData(nativeFormat))
    )
    #expect(CMSampleBufferGetDuration(buffer) == CMTime(value: 2_048, timescale: 48_000))
    #expect(metadata.payloadByteCount > 0)
}

@Test func xHEAACWithLoudnessInfoRemainsADemuxOnlyPath() throws {
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

    #expect(description.mFormatID == kAudioFormatMPEGD_USAC)
    #expect(description.mFramesPerPacket == 2_048)
    #expect(PBFFmpegAudioReaderOutputsPCM(activeReader) == false)
    #expect(metadata.payloadByteCount > 0)
}

@Test func appleAPACHLSKeepsItsCompressedPacketsAndConfiguration() async throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Upstream/Apple/Audio/APAC-HLS/playlist.m3u8"
    )

    let initializationSegment = fixture.deletingLastPathComponent()
        .appendingPathComponent("fileSequence0.mp4")
    let asset = AVURLAsset(url: initializationSegment)
    let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
    let nativeFormat = try #require(try await track.load(.formatDescriptions).first)
    let nativeDescription = try #require(
        CMAudioFormatDescriptionGetStreamBasicDescription(nativeFormat)
    ).pointee

    #expect(fixture.path.withCString(PBFFmpegAudioTrackCount) == 1)
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
    #expect(bridgeDescription.mFormatID == nativeDescription.mFormatID)
    #expect(bridgeDescription.mSampleRate == nativeDescription.mSampleRate)
    #expect(bridgeDescription.mChannelsPerFrame == nativeDescription.mChannelsPerFrame)
    #expect(bridgeDescription.mFramesPerPacket == nativeDescription.mFramesPerPacket)
    #expect(magicCookieData(bridgeFormat) == magicCookieData(nativeFormat))
    #expect(CMSampleBufferGetDuration(buffer) == CMTime(value: 1_024, timescale: 48_000))
    #expect(metadata.payloadByteCount > 0)
}

@Test func appleAudioRendererAcceptsTheCompressedAudioCapabilitySet() throws {
    silenceFFmpegDiagnostics()
    let fixtures = [
        "TestVectors/Upstream/Fraunhofer/Audio/xHE-AAC/Sintel_24kbps_rap5s.mp4",
        "TestVectors/Upstream/Apple/Audio/APAC-HLS/playlist.m3u8",
        "Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4",
        "TestVectors/Enchron/PlaybackBehavior/av1-flac-avsync-10s.mkv",
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

@Test func opusUsesPacketTimingInsteadOfClaimingAFixedFrameCount() throws {
    silenceFFmpegDiagnostics()
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-audio-codec-matrix-15s.mkv"
    )
    var streamIndex: Int32 = -1
    var sampleRate: Int32 = 0
    var channelCount: Int32 = 0
    var codec = [CChar](repeating: 0, count: 32)
    var language = [CChar](repeating: 0, count: 32)
    var title = [CChar](repeating: 0, count: 128)
    #expect(
        fixture.path.withCString { path in
            PBFFmpegAudioTrackCopyInfo(
                path,
                6,
                &streamIndex,
                &sampleRate,
                &channelCount,
                &codec,
                codec.count,
                &language,
                language.count,
                &title,
                title.count
            )
        }
    )
    #expect(cString(codec) == "opus")

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

    #expect(description.mFormatID == kAudioFormatOpus)
    #expect(description.mFramesPerPacket == 0)
    #expect(CMSampleBufferGetDuration(buffer) == CMTime(value: 20, timescale: 1_000))
    #expect(metadata.packetDuration == 20)
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
        ("aac", kAudioFormatMPEG4AAC, false),
        ("ac3", kAudioFormatAC3, false),
        ("eac3", kAudioFormatEnhancedAC3, false),
        ("mp2", kAudioFormatMPEGLayer2, false),
        ("mp3", kAudioFormatMPEGLayer3, false),
        ("alac", kAudioFormatAppleLossless, false),
        ("opus", kAudioFormatOpus, false),
        ("flac", kAudioFormatFLAC, false),
    ]

    #expect(fixture.path.withCString(PBFFmpegAudioTrackCount) == expectedFormats.count)
    for (ordinal, expected) in expectedFormats.enumerated() {
        var streamIndex: Int32 = -1
        var sampleRate: Int32 = 0
        var channelCount: Int32 = 0
        var codec = [CChar](repeating: 0, count: 32)
        var language = [CChar](repeating: 0, count: 32)
        var title = [CChar](repeating: 0, count: 128)
        let copied = fixture.path.withCString { path in
            PBFFmpegAudioTrackCopyInfo(
                path,
                Int32(ordinal),
                &streamIndex,
                &sampleRate,
                &channelCount,
                &codec,
                codec.count,
                &language,
                language.count,
                &title,
                title.count
            )
        }
        #expect(copied)
        #expect(cString(codec) == expected.codec)
        #expect(sampleRate == 48_000)
        #expect(channelCount == 2)

        var error = [CChar](repeating: 0, count: 512)
        let reader = fixture.path.withCString { path in
            PBFFmpegAudioReaderCreate(
                path,
                0,
                Int32(streamIndex),
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

@Test func generatedAV1AndFLACFixtureKeepsBothTracksCompressed() throws {
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
    #expect(PBFFmpegAudioReaderOutputsPCM(activeAudioReader) == false)
}

@Test func generatedVideoOnlyFixtureHasNoAudioTracks() {
    let fixture = playbackTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-video-only-15s.mp4"
    )
    #expect(fixture.path.withCString(PBFFmpegAudioTrackCount) == 0)
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
