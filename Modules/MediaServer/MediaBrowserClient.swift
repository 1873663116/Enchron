import Foundation
import MediaSource

public final class MediaBrowserClient: MediaServerClientProtocol, Sendable {
    private static let itemFields = [
        "Overview",
        "MediaStreams",
        "MediaSources",
        "ProductionYear",
        "OfficialRating",
        "CommunityRating",
        "Genres",
        "Studios",
        "People",
        "ProductionLocations"
    ].joined(separator: ",")

    public let dialect: MediaBrowserDialect
    public var kind: MediaServerKind { dialect == .emby ? .emby : .jellyfin }
    private let session: URLSession
    private let clientIdentity: MediaServerClientIdentity
    private let failureDiagnoser: RemoteConnectionFailureDiagnoser

    public init(
        session: URLSession = MediaSourceNetwork.shared.session,
        dialect: MediaBrowserDialect = .emby,
        clientIdentity: MediaServerClientIdentity,
        failureDiagnoser: RemoteConnectionFailureDiagnoser = .live
    ) {
        self.dialect = dialect
        self.session = session
        self.clientIdentity = clientIdentity
        self.failureDiagnoser = failureDiagnoser
    }

    public func publicSystemInfo(at address: URL) async throws -> EmbyPublicSystemInfo {
        let request = try request(address: address, path: "/System/Info/Public")
        let data = try await data(for: request)
        return try JSONDecoder().decode(EmbyPublicSystemInfo.self, from: data)
    }

    public func publicUsers(at address: URL) async throws -> [EmbyPublicUser] {
        let request = try request(address: address, path: "/Users/Public")
        let data = try await data(for: request)
        return try JSONDecoder().decode([EmbyPublicUser].self, from: data)
    }

    public func authenticate(_ login: MediaServerLogin) async throws -> MediaServerAuthenticatedServer {
        guard case let .password(address, username, password) = login else {
            throw MediaServerError.notAuthenticated
        }
        do {
            return try await MediaSourceNetwork.shared.withConnectionApproval(
                to: address
            ) { [self] in
                let systemInfo = try await publicSystemInfo(at: address)
                let body = try Self.makeEncoder().encode(
                    AuthenticationRequest(username: username, pw: password)
                )
                let request = try request(
                    address: address,
                    path: "/Users/AuthenticateByName",
                    method: "POST",
                    body: body
                )
                let data = try await data(for: request)
                let result = try Self.makeDecoder().decode(
                    AuthenticationResultDTO.self,
                    from: data
                )
                guard let token = result.accessToken, token.isEmpty == false else {
                    throw MediaServerError.missingRequiredField("AccessToken")
                }
                guard let userID = result.user?.id, userID.isEmpty == false else {
                    throw MediaServerError.missingRequiredField("User.Id")
                }
                let serverID = result.serverId.flatMap { $0.isEmpty ? nil : $0 }
                    ?? systemInfo.id.rawValue
                return MediaServerAuthenticatedServer(
                    kind: kind,
                    id: MediaServerServerID(rawValue: serverID),
                    name: systemInfo.serverName,
                    baseAddress: try normalizedAddress(address),
                    accessToken: token,
                    userID: MediaServerUserID(rawValue: userID)
                )
            }
        } catch {
            if let failure = Self.authenticationFailure(for: error) {
                throw failure
            }
            throw await failureDiagnoser.diagnose(
                error,
                attemptedURL: address
            )
        }
    }

    private static func authenticationFailure(
        for error: any Error
    ) -> RemoteConnectionFailure? {
        if let failure = error as? RemoteConnectionFailure {
            return failure
        }
        guard let embyError = error as? MediaServerError else { return nil }

        switch embyError {
        case .invalidBaseAddress:
            return .invalidAddress
        case .httpStatus(let statusCode) where statusCode == 401 || statusCode == 403:
            return .credentialsRejected
        case .invalidImageSize, .invalidResponse, .httpStatus, .missingRequiredField,
             .childrenUnavailable, .directPlayUnavailable, .externalSubtitleUnavailable,
             .mediaSourceUnavailable, .notAuthenticated:
            return nil
        }
    }

    public func views(on server: MediaServerAuthenticatedServer) async throws -> [MediaServerLibraryView] {
        let request = try authorizedRequest(
            server: server,
            path: "/Users/\(server.userID.rawValue)/Views",
            queryItems: [URLQueryItem(name: "IncludeExternalContent", value: "false")]
        )
        let result: ItemQueryResultDTO = try await response(for: request)
        return try result.items.map(mapView)
    }

