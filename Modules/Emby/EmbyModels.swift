import Foundation
import MediaSource

public struct EmbyServerID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct EmbyUserID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct EmbyItemID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct EmbyMediaSourceID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct EmbyPlaySessionID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct EmbyImageTag: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct EmbyClientIdentity: Equatable, Hashable, Sendable {
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

public struct EmbyAuthenticatedServer: Equatable, Hashable, Sendable {
    public let id: EmbyServerID
    public let name: String
    public let baseAddress: URL
    public let accessToken: String
    public let userID: EmbyUserID

    public init(
        id: EmbyServerID,
        name: String,
        baseAddress: URL,
        accessToken: String,
        userID: EmbyUserID
    ) {
        self.id = id
        self.name = name
        self.baseAddress = baseAddress
        self.accessToken = accessToken
        self.userID = userID
    }
}

public struct EmbyPublicSystemInfo: Codable, Equatable, Hashable, Sendable {
    public let id: EmbyServerID
    public let serverName: String
    public let version: String
    public let localAddresses: [String]
    public let remoteAddresses: [String]

    public init(
        id: EmbyServerID,
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

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case serverName = "ServerName"
        case version = "Version"
        case localAddresses = "LocalAddresses"
        case remoteAddresses = "RemoteAddresses"
    }
}

public struct EmbyPublicUser: Codable, Equatable, Hashable, Sendable {
    public let id: EmbyUserID
    public let name: String
    public let serverID: EmbyServerID
    public let hasPassword: Bool
    public let hasConfiguredPassword: Bool

