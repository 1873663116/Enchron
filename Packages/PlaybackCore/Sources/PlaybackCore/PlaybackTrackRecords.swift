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

public struct SubtitleStateRecord: Codable, Equatable, Sendable {
    public var availableTracks: [PlaybackSubtitleTrack]
    public var selectedTrackID: PlaybackSubtitleTrack.ID?
    public var activeCueIDs: [PlaybackSubtitleCue.ID]
    public var streamEpoch: UInt64
    public var selectionGeneration: UInt64
    public var suppressesActiveCues: Bool

    public init(
        availableTracks: [PlaybackSubtitleTrack],
        selectedTrackID: PlaybackSubtitleTrack.ID?,
        activeCueIDs: [PlaybackSubtitleCue.ID],
        streamEpoch: UInt64,
        selectionGeneration: UInt64,
        suppressesActiveCues: Bool
    ) {
        self.availableTracks = availableTracks
        self.selectedTrackID = selectedTrackID
        self.activeCueIDs = activeCueIDs
        self.streamEpoch = streamEpoch
        self.selectionGeneration = selectionGeneration
        self.suppressesActiveCues = suppressesActiveCues
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
        payloadOwnershipState: String = "unknown"
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
        volume = try container.decode(Float.self, forKey: .volume)
        muted = try container.decode(Bool.self, forKey: .muted)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}