    public func items(
        in viewID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery = MediaServerItemQuery()
    ) async throws -> MediaServerItemPage {
        try await itemPage(
            path: "/Users/\(server.userID.rawValue)/Items",
            server: server,
            query: query,
            additionalQueryItems: [
                URLQueryItem(name: "ParentId", value: viewID.rawValue)
            ]
        )
    }

    public func item(
        withID itemID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer
    ) async throws -> MediaServerLibraryItem {
        let request = try authorizedRequest(
            server: server,
            path: "/Users/\(server.userID.rawValue)/Items/\(itemID.rawValue)",
            queryItems: [
                URLQueryItem(name: "Fields", value: Self.itemFields),
                URLQueryItem(name: "EnableImages", value: "true"),
                URLQueryItem(name: "EnableUserData", value: "true")
            ]
        )
        let result: ItemDTO = try await response(for: request)
        guard let item = try mapItem(result) else {
            throw MediaServerError.missingRequiredField("Item.Type")
        }
        return item
    }

    public func children(
        of parent: MediaServerLibraryItem,
        on server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery = MediaServerItemQuery(sortBy: [])
    ) async throws -> MediaServerItemPage {
        let path: String
        let itemTypes: String
        let parentQuery: [URLQueryItem]
        switch parent {
        case .series:
            path = "/Shows/\(parent.metadata.id.rawValue)/Seasons"
            itemTypes = "Season"
            parentQuery = [URLQueryItem(name: "UserId", value: server.userID.rawValue)]
        case .season(let season):
            path = "/Shows/\(season.seriesID.rawValue)/Episodes"
            itemTypes = "Episode"
            parentQuery = [
                URLQueryItem(name: "UserId", value: server.userID.rawValue),
                URLQueryItem(name: "SeasonId", value: season.metadata.id.rawValue)
            ]
        case .boxSet:
            path = "/Users/\(server.userID.rawValue)/Items"
            itemTypes = "Movie,Series,BoxSet"
            parentQuery = [URLQueryItem(name: "ParentId", value: parent.metadata.id.rawValue)]
        case .movie, .episode:
            throw MediaServerError.childrenUnavailable(parent.metadata.id)
        }
        return try await itemPage(
            path: path,
            server: server,
            query: query,
            additionalQueryItems: parentQuery,
            forcedItemTypes: itemTypes
        )
    }

    public func resumeItems(
        on server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery = MediaServerItemQuery(sortBy: [.datePlayed], sortOrder: .descending)
    ) async throws -> MediaServerItemPage {
        try await itemPage(
            path: "/Users/\(server.userID.rawValue)/Items",
            server: server,
            query: query,
            additionalQueryItems: [URLQueryItem(name: "Filters", value: "IsResumable")]
        )
    }

    public func latestItems(
        in viewID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer,
        limit: Int? = nil
    ) async throws -> [MediaServerLibraryItem] {
        var queryItems = [
            URLQueryItem(name: "ParentId", value: viewID.rawValue),
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true")
        ]
        if let limit {
            queryItems.append(URLQueryItem(name: "Limit", value: String(limit)))
        }
        let request = try authorizedRequest(
            server: server,
            path: "/Users/\(server.userID.rawValue)/Items/Latest",
            queryItems: queryItems
        )
        let result: [ItemDTO] = try await response(for: request)
        return try result.compactMap(mapItem)
    }

    public func nextUp(
        on server: MediaServerAuthenticatedServer,
        seriesID: MediaServerItemID? = nil,
        startIndex: Int? = nil,
        limit: Int? = nil
    ) async throws -> MediaServerItemPage {
        var items = [URLQueryItem(name: "UserId", value: server.userID.rawValue)]
        if let seriesID {
            items.append(URLQueryItem(name: "SeriesId", value: seriesID.rawValue))
        }
        if let startIndex {
            items.append(URLQueryItem(name: "StartIndex", value: String(startIndex)))
        }
        if let limit {
            items.append(URLQueryItem(name: "Limit", value: String(limit)))
        }
        items.append(contentsOf: [
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true")
        ])
        let request = try authorizedRequest(
            server: server,
            path: "/Shows/NextUp",
            queryItems: items
        )
        let result: ItemQueryResultDTO = try await response(for: request)
        return MediaServerItemPage(
            items: try result.items.compactMap(mapItem),
            totalRecordCount: result.totalRecordCount
        )
    }

