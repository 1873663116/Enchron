import Foundation

public struct VideoTrackRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var videoTrackID: String
    public var rawSourceMapping: String
    public var codecName: String
    public var sourceSnapshotID: String
    public var dimensions: String
    public var nominalFrameRate: Double
    public var timebase: ObservedStringFact
    public var formatSummary: String
    public var selected: Bool
    public var notSelectedReason: String?

    public init(
        mediaSessionID: String,
        videoTrackID: String,
        rawSourceMapping: String,
        codecName: String,
        sourceSnapshotID: String = "unknown",
        dimensions: String = "unknown",
        nominalFrameRate: Double = 0,
        timebase: ObservedStringFact = .init(.notExposed),
        formatSummary: String = "unknown",
        selected: Bool,
        notSelectedReason: String? = nil
    ) {
        self.mediaSessionID = mediaSessionID
        self.videoTrackID = videoTrackID
        self.rawSourceMapping = rawSourceMapping
        self.codecName = codecName
        self.sourceSnapshotID = sourceSnapshotID
        self.dimensions = dimensions
        self.nominalFrameRate = nominalFrameRate
        self.timebase = timebase
        self.formatSummary = formatSummary
        self.selected = selected
        self.notSelectedReason = notSelectedReason
    }
}
public struct AudioTrackRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var audioTrackID: String
    public var rawStreamIndex: Int
    public var codecName: String
    public var sampleRate: Int
    public var channelCount: Int
    public var selected: Bool

    public init(
        mediaSessionID: String,
        audioTrackID: String,
        rawStreamIndex: Int,
        codecName: String,
        sampleRate: Int,
        channelCount: Int,
        selected: Bool
    ) {
        self.mediaSessionID = mediaSessionID
        self.audioTrackID = audioTrackID
        self.rawStreamIndex = rawStreamIndex
        self.codecName = codecName
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.selected = selected
    }
}

// Where a subtitle selection ended up, as one machine state rather than
// something to be inferred from an absence. Drawing nothing is ordinary
// between cues and a defect when packets went in and no picture ever came
// out; those two used to look identical from outside, which is what made the
// zlib defect take a device session to find.
public enum SubtitleTrackOutcome: String, Codable, Equatable, Sendable {
    // Nothing is selected.
    case notSelected
    // Selected and carrying something to draw; nothing drawn yet.
    case selected
    // At least one cue or frame reached the screen.
    case producing
    // Packets reached the decoder and not one of them became a display set.
    case producedNothing
    // Selected, and the source offered neither cues nor a renderer for it.
    case unsupported
    // Given up, with the reason in the failure record that accompanies it.
    case retired
}

public struct SubtitleStateRecord: Codable, Equatable, Sendable {
    public var availableTracks: [PlaybackSubtitleTrack]
    public var selectedTrackID: PlaybackSubtitleTrack.ID?
    public var activeCueIDs: [PlaybackSubtitleCue.ID]
    public var streamEpoch: UInt64
    public var selectionGeneration: UInt64
    public var suppressesActiveCues: Bool
    public var outcome: SubtitleTrackOutcome

    public init(
        availableTracks: [PlaybackSubtitleTrack],
        selectedTrackID: PlaybackSubtitleTrack.ID?,
        activeCueIDs: [PlaybackSubtitleCue.ID],
        streamEpoch: UInt64,
        selectionGeneration: UInt64,
        suppressesActiveCues: Bool,
        outcome: SubtitleTrackOutcome = .notSelected
    ) {
        self.availableTracks = availableTracks
        self.selectedTrackID = selectedTrackID
        self.activeCueIDs = activeCueIDs
        self.streamEpoch = streamEpoch
        self.selectionGeneration = selectionGeneration
        self.suppressesActiveCues = suppressesActiveCues
        self.outcome = outcome
    }
}

public struct AudioDeliveryObservation: Codable, Equatable, Sendable {
    public var providerKind: String
    public var sourceCodecName: String
    public var mediaSubtype: String
    public var formatID: String
    public var formatFlags: UInt32
    public var sourceSampleRate: Int
    public var deliveredSampleRate: Double
    public var sourceChannelCount: Int
    public var deliveredChannelCount: UInt32
    public var bitsPerChannel: UInt32
    public var bytesPerFrame: UInt32
    public var framesPerPacket: UInt32
    public var isFloatPCM: Bool
    public var isInterleaved: Bool?
    public var channelLayoutTag: UInt32?
    public var presentationTimestampsMonotonic: Bool
    public var timestampObservationCount: UInt64
    public var trueHDDecoderInputPacketCount: UInt64?
    public var trueHDDecoderBatchCount: UInt64?
    public var trueHDAggregatedDecoderBatchCount: UInt64?
    public var trueHDOutputSampleBufferCount: UInt64?
    public var trueHDLastDecoderBatchInputPacketCount: UInt32?

