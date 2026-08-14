import PlaybackFeature
import Testing

@Test("a single-layer profile names itself and nothing else")
func singleLayerDolbyVisionNamesItsProfile() {
    let dolbyVision = PlaybackModel.DolbyVision(profile: 8, level: 1)
    #expect(dolbyVision.label == "Dolby Vision Profile 8.1")
}

@Test("a two-layer profile names what the picture became")
func twoLayerDolbyVisionNamesItsFallback() {
    let dolbyVision = PlaybackModel.DolbyVision(profile: 7, level: 6, fallbackTo: .hdr10)
    #expect(dolbyVision.label == "Dolby Vision Profile 7.6 Fallback to HDR10")
}

@Test("the fallback names the base layer that was actually delivered")
func theFallbackFollowsTheBaseLayer() {
    let hlgBase = PlaybackModel.DolbyVision(profile: 7, level: 6, fallbackTo: .hlg)
    #expect(hlgBase.label == "Dolby Vision Profile 7.6 Fallback to HLG")
}

@Test("a source with no Dolby Vision keeps the plain dynamic range")
func withoutDolbyVisionTheRangeStandsAlone() {
    #expect(PlaybackModel.HDRType.hdr10.label == "HDR10")
    #expect(PlaybackModel.HDRType.hlg.label == "HLG")
    #expect(PlaybackModel.HDRType.dolbyVision.label == "Dolby Vision")
}

@Test("the media profile prefers the Dolby Vision label over its delivered range")
func theProfilePrefersTheDolbyVisionLabel() {
    let profile = PlaybackModel.MediaProfile(
        projectionType: .flat,
        hdrType: .hdr10,
        dolbyVision: PlaybackModel.DolbyVision(profile: 7, level: 6, fallbackTo: .hdr10),
        resolution: .init(width: 3840, height: 2160)
    )
    #expect(profile.dolbyVision?.label == "Dolby Vision Profile 7.6 Fallback to HDR10")
    // The delivered range stays HDR10, because that is the picture, and a surface with
    // no room for the profile can still say something true.
    #expect(profile.hdrType == .hdr10)
}