    public func search(
        _ searchTerm: String,
        on server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery = MediaServerItemQuery()
    ) async throws -> MediaServerItemPage {
        try await itemPage(
            path: "/Users/\(server.userID.rawValue)/Items",
            server: server,
            query: query,
            additionalQueryItems: [
                URLQueryItem(name: "SearchTerm", value: searchTerm)
            ]
        )
    }

    public func specialFeatures(
        for itemID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer
    ) async throws -> [MediaServerLibraryItem] {
        let request = try authorizedRequest(
            server: server,
            path: "/Users/\(server.userID.rawValue)/Items/\(itemID.rawValue)/SpecialFeatures",
            queryItems: [
                URLQueryItem(name: "Fields", value: Self.itemFields),
                URLQueryItem(name: "EnableImages", value: "true"),
                URLQueryItem(name: "EnableUserData", value: "true")
            ]
        )
        let data = try await data(for: request)
        let decoder = Self.makeDecoder()
        if let items = try? decoder.decode([ItemDTO].self, from: data) {
            return try items.compactMap(mapItem)
        }
        let result = try decoder.decode(ItemQueryResultDTO.self, from: data)
        return try result.items.compactMap(mapItem)
    }

    public func similarItems(
        to itemID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer,
        limit: Int? = nil
    ) async throws -> MediaServerItemPage {
        var queryItems = [
            URLQueryItem(name: "UserId", value: server.userID.rawValue),
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true")
        ]
        if let limit {
            queryItems.append(URLQueryItem(name: "Limit", value: String(limit)))
        }
        let request = try authorizedRequest(
            server: server,
            path: "/Items/\(itemID.rawValue)/Similar",
            queryItems: queryItems
        )
        let result: ItemQueryResultDTO = try await response(for: request)
        return MediaServerItemPage(
            items: try result.items.compactMap(mapItem),
            totalRecordCount: result.totalRecordCount
        )
    }

    public func imageURL(
        for itemID: MediaServerItemID,
        type: MediaServerImageType,
        tag: MediaServerImageTag? = nil,
        size: MediaServerImageSize? = nil,
        on server: MediaServerAuthenticatedServer
    ) throws -> URL {
        var queryItems = [URLQueryItem(name: "api_key", value: server.accessToken)]
        if let tag {
            queryItems.append(URLQueryItem(name: "Tag", value: tag.rawValue))
        }
        if let maxWidth = size?.maxWidth {
            queryItems.append(URLQueryItem(name: "MaxWidth", value: String(maxWidth)))
        }
        if let maxHeight = size?.maxHeight {
            queryItems.append(URLQueryItem(name: "MaxHeight", value: String(maxHeight)))
        }
        return try url(
            address: server.baseAddress,
            path: "/Items/\(itemID.rawValue)/Images/\(type.rawValue)",
            queryItems: queryItems
        )
    }

    public func backdropImageURL(
        for itemID: MediaServerItemID,
        index: Int,
        tag: MediaServerImageTag? = nil,
        size: MediaServerImageSize? = nil,
        on server: MediaServerAuthenticatedServer
    ) throws -> URL {
        var queryItems = [URLQueryItem(name: "api_key", value: server.accessToken)]
        if let tag {
            queryItems.append(URLQueryItem(name: "Tag", value: tag.rawValue))
        }
        if let maxWidth = size?.maxWidth {
            queryItems.append(URLQueryItem(name: "MaxWidth", value: String(maxWidth)))
        }
        if let maxHeight = size?.maxHeight {
            queryItems.append(URLQueryItem(name: "MaxHeight", value: String(maxHeight)))
        }
        return try url(
            address: server.baseAddress,
            path: "/Items/\(itemID.rawValue)/Images/Backdrop/\(index)",
            queryItems: queryItems
        )
    }

