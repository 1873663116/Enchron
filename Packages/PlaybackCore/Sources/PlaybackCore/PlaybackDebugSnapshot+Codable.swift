import Foundation


private enum PlaybackDebugSnapshotV1CodingKey: String, CodingKey {
    case schemaVersion
    case generatedAt
    case lifecycle
    case mediaSession
    case lastMediaSession
    case lastOpenRejection
    case lastControlRejection
    case lastFailure
    case currentOperation
    case lastCompletedOperation
    case lastOpenOperation
    case providerOpen
    case videoTrack
    case availableAudioTracks
    case audioTrack
    case subtitleState
    case lastMediaEvent
    case lastVideoSample
    case lastAudioSample
    case lastRendererInput
    case lastAcceptedRendererInput
    case rendererState
    case audioRendererState
    case realityKitBinding
    case presentationBinding
    case presentationState
    case platform
    case hardwareDisplayFacts
    case evidenceCorrelationIDs
    case streamEpoch
    case formatRevision
    case sampleCount
    case audioSampleBufferCount
    case acceptedRendererInputCount
    case backpressureCount
    case staleRejectionCount
    case lastError
}

extension PlaybackDebugSnapshotV1 {

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: PlaybackDebugSnapshotV1CodingKey.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        lifecycle = try container.decode(PlaybackLifecycle.self, forKey: .lifecycle)
        mediaSession = try container.decodeIfPresent(
            MediaSessionDebugSummary.self,
            forKey: .mediaSession
        )
        lastMediaSession = try container.decodeIfPresent(
            MediaSessionDebugSummary.self,
            forKey: .lastMediaSession
        )
        lastOpenRejection = try container.decodeIfPresent(
            OpenRejectionRecord.self,
            forKey: .lastOpenRejection
        )
        lastControlRejection = try container.decodeIfPresent(
            ControlRejectionRecord.self,
            forKey: .lastControlRejection
        )
        lastFailure = try container.decodeIfPresent(
            PlaybackFailureRecord.self,
            forKey: .lastFailure
        )
        currentOperation = try container.decodeIfPresent(
            PlaybackOperationRecord.self,
            forKey: .currentOperation
        )
        lastCompletedOperation = try container.decodeIfPresent(
            PlaybackOperationRecord.self,
            forKey: .lastCompletedOperation
        )
        lastOpenOperation = try container.decodeIfPresent(
            PlaybackOperationRecord.self,
            forKey: .lastOpenOperation
        )
        providerOpen = try container.decodeIfPresent(
            ProviderOpenSnapshot.self,
            forKey: .providerOpen
        )
        videoTrack = try container.decodeIfPresent(VideoTrackRecord.self, forKey: .videoTrack)
        availableAudioTracks = try container.decodeIfPresent(
            [PlaybackAudioTrack].self,
            forKey: .availableAudioTracks
        ) ?? []
        audioTrack = try container.decodeIfPresent(AudioTrackRecord.self, forKey: .audioTrack)
        subtitleState = try container.decodeIfPresent(
            SubtitleStateRecord.self,
            forKey: .subtitleState
        )
        lastMediaEvent = try container.decodeIfPresent(
            MediaEventRecord.self,
            forKey: .lastMediaEvent
        )
        lastVideoSample = try container.decodeIfPresent(
            VideoSampleRecord.self,
            forKey: .lastVideoSample
        )
        lastAudioSample = try container.decodeIfPresent(
            AudioSampleRecord.self,
            forKey: .lastAudioSample
        )
        lastRendererInput = try container.decodeIfPresent(
            RendererInputRecord.self,
            forKey: .lastRendererInput
        )
        lastAcceptedRendererInput = try container.decodeIfPresent(
            RendererInputRecord.self,
            forKey: .lastAcceptedRendererInput
        )
        rendererState = try container.decodeIfPresent(
            RendererStateRecord.self,
            forKey: .rendererState
        )
        audioRendererState = try container.decodeIfPresent(
            AudioRendererStateRecord.self,
            forKey: .audioRendererState
        )
        realityKitBinding = try container.decodeIfPresent(
            RealityKitBindingRecord.self,
            forKey: .realityKitBinding
        )
        presentationBinding = try container.decodeIfPresent(
            PresentationBindingRecord.self,
            forKey: .presentationBinding
        )
        presentationState = try container.decodeIfPresent(
            PresentationStateRecord.self,
            forKey: .presentationState
        )
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        hardwareDisplayFacts = try container.decode(
            FactAvailability.self,
            forKey: .hardwareDisplayFacts
        )
        evidenceCorrelationIDs = try container.decode(
            [String].self,
            forKey: .evidenceCorrelationIDs
        )
        streamEpoch = try container.decode(UInt64.self, forKey: .streamEpoch)
        formatRevision = try container.decode(UInt64.self, forKey: .formatRevision)
        sampleCount = try container.decode(UInt64.self, forKey: .sampleCount)
        audioSampleBufferCount = try container.decode(
            UInt64.self,
            forKey: .audioSampleBufferCount
        )
        acceptedRendererInputCount = try container.decode(
            UInt64.self,
            forKey: .acceptedRendererInputCount
        )
        backpressureCount = try container.decode(UInt64.self, forKey: .backpressureCount)
        staleRejectionCount = try container.decode(
            UInt64.self,
            forKey: .staleRejectionCount
        )
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}