    public init(
        providerKind: String,
        sourceCodecName: String,
        mediaSubtype: String,
        formatID: String,
        formatFlags: UInt32,
        sourceSampleRate: Int,
        deliveredSampleRate: Double,
        sourceChannelCount: Int,
        deliveredChannelCount: UInt32,
        bitsPerChannel: UInt32,
        bytesPerFrame: UInt32,
        framesPerPacket: UInt32,
        isFloatPCM: Bool,
        isInterleaved: Bool?,
        channelLayoutTag: UInt32?,
        presentationTimestampsMonotonic: Bool,
        timestampObservationCount: UInt64,
        trueHDDecoderInputPacketCount: UInt64? = nil,
        trueHDDecoderBatchCount: UInt64? = nil,
        trueHDAggregatedDecoderBatchCount: UInt64? = nil,
        trueHDOutputSampleBufferCount: UInt64? = nil,
        trueHDLastDecoderBatchInputPacketCount: UInt32? = nil
    ) {
        self.providerKind = providerKind
        self.sourceCodecName = sourceCodecName
        self.mediaSubtype = mediaSubtype
        self.formatID = formatID
        self.formatFlags = formatFlags
        self.sourceSampleRate = sourceSampleRate
        self.deliveredSampleRate = deliveredSampleRate
        self.sourceChannelCount = sourceChannelCount
        self.deliveredChannelCount = deliveredChannelCount
        self.bitsPerChannel = bitsPerChannel
        self.bytesPerFrame = bytesPerFrame
        self.framesPerPacket = framesPerPacket
        self.isFloatPCM = isFloatPCM
        self.isInterleaved = isInterleaved
        self.channelLayoutTag = channelLayoutTag
        self.presentationTimestampsMonotonic = presentationTimestampsMonotonic
        self.timestampObservationCount = timestampObservationCount
        self.trueHDDecoderInputPacketCount = trueHDDecoderInputPacketCount
        self.trueHDDecoderBatchCount = trueHDDecoderBatchCount
        self.trueHDAggregatedDecoderBatchCount = trueHDAggregatedDecoderBatchCount
        self.trueHDOutputSampleBufferCount = trueHDOutputSampleBufferCount
        self.trueHDLastDecoderBatchInputPacketCount =
            trueHDLastDecoderBatchInputPacketCount
    }
}

public struct AudioSampleRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var audioTrackID: String
    public var streamEpoch: UInt64
    public var rawStreamIndex: Int
    public var presentationTimeSeconds: Double
    public var durationSeconds: Double
    public var sampleRate: Int
    public var channelCount: Int
    public var sampleCount: Int
    public var payloadOwnershipState: String
    public var deliveryObservation: AudioDeliveryObservation?

    public init(
        mediaSessionID: String,
        audioTrackID: String,
        streamEpoch: UInt64,
        rawStreamIndex: Int = -1,
        presentationTimeSeconds: Double,
        durationSeconds: Double,
        sampleRate: Int = 0,
        channelCount: Int = 0,
        sampleCount: Int,
        payloadOwnershipState: String = "unknown",
        deliveryObservation: AudioDeliveryObservation? = nil
    ) {
        self.mediaSessionID = mediaSessionID
        self.audioTrackID = audioTrackID
        self.streamEpoch = streamEpoch
        self.rawStreamIndex = rawStreamIndex
        self.presentationTimeSeconds = presentationTimeSeconds
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.sampleCount = sampleCount
        self.payloadOwnershipState = payloadOwnershipState
        self.deliveryObservation = deliveryObservation
    }

    private enum CodingKeys: String, CodingKey {
        case mediaSessionID
        case audioTrackID
        case streamEpoch
        case rawStreamIndex
        case presentationTimeSeconds
        case durationSeconds
        case sampleRate
        case channelCount
        case sampleCount
        case payloadOwnershipState
        case deliveryObservation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaSessionID = try container.decode(String.self, forKey: .mediaSessionID)
        audioTrackID = try container.decode(String.self, forKey: .audioTrackID)
        streamEpoch = try container.decode(UInt64.self, forKey: .streamEpoch)
        rawStreamIndex = try container.decodeIfPresent(
            Int.self,
            forKey: .rawStreamIndex
        ) ?? -1
        presentationTimeSeconds = try container.decode(
            Double.self,
            forKey: .presentationTimeSeconds
        )
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 0
        channelCount = try container.decodeIfPresent(Int.self, forKey: .channelCount) ?? 0
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        payloadOwnershipState = try container.decodeIfPresent(
            String.self,
            forKey: .payloadOwnershipState
        ) ?? "unknown"
        deliveryObservation = try container.decodeIfPresent(
            AudioDeliveryObservation.self,
            forKey: .deliveryObservation
        )
    }
}