    public func playbackInfo(
        for item: MediaServerLibraryItem,
        on server: MediaServerAuthenticatedServer
    ) async throws -> MediaServerPlaybackSession {
        let itemID = item.metadata.id
        let body = try Self.makeEncoder().encode(PlaybackInfoRequestDTO(
            userId: server.userID.rawValue,
            enableDirectPlay: true,
            enableDirectStream: false,
            enableTranscoding: false,
            isPlayback: true
        ))
        let request = try authorizedRequest(
            server: server,
            path: "/Items/\(itemID.rawValue)/PlaybackInfo",
            method: "POST",
            body: body
        )
        let result: PlaybackInfoResponseDTO = try await response(for: request)
        guard let playSessionId = result.playSessionId, playSessionId.isEmpty == false else {
            throw MediaServerError.missingRequiredField("PlaySessionId")
        }
        let mediaSources = try result.mediaSources.compactMap { source in
            try mapMediaSource(source, item: item, server: server)
        }
        guard mediaSources.isEmpty == false else {
            throw MediaServerError.directPlayUnavailable(itemID)
        }
        return MediaServerPlaybackSession(
            id: MediaServerPlaySessionID(rawValue: playSessionId),
            mediaSources: mediaSources
        )
    }

    public func externalSubtitleURL(
        for stream: MediaServerMediaStream,
        on server: MediaServerAuthenticatedServer
    ) throws -> URL {
        guard stream.kind == .subtitle,
              stream.isExternal,
              let deliveryURL = stream.deliveryURL,
              deliveryURL.isEmpty == false else {
            throw MediaServerError.externalSubtitleUnavailable(stream.index)
        }
        if let absoluteURL = URL(string: deliveryURL), absoluteURL.scheme != nil {
            guard var components = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: false) else {
                throw MediaServerError.externalSubtitleUnavailable(stream.index)
            }
            var queryItems = components.queryItems ?? []
            if queryItems.contains(where: { $0.name == "api_key" }) == false {
                queryItems.append(URLQueryItem(name: "api_key", value: server.accessToken))
            }
            components.queryItems = queryItems
            guard let url = components.url else {
                throw MediaServerError.externalSubtitleUnavailable(stream.index)
            }
            return url
        }
        guard let deliveryComponents = URLComponents(string: deliveryURL) else {
            throw MediaServerError.externalSubtitleUnavailable(stream.index)
        }
        var queryItems = deliveryComponents.queryItems ?? []
        if queryItems.contains(where: { $0.name == "api_key" }) == false {
            queryItems.append(URLQueryItem(name: "api_key", value: server.accessToken))
        }
        return try url(
            address: server.baseAddress,
            path: deliveryComponents.path,
            queryItems: queryItems
        )
    }

    public func sendPlayingStarted(
        _ report: MediaServerPlaybackReport,
        on server: MediaServerAuthenticatedServer
    ) async throws {
        try await sendReport(report, event: .started, server: server)
    }

    public func sendProgress(
        _ report: MediaServerPlaybackReport,
        on server: MediaServerAuthenticatedServer
    ) async throws {
        try await sendReport(report, event: .progress, server: server)
    }

    public func sendStopped(
        _ report: MediaServerPlaybackReport,
        on server: MediaServerAuthenticatedServer
    ) async throws {
        try await sendReport(report, event: .stopped, server: server)
    }

    private func itemPage(
        path: String,
        server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery,
        additionalQueryItems: [URLQueryItem],
        forcedItemTypes: String? = nil
    ) async throws -> MediaServerItemPage {
        var queryItems = additionalQueryItems
        if query.sortBy.isEmpty == false {
            queryItems.append(URLQueryItem(
                name: "SortBy",
                value: query.sortBy.map(\.rawValue).joined(separator: ",")
            ))
        }
        queryItems.append(URLQueryItem(name: "SortOrder", value: query.sortOrder.rawValue))
        if let startIndex = query.startIndex {
            queryItems.append(URLQueryItem(name: "StartIndex", value: String(startIndex)))
        }
        if let limit = query.limit {
            queryItems.append(URLQueryItem(name: "Limit", value: String(limit)))
        }
        if let forcedItemTypes {
            queryItems.append(URLQueryItem(name: "IncludeItemTypes", value: forcedItemTypes))
        } else if let includeItemTypes = query.includeItemTypes {
            queryItems.append(URLQueryItem(
                name: "IncludeItemTypes",
                value: includeItemTypes.flatMap { $0 == .movie ? ["Movie", "Video"] : [$0.rawValue] }.joined(separator: ",")
            ))
        } else {
            queryItems.append(URLQueryItem(
                name: "IncludeItemTypes",
                value: (MediaServerItemKind.allCases.map(\.rawValue) + ["Video"]).joined(separator: ",")
            ))
        }
        queryItems.append(contentsOf: [
            URLQueryItem(name: "Recursive", value: query.recursive ? "true" : "false"),
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true")
        ])
        let request = try authorizedRequest(server: server, path: path, queryItems: queryItems)
        let result: ItemQueryResultDTO = try await response(for: request)
        return MediaServerItemPage(
            items: try result.items.compactMap(mapItem),
            totalRecordCount: result.totalRecordCount
        )
    }

    private func mapView(_ item: ItemDTO) throws -> MediaServerLibraryView {
        guard let id = item.id, id.isEmpty == false else {
            throw MediaServerError.missingRequiredField("Items[].Id")
        }
        guard let name = item.name, name.isEmpty == false else {
            throw MediaServerError.missingRequiredField("Items[].Name")
        }
        return MediaServerLibraryView(
            id: MediaServerItemID(rawValue: id),
            name: name,
            collectionType: item.collectionType,
            imageTags: imageTags(from: item)
        )
    }

    private func mapItem(_ item: ItemDTO) throws -> MediaServerLibraryItem? {
        guard let type = item.type else { return nil }
        let supportedTypes = ["movie", "video", "series", "season", "episode", "boxset"]
        guard supportedTypes.contains(type.lowercased()) else { return nil }
        guard let id = item.id, id.isEmpty == false else {
            throw MediaServerError.missingRequiredField("Items[].Id")
        }
        guard let name = item.name, name.isEmpty == false else {
            throw MediaServerError.missingRequiredField("Items[].Name")
        }
        let metadata = MediaServerItemMetadata(
            id: MediaServerItemID(rawValue: id),
            name: name,
            imageTags: imageTags(from: item),
            overview: item.overview,
            runTimeTicks: item.runTimeTicks,
            userData: item.userData.map {
                MediaServerUserData(
                    playbackPositionTicks: $0.playbackPositionTicks ?? 0,
                    played: $0.played ?? false,
                    unplayedItemCount: $0.unplayedItemCount
                )
            },
            entityTag: item.etag,
            sizeInBytes: Self.positiveByteCount(item.size),
            productionYear: item.productionYear,
            officialRating: item.officialRating,
            communityRating: item.communityRating,
            genres: item.genres ?? [],
            studios: (item.studios ?? []).compactMap { studio in
                studio.name?.nonEmpty.map(MediaServerStudio.init(name:))
            },
            people: (item.people ?? []).compactMap(mapPerson),
            productionLocations: item.productionLocations ?? [],
            mediaSources: (item.mediaSources ?? []).compactMap(mapMediaSourceDescription)
        )
        switch type.lowercased() {
        case "movie", "video":
            return .movie(MediaServerMovie(metadata: metadata))
        case "series":
            return .series(MediaServerSeries(metadata: metadata))
        case "season":
            guard let seriesId = item.seriesId, seriesId.isEmpty == false else {
                throw MediaServerError.missingRequiredField("Season.SeriesId")
            }
            return .season(MediaServerSeason(
                metadata: metadata,
                seriesID: MediaServerItemID(rawValue: seriesId),
                indexNumber: item.indexNumber
            ))
        case "episode":
            guard let seriesId = item.seriesId, seriesId.isEmpty == false else {
                throw MediaServerError.missingRequiredField("Episode.SeriesId")
            }
            return .episode(MediaServerEpisode(
                metadata: metadata,
                seriesID: MediaServerItemID(rawValue: seriesId),
                seasonID: item.seasonId.map(MediaServerItemID.init(rawValue:)),
                seasonNumber: item.parentIndexNumber,
                episodeNumber: item.indexNumber
            ))
        case "boxset":
            return .boxSet(MediaServerBoxSet(metadata: metadata))
        default:
            return nil
        }
    }

    private func mapPerson(_ person: PersonDTO) -> MediaServerPerson? {
        guard let name = person.name?.nonEmpty else { return nil }
        return MediaServerPerson(
            id: person.id?.nonEmpty.map { MediaServerItemID(rawValue: $0) },
            name: name,
            role: person.role?.nonEmpty,
            type: person.type?.nonEmpty,
            primaryImageTag: person.primaryImageTag?.nonEmpty.map(MediaServerImageTag.init(rawValue:))
        )
    }

    private func mapMediaSourceDescription(
        _ source: MediaSourceDTO
    ) -> MediaServerMediaSourceDescription? {
        guard let id = source.id?.nonEmpty else { return nil }
        let streams = mapStreams(source.mediaStreams)
        return MediaServerMediaSourceDescription(
            id: MediaServerMediaSourceID(rawValue: id),
            displayName: source.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? source.path?.lastPathComponentFromServerPath
                ?? source.container?.uppercased()
                ?? "Version",
            container: source.container,
            sizeInBytes: Self.positiveByteCount(source.size),
            bitrate: source.bitrate,
            mediaStreams: streams
        )
    }

    private func mapMediaSource(
        _ source: MediaSourceDTO,
        item: MediaServerLibraryItem,
        server: MediaServerAuthenticatedServer
    ) throws -> MediaServerMediaSource? {
        guard source.supportsDirectPlay == true else { return nil }
        guard let id = source.id, id.isEmpty == false else {
            throw MediaServerError.missingRequiredField("MediaSources[].Id")
        }
        let itemID = item.metadata.id
        let directPlayURL = try url(
            address: server.baseAddress,
            path: "/Videos/\(itemID.rawValue)/stream",
            queryItems: [
                URLQueryItem(name: "Static", value: "true"),
                URLQueryItem(name: "MediaSourceId", value: id),
                URLQueryItem(name: "api_key", value: server.accessToken)
            ]
        )
        let streams = mapStreams(source.mediaStreams, subtitlePath: "/Videos/\(itemID.rawValue)/\(id)")
        let videoIndex = streams.first { $0.kind == .video && $0.isDefault }?.index
            ?? streams.first { $0.kind == .video }?.index
        return MediaServerMediaSource(
            id: MediaServerMediaSourceID(rawValue: id),
            displayName: source.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? source.path?.lastPathComponentFromServerPath
                ?? source.container?.uppercased()
                ?? "Video",
            container: source.container,
            sizeInBytes: Self.positiveByteCount(source.size),
            mediaStreams: streams,
            defaultStreamIndexes: MediaServerDefaultStreamIndexes(
                video: videoIndex,
                audio: source.defaultAudioStreamIndex,
                subtitle: source.defaultSubtitleStreamIndex
            ),
            directPlayURL: directPlayURL,
            versionedIdentity: VersionedMediaIdentity.mediaServer(
                provider: kind.rawValue,
                serverID: server.id.rawValue,
                itemID: itemID.rawValue,
                mediaSourceID: id,
                itemEntityTag: item.metadata.entityTag,
                sizeInBytes: Self.positiveByteCount(source.size),
                runTimeTicks: item.metadata.runTimeTicks
            )
        )
    }

    private func mapStreams(_ sourceStreams: [MediaStreamDTO]?, subtitlePath: String? = nil) -> [MediaServerMediaStream] {
        (sourceStreams ?? []).map { stream in
            MediaServerMediaStream(
                index: stream.index,
                playbackIndex: dialect == .jellyfin ? stream.index - (sourceStreams ?? []).filter {
                    $0.isExternal == true && $0.index < stream.index
                }.count : stream.index,
                kind: MediaServerMediaStreamKind(rawValue: stream.type ?? "") ?? .unknown,
                codec: stream.codec,
                language: stream.language,
                displayLanguage: stream.displayLanguage,
                displayTitle: stream.displayTitle ?? stream.title,
                channels: stream.channels,
                channelLayout: stream.channelLayout,
                width: stream.width,
                height: stream.height,
                videoRange: stream.videoRange,
                extendedVideoType: stream.extendedVideoType,
                extendedVideoSubTypeDescription: stream.extendedVideoSubTypeDescription,
                bitRate: stream.bitRate,
                bitDepth: stream.bitDepth,
                sampleRate: stream.sampleRate,
                profile: stream.profile,
                averageFrameRate: stream.averageFrameRate,
                aspectRatio: stream.aspectRatio,
                pixelFormat: stream.pixelFormat,
                title: stream.title,
                isDefault: stream.isDefault ?? false,
                isForced: stream.isForced ?? false,
                isExternal: stream.isExternal ?? false,
                isHearingImpaired: stream.isHearingImpaired ?? false,
                deliveryURL: stream.deliveryUrl ?? subtitlePath.flatMap { base in
                    guard stream.isExternal == true, let codec = stream.codec,
                          ["srt", "subrip", "ass", "ssa", "vtt", "webvtt"].contains(codec) else { return nil }
                    let format = codec == "subrip" ? "srt" : codec == "webvtt" ? "vtt" : codec
                    return "\(base)/Subtitles/\(stream.index)/Stream.\(format)"
                }
            )
        }
    }

    private static func positiveByteCount(_ count: Int64?) -> Int64? {
        count.flatMap { $0 > 0 ? $0 : nil }
    }

    private func imageTags(from item: ItemDTO) -> MediaServerImageTags {
        MediaServerImageTags(
            primary: item.imageTags?["Primary"].map(MediaServerImageTag.init(rawValue:)),
            logo: item.imageTags?["Logo"].map(MediaServerImageTag.init(rawValue:)),
            thumb: item.imageTags?["Thumb"].map(MediaServerImageTag.init(rawValue:)),
            backdrops: (item.backdropImageTags ?? []).map(MediaServerImageTag.init(rawValue:))
        )
    }

    private enum ReportEvent {
        case started
        case progress
        case stopped

        var path: String {
            switch self {
            case .started: "/Sessions/Playing"
            case .progress: "/Sessions/Playing/Progress"
            case .stopped: "/Sessions/Playing/Stopped"
            }
        }
    }

    private func sendReport(
        _ report: MediaServerPlaybackReport,
        event: ReportEvent,
        server: MediaServerAuthenticatedServer
    ) async throws {
        let body: Data
        switch event {
        case .started, .progress:
            body = try Self.makeEncoder().encode(PlaybackStatusReportDTO(
                itemId: report.itemID.rawValue,
                mediaSourceId: report.mediaSourceID.rawValue,
                playSessionId: report.playSessionID.rawValue,
                positionTicks: report.positionTicks,
                audioStreamIndex: report.audioStreamIndex,
                subtitleStreamIndex: report.subtitleStreamIndex,
                isPaused: report.isPaused,
                playMethod: "DirectPlay",
                eventName: event == .progress ? report.progressEvent ?? .timeUpdate : nil
            ))
        case .stopped:
            body = try Self.makeEncoder().encode(PlaybackStoppedReportDTO(
                itemId: report.itemID.rawValue,
                mediaSourceId: report.mediaSourceID.rawValue,
                playSessionId: report.playSessionID.rawValue,
                positionTicks: report.positionTicks
            ))
        }
        let request = try authorizedRequest(
            server: server,
            path: event.path,
            method: "POST",
            body: body
        )
        _ = try await data(for: request)
    }

    private func response<Response: Decodable>(for request: URLRequest) async throws -> Response {
        let data = try await data(for: request)
        return try Self.makeDecoder().decode(Response.self, from: data)
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MediaServerError.invalidResponse
        }
        guard 200..<300 ~= response.statusCode else {
            throw MediaServerError.httpStatus(response.statusCode)
        }
        return data
    }

    private func authorizedRequest(
        server: MediaServerAuthenticatedServer,
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) throws -> URLRequest {
        var request = try request(
            address: server.baseAddress,
            path: path,
            method: method,
            queryItems: queryItems,
            body: body
        )
        request.setValue(server.accessToken, forHTTPHeaderField: "X-Emby-Token")
        request.setValue(
            authorizationValue(userID: server.userID.rawValue, token: server.accessToken),
            forHTTPHeaderField: dialect == .jellyfin ? "Authorization" : "X-Emby-Authorization"
        )
        return request
    }

    private func request(
        address: URL,
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: try url(address: address, path: path, queryItems: queryItems))
        request.httpMethod = method
        request.httpBody = body
        request.setValue(authorizationValue(userID: nil, token: nil), forHTTPHeaderField: dialect == .jellyfin ? "Authorization" : "X-Emby-Authorization")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func authorizationValue(userID: String?, token: String?) -> String {
        var values = [
            "Client=\"\(clientIdentity.name)\"",
            "Device=\"\(clientIdentity.deviceName)\"",
            "DeviceId=\"\(clientIdentity.deviceID)\"",
            "Version=\"\(clientIdentity.version)\""
        ]
        if let userID {
            values.insert("UserId=\"\(userID)\"", at: 0)
        }
        if let token {
            values.append("Token=\"\(token)\"")
        }
        return "MediaBrowser " + values.joined(separator: ", ")
    }

    private func url(
        address: URL,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        let address = try normalizedAddress(address)
        guard var components = URLComponents(url: address, resolvingAgainstBaseURL: false) else {
            throw MediaServerError.invalidBaseAddress
        }
        var basePath = components.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        if dialect == .emby, basePath.lowercased().hasSuffix("/emby") == false {
            basePath += "/emby"
        }
        components.path = basePath + (path.hasPrefix("/") ? path : "/" + path)
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let result = components.url else { throw MediaServerError.invalidBaseAddress }
        return result
    }

    private func normalizedAddress(_ address: URL) throws -> URL {
        guard let scheme = address.scheme?.lowercased(), ["http", "https"].contains(scheme),
              address.host != nil,
              var components = URLComponents(url: address, resolvingAgainstBaseURL: false) else {
            throw MediaServerError.invalidBaseAddress
        }
        components.query = nil
        components.fragment = nil
        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let result = components.url else { throw MediaServerError.invalidBaseAddress }
        return result
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { keys in
            let value = keys.last?.stringValue ?? ""
            return MediaServerCodingKey(lowercasingFirstCharacterOf: value)
        }
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .custom { keys in
            let value = keys.last?.stringValue ?? ""
            return MediaServerCodingKey(uppercasingFirstCharacterOf: value)
        }
        return encoder
    }
}

