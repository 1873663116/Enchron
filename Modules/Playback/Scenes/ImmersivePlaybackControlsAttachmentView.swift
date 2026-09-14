import PlaybackCore
import SwiftUI

struct ImmersivePlaybackControlsAttachmentView: View {
    let presentation: PlaybackPresentation
    @Environment(PlaybackSessionModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    @Environment(SpatialPlatformEffectCoordinator.self)
    private var spatialPlatformEffectCoordinator
    @State private var isStoppingPlayback = false

    private var controlsAcceptInput: Bool {
        let issueRequiresControls = playbackRuntime.userVisibleIssue.map {
            $0.canPresent(at: .playerDeck) || $0.canPresent(at: .immersiveSpace)
        } == true
        return issueRequiresControls || ImmersivePlaybackControlsAttachmentPolicy.isVisible(
            presentation: presentation,
            controlsVisible: appModel.showControls,
            transitionIsActive: appModel.presentationTransition != nil
        )
    }

    var body: some View {
        WindowPlayerDeckView(
            presentationOverride: presentation,
            onExitPlayback: { Task { await stopSpatialPlayback() } }
        )
        .opacity(controlsAcceptInput ? 1 : 0)
        .allowsHitTesting(controlsAcceptInput)
        .accessibilityHidden(controlsAcceptInput == false)
        .disabled(isStoppingPlayback)
        .onChange(of: controlsAcceptInput, initial: true) { _, visible in
            appModel.recordSurfaceInputProbe(
                "immersiveControlsAttachment visible=\(visible) scope=attachment"
            )
        }
        .overlay {
            if ProcessInfo.processInfo.environment["ENCHRON_SPATIAL_ACCEPTANCE"] == "1" {
                Text("Spatial playback state")
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("PlayerUI-spatial-state")
                    .accessibilityValue(spatialAcceptanceValue)
            }
        }
    }

    private var spatialAcceptanceValue: String {
        let position = playbackRuntime.playbackPosition
        let output = playbackRuntime.outputObservation()
        let debugSnapshot = playbackRuntime.debugSnapshot()
        let lastRendererInputEpoch = debugSnapshot?.lastAcceptedRendererInput
            .map { String($0.streamEpoch) } ?? "none"
        let lastRendererInputGraphRevision = debugSnapshot?.lastAcceptedRendererInput
            .map { String($0.graphRevision) } ?? "none"
        let lastRendererInputFormatRevision = debugSnapshot?.lastAcceptedRendererInput
            .map { String($0.formatRevision) } ?? "none"
        let providerProjectionKind = debugSnapshot?.providerOpen?.formatSignaling
            .projectionKind.value
            ?? debugSnapshot?.providerOpen.map {
                String(describing: $0.formatSignaling.projectionKind.availability)
            }
            ?? "none"
        let sampleProjectionKind = debugSnapshot?.lastVideoSample?.formatSignaling
            .projectionKind.value
            ?? debugSnapshot?.lastVideoSample.map {
                String(describing: $0.formatSignaling.projectionKind.availability)
            }
            ?? "none"
        let rendererProjectionKind = debugSnapshot?.lastAcceptedRendererInput?
            .formatSignaling?.projectionKind.value ?? "none"
        let rendererViewPackingKind = debugSnapshot?.lastAcceptedRendererInput?
            .formatSignaling?.viewPackingKind.value ?? "none"
        let providerTransferFunction = debugSnapshot?.providerOpen?.formatSignaling
            .transferFunction.value
            ?? debugSnapshot?.providerOpen.map {
                String(describing: $0.formatSignaling.transferFunction.availability)
            }
            ?? "none"
        let presentationRecord = debugSnapshot?.presentationState
        let displayedFrameObservations = (
            debugSnapshot?.rendererState?.displayedFrameObservationCount
        ).map(String.init) ?? "none"
        let environment = PlaybackStateAccessibility.environmentAccessibilityValues(
            for: appModel.environmentContext
        )
        let panoramaReturnEnvironment = PlaybackStateAccessibility.environmentAccessibilityValues(
            for: appModel.panoramaReturnEnvironmentContext
        )
        let immersionAmount = appModel.lastObservedImmersionAmount.map {
            String($0)
        } ?? "none"
        let skyboxOpacity = appModel.environmentSkyboxOpacity.map {
            String(format: "%.4f", $0)
        } ?? "none"
        var fields: [String] = [
            "presentation=\(appModel.playbackPresentation.rawValue)",
            "transition=\(appModel.presentationTransition?.targetPresentation.rawValue ?? "none")",
            "controls=\(appModel.showControls ? "shown" : "hidden")",
            "controlsInteractive=\(controlsAcceptInput)",
            "controlsOpacityTarget=\(controlsAcceptInput ? 1 : 0)",
            "sourceRendererMayRelease=\(appModel.presentationSourceRendererMayRelease)",
            "targetRendererMayBind=\(appModel.presentationTargetRendererMayBind)",
            "immersiveSpaceResidency=\(String(describing: appModel.immersiveSpaceResidency))",
            "immersiveSpaceLifecycleRevision=\(appModel.immersiveSpaceLifecycleRevision)",
            "environmentCardResidency=\(String(describing: appModel.environmentCardResidency))",
            "environment=\(environment.environment)",
            "environmentEffect=\(environment.effect)",
            "panoramaReturnEnvironment=\(panoramaReturnEnvironment.environment)",
            "panoramaReturnEnvironmentEffect=\(panoramaReturnEnvironment.effect)",
            "immersionAmount=\(immersionAmount)",
            "skyboxOpacity=\(skyboxOpacity)",
            "skyboxActive=\(appModel.environmentSkyboxIsActive)",
            "surfacePreparation=\(appModel.spatialPlaybackSurfacePreparationStage.replacingOccurrences(of: ";", with: ","))",
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "residency=\(playbackRuntime.residency.probeDescription)",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "rendererConsumer=\(playbackRuntime.rendererConsumerPresentation?.rawValue ?? "none")",
            "rendererConsumerEntity=\(playbackRuntime.rendererConsumerEntityID == nil ? "none" : "present")",
            "playbackEntity=\(playbackVideoEntityStore.entityID)",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "technicalSession=\(playbackRuntime.activeTechnicalSessionID ?? "none")",
            "technicalSessionReplacementStage=\(playbackRuntime.technicalSessionReplacementStage.rawValue)",
            "seekInProgress=\(playbackRuntime.seekIsInProgress)",
            "liveTechnicalSessions=\(playbackRuntime.liveTechnicalSessionCount)",
            "retiringTechnicalSessions=\(playbackRuntime.retiringTechnicalSessionCount)",
            "position=\(position.seconds)",
            "duration=\(position.duration)",
            "streamEpoch=\(output.streamEpoch)",
            "videoSamples=\(output.videoSampleCount)",
            "rendererInputs=\(output.acceptedRendererInputCount)",
            "lastRendererInputEpoch=\(lastRendererInputEpoch)",
            "lastRendererInputGraphRevision=\(lastRendererInputGraphRevision)",
            "lastRendererInputFormatRevision=\(lastRendererInputFormatRevision)",
            "providerProjectionKind=\(providerProjectionKind)",
            "sampleProjectionKind=\(sampleProjectionKind)",
            "rendererProjectionKind=\(rendererProjectionKind)",
            "rendererViewPackingKind=\(rendererViewPackingKind)",
            "providerCodecName=\(debugSnapshot?.providerOpen?.codecName ?? "none")",
            "providerCodecTag=\(debugSnapshot?.providerOpen?.codecTag ?? "none")",
            "providerCodecConfiguration=\(debugSnapshot?.providerOpen?.codecConfigurationSummary.value ?? "none")",
            "sampleMediaSubtype=\(debugSnapshot?.lastVideoSample?.mediaSubtype ?? "none")",
            "providerTransferFunction=\(providerTransferFunction)",
            "sampleHasLhvC=\(debugSnapshot?.lastVideoSample?.formatSignaling.lhvC.value.map(String.init) ?? "none")",
            "rendererHasLhvC=\(debugSnapshot?.lastAcceptedRendererInput?.formatSignaling?.lhvC.value.map(String.init) ?? "none")",
            "rendererInputIsMultiview=\(playbackRuntime.diagnostics.rendererInputIsMultiview.map(String.init) ?? "none")",
            "sampleHasDvcC=\(debugSnapshot?.lastVideoSample?.formatSignaling.dvcC.value.map(String.init) ?? "none")",
            "sampleHasDvvC=\(debugSnapshot?.lastVideoSample?.formatSignaling.dvvC.value.map(String.init) ?? "none")",
            "formatProvenance=\(playbackRuntime.activeMediaFormatProvenance.rawValue)",
            "sourceContentKind=\(playbackRuntime.sourceVideoContentKind.rawValue)",
            "projection=\(playbackRuntime.effectiveProjectionType.rawValue)",
            "stereoLayout=\(playbackRuntime.effectiveStereoLayout.rawValue)",
            "mvHEVC=\(playbackRuntime.diagnostics.isMVHEVC)",
            "effectiveContentIsPanoramic=\(playbackRuntime.effectiveContentIsPanoramic)",
            "windowComponentContentType=\(playbackVideoEntityStore.realityKitContentType)",
            "corePresentationMode=\(presentationRecord?.requestedMode ?? "none")",
            "corePresentationPhase=\(presentationRecord?.phase ?? "none")",
            "corePresentationComponentStatus=\(presentationRecord?.componentRenderingStatus?.value ?? "none")",
            "corePresentationDisplayedPixel=\(presentationRecord?.displayedPixelBuffer.map(String.init) ?? "none")",
            "displayedFrameObservations=\(displayedFrameObservations)",
            "desiredImmersiveMode=\(output.desiredImmersiveViewingMode ?? "none")",
            "actualImmersiveMode=\(output.actualImmersiveViewingMode ?? "none")",
            "desiredViewingMode=\(output.desiredViewingMode ?? "none")",
            "actualViewingMode=\(output.actualViewingMode ?? "none")",
            "desiredSpatialVideoMode=\(output.desiredSpatialVideoMode ?? "none")",
            "actualSpatialVideoMode=\(output.actualSpatialVideoMode ?? "none")",
            "error=\(playbackRuntime.userVisibleIssue?.category.rawValue ?? "none")",
            "videoRendererStatus=\(playbackRuntime.diagnostics.rendererStatus)",
            "videoRendererError=\(playbackRuntime.diagnostics.rendererError)",
            "bootstrapComplete=\(output.decoderBootstrapComplete)",
            "targetRate=\(output.requestedPlaybackRate)",
            "actualRate=\(output.actualTimebaseRate)",
            "componentReady=\(output.videoComponentReady)",
            "displayedPixel=\(output.displayedPixelBuffer)",
            "videoComponentRevision=\(playbackRuntime.videoComponentRevision)",
            "boundVideoComponentRevision=\(playbackRuntime.boundVideoComponentRevision.map(String.init) ?? "none")",
            "rendererPixelVideoComponentRevision=\(playbackRuntime.rendererPixelVideoComponentRevision.map(String.init) ?? "none")",
            "rendererPixelStreamEpoch=\(playbackRuntime.rendererPixelStreamEpoch.map(String.init) ?? "none")",
            "hasAudio=\(output.hasAudio)",
            "audioSamples=\(output.audioSampleBufferCount)",
            "audioRendererSamples=\(output.audioRendererSampleBufferCount)",
            "audioRendererEpoch=\(output.audioRendererStreamEpoch)",
            "audioRendererStatus=\(output.audioRendererStatus)",
            "audioRendererVolume=\(output.audioRendererVolume)",
            "audioRendererMuted=\(output.audioRendererMuted)",
            "audioRendererError=\(output.audioRendererError ?? "none")",
            "audioSessionCategory=\(output.audioSessionCategory)",
            "audioSessionMode=\(output.audioSessionMode)",
            "audioOutputPorts=\(output.audioSessionOutputPortTypes.joined(separator: ","))",
            "systemOutputVolume=\(output.systemOutputVolume)",
            "audioSessionActive=\(output.audioSessionActive)",
            "subtitleTracks=\(playbackRuntime.availableSubtitleTracks.count)",
            "subtitleTrack=\(playbackRuntime.currentSubtitleTrackID ?? "off")",
            "subtitleCues=\(playbackRuntime.activeSubtitleCues.count)",
            "screenScale=\(String(format: "%.4f", appModel.screenScale))",
            "viewerHeight=\(String(format: "%.4f", appModel.viewerHeight))",
            "screenDistance=\(String(format: "%.4f", appModel.screenDepthOffset))",
            "screenElevation=\(String(format: "%.4f", appModel.screenViewAngle))",
            "registeredPlatformExecutorCount=\(spatialPlatformEffectCoordinator.registeredPlatformExecutorCount)",
            "lastPlatformOperation=\(spatialPlatformEffectCoordinator.lastPlatformOperation)",
            "lastExecutionCheckpoint=\(spatialPlatformEffectCoordinator.lastExecutionCheckpoint)",
            "executionAttemptCount=\(spatialPlatformEffectCoordinator.executionAttemptCount)",
            "lastExecutionResolution=\(spatialPlatformEffectCoordinator.lastExecutionResolution)",
            "playerWindowObservedResidency=\(spatialPlatformEffectCoordinator.playerWindowObservedResidency)",
            "playerWindowObservationRevision=\(spatialPlatformEffectCoordinator.playerWindowObservationRevision)"
        ]
        fields.append(contentsOf: PlaybackStateAccessibility.rendererPerformanceAccessibilityFields(
            playbackRuntime.diagnostics
        ))
        fields.append(contentsOf: PlaybackStateAccessibility.deliveryAccessibilityFields(
            diagnostics: playbackRuntime.diagnostics,
            debugSnapshot: debugSnapshot
        ))
        return (fields + appModel.spatialPlaybackSurfaceObservation.accessibilityFields)
            .joined(separator: ";")
    }

    @MainActor
    private func stopSpatialPlayback() async {
        guard isStoppingPlayback == false else { return }
        isStoppingPlayback = true
        defer { isStoppingPlayback = false }

        await playbackLauncher.stopPlaybackAndWait(reason: .backButton)
        appModel.requestStoppedPlaybackCleanup()
    }

}

public enum PlaybackStateAccessibility {
    public static func deliveryAccessibilityFields(
        diagnostics: PlaybackDiagnostics,
        debugSnapshot: PlaybackDebugSnapshotV1?
    ) -> [String] {
        let source = debugSnapshot?.providerOpen?.formatSignaling
        let sample = debugSnapshot?.lastVideoSample?.formatSignaling
        let renderer = debugSnapshot?.lastAcceptedRendererInput?.formatSignaling
        let audioSample = debugSnapshot?.lastAudioSample
        let audio = audioSample?.deliveryObservation
        return [
            "sourceFormatProvenance=\(source?.provenance ?? "none")",
            "sourceColorPrimaries=\(stringFact(source?.colorPrimaries))",
            "sourceTransferFunction=\(stringFact(source?.transferFunction))",
            "sourceYCbCrMatrix=\(stringFact(source?.yCbCrMatrix))",
            "sourceRange=\(stringFact(source?.range))",
            "sourceMasteringDisplayMetadata=\(booleanFact(source?.masteringDisplayMetadata))",
            "sourceContentLightLevelMetadata=\(booleanFact(source?.contentLightLevelMetadata))",
            "sampleFormatProvenance=\(sample?.provenance ?? "none")",
            "sampleColorPrimaries=\(stringFact(sample?.colorPrimaries))",
            "sampleTransferFunction=\(stringFact(sample?.transferFunction))",
            "sampleYCbCrMatrix=\(stringFact(sample?.yCbCrMatrix))",
            "sampleRange=\(stringFact(sample?.range))",
            "sampleMasteringDisplayMetadata=\(booleanFact(sample?.masteringDisplayMetadata))",
            "sampleContentLightLevelMetadata=\(booleanFact(sample?.contentLightLevelMetadata))",
            "rendererFormatProvenance=\(renderer?.provenance ?? "none")",
            "rendererTransferFunction=\(stringFact(renderer?.transferFunction))",
            "rendererColorPrimaries=\(stringFact(renderer?.colorPrimaries))",
            "rendererYCbCrMatrix=\(stringFact(renderer?.yCbCrMatrix))",
            "rendererRange=\(stringFact(renderer?.range))",
            "rendererMasteringDisplayMetadata=\(booleanFact(renderer?.masteringDisplayMetadata))",
            "rendererContentLightLevelMetadata=\(booleanFact(renderer?.contentLightLevelMetadata))",
            "sourcePixelFormat=\(diagnostics.sourcePixelFormat)",
            "destinationPixelFormat=\(diagnostics.destinationPixelFormat)",
            "dolbyVisionProfile=\(diagnostics.dolbyVisionProfile)",
            "dolbyVisionCrossCompatibilityID=\(diagnostics.dolbyVisionCrossCompatibilityID)",
            "dolbyVisionHasEnhancementLayer=\(diagnostics.dolbyVisionHasEnhancementLayer)",
            "sourceHasDvcC=\(booleanFact(source?.dvcC))",
            "sourceHasDvvC=\(booleanFact(source?.dvvC))",
            "rendererHasDvcC=\(booleanFact(renderer?.dvcC))",
            "rendererHasDvvC=\(booleanFact(renderer?.dvvC))",
            "audioProviderKind=\(audio?.providerKind ?? "none")",
            "audioSourceCodec=\(audio?.sourceCodecName ?? "none")",
            "audioSourceSampleRate=\(audio.map { String($0.sourceSampleRate) } ?? "none")",
            "audioSourceChannelCount=\(audio.map { String($0.sourceChannelCount) } ?? "none")",
            "audioDeliveryMediaSubtype=\(audio?.mediaSubtype ?? "none")",
            "audioDeliveryFormatID=\(audio?.formatID ?? "none")",
            "audioDeliveryFormatFlags=\(audio.map { String($0.formatFlags) } ?? "none")",
            "audioDeliverySampleRate=\(audio.map { String($0.deliveredSampleRate) } ?? "none")",
            "audioDeliveryChannelCount=\(audio.map { String($0.deliveredChannelCount) } ?? "none")",
            "audioDeliveryBitsPerChannel=\(audio.map { String($0.bitsPerChannel) } ?? "none")",
            "audioDeliveryBytesPerFrame=\(audio.map { String($0.bytesPerFrame) } ?? "none")",
            "audioDeliveryFramesPerPacket=\(audio.map { String($0.framesPerPacket) } ?? "none")",
            "audioDeliveryIsFloatPCM=\(audio.map { String($0.isFloatPCM) } ?? "none")",
            "audioDeliveryIsInterleaved=\(audio?.isInterleaved.map(String.init) ?? "none")",
            "audioDeliveryChannelLayoutTag=\(audio?.channelLayoutTag.map(String.init) ?? "none")",
            "audioDeliverySampleCount=\(audioSample.map { String($0.sampleCount) } ?? "none")",
            "audioDeliveryPresentationTime=\(audioSample.map { String($0.presentationTimeSeconds) } ?? "none")",
            "audioDeliveryTimestampsMonotonic=\(audio.map { String($0.presentationTimestampsMonotonic) } ?? "none")",
            "audioDeliveryTimestampObservationCount=\(audio.map { String($0.timestampObservationCount) } ?? "none")",
            "audioTrueHDDecoderInputPacketCount=\(audio?.trueHDDecoderInputPacketCount.map(String.init) ?? "none")",
            "audioTrueHDDecoderBatchCount=\(audio?.trueHDDecoderBatchCount.map(String.init) ?? "none")",
            "audioTrueHDAggregatedDecoderBatchCount=\(audio?.trueHDAggregatedDecoderBatchCount.map(String.init) ?? "none")",
            "audioTrueHDOutputSampleBufferCount=\(audio?.trueHDOutputSampleBufferCount.map(String.init) ?? "none")",
            "audioTrueHDLastDecoderBatchInputPacketCount=\(audio?.trueHDLastDecoderBatchInputPacketCount.map(String.init) ?? "none")"
        ]
    }

