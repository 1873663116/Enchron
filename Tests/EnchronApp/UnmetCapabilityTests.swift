import PlaybackFeature
import Testing

@Test("a ProRes file the device cannot decode is the only case that stops playback")
func proResIsTheOnlyPreventingCapability() {
    let found = UnmetCapability.all(
        from: PlaybackCapabilityFacts(
            codecName: "prores",
            rendererFailedToDecode: true
        )
    )
    #expect(found.count == 1)
    #expect(found.first?.preventsPlayback == true)
    #expect(found.first?.reason.contains("no ProRes decoder") == true)
}

@Test("ProRes that decodes is not reported, so the codec name alone never accuses")
func proResThatDecodesIsSilent() {
    let found = UnmetCapability.all(
        from: PlaybackCapabilityFacts(codecName: "prores", rendererFailedToDecode: false)
    )
    #expect(found.isEmpty)
}

@Test("a second view that was lost is reported without stopping playback")
func flattenedMultiviewIsPersistentOnly() {
    let found = UnmetCapability.all(
        from: PlaybackCapabilityFacts(
            codecName: "hevc",
            sourceIsMultiview: true,
            deliveredIsMultiview: false
        )
    )
    #expect(found.map(\.id) == ["video.multiviewFlattened"])
    #expect(found.allSatisfy { $0.preventsPlayback == false })
}

@Test("multiview that survived to the renderer reports nothing")
func intactMultiviewIsSilent() {
    let found = UnmetCapability.all(
        from: PlaybackCapabilityFacts(
            codecName: "hevc",
            sourceIsMultiview: true,
            deliveredIsMultiview: true
        )
    )
    #expect(found.isEmpty)
}

@Test("retired audio carries the reason PlaybackCore gave rather than a guess")
func retiredAudioPrefersTheReportedReason() {
    let found = UnmetCapability.all(
        from: PlaybackCapabilityFacts(
            audioRetired: true,
            audioRetirementReason: "The audio track is DTS, which this device cannot decode."
        )
    )
    #expect(found.map(\.id) == ["audio.retired"])
    #expect(found.first?.reason.contains("DTS") == true)
}

@Test("several unmet capabilities coexist and only the picture one interrupts")
func onlyThePictureCaseInterrupts() {
    let found = UnmetCapability.all(
        from: PlaybackCapabilityFacts(
            codecName: "prores",
            sourceIsMultiview: true,
            deliveredIsMultiview: false,
            audioRetired: true,
            rendererFailedToDecode: true
        )
    )
    #expect(found.count == 3)
    #expect(found.filter(\.preventsPlayback).count == 1)
}
