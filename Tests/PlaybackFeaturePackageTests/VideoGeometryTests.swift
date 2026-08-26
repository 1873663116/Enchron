import Foundation
import Playback
import Testing

@Suite("Video display geometry")
struct VideoGeometryTests {
    @Test("sample aspect ratio derives presentation dimensions")
    func presentationDimensions() {
        let squarePixels = PlaybackModel.MediaProfile.PixelAspectRatio.square
        let tallPixels = PlaybackModel.MediaProfile.PixelAspectRatio(
            horizontalSpacing: 1,
            verticalSpacing: 4
        )

        #expect(
            PlaybackModel.StereoLayout.sideBySide.outputDisplayDimensions(
                inputWidth: 8_192,
                inputHeight: 4_096,
                pixelAspectRatio: squarePixels
            ) == .init(width: 4_096, height: 4_096)
        )
        #expect(
            PlaybackModel.StereoLayout.topBottom.outputDisplayDimensions(
                inputWidth: 8_192,
                inputHeight: 4_096,
                pixelAspectRatio: tallPixels
            ) == .init(width: 2_048, height: 2_048)
        )
    }

    @Test("encoded dimensions stay separate from display geometry")
    func encodedDimensionsRemainStable() {
        let profile = PlaybackModel.MediaProfile(
            projectionType: .equirectangular180,
            stereoLayout: .topBottom,
            hdrType: .sdr,
            resolution: .init(width: 8_192, height: 4_096),
            pixelAspectRatio: .init(horizontalSpacing: 1, verticalSpacing: 4)
        )

        #expect(profile.resolution == .init(width: 8_192, height: 4_096))
        #expect(
            profile.displayDimensions(for: .topBottom)
                == .init(width: 2_048, height: 2_048)
        )
    }

    @Test("cached profiles without sample aspect ratio remain square-pixel profiles")
    func legacyProfileDecoding() throws {
        let profile = PlaybackModel.MediaProfile(
            projectionType: .flat,
            hdrType: .sdr,
            resolution: .init(width: 1_920, height: 1_080)
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))
                as? [String: Any]
        )
        object.removeValue(forKey: "sampleAspectRatio")

        let decoded = try JSONDecoder().decode(
            PlaybackModel.MediaProfile.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.pixelAspectRatio == .square)
    }

    @Test("non-square sample aspect ratio survives profile persistence")
    func profileRoundTrip() throws {
        let profile = PlaybackModel.MediaProfile(
            projectionType: .equirectangular180,
            stereoLayout: .topBottom,
            hdrType: .sdr,
            resolution: .init(width: 8_192, height: 4_096),
            pixelAspectRatio: .init(horizontalSpacing: 1, verticalSpacing: 4)
        )

        let decoded = try JSONDecoder().decode(
            PlaybackModel.MediaProfile.self,
            from: JSONEncoder().encode(profile)
        )

        #expect(decoded == profile)
        #expect(decoded.pixelAspectRatio == .init(horizontalSpacing: 1, verticalSpacing: 4))
    }
}