    public static func rendererPerformanceAccessibilityFields(
        _ diagnostics: PlaybackDiagnostics
    ) -> [String] {
        [
            "sourceFrameRate=\(diagnostics.nominalFrameRate)",
            "rendererTotalFrames=\(diagnostics.rendererTotalFrameCount.map { String($0) } ?? "none")",
            "rendererDroppedFrames=\(diagnostics.rendererDroppedFrameCount.map { String($0) } ?? "none")",
            "rendererCorruptedFrames=\(diagnostics.rendererCorruptedFrameCount.map { String($0) } ?? "none")",
            "rendererOptimizedFrames=\(diagnostics.rendererOptimizedCompositingFrameCount.map { String($0) } ?? "none")",
            "rendererAccumulatedFrameDelay=\(diagnostics.rendererAccumulatedFrameDelaySeconds.map { String($0) } ?? "none")",
            "rendererMetricsObservations=\(diagnostics.rendererPerformanceMetricsObservationCount)"
        ]
    }

    public static func environmentAccessibilityValues(
        for context: EnvironmentContext?
    ) -> (environment: String, effect: String) {
        switch context {
        case nil:
            ("inactive", "none")
        case .some(.none):
            ("none", "none")
        case .some(.active(let environment, let effect)):
            (environment.rawValue, effect?.rawValue ?? "none")
        }
    }

    private static func stringFact(_ fact: ObservedStringFact?) -> String {
        guard let fact else { return "none" }
        return fact.value ?? String(describing: fact.availability)
    }

    private static func booleanFact(_ fact: ObservedBooleanFact?) -> String {
        guard let fact else { return "none" }
        return fact.value.map(String.init)
            ?? String(describing: fact.availability)
    }
}
