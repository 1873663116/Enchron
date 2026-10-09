import Foundation
import MediaSource

public struct MediaServerServerID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct MediaServerUserID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct MediaServerItemID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct MediaServerMediaSourceID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct MediaServerPlaySessionID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct MediaServerImageTag: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct MediaServerClientIdentity: Equatable, Hashable, Sendable {
    public let name: String
    public let version: String
    public let deviceName: String
    public let deviceID: String

    public init(name: String, version: String, deviceName: String, deviceID: String) {
        self.name = name
        self.version = version
        self.deviceName = deviceName
        self.deviceID = deviceID
    }
}

public struct MediaServerAuthenticatedServer: Equatable, Hashable, Sendable {
    public let kind: MediaServerKind
    public let id: MediaServerServerID
    public let name: String
    public let baseAddress: URL
    public let accessToken: String
    public let userID: MediaServerUserID

    public init(
        kind: MediaServerKind = .emby,
        id: MediaServerServerID,
        name: String,
        baseAddress: URL,
        accessToken: String,
        userID: MediaServerUserID
    ) {
        self.kind = kind
        self.id = id
        self.name = name
        self.baseAddress = baseAddress
        self.accessToken = accessToken
        self.userID = userID
    }
}

public struct EmbyPublicSystemInfo: Codable, Equatable, Hashable, Sendable {
    public let id: MediaServerServerID
    public let serverName: String
    public let version: String
    public let localAddresses: [String]
    public let remoteAddresses: [String]

    public init(
        id: MediaServerServerID,
        serverName: String,
        version: String,
        localAddresses: [String],
        remoteAddresses: [String]
    ) {
        self.id = id
        self.serverName = serverName
        self.version = version
        self.localAddresses = localAddresses
        self.remoteAddresses = remoteAddresses
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(MediaServerServerID.self, forKey: .id)
        serverName = try values.decode(String.self, forKey: .serverName)
        version = try values.decode(String.self, forKey: .version)
        localAddresses = try values.decodeIfPresent([String].self, forKey: .localAddresses) ?? []
        remoteAddresses = try values.decodeIfPresent([String].self, forKey: .remoteAddresses) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case serverName = "ServerName"
        case version = "Version"
        case localAddresses = "LocalAddresses"
        case remoteAddresses = "RemoteAddresses"
    }
}

public struct EmbyPublicUser: Codable, Equatable, Hashable, Sendable {
    public let id: MediaServerUserID
    public let name: String
    public let serverID: MediaServerServerID
    public let hasPassword: Bool
    public let hasConfiguredPassword: Bool

    public init(
        id: MediaServerUserID,
        name: String,
        serverID: MediaServerServerID,
        hasPassword: Bool,
        hasConfiguredPassword: Bool
    ) {
        self.id = id
        self.name = name
        self.serverID = serverID
        self.hasPassword = hasPassword
        self.hasConfiguredPassword = hasConfiguredPassword
    }

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case serverID = "ServerId"
        case hasPassword = "HasPassword"
        case hasConfiguredPassword = "HasConfiguredPassword"
    }
}

public struct MediaServerImageTags: Equatable, Hashable, Sendable {
    public let primary: MediaServerImageTag?
    public let logo: MediaServerImageTag?
    public let thumb: MediaServerImageTag?
    public let backdrops: [MediaServerImageTag]

    public init(
        primary: MediaServerImageTag? = nil,
        logo: MediaServerImageTag? = nil,
        thumb: MediaServerImageTag? = nil,
        backdrops: [MediaServerImageTag] = []
    ) {
        self.primary = primary
        self.logo = logo
        self.thumb = thumb
        self.backdrops = backdrops
    }
}

public struct MediaServerUserData: Equatable, Hashable, Sendable {
    public let playbackPositionTicks: Int64
    public let played: Bool
    public let unplayedItemCount: Int?

    public init(playbackPositionTicks: Int64, played: Bool, unplayedItemCount: Int?) {
        self.playbackPositionTicks = playbackPositionTicks
        self.played = played
        self.unplayedItemCount = unplayedItemCount
    }
}

