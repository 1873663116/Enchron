import Testing

@testable import Playback

@MainActor
struct MediaFormatInterpreterTests {
    @Test("provider signaling takes precedence over sample signaling")
    func providerSignalingTakesPrecedenceOverSampleSignaling() {
        let format = MediaFormatInterpreter.sourceFormat(
            from: .init(
                providerProjectionKind: "HalfEquirectangular",
                sampleProjectionKind: "Equirectangular",
                providerViewPackingKind: "SideBySide",
                sampleViewPackingKind: "OverUnder",
                isMVHEVC: false
            )
        )

        #expect(
            format
                == SourceMediaFormatFact(
                    contentKind: .halfEquirectangular,
                    projection: .equirectangular180,
                    horizontalFieldOfViewDegrees: 180,
                    stereoLayout: .sideBySide
                )
        )
    }

    @Test("sample signaling supplies unrecognized provider facts")
    func sampleSignalingSuppliesUnrecognizedProviderFacts() {
        let format = MediaFormatInterpreter.sourceFormat(
            from: .init(
                providerProjectionKind: "Unspecified",
                sampleProjectionKind: "Parametric Immersive",
                providerViewPackingKind: "Unspecified",
                sampleViewPackingKind: "Top-Bottom",
                isMVHEVC: false
            )
        )

        #expect(format.contentKind == .parametricImmersive)
        #expect(format.projection == .flat)
        #expect(format.horizontalFieldOfViewDegrees == nil)
        #expect(format.stereoLayout == .topBottom)
    }

    @Test("MV-HEVC supplies spatial video and native stereo fallbacks")
    func mvhevcSuppliesSpatialVideoAndNativeStereoFallbacks() {
        let format = MediaFormatInterpreter.sourceFormat(
            from: .init(
                providerProjectionKind: nil,
                sampleProjectionKind: nil,
                providerViewPackingKind: nil,
                sampleViewPackingKind: nil,
                isMVHEVC: true
            )
        )

        #expect(format.contentKind == .spatialVideo)
        #expect(format.projection == .flat)
        #expect(format.horizontalFieldOfViewDegrees == nil)
        #expect(format.stereoLayout == .multiview)

        let immersiveFormat = MediaFormatInterpreter.sourceFormat(
            from: .init(
                providerProjectionKind: "AppleImmersiveVideo",
                sampleProjectionKind: nil,
                providerViewPackingKind: nil,
                sampleViewPackingKind: nil,
                isMVHEVC: true
            )
        )
        #expect(immersiveFormat.contentKind == .appleImmersiveVideo)
    }

    @Test("technical format strings and horizontal coverage are normalized")
    func technicalFormatStringsAndHorizontalCoverageAreNormalized() {
        #expect(
            MediaFormatInterpreter.projection(from: "Half-Equirectangular")
                == .equirectangular180
        )
        #expect(
            MediaFormatInterpreter.projection(from: "Apple Immersive Video") == .flat
        )
        #expect(
            MediaFormatInterpreter.stereoLayout(from: "Left_Right") == .sideBySide
        )
        #expect(
            MediaFormatInterpreter.stereoLayout(from: "Over Under") == .topBottom
        )
        #expect(MediaFormatInterpreter.projection(from: "Unspecified") == nil)
        #expect(MediaFormatInterpreter.stereoLayout(from: "Unspecified") == nil)
        #expect(
            MediaFormatInterpreter.effectiveHorizontalFieldOfViewDegrees(
                for: .equirectangular360,
                explicitDegrees: nil
            ) == 360
        )
        #expect(
            MediaFormatInterpreter.effectiveHorizontalFieldOfViewDegrees(
                for: .customAngle,
                explicitDegrees: 237
            ) == 240
        )
    }
}
