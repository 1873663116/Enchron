import Foundation
import MediaSource

public final class EmbyClient: Sendable {
    private let session: URLSession
    private let clientIdentity: EmbyClientIdentity

    public init(session: URLSession = .shared, clientIdentity: EmbyClientIdentity) {
        self.session = session
        self.clientIdentity = clientIdentity
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

    public func authenticate(
        address: URL,
        username: String,
        password: String
    ) async throws -> EmbyAuthenticatedServer {
        let systemInfo = try await publicSystemInfo(at: address)
        let body = try Self.makeEncoder().encode(AuthenticationRequest(username: username, pw: password))
        let request = try request(
            address: address,
            path: "/Users/AuthenticateByName",
            method: "POST",
            body: body
        )
        let data = try await data(for: request)
        let result = try Self.makeDecoder().decode(AuthenticationResultDTO.self, from: data)
        guard let token = result.accessToken, token.isEmpty == false else {
            throw EmbyError.missingRequiredField("AccessToken")
        }
        guard let userID = result.user?.id, userID.isEmpty == false else {
            throw EmbyError.missingRequiredField("User.Id")
        }
        let serverID = result.serverId.flatMap { $0.isEmpty ? nil : $0 } ?? systemInfo.id.rawValue
        return EmbyAuthenticatedServer(
            id: EmbyServerID(rawValue: serverID),
            name: systemInfo.serverName,
            baseAddress: try normalizedAddress(address),
            accessToken: token,
            userID: EmbyUserID(rawValue: userID)
        )
    }

    public func views(on server: EmbyAuthenticatedServer) async throws -> [EmbyLibraryView] {
        let request = try authorizedRequest(
            server: server,
            path: "/Users/\(server.userID.rawValue)/Views",
            queryItems: [URLQueryItem(name: "IncludeExternalContent", value: "false")]
        )
        let result: ItemQueryResultDTO = try await response(for: request)
        return try result.items.map(mapView)
    }

    public func items(
        in viewID: EmbyItemID,
        on server: EmbyAuthenticatedServer,
        query: EmbyItemQuery = EmbyItemQuery()
    ) async throws -> EmbyItemPage {
        try await itemPage(
            path: "/Users/\(server.userID.rawValue)/Items",
            server: server,
            query: query,
            additionalQueryItems: [
                URLQueryItem(name: "ParentId", value: viewID.rawValue),
                URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series,Season,Episode,BoxSet"),
            ]
        )
    }

    public func children(
        of parent: EmbyLibraryItem,
        on server: EmbyAuthenticatedServer,
        query: EmbyItemQuery = EmbyItemQuery()
    ) async throws -> EmbyItemPage {
        let itemTypes: String
        switch parent {
        case .series:
            itemTypes = "Season"
        case .season:
            itemTypes = "Episode"
        case .boxSet:
            itemTypes = "Movie"
        case .movie, .episode:
            throw EmbyError.childrenUnavailable(parent.metadata.id)
        }
        return try await itemPage(
            path: "/Users/\(server.userID.rawValue)/Items",
            server: server,
            query: query,
            additionalQueryItems: [
                URLQueryItem(name: "ParentId", value: parent.metadata.id.rawValue),
                URLQueryItem(name: "IncludeItemTypes", value: itemTypes),
            ]
        )
    }

    public func resumeItems(
        on server: EmbyAuthenticatedServer,
        query: EmbyItemQuery = EmbyItemQuery(sortBy: [.dateCreated], sortOrder: .descending)
    ) async throws -> EmbyItemPage {
        try await itemPage(
            path: "/Users/\(server.userID.rawValue)/Items/Resume",
            server: server,
            query: query,
            additionalQueryItems: []
        )
    }

    public func nextUp(
        on server: EmbyAuthenticatedServer,
        seriesID: EmbyItemID? = nil,
        startIndex: Int? = nil,
        limit: Int? = nil
    ) async throws -> EmbyItemPage {
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
            URLQueryItem(name: "Fields", value: "Overview,MediaStreams"),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true"),
        ])
        let request = try authorizedRequest(
            server: server,
            path: "/Shows/NextUp",
            queryItems: items
        )
        let result: ItemQueryResultDTO = try await response(for: request)
        return EmbyItemPage(
            items: try result.items.compactMap(mapItem),
            totalRecordCount: result.totalRecordCount
        )
    }

    public func search(
        _ searchTerm: String,
        on server: EmbyAuthenticatedServer,
        query: EmbyItemQuery = EmbyItemQuery()
    ) async throws -> EmbyItemPage {
        try await itemPage(
            path: "/Users/\(server.userID.rawValue)/Items",
            server: server,
            query: query,
            additionalQueryItems: [
                URLQueryItem(name: "SearchTerm", value: searchTerm),
                URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series,Season,Episode,BoxSet"),
            ]
        )
    }

    public func imageURL(
        for itemID: EmbyItemID,
        type: EmbyImageType,
        tag: EmbyImageTag? = nil,
        size: EmbyImageSize? = nil,
        on server: EmbyAuthenticatedServer
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

    public func playbackInfo(
        for item: EmbyLibraryItem,
        on server: EmbyAuthenticatedServer
    ) async throws -> EmbyPlaybackSession {
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
            throw EmbyError.missingRequiredField("PlaySessionId")
        }
        let mediaSources = try result.mediaSources.compactMap { source in
            try mapMediaSource(source, item: item, server: server)
        }
        guard mediaSources.isEmpty == false else {
            throw EmbyError.directPlayUnavailable(itemID)
        }
        return EmbyPlaybackSession(
            id: EmbyPlaySessionID(rawValue: playSessionId),
            mediaSources: mediaSources
        )
    }

    public func reportPlayingStarted(
        _ report: EmbyPlaybackReport,
        on server: EmbyAuthenticatedServer
    ) {
        Task { try? await sendReport(report, event: .started, server: server) }
    }

    public func reportProgress(
        _ report: EmbyPlaybackReport,
        on server: EmbyAuthenticatedServer
    ) {
        Task { try? await sendReport(report, event: .progress, server: server) }
    }

    public func reportStopped(
        _ report: EmbyPlaybackReport,
        on server: EmbyAuthenticatedServer
    ) {
        Task { try? await sendReport(report, event: .stopped, server: server) }
    }

    private func itemPage(
        path: String,
        server: EmbyAuthenticatedServer,
        query: EmbyItemQuery,
        additionalQueryItems: [URLQueryItem]
    ) async throws -> EmbyItemPage {
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
        queryItems.append(contentsOf: [
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "Overview,MediaStreams"),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true"),
        ])
        let request = try authorizedRequest(server: server, path: path, queryItems: queryItems)
        let result: ItemQueryResultDTO = try await response(for: request)
        return EmbyItemPage(
            items: try result.items.compactMap(mapItem),
            totalRecordCount: result.totalRecordCount
        )
    }

    private func mapView(_ item: ItemDTO) throws -> EmbyLibraryView {
        guard let id = item.id, id.isEmpty == false else {
            throw EmbyError.missingRequiredField("Items[].Id")
        }
        guard let name = item.name, name.isEmpty == false else {
            throw EmbyError.missingRequiredField("Items[].Name")
        }
        return EmbyLibraryView(
            id: EmbyItemID(rawValue: id),
            name: name,
            collectionType: item.collectionType,
            imageTags: imageTags(from: item)
        )
    }

    private func mapItem(_ item: ItemDTO) throws -> EmbyLibraryItem? {
        guard let type = item.type else { return nil }
        let supportedTypes = ["movie", "series", "season", "episode", "boxset"]
        guard supportedTypes.contains(type.lowercased()) else { return nil }
        guard let id = item.id, id.isEmpty == false else {
            throw EmbyError.missingRequiredField("Items[].Id")
        }
        guard let name = item.name, name.isEmpty == false else {
            throw EmbyError.missingRequiredField("Items[].Name")
        }
        let metadata = EmbyItemMetadata(
            id: EmbyItemID(rawValue: id),
            name: name,
            imageTags: imageTags(from: item),
            overview: item.overview,
            runTimeTicks: item.runTimeTicks,
            userData: item.userData.map {
                EmbyUserData(
                    playbackPositionTicks: $0.playbackPositionTicks ?? 0,
                    played: $0.played ?? false,
                    unplayedItemCount: $0.unplayedItemCount
                )
            },
            entityTag: item.etag,
            sizeInBytes: item.size
        )
        switch type.lowercased() {
        case "movie":
            return .movie(EmbyMovie(metadata: metadata))
        case "series":
            return .series(EmbySeries(metadata: metadata))
        case "season":
            guard let seriesId = item.seriesId, seriesId.isEmpty == false else {
                throw EmbyError.missingRequiredField("Season.SeriesId")
            }
            return .season(EmbySeason(
                metadata: metadata,
                seriesID: EmbyItemID(rawValue: seriesId),
                indexNumber: item.indexNumber
            ))
        case "episode":
            guard let seriesId = item.seriesId, seriesId.isEmpty == false else {
                throw EmbyError.missingRequiredField("Episode.SeriesId")
            }
            return .episode(EmbyEpisode(
                metadata: metadata,
                seriesID: EmbyItemID(rawValue: seriesId),
                seasonID: item.seasonId.map(EmbyItemID.init(rawValue:)),
                seasonNumber: item.parentIndexNumber,
                episodeNumber: item.indexNumber
            ))
        case "boxset":
            return .boxSet(EmbyBoxSet(metadata: metadata))
        default:
            return nil
        }
    }

    private func mapMediaSource(
        _ source: MediaSourceDTO,
        item: EmbyLibraryItem,
        server: EmbyAuthenticatedServer
    ) throws -> EmbyMediaSource? {
        guard source.supportsDirectPlay == true else { return nil }
        guard let id = source.id, id.isEmpty == false else {
            throw EmbyError.missingRequiredField("MediaSources[].Id")
        }
        guard let container = source.container, container.isEmpty == false else {
            throw EmbyError.missingRequiredField("MediaSources[].Container")
        }
        let itemID = item.metadata.id
        let directPlayURL = try url(
            address: server.baseAddress,
            path: "/Videos/\(itemID.rawValue)/stream.\(container)",
            queryItems: [
                URLQueryItem(name: "Static", value: "true"),
                URLQueryItem(name: "MediaSourceId", value: id),
                URLQueryItem(name: "api_key", value: server.accessToken),
            ]
        )
        let streams = source.mediaStreams.map { stream in
            EmbyMediaStream(
                index: stream.index,
                kind: EmbyMediaStreamKind(rawValue: stream.type ?? "") ?? .unknown,
                codec: stream.codec,
                language: stream.language,
                displayTitle: stream.displayTitle ?? stream.title,
                channels: stream.channels,
                isDefault: stream.isDefault ?? false,
                isForced: stream.isForced ?? false,
                isExternal: stream.isExternal ?? false,
                deliveryURL: stream.deliveryUrl
            )
        }
        let videoIndex = streams.first { $0.kind == .video && $0.isDefault }?.index
            ?? streams.first { $0.kind == .video }?.index
        return EmbyMediaSource(
            id: EmbyMediaSourceID(rawValue: id),
            container: container,
            sizeInBytes: source.size,
            mediaStreams: streams,
            defaultStreamIndexes: EmbyDefaultStreamIndexes(
                video: videoIndex,
                audio: source.defaultAudioStreamIndex,
                subtitle: source.defaultSubtitleStreamIndex
            ),
            directPlayURL: directPlayURL,
            versionedIdentity: VersionedMediaIdentity.emby(
                serverID: server.id.rawValue,
                itemID: itemID.rawValue,
                mediaSourceID: id,
                itemEntityTag: item.metadata.entityTag,
                sizeInBytes: source.size,
                runTimeTicks: item.metadata.runTimeTicks
            )
        )
    }

    private func imageTags(from item: ItemDTO) -> EmbyImageTags {
        EmbyImageTags(
            primary: item.imageTags?["Primary"].map(EmbyImageTag.init(rawValue:)),
            logo: item.imageTags?["Logo"].map(EmbyImageTag.init(rawValue:)),
            thumb: item.imageTags?["Thumb"].map(EmbyImageTag.init(rawValue:)),
            backdrops: (item.backdropImageTags ?? []).map(EmbyImageTag.init(rawValue:))
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
        _ report: EmbyPlaybackReport,
        event: ReportEvent,
        server: EmbyAuthenticatedServer
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
                playMethod: "DirectPlay"
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
            throw EmbyError.invalidResponse
        }
        guard 200..<300 ~= response.statusCode else {
            throw EmbyError.httpStatus(response.statusCode)
        }
        return data
    }

    private func authorizedRequest(
        server: EmbyAuthenticatedServer,
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
            forHTTPHeaderField: "X-Emby-Authorization"
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
        request.setValue(authorizationValue(userID: nil, token: nil), forHTTPHeaderField: "X-Emby-Authorization")
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
            "Version=\"\(clientIdentity.version)\"",
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
            throw EmbyError.invalidBaseAddress
        }
        var basePath = components.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        if basePath.lowercased().hasSuffix("/emby") == false {
            basePath += "/emby"
        }
        components.path = basePath + (path.hasPrefix("/") ? path : "/" + path)
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let result = components.url else { throw EmbyError.invalidBaseAddress }
        return result
    }

    private func normalizedAddress(_ address: URL) throws -> URL {
        guard let scheme = address.scheme?.lowercased(), ["http", "https"].contains(scheme),
              address.host != nil,
              var components = URLComponents(url: address, resolvingAgainstBaseURL: false) else {
            throw EmbyError.invalidBaseAddress
        }
        components.query = nil
        components.fragment = nil
        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let result = components.url else { throw EmbyError.invalidBaseAddress }
        return result
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { keys in
            let value = keys.last?.stringValue ?? ""
            return EmbyCodingKey(lowercasingFirstCharacterOf: value)
        }
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .custom { keys in
            let value = keys.last?.stringValue ?? ""
            return EmbyCodingKey(uppercasingFirstCharacterOf: value)
        }
        return encoder
    }
}

private struct EmbyCodingKey: CodingKey {
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
    let container: String?
    let size: Int64?
    let supportsDirectPlay: Bool?
    let mediaStreams: [MediaStreamDTO]
    let defaultAudioStreamIndex: Int?
    let defaultSubtitleStreamIndex: Int?
}

private struct MediaStreamDTO: Decodable {
    let index: Int
    let type: String?
    let codec: String?
    let language: String?
    let displayTitle: String?
    let title: String?
    let channels: Int?
    let isDefault: Bool?
    let isForced: Bool?
    let isExternal: Bool?
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
}

private struct PlaybackStoppedReportDTO: Encodable {
    let itemId: String
    let mediaSourceId: String
    let playSessionId: String
    let positionTicks: Int64
}