public struct MediaServerStudio: Equatable, Hashable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct MediaServerPerson: Equatable, Hashable, Sendable, Identifiable {
    public let id: MediaServerItemID?
    public let name: String
    public let role: String?
    public let type: String?
    public let primaryImageTag: MediaServerImageTag?

    public init(
        id: MediaServerItemID?,
        name: String,
        role: String?,
        type: String?,
        primaryImageTag: MediaServerImageTag?
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.type = type
        self.primaryImageTag = primaryImageTag
    }
}

public struct MediaServerMediaSourceDescription: Equatable, Hashable, Sendable, Identifiable {
    public let id: MediaServerMediaSourceID
    public let displayName: String
    public let container: String?
    public let sizeInBytes: Int64?
    public let bitrate: Int?
    public let mediaStreams: [MediaServerMediaStream]

    public init(
        id: MediaServerMediaSourceID,
        displayName: String,
        container: String?,
        sizeInBytes: Int64? = nil,
        bitrate: Int? = nil,
        mediaStreams: [MediaServerMediaStream]
    ) {
        self.id = id
        self.displayName = displayName
        self.container = container
        self.sizeInBytes = sizeInBytes
        self.bitrate = bitrate
        self.mediaStreams = mediaStreams
    }
}

public struct MediaServerItemMetadata: Equatable, Hashable, Sendable {
    public let id: MediaServerItemID
    public let name: String
    public let imageTags: MediaServerImageTags
    public let overview: String?
    public let runTimeTicks: Int64?
    public let userData: MediaServerUserData?
    public let entityTag: String?
    public let sizeInBytes: Int64?
    public let productionYear: Int?
    public let officialRating: String?
    public let communityRating: Double?
    public let genres: [String]
    public let studios: [MediaServerStudio]
    public let people: [MediaServerPerson]
    public let productionLocations: [String]
    public let mediaSources: [MediaServerMediaSourceDescription]

    public init(
        id: MediaServerItemID,
        name: String,
        imageTags: MediaServerImageTags,
        overview: String?,
        runTimeTicks: Int64?,
        userData: MediaServerUserData?,
        entityTag: String?,
        sizeInBytes: Int64?,
        productionYear: Int? = nil,
        officialRating: String? = nil,
        communityRating: Double? = nil,
        genres: [String] = [],
        studios: [MediaServerStudio] = [],
        people: [MediaServerPerson] = [],
        productionLocations: [String] = [],
        mediaSources: [MediaServerMediaSourceDescription] = []
    ) {
        self.id = id
        self.name = name
        self.imageTags = imageTags
        self.overview = overview
        self.runTimeTicks = runTimeTicks
        self.userData = userData
        self.entityTag = entityTag
        self.sizeInBytes = sizeInBytes
        self.productionYear = productionYear
        self.officialRating = officialRating
        self.communityRating = communityRating
        self.genres = genres
        self.studios = studios
        self.people = people
        self.productionLocations = productionLocations
        self.mediaSources = mediaSources
    }
}

public struct MediaServerMovie: Equatable, Hashable, Sendable {
    public let metadata: MediaServerItemMetadata

    public init(metadata: MediaServerItemMetadata) {
        self.metadata = metadata
    }
}

public struct MediaServerSeries: Equatable, Hashable, Sendable {
    public let metadata: MediaServerItemMetadata

    public init(metadata: MediaServerItemMetadata) {
        self.metadata = metadata
    }
}

public struct MediaServerSeason: Equatable, Hashable, Sendable {
    public let metadata: MediaServerItemMetadata
    public let seriesID: MediaServerItemID
    public let indexNumber: Int?

    public init(metadata: MediaServerItemMetadata, seriesID: MediaServerItemID, indexNumber: Int?) {
        self.metadata = metadata
        self.seriesID = seriesID
        self.indexNumber = indexNumber
    }
}

public struct MediaServerEpisode: Equatable, Hashable, Sendable {
    public let metadata: MediaServerItemMetadata
    public let seriesID: MediaServerItemID
    public let seasonID: MediaServerItemID?
    public let seasonNumber: Int?
    public let episodeNumber: Int?