private struct MediaServerCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(lowercasingFirstCharacterOf value: String) {
        stringValue = value.prefix(1).lowercased() + value.dropFirst()
    }

    init(uppercasingFirstCharacterOf value: String) {
        stringValue = value.prefix(1).uppercased() + value.dropFirst()
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
    }
}

private struct AuthenticationRequest: Encodable {
    let username: String
    let pw: String
}

private struct AuthenticationResultDTO: Decodable {
    let user: AuthenticationUserDTO?
    let accessToken: String?
    let serverId: String?
}

private struct AuthenticationUserDTO: Decodable {
    let id: String?
}

private struct ItemQueryResultDTO: Decodable {
    let items: [ItemDTO]
    let totalRecordCount: Int
}

private struct ItemDTO: Decodable {
    let id: String?
    let name: String?
    let type: String?
    let collectionType: String?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let overview: String?
    let runTimeTicks: Int64?
    let userData: UserDataDTO?
    let etag: String?
    let size: Int64?
    let seriesId: String?
    let seasonId: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let productionYear: Int?
    let officialRating: String?
    let communityRating: Double?
    let genres: [String]?
    let studios: [StudioDTO]?
    let people: [PersonDTO]?
    let productionLocations: [String]?
    let mediaSources: [MediaSourceDTO]?
}

