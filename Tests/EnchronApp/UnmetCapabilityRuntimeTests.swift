import Foundation
import PlaybackCore
import PlaybackFeature
import Testing
@testable import Enchron

@MainActor
@Test("PlaybackRuntime maps the published delivery facts without interpreting diagnostic text")
func runtimeMapsPublishedCapabilityFacts() {
    var diagnostics = PlaybackDiagnostics()
    diagnostics.codecName = "hevc"
    diagnostics.isMVHEVC = true
    diagnostics.rendererInputIsMultiview = false
    diagnostics.audioRetired = true
    diagnostics.audioRetirementReason = "The selected audio track could not be decoded."

    let facts = PlaybackRuntime.capabilityFacts(from: diagnostics)

    #expect(facts.codecName == "hevc")
    #expect(facts.sourceIsMultiview)
    #expect(facts.deliveredIsMultiview == false)
    #expect(facts.audioRetired)
    #expect(facts.audioRetirementReason == diagnostics.audioRetirementReason)
    #expect(facts.rendererFailedToDecode == false)
}

@MainActor
@Test("multiview loss is not reported before a renderer input publishes delivery")
func runtimeWaitsForRendererInputBeforeReportingFlattening() {
    var diagnostics = PlaybackDiagnostics()
    diagnostics.codecName = "hevc"
    diagnostics.isMVHEVC = true

    let facts = PlaybackRuntime.capabilityFacts(from: diagnostics)

    #expect(UnmetCapability.all(from: facts).isEmpty)
}

@MainActor
@Test("a preventing capability replaces the renderer's diagnostic wording")
func preventingCapabilitySuppressesRendererDiagnosticText() {
    let controller = PlaybackCoreController()
    let runtime = PlaybackRuntime(controller: controller)
    var diagnostics = PlaybackDiagnostics()
    diagnostics.codecName = "prores"
    diagnostics.rendererFailedToDecode = true
    diagnostics.rendererError = "Cannot Decode"
    controller.onDiagnosticsChange?(diagnostics)
    controller.onStatusChange?(.failed("Cannot Decode"))

    #expect(runtime.unmetCapabilities.first?.reason.contains("ProRes decoder") == true)
    #expect(runtime.lastErrorMessage == nil)
    #expect(runtime.diagnostics.rendererError == "Cannot Decode")
}

@MainActor
@Test("overview remains source-neutral metadata and resets for a local request")
func overviewFlowsThroughRuntimeMetadataWithoutSourceBranching() throws {
    let runtime = PlaybackRuntime()
    let serverURL = try #require(URL(string: "https://example.invalid/video.mp4"))
    let serverRequest = PlaybackLaunchRequest(
        url: serverURL,
        displayName: "Episode",
        initialMetadata: PlaybackMediaMetadata(overview: "Episode overview")
    )
    runtime.prepareForPlayback(serverRequest)
    #expect(runtime.overview == "Episode overview")

    let localRequest = PlaybackLaunchRequest(
        url: URL(fileURLWithPath: "/Volumes/Cortisol/Media/local.mp4"),
        displayName: "local.mp4"
    )
    runtime.prepareForPlayback(localRequest)
    #expect(runtime.overview == nil)
}

@MainActor
@Test("starting another request clears capability facts from the previous session")
func preparingPlaybackClearsPreviousCapabilityFacts() {
    let controller = PlaybackCoreController()
    let runtime = PlaybackRuntime(controller: controller)
    var diagnostics = PlaybackDiagnostics()
    diagnostics.codecName = "prores"
    diagnostics.rendererFailedToDecode = true
    controller.onDiagnosticsChange?(diagnostics)
    #expect(runtime.unmetCapabilities.first?.preventsPlayback == true)

    runtime.prepareForPlayback(
        PlaybackLaunchRequest(
            url: URL(fileURLWithPath: "/Volumes/Cortisol/Media/next.mp4"),
            displayName: "next.mp4"
        )
    )
    #expect(runtime.unmetCapabilities.isEmpty)
}