    public init(
        metadata: MediaServerItemMetadata,
        seriesID: MediaServerItemID,
        seasonID: MediaServerItemID?,
        seasonNumber: Int?,
        episodeNumber: Int?
    ) {
        self.metadata = metadata
        self.seriesID = seriesID
        self.seasonID = seasonID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }
}

public struct MediaServerBoxSet: Equatable, Hashable, Sendable {
    public let metadata: MediaServerItemMetadata

    public init(metadata: MediaServerItemMetadata) {
        self.metadata = metadata
    }
}

public enum MediaServerLibraryItem: Equatable, Hashable, Sendable {
    case movie(MediaServerMovie)
    case series(MediaServerSeries)
    case season(MediaServerSeason)
    case episode(MediaServerEpisode)
    case boxSet(MediaServerBoxSet)

    public var metadata: MediaServerItemMetadata {
        switch self {
        case .movie(let item): item.metadata
        case .series(let item): item.metadata
        case .season(let item): item.metadata
        case .episode(let item): item.metadata
        case .boxSet(let item): item.metadata
        }
    }

    public var isPlayable: Bool {
        switch self {
        case .movie, .episode: true
        case .series, .season, .boxSet: false
        }
    }

    public var season: MediaServerSeason? {
        guard case .season(let season) = self else { return nil }
        return season
    }

    public var episode: MediaServerEpisode? {
        guard case .episode(let episode) = self else { return nil }
        return episode
    }
}

public struct MediaServerLibraryView: Equatable, Hashable, Sendable {
    public let id: MediaServerItemID
    public let name: String
    public let collectionType: String?
    public let imageTags: MediaServerImageTags

    public init(id: MediaServerItemID, name: String, collectionType: String?, imageTags: MediaServerImageTags) {
        self.id = id
        self.name = name
        self.collectionType = collectionType
        self.imageTags = imageTags
    }

    public var topLevelItemKinds: [MediaServerItemKind] {
        switch collectionType?.lowercased() {
        case "tvshows": [.series]
        case "movies": [.movie, .boxSet]
        default: [.movie, .series, .boxSet]
        }
    }
}

public struct MediaServerItemPage: Equatable, Hashable, Sendable {
    public let items: [MediaServerLibraryItem]
    public let totalRecordCount: Int

    public init(items: [MediaServerLibraryItem], totalRecordCount: Int) {
        self.items = items
        self.totalRecordCount = totalRecordCount
    }
}

public enum MediaServerItemSort: String, Codable, CaseIterable, Sendable {
    case sortName = "SortName"
    case indexNumber = "IndexNumber"
    case dateCreated = "DateCreated"
    case datePlayed = "DatePlayed"
    case premiereDate = "PremiereDate"
    case communityRating = "CommunityRating"
    case runtime = "Runtime"
    case random = "Random"
}

public enum MediaServerSortOrder: String, Codable, Sendable {
    case ascending = "Ascending"
    case descending = "Descending"
}

public enum MediaServerItemKind: String, Codable, CaseIterable, Sendable {
    case movie = "Movie"
    case series = "Series"
    case season = "Season"
    case episode = "Episode"
    case boxSet = "BoxSet"
}

public struct MediaServerItemQuery: Equatable, Hashable, Sendable {
    public let sortBy: [MediaServerItemSort]
    public let sortOrder: MediaServerSortOrder
    public let startIndex: Int?
    public let limit: Int?
    public let includeItemTypes: [MediaServerItemKind]?
    public let recursive: Bool

    public init(
        sortBy: [MediaServerItemSort] = [.sortName],
        sortOrder: MediaServerSortOrder = .ascending,
        startIndex: Int? = nil,
        limit: Int? = nil,
        includeItemTypes: [MediaServerItemKind]? = nil,
        recursive: Bool = true
    ) {
        self.sortBy = sortBy
        self.sortOrder = sortOrder
        self.startIndex = startIndex
        self.limit = limit
        self.includeItemTypes = includeItemTypes
        self.recursive = recursive
    }
}