    public init(
        id: EmbyUserID,
        name: String,
        serverID: EmbyServerID,
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

public struct EmbyImageTags: Equatable, Hashable, Sendable {
    public let primary: EmbyImageTag?
    public let logo: EmbyImageTag?
    public let thumb: EmbyImageTag?
    public let backdrops: [EmbyImageTag]

    public init(
        primary: EmbyImageTag? = nil,
        logo: EmbyImageTag? = nil,
        thumb: EmbyImageTag? = nil,
        backdrops: [EmbyImageTag] = []
    ) {
        self.primary = primary
        self.logo = logo
        self.thumb = thumb
        self.backdrops = backdrops
    }
}

public struct EmbyUserData: Equatable, Hashable, Sendable {
    public let playbackPositionTicks: Int64
    public let played: Bool
    public let unplayedItemCount: Int?

    public init(playbackPositionTicks: Int64, played: Bool, unplayedItemCount: Int?) {
        self.playbackPositionTicks = playbackPositionTicks
        self.played = played
        self.unplayedItemCount = unplayedItemCount
    }
}

public struct EmbyStudio: Equatable, Hashable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct EmbyPerson: Equatable, Hashable, Sendable, Identifiable {
    public let id: EmbyItemID?
    public let name: String
    public let role: String?
    public let type: String?
    public let primaryImageTag: EmbyImageTag?

    public init(
        id: EmbyItemID?,
        name: String,
        role: String?,
        type: String?,
        primaryImageTag: EmbyImageTag?
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.type = type
        self.primaryImageTag = primaryImageTag
    }
}

public struct EmbyMediaSourceDescription: Equatable, Hashable, Sendable, Identifiable {
    public let id: EmbyMediaSourceID
    public let displayName: String
    public let container: String?
    public let sizeInBytes: Int64?
    public let bitrate: Int?
    public let mediaStreams: [EmbyMediaStream]

    public init(
        id: EmbyMediaSourceID,
        displayName: String,
        container: String?,
        sizeInBytes: Int64? = nil,
        bitrate: Int? = nil,
        mediaStreams: [EmbyMediaStream]
    ) {
        self.id = id
        self.displayName = displayName
        self.container = container
        self.sizeInBytes = sizeInBytes
        self.bitrate = bitrate
        self.mediaStreams = mediaStreams
    }
}

public struct EmbyItemMetadata: Equatable, Hashable, Sendable {
    public let id: EmbyItemID
    public let name: String
    public let imageTags: EmbyImageTags
    public let overview: String?
    public let runTimeTicks: Int64?
    public let userData: EmbyUserData?
    public let entityTag: String?
    public let sizeInBytes: Int64?
    public let productionYear: Int?
    public let officialRating: String?
    public let communityRating: Double?
    public let genres: [String]
    public let studios: [EmbyStudio]
    public let people: [EmbyPerson]
    public let productionLocations: [String]
    public let mediaSources: [EmbyMediaSourceDescription]

    public init(
        id: EmbyItemID,
        name: String,
        imageTags: EmbyImageTags,
        overview: String?,
        runTimeTicks: Int64?,
        userData: EmbyUserData?,
        entityTag: String?,
        sizeInBytes: Int64?,
        productionYear: Int? = nil,
        officialRating: String? = nil,
        communityRating: Double? = nil,
        genres: [String] = [],
        studios: [EmbyStudio] = [],
        people: [EmbyPerson] = [],
        productionLocations: [String] = [],
        mediaSources: [EmbyMediaSourceDescription] = []
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

public struct EmbyMovie: Equatable, Hashable, Sendable {
    public let metadata: EmbyItemMetadata

    public init(metadata: EmbyItemMetadata) {
        self.metadata = metadata
    }
}

public struct EmbySeries: Equatable, Hashable, Sendable {
    public let metadata: EmbyItemMetadata

    public init(metadata: EmbyItemMetadata) {
        self.metadata = metadata
    }
}

public struct EmbySeason: Equatable, Hashable, Sendable {
    public let metadata: EmbyItemMetadata
    public let seriesID: EmbyItemID
    public let indexNumber: Int?

    public init(metadata: EmbyItemMetadata, seriesID: EmbyItemID, indexNumber: Int?) {
        self.metadata = metadata
        self.seriesID = seriesID
        self.indexNumber = indexNumber
    }
}

public struct EmbyEpisode: Equatable, Hashable, Sendable {
    public let metadata: EmbyItemMetadata
    public let seriesID: EmbyItemID
    public let seasonID: EmbyItemID?
    public let seasonNumber: Int?
    public let episodeNumber: Int?

    public init(
        metadata: EmbyItemMetadata,
        seriesID: EmbyItemID,
        seasonID: EmbyItemID?,
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

public struct EmbyBoxSet: Equatable, Hashable, Sendable {
    public let metadata: EmbyItemMetadata

    public init(metadata: EmbyItemMetadata) {
        self.metadata = metadata
    }
}

public enum EmbyLibraryItem: Equatable, Hashable, Sendable {
    case movie(EmbyMovie)
    case series(EmbySeries)
    case season(EmbySeason)
    case episode(EmbyEpisode)
    case boxSet(EmbyBoxSet)

    public var metadata: EmbyItemMetadata {
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

    public var season: EmbySeason? {
        guard case .season(let season) = self else { return nil }
        return season
    }

    public var episode: EmbyEpisode? {
        guard case .episode(let episode) = self else { return nil }
        return episode
    }
}

public struct EmbyLibraryView: Equatable, Hashable, Sendable {
    public let id: EmbyItemID
    public let name: String
    public let collectionType: String?
    public let imageTags: EmbyImageTags

    public init(id: EmbyItemID, name: String, collectionType: String?, imageTags: EmbyImageTags) {
        self.id = id
        self.name = name
        self.collectionType = collectionType
        self.imageTags = imageTags
    }

    public var topLevelItemKinds: [EmbyItemKind] {
        switch collectionType?.lowercased() {
        case "tvshows": [.series]
        case "movies": [.movie, .boxSet]
        default: [.movie, .series, .boxSet]
        }
    }
}

public struct EmbyItemPage: Equatable, Hashable, Sendable {
    public let items: [EmbyLibraryItem]
    public let totalRecordCount: Int

    public init(items: [EmbyLibraryItem], totalRecordCount: Int) {
        self.items = items
        self.totalRecordCount = totalRecordCount
    }
}

public enum EmbyItemSort: String, Codable, CaseIterable, Sendable {
    case sortName = "SortName"
    case indexNumber = "IndexNumber"
    case dateCreated = "DateCreated"
    case datePlayed = "DatePlayed"
    case premiereDate = "PremiereDate"
    case communityRating = "CommunityRating"
    case runtime = "Runtime"
    case random = "Random"
}

public enum EmbySortOrder: String, Codable, Sendable {
    case ascending = "Ascending"
    case descending = "Descending"
}

public enum EmbyItemKind: String, Codable, CaseIterable, Sendable {
    case movie = "Movie"
    case series = "Series"
    case season = "Season"
    case episode = "Episode"
    case boxSet = "BoxSet"
}

public struct EmbyItemQuery: Equatable, Hashable, Sendable {
    public let sortBy: [EmbyItemSort]
    public let sortOrder: EmbySortOrder
    public let startIndex: Int?
    public let limit: Int?
    public let includeItemTypes: [EmbyItemKind]?
    public let recursive: Bool

    public init(
        sortBy: [EmbyItemSort] = [.sortName],
        sortOrder: EmbySortOrder = .ascending,
        startIndex: Int? = nil,
        limit: Int? = nil,
        includeItemTypes: [EmbyItemKind]? = nil,
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

public enum EmbyImageType: String, Codable, Sendable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case logo = "Logo"
    case thumb = "Thumb"
}

public struct EmbyImageSize: Equatable, Hashable, Sendable {
    public let maxWidth: Int?
    public let maxHeight: Int?

    private init(maxWidth: Int?, maxHeight: Int?) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
    }

    public static func width(_ value: Int) throws -> Self {
        guard value > 0 else { throw EmbyError.invalidImageSize }
        return Self(maxWidth: value, maxHeight: nil)
    }

    public static func height(_ value: Int) throws -> Self {
        guard value > 0 else { throw EmbyError.invalidImageSize }
        return Self(maxWidth: nil, maxHeight: value)
    }

    public static func fitting(maxWidth: Int, maxHeight: Int) throws -> Self {
        guard maxWidth > 0, maxHeight > 0 else { throw EmbyError.invalidImageSize }
        return Self(maxWidth: maxWidth, maxHeight: maxHeight)
    }
}

public enum EmbyMediaStreamKind: String, Codable, Sendable {
    case video = "Video"
    case audio = "Audio"
    case subtitle = "Subtitle"
    case unknown = "Unknown"
}

public struct EmbyMediaStream: Equatable, Hashable, Sendable {
    public let index: Int
    public let kind: EmbyMediaStreamKind
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
        kind: EmbyMediaStreamKind,
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

public struct EmbyDefaultStreamIndexes: Equatable, Hashable, Sendable {
    public let video: Int?
    public let audio: Int?
    public let subtitle: Int?

    public init(video: Int?, audio: Int?, subtitle: Int?) {
        self.video = video
        self.audio = audio
        self.subtitle = subtitle
    }
}

public struct EmbyMediaSource: Equatable, Hashable, Sendable, Identifiable {
    public let id: EmbyMediaSourceID
    public let displayName: String
    public let container: String?
    public let sizeInBytes: Int64?
    public let mediaStreams: [EmbyMediaStream]
    public let defaultStreamIndexes: EmbyDefaultStreamIndexes
    public let directPlayURL: URL
    public let versionedIdentity: VersionedMediaIdentity?

    public init(
        id: EmbyMediaSourceID,
        displayName: String,
        container: String?,
        sizeInBytes: Int64?,
        mediaStreams: [EmbyMediaStream],
        defaultStreamIndexes: EmbyDefaultStreamIndexes,
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

public struct EmbyPlaybackSession: Equatable, Hashable, Sendable {
    public let id: EmbyPlaySessionID
    public let mediaSources: [EmbyMediaSource]

    public init(id: EmbyPlaySessionID, mediaSources: [EmbyMediaSource]) {
        self.id = id
        self.mediaSources = mediaSources
    }
}

public struct EmbyPlaybackReport: Equatable, Hashable, Sendable {
    public enum ProgressEvent: String, Encodable, Sendable {
        case timeUpdate = "TimeUpdate"
        case pause = "Pause"
        case unpause = "Unpause"
        case audioTrackChange = "AudioTrackChange"
        case subtitleTrackChange = "SubtitleTrackChange"
    }

    public let itemID: EmbyItemID
    public let mediaSourceID: EmbyMediaSourceID
    public let playSessionID: EmbyPlaySessionID
    public let positionTicks: Int64
    public let audioStreamIndex: Int?
    public let subtitleStreamIndex: Int?
    public let isPaused: Bool
    public let progressEvent: ProgressEvent?

    public init(
        itemID: EmbyItemID,
        mediaSourceID: EmbyMediaSourceID,
        playSessionID: EmbyPlaySessionID,
        positionTicks: Int64,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        isPaused: Bool = false,
        progressEvent: ProgressEvent? = nil
    ) {
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.playSessionID = playSessionID
        self.positionTicks = positionTicks
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.isPaused = isPaused
        self.progressEvent = progressEvent
    }
}

public enum EmbyError: Error, Equatable, Sendable {
    case invalidBaseAddress
    case invalidImageSize
    case invalidResponse
    case httpStatus(Int)
    case missingRequiredField(String)
    case childrenUnavailable(EmbyItemID)
    case directPlayUnavailable(EmbyItemID)
    case externalSubtitleUnavailable(Int)
    case mediaSourceUnavailable(EmbyItemID, EmbyMediaSourceID)
    case notAuthenticated
}

extension EmbyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBaseAddress:
            "The Emby server address is invalid."
        case .invalidImageSize:
            "The requested Emby image size is invalid."
        case .invalidResponse:
            "The Emby server returned an invalid response."
        case let .httpStatus(status):
            "The Emby server returned HTTP status \(status)."
        case let .missingRequiredField(field):
            "The Emby response is missing \(field)."
        case .childrenUnavailable:
            "The requested Emby collection is unavailable."
        case .directPlayUnavailable:
            "Emby did not provide a direct-play media source."
        case let .externalSubtitleUnavailable(index):
            "Emby did not provide external subtitle track \(index)."
        case .mediaSourceUnavailable:
            "The selected Emby media source is unavailable."
        case .notAuthenticated:
            "Sign in to the Emby server before playing this item."
        }
    }
}
