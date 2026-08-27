import Playback
import Testing

@Test("a single-layer profile names itself and nothing else")
func singleLayerDolbyVisionNamesItsProfile() {
    let dolbyVision = PlaybackModel.DolbyVision(profile: 8, crossCompatibilityID: 1)
    #expect(dolbyVision.label == "Dolby Vision Profile 8.1")
}

@Test("a two-layer profile names what the picture became")
func twoLayerDolbyVisionNamesItsFallback() {
    let dolbyVision = PlaybackModel.DolbyVision(
        profile: 7,
        crossCompatibilityID: 6,
        fallbackTo: .hdr10
    )
    #expect(dolbyVision.label == "Dolby Vision Profile 7.6 Fallback to HDR10")
}

@Test("the fallback names the base layer that was actually delivered")
func theFallbackFollowsTheBaseLayer() {
    let hlgBase = PlaybackModel.DolbyVision(
        profile: 7,
        crossCompatibilityID: 6,
        fallbackTo: .hlg
    )
    #expect(hlgBase.label == "Dolby Vision Profile 7.6 Fallback to HLG")
}

@Test("the second digit is the cross compatibility, not the level")
func theSecondDigitIsTheCrossCompatibility() {
    let hlgCompatible = PlaybackModel.DolbyVision(profile: 8, crossCompatibilityID: 4)
    #expect(hlgCompatible.label == "Dolby Vision Profile 8.4")
}

@Test("a high level does not invent a profile that does not exist")
func aHighLevelDoesNotInventAProfile() {
    let hdr10Compatible = PlaybackModel.DolbyVision(profile: 8, crossCompatibilityID: 1)
    #expect(hdr10Compatible.label == "Dolby Vision Profile 8.1")
}

@Test("a profile compatible with nothing has no second digit")
func aProfileCompatibleWithNothingHasNoSecondDigit() {
    let profileFive = PlaybackModel.DolbyVision(profile: 5, crossCompatibilityID: 0)
    #expect(profileFive.label == "Dolby Vision Profile 5")
}

@Test("only a compatible single-layer declaration offers a user fallback")
func fallbackAvailabilityFollowsTheDeclarationShape() {
    #expect(
        PlaybackModel.DolbyVision(
            profile: 8,
            crossCompatibilityID: 1
        ).offersUserSelectableFallback
    )
    #expect(
        !PlaybackModel.DolbyVision(
            profile: 5,
            crossCompatibilityID: 0
        ).offersUserSelectableFallback
    )
    #expect(
        !PlaybackModel.DolbyVision(
            profile: 7,
            crossCompatibilityID: 6,
            fallbackTo: .hdr10
        ).offersUserSelectableFallback
    )
}

@Test("a fallback still reads after a profile with no second digit")
func aFallbackReadsAfterAProfileWithNoSecondDigit() {
    let profileFive = PlaybackModel.DolbyVision(
        profile: 5,
        crossCompatibilityID: 0,
        fallbackTo: .hdr10
    )
    #expect(profileFive.label == "Dolby Vision Profile 5 Fallback to HDR10")
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
        dolbyVision: PlaybackModel.DolbyVision(
            profile: 7,
            crossCompatibilityID: 6,
            fallbackTo: .hdr10
        ),
        resolution: .init(width: 3840, height: 2160)
    )
    #expect(profile.dolbyVision?.label == "Dolby Vision Profile 7.6 Fallback to HDR10")
    #expect(profile.hdrType == .hdr10)
}