public enum MediaServerImageType: String, Codable, Sendable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case logo = "Logo"
    case thumb = "Thumb"
}

public struct MediaServerImageSize: Equatable, Hashable, Sendable {
    public let maxWidth: Int?
    public let maxHeight: Int?

    private init(maxWidth: Int?, maxHeight: Int?) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
    }

    public static func width(_ value: Int) throws -> Self {
        guard value > 0 else { throw MediaServerError.invalidImageSize }
        return Self(maxWidth: value, maxHeight: nil)
    }

    public static func height(_ value: Int) throws -> Self {
        guard value > 0 else { throw MediaServerError.invalidImageSize }
        return Self(maxWidth: nil, maxHeight: value)
    }

    public static func fitting(maxWidth: Int, maxHeight: Int) throws -> Self {
        guard maxWidth > 0, maxHeight > 0 else { throw MediaServerError.invalidImageSize }
        return Self(maxWidth: maxWidth, maxHeight: maxHeight)
    }
}

public enum MediaServerMediaStreamKind: String, Codable, Sendable {
    case video = "Video"
    case audio = "Audio"
    case subtitle = "Subtitle"
    case unknown = "Unknown"
}

public struct MediaServerMediaStream: Equatable, Hashable, Sendable {
    public let index: Int
    public let playbackIndex: Int?
    public let kind: MediaServerMediaStreamKind
    public let codec: String?
    public let language: String?
    public let displayLanguage: String?
    public let displayTitle: String?
    public let channels: Int?
    public let channelLayout: String?
    public let width: Int?
    public let height: Int?
    public let videoRange: String?
    public let extendedVideoType: String?
    public let extendedVideoSubTypeDescription: String?
    public let bitRate: Int?
    public let bitDepth: Int?
    public let sampleRate: Int?
    public let profile: String?
    public let averageFrameRate: Double?
    public let aspectRatio: String?
    public let pixelFormat: String?
    public let title: String?
    public let isDefault: Bool
    public let isForced: Bool
    public let isExternal: Bool
    public let isHearingImpaired: Bool
    public let deliveryURL: String?

    public init(
        index: Int,
        playbackIndex: Int? = nil,
        kind: MediaServerMediaStreamKind,
        codec: String?,
        language: String?,
        displayLanguage: String? = nil,
        displayTitle: String?,
        channels: Int?,
        channelLayout: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        videoRange: String? = nil,
        extendedVideoType: String? = nil,
        extendedVideoSubTypeDescription: String? = nil,
        bitRate: Int? = nil,
        bitDepth: Int? = nil,
        sampleRate: Int? = nil,
        profile: String? = nil,
        averageFrameRate: Double? = nil,
        aspectRatio: String? = nil,
        pixelFormat: String? = nil,
        title: String? = nil,
        isDefault: Bool,
        isForced: Bool,
        isExternal: Bool,
        isHearingImpaired: Bool = false,
        deliveryURL: String?
    ) {
        self.index = index
        self.playbackIndex = isExternal ? nil : (playbackIndex ?? index)
        self.kind = kind
        self.codec = codec
        self.language = language
        self.displayLanguage = displayLanguage
        self.displayTitle = displayTitle
        self.channels = channels
        self.channelLayout = channelLayout
        self.width = width
        self.height = height
        self.videoRange = videoRange
        self.extendedVideoType = extendedVideoType
        self.extendedVideoSubTypeDescription = extendedVideoSubTypeDescription
        self.bitRate = bitRate
        self.bitDepth = bitDepth
        self.sampleRate = sampleRate
        self.profile = profile
        self.averageFrameRate = averageFrameRate
        self.aspectRatio = aspectRatio
        self.pixelFormat = pixelFormat
        self.title = title
        self.isDefault = isDefault
        self.isForced = isForced
        self.isExternal = isExternal
        self.isHearingImpaired = isHearingImpaired
        self.deliveryURL = deliveryURL
    }
}

public struct MediaServerDefaultStreamIndexes: Equatable, Hashable, Sendable {
    public let video: Int?
    public let audio: Int?
    public let subtitle: Int?