private struct StudioDTO: Decodable {
    let name: String?
}

private struct PersonDTO: Decodable {
    let id: String?
    let name: String?
    let role: String?
    let type: String?
    let primaryImageTag: String?
}

private struct UserDataDTO: Decodable {
    let playbackPositionTicks: Int64?
    let played: Bool?
    let unplayedItemCount: Int?
}

private struct PlaybackInfoRequestDTO: Encodable {
    let userId: String
    let enableDirectPlay: Bool
    let enableDirectStream: Bool
    let enableTranscoding: Bool
    let isPlayback: Bool
}

private struct PlaybackInfoResponseDTO: Decodable {
    let mediaSources: [MediaSourceDTO]
    let playSessionId: String?
}

private struct MediaSourceDTO: Decodable {
    let id: String?
    let name: String?
    let path: String?
    let container: String?
    let size: Int64?
    let bitrate: Int?
    let supportsDirectPlay: Bool?
    let mediaStreams: [MediaStreamDTO]?
    let defaultAudioStreamIndex: Int?
    let defaultSubtitleStreamIndex: Int?
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }

    var lastPathComponentFromServerPath: String? {
        replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init)?
            .nonEmpty
    }
}

private struct MediaStreamDTO: Decodable {
    let index: Int
    let type: String?
    let codec: String?
    let language: String?
    let displayLanguage: String?
    let displayTitle: String?
    let title: String?
    let channels: Int?
    let channelLayout: String?
    let width: Int?
    let height: Int?
    let videoRange: String?
    let extendedVideoType: String?
    let extendedVideoSubTypeDescription: String?
    let bitRate: Int?
    let bitDepth: Int?
    let sampleRate: Int?
    let profile: String?
    let averageFrameRate: Double?
    let aspectRatio: String?
    let pixelFormat: String?
    let isDefault: Bool?
    let isForced: Bool?
    let isExternal: Bool?
    let isHearingImpaired: Bool?
    let deliveryUrl: String?
}

private struct PlaybackStatusReportDTO: Encodable {
    let itemId: String
    let mediaSourceId: String
    let playSessionId: String
    let positionTicks: Int64
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    let isPaused: Bool
    let playMethod: String
    let eventName: MediaServerPlaybackReport.ProgressEvent?
}

private struct PlaybackStoppedReportDTO: Encodable {
    let itemId: String
    let mediaSourceId: String
    let playSessionId: String
    let positionTicks: Int64
}