public struct AudioRendererStateRecord: Codable, Equatable, Sendable {
    public var mediaSessionID: String
    public var graphID: String
    public var rendererIdentity: String
    public var videoRendererIdentity: String
    public var synchronizerIdentity: String
    public var streamEpoch: UInt64
    public var enqueuedSampleBufferCount: UInt64
    public var enqueuedAudioFrameCount: UInt64
    public var status: String
    public var isReadyForMoreMediaData: Bool
    public var hasSufficientMediaDataForReliablePlaybackStart: Bool
    public var volume: Float
    public var muted: Bool
    public var error: String?

    public init(
        mediaSessionID: String,
        graphID: String = "unknown",
        rendererIdentity: String,
        videoRendererIdentity: String = "unknown",
        synchronizerIdentity: String = "unknown",
        streamEpoch: UInt64,
        enqueuedSampleBufferCount: UInt64,
        enqueuedAudioFrameCount: UInt64,
        status: String = "unknown",
        isReadyForMoreMediaData: Bool = false,
        hasSufficientMediaDataForReliablePlaybackStart: Bool = false,
        volume: Float,
        muted: Bool,
        error: String?
    ) {
        self.mediaSessionID = mediaSessionID
        self.graphID = graphID
        self.rendererIdentity = rendererIdentity
        self.videoRendererIdentity = videoRendererIdentity
        self.synchronizerIdentity = synchronizerIdentity
        self.streamEpoch = streamEpoch
        self.enqueuedSampleBufferCount = enqueuedSampleBufferCount
        self.enqueuedAudioFrameCount = enqueuedAudioFrameCount
        self.status = status
        self.isReadyForMoreMediaData = isReadyForMoreMediaData
        self.hasSufficientMediaDataForReliablePlaybackStart =
            hasSufficientMediaDataForReliablePlaybackStart
        self.volume = volume
        self.muted = muted
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case mediaSessionID
        case graphID
        case rendererIdentity
        case videoRendererIdentity
        case synchronizerIdentity
        case streamEpoch
        case enqueuedSampleBufferCount
        case enqueuedAudioFrameCount
        case status
        case isReadyForMoreMediaData
        case hasSufficientMediaDataForReliablePlaybackStart
        case volume
        case muted
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaSessionID = try container.decode(String.self, forKey: .mediaSessionID)
        graphID = try container.decodeIfPresent(String.self, forKey: .graphID) ?? "unknown"
        rendererIdentity = try container.decode(String.self, forKey: .rendererIdentity)
        videoRendererIdentity = try container.decodeIfPresent(
            String.self,
            forKey: .videoRendererIdentity
        ) ?? "unknown"
        synchronizerIdentity = try container.decodeIfPresent(
            String.self,
            forKey: .synchronizerIdentity
        ) ?? "unknown"
        streamEpoch = try container.decode(UInt64.self, forKey: .streamEpoch)
        enqueuedSampleBufferCount = try container.decode(
            UInt64.self,
            forKey: .enqueuedSampleBufferCount
        )
        enqueuedAudioFrameCount = try container.decode(
            UInt64.self,
            forKey: .enqueuedAudioFrameCount
        )
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        isReadyForMoreMediaData = try container.decodeIfPresent(
            Bool.self,
            forKey: .isReadyForMoreMediaData
        ) ?? false
        hasSufficientMediaDataForReliablePlaybackStart = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasSufficientMediaDataForReliablePlaybackStart
        ) ?? false
        volume = try container.decode(Float.self, forKey: .volume)
        muted = try container.decode(Bool.self, forKey: .muted)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}