    public init(video: Int?, audio: Int?, subtitle: Int?) {
        self.video = video
        self.audio = audio
        self.subtitle = subtitle
    }
}

public struct MediaServerMediaSource: Equatable, Hashable, Sendable, Identifiable {
    public let id: MediaServerMediaSourceID
    public let displayName: String
    public let container: String?
    public let sizeInBytes: Int64?
    public let mediaStreams: [MediaServerMediaStream]
    public let defaultStreamIndexes: MediaServerDefaultStreamIndexes
    public let directPlayURL: URL
    public let versionedIdentity: VersionedMediaIdentity?

    public init(
        id: MediaServerMediaSourceID,
        displayName: String,
        container: String?,
        sizeInBytes: Int64?,
        mediaStreams: [MediaServerMediaStream],
        defaultStreamIndexes: MediaServerDefaultStreamIndexes,
        directPlayURL: URL,
        versionedIdentity: VersionedMediaIdentity?
    ) {
        self.id = id
        self.displayName = displayName
        self.container = container
        self.sizeInBytes = sizeInBytes
        self.mediaStreams = mediaStreams
        self.defaultStreamIndexes = defaultStreamIndexes
        self.directPlayURL = directPlayURL
        self.versionedIdentity = versionedIdentity
    }
}

public struct MediaServerPlaybackSession: Equatable, Hashable, Sendable {
    public let id: MediaServerPlaySessionID
    public let mediaSources: [MediaServerMediaSource]

    public init(id: MediaServerPlaySessionID, mediaSources: [MediaServerMediaSource]) {
        self.id = id
        self.mediaSources = mediaSources
    }
}

public struct MediaServerPlaybackReport: Equatable, Hashable, Sendable {
    public enum ProgressEvent: String, Encodable, Sendable {
        case timeUpdate = "TimeUpdate"
        case pause = "Pause"
        case unpause = "Unpause"
        case audioTrackChange = "AudioTrackChange"
        case subtitleTrackChange = "SubtitleTrackChange"
    }

    public let itemID: MediaServerItemID
    public let mediaSourceID: MediaServerMediaSourceID
    public let playSessionID: MediaServerPlaySessionID
    public let positionTicks: Int64
    public let durationTicks: Int64?
    public let audioStreamIndex: Int?
    public let subtitleStreamIndex: Int?
    public let isPaused: Bool
    public let progressEvent: ProgressEvent?

    public init(
        itemID: MediaServerItemID,
        mediaSourceID: MediaServerMediaSourceID,
        playSessionID: MediaServerPlaySessionID,
        positionTicks: Int64,
        durationTicks: Int64? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        isPaused: Bool = false,
        progressEvent: ProgressEvent? = nil
    ) {
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.playSessionID = playSessionID
        self.positionTicks = positionTicks
        self.durationTicks = durationTicks
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.isPaused = isPaused
        self.progressEvent = progressEvent
    }
}

public enum MediaServerError: Error, Equatable, Sendable {
    case invalidBaseAddress
    case invalidImageSize
    case invalidResponse
    case httpStatus(Int)
    case missingRequiredField(String)
    case childrenUnavailable(MediaServerItemID)
    case directPlayUnavailable(MediaServerItemID)
    case externalSubtitleUnavailable(Int)
    case mediaSourceUnavailable(MediaServerItemID, MediaServerMediaSourceID)
    case notAuthenticated
}

extension MediaServerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBaseAddress:
            "The media server address is invalid."
        case .invalidImageSize:
            "The requested media image size is invalid."
        case .invalidResponse:
            "The media server returned an invalid response."
        case let .httpStatus(status):
            "The media server returned HTTP status \(status)."
        case let .missingRequiredField(field):
            "The media response is missing \(field)."
        case .childrenUnavailable:
            "The requested media collection is unavailable."
        case .directPlayUnavailable:
            "The server did not provide a direct-play media source."
        case let .externalSubtitleUnavailable(index):
            "The server did not provide external subtitle track \(index)."
        case .mediaSourceUnavailable:
            "The selected media media source is unavailable."
        case .notAuthenticated:
            "Sign in to the media server before playing this item."
        }
    }
}
