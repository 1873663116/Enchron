import Foundation
import MediaSource

public final class PlexClient: MediaServerClientProtocol, Sendable {
    public let kind = MediaServerKind.plex
    private let session: URLSession
    let clientIdentity: MediaServerClientIdentity

    public init(session: URLSession = MediaSourceNetwork.shared.session, clientIdentity: MediaServerClientIdentity) {
        self.session = session
        self.clientIdentity = clientIdentity
    }

    public func authenticate(_ login: MediaServerLogin) async throws -> MediaServerAuthenticatedServer {
        guard case let .plexToken(address, token, userID) = login else {
            throw MediaServerError.notAuthenticated
        }
        let provisional = MediaServerAuthenticatedServer(kind: .plex, id: .init(rawValue: ""), name: "Plex",
                                                        baseAddress: address, accessToken: token, userID: .init(rawValue: userID))
        return try await MediaSourceNetwork.shared.withConnectionApproval(to: address) { [self] in
            let root = try await container(path: "/", server: provisional)
            guard let identifier = root.machineIdentifier, !identifier.isEmpty else {
                throw MediaServerError.missingRequiredField("machineIdentifier")
            }
            return MediaServerAuthenticatedServer(kind: .plex, id: .init(rawValue: identifier), name: root.friendlyName ?? "Plex",
                                                  baseAddress: address, accessToken: token, userID: .init(rawValue: userID))
        }
    }

    public func views(on server: MediaServerAuthenticatedServer) async throws -> [MediaServerLibraryView] {
        let result = try await container(path: "/library/sections", server: server)
        return (result.Directory ?? []).compactMap { directory in
            guard let id = directory.key, let title = directory.title,
                  let type = directory.type, ["movie", "show"].contains(type) else { return nil }
            return MediaServerLibraryView(id: .init(rawValue: id), name: title,
                                         collectionType: type == "movie" ? "movies" : "tvshows", imageTags: .init())
        }
    }

    public func items(in viewID: MediaServerItemID, on server: MediaServerAuthenticatedServer,
                      query: MediaServerItemQuery) async throws -> MediaServerItemPage {
        var parameters = sortParameters(query)
        if let kinds = query.includeItemTypes {
            let types = kinds.map { kind -> String in
                switch kind {
                case .movie: "1"
                case .series: "2"
                case .season: "3"
                case .episode: "4"
                case .boxSet: "18"
                }
            }
            parameters.append(.init(name: "type", value: types.joined(separator: ",")))
        }
        return try await page(path: "/library/sections/\(viewID.rawValue)/all", server: server, query: query,
                              parameters: parameters)
    }

    public func item(withID itemID: MediaServerItemID, on server: MediaServerAuthenticatedServer) async throws -> MediaServerLibraryItem {
        let result = try await container(path: "/library/metadata/\(itemID.rawValue)", server: server,
                                         parameters: [.init(name: "includeExtras", value: "1")])
        guard let value = result.Metadata?.first, let item = try mapItem(value) else {
            throw MediaServerError.missingRequiredField("Metadata")
        }
        return item
    }

    public func children(of parent: MediaServerLibraryItem, on server: MediaServerAuthenticatedServer,
                         query: MediaServerItemQuery) async throws -> MediaServerItemPage {
        try await page(path: "/library/metadata/\(parent.metadata.id.rawValue)/children", server: server, query: query)
    }

    public func resumeItems(on server: MediaServerAuthenticatedServer, query: MediaServerItemQuery) async throws -> MediaServerItemPage {
        let values = try await allMetadata(path: "/hubs/home/continueWatching", server: server)
        let items = try values.compactMap(mapItem).filter { ($0.metadata.userData?.playbackPositionTicks ?? 0) > 0 }
        return .init(items: Array(items.dropFirst(query.startIndex ?? 0).prefix(query.limit ?? items.count)), totalRecordCount: items.count)
    }

    public func latestItems(in viewID: MediaServerItemID, on server: MediaServerAuthenticatedServer,
                            limit: Int?) async throws -> [MediaServerLibraryItem] {
        try await page(path: "/library/sections/\(viewID.rawValue)/recentlyAdded", server: server,
                       query: .init(limit: limit)).items
    }

    public func nextUp(on server: MediaServerAuthenticatedServer, seriesID: MediaServerItemID?,
                       startIndex: Int?, limit: Int?) async throws -> MediaServerItemPage {
        let values = try await allMetadata(path: "/library/onDeck", server: server)
        let items = try values.compactMap(mapItem).filter { item in
            guard let episode = item.episode else { return false }
            return (seriesID == nil || episode.seriesID == seriesID) && (item.metadata.userData?.playbackPositionTicks ?? 0) == 0
        }
        let start = min(max(0, startIndex ?? 0), items.count)
        return MediaServerItemPage(items: Array(items.dropFirst(start).prefix(limit ?? items.count)), totalRecordCount: items.count)
    }

    public func search(_ searchTerm: String, on server: MediaServerAuthenticatedServer,
                        query: MediaServerItemQuery) async throws -> MediaServerItemPage {
        var values = try await allMetadata(path: "/search", server: server,
                                          parameters: [.init(name: "query", value: searchTerm)])
        if query.includeItemTypes?.contains(.boxSet) ?? true {
            let collections = try await allMetadata(path: "/library/all", server: server,
                                                     parameters: [.init(name: "type", value: "18"),
                                                                  .init(name: "title", value: searchTerm)])
            values.append(contentsOf: collections)
        }
        var seen = Set<MediaServerItemID>()
        let items = try values.compactMap(mapItem).filter { item in
            let type: MediaServerItemKind = switch item {
            case .movie: .movie
            case .series: .series
            case .season: .season
            case .episode: .episode
            case .boxSet: .boxSet
            }
            return (query.includeItemTypes?.contains(type) ?? true) && seen.insert(item.metadata.id).inserted
        }.sorted { left, right in
            let order = left.metadata.name.localizedStandardCompare(right.metadata.name)
            return query.sortOrder == .ascending ? order == .orderedAscending : order == .orderedDescending
        }
        return MediaServerItemPage(items: Array(items.dropFirst(query.startIndex ?? 0).prefix(query.limit ?? items.count)),
                                   totalRecordCount: items.count)
    }

    public func specialFeatures(for itemID: MediaServerItemID, on server: MediaServerAuthenticatedServer) async throws -> [MediaServerLibraryItem] {
        let result = try await container(path: "/library/metadata/\(itemID.rawValue)", server: server,
                                         parameters: [.init(name: "includeExtras", value: "1")])
        var extras = result.Metadata?.first?.Extras?.Metadata ?? []
        if let key = result.Metadata?.first?.primaryExtraKey,
           !extras.contains(where: { key == "/library/metadata/" + ($0.ratingKey ?? "") }) {
            let primary = try await container(path: key, server: server)
            extras.append(contentsOf: primary.Metadata ?? [])
        }
        return try extras.compactMap(mapItem)
    }

    public func similarItems(to itemID: MediaServerItemID, on server: MediaServerAuthenticatedServer,
                             limit: Int?) async throws -> MediaServerItemPage {
        let result = try await container(path: "/library/metadata/\(itemID.rawValue)/related", server: server)
        let items = try (result.Hub ?? []).filter { $0.hubIdentifier?.contains("similar") == true }
            .flatMap { $0.Metadata ?? [] }.compactMap(mapItem)
        return .init(items: Array(items.prefix(limit ?? items.count)), totalRecordCount: items.count)
    }

    public func imageURL(for itemID: MediaServerItemID, type: MediaServerImageType, tag: MediaServerImageTag?,
                          size: MediaServerImageSize?, on server: MediaServerAuthenticatedServer) throws -> URL {
        let path = tag?.rawValue ?? "/library/metadata/\(itemID.rawValue)/thumb"
        if let external = URL(string: path), let scheme = external.scheme {
            guard ["http", "https"].contains(scheme), external.host != nil else { throw MediaServerError.invalidResponse }
            return external
        }
        return try url(path: path, server: server)
    }

    public func playbackInfo(for item: MediaServerLibraryItem, on server: MediaServerAuthenticatedServer) async throws -> MediaServerPlaybackSession {
        let result = try await container(path: "/library/metadata/\(item.metadata.id.rawValue)", server: server)
        guard let metadata = result.Metadata?.first else { throw MediaServerError.invalidResponse }
        let sources: [MediaServerMediaSource] = try (metadata.Media ?? []).compactMap { media in
            guard let mediaID = media.id, let parts = media.Part, parts.count == 1,
                  let part = parts.first, let key = part.key else { return nil }
            let streams = mapStreams(part.Stream ?? [])
            return MediaServerMediaSource(
                id: .init(rawValue: String(mediaID)), displayName: mediaLabel(media), container: media.container,
                sizeInBytes: part.size, mediaStreams: streams,
                defaultStreamIndexes: .init(video: streams.first { $0.kind == .video }?.index,
                                           audio: streams.first { $0.kind == .audio && $0.isDefault }?.index,
                                           subtitle: streams.first { $0.kind == .subtitle && $0.isDefault }?.index),
                directPlayURL: try url(path: key, server: server),
                versionedIdentity: .mediaServer(provider: "plex", serverID: server.id.rawValue, itemID: item.metadata.id.rawValue,
                                                mediaSourceID: String(mediaID), itemEntityTag: metadata.updatedAt.map(String.init),
                                                sizeInBytes: part.size, runTimeTicks: metadata.duration.map { $0 * 10_000 })
            )
        }
        guard !sources.isEmpty else { throw MediaServerError.directPlayUnavailable(item.metadata.id) }
        return .init(id: .init(rawValue: UUID().uuidString), mediaSources: sources)
    }

    public func externalSubtitleURL(for stream: MediaServerMediaStream, on server: MediaServerAuthenticatedServer) throws -> URL {
        guard let path = stream.deliveryURL else { throw MediaServerError.externalSubtitleUnavailable(stream.index) }
        return try url(path: path, server: server)
    }

    public func sendPlayingStarted(_ report: MediaServerPlaybackReport, on server: MediaServerAuthenticatedServer) async throws {
        try await timeline(report, state: "playing", server: server)
    }

    public func sendProgress(_ report: MediaServerPlaybackReport, on server: MediaServerAuthenticatedServer) async throws {
        switch report.progressEvent {
        case .audioTrackChange, .subtitleTrackChange:
            try await persistTrackSelection(report, server: server)
        case .timeUpdate, .pause, .unpause, nil:
            break
        }
        try await timeline(report, state: report.isPaused ? "paused" : "playing", server: server)
    }

    public func sendStopped(_ report: MediaServerPlaybackReport, on server: MediaServerAuthenticatedServer) async throws {
        try await timeline(report, state: "stopped", server: server)
    }

    private func persistTrackSelection(_ report: MediaServerPlaybackReport, server: MediaServerAuthenticatedServer) async throws {
        let result = try await container(path: "/library/metadata/\(report.itemID.rawValue)", server: server)
        guard let part = result.Metadata?.first?.Media?.first(where: { $0.id.map(String.init) == report.mediaSourceID.rawValue })?.Part?.first,
              let partID = part.id else { throw MediaServerError.invalidResponse }
        let parameter: URLQueryItem
        switch report.progressEvent {
        case .audioTrackChange:
            guard let index = report.audioStreamIndex,
                  let id = part.Stream?.first(where: { $0.streamType == 2 && $0.index == index })?.id else { return }
            parameter = .init(name: "audioStreamID", value: String(id))
        case .subtitleTrackChange:
            let index = report.subtitleStreamIndex ?? -1
            if index < 0 {
                parameter = .init(name: "subtitleStreamID", value: "0")
            } else {
                guard let id = part.Stream?.first(where: { $0.streamType == 3 && ($0.index ?? $0.id) == index })?.id else { return }
                parameter = .init(name: "subtitleStreamID", value: String(id))
            }
        case .timeUpdate, .pause, .unpause, nil:
            return
        }
        _ = try await data(path: "/library/parts/\(partID)", server: server,
                           parameters: [parameter, .init(name: "allParts", value: "1")], method: "PUT")
    }

    private func timeline(_ report: MediaServerPlaybackReport, state: String, server: MediaServerAuthenticatedServer) async throws {
        let duration = if let ticks = report.durationTicks {
            ticks / 10_000
        } else {
            (try await item(withID: report.itemID, on: server).metadata.runTimeTicks ?? 0) / 10_000
        }
        _ = try await data(path: "/:/timeline", server: server, parameters: [
            .init(name: "ratingKey", value: report.itemID.rawValue),
            .init(name: "key", value: "/library/metadata/\(report.itemID.rawValue)"),
            .init(name: "duration", value: String(duration)),
            .init(name: "state", value: state), .init(name: "time", value: String(report.positionTicks / 10_000)),
            .init(name: "playbackTime", value: String(report.positionTicks / 10_000)),
            .init(name: "session", value: report.playSessionID.rawValue)
        ])
    }

    private func allMetadata(path: String, server: MediaServerAuthenticatedServer,
                             parameters: [URLQueryItem] = []) async throws -> [PlexMetadata] {
        var values: [PlexMetadata] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let result = try await container(path: path, server: server, parameters: parameters + [
                .init(name: "X-Plex-Container-Start", value: String(offset)),
                .init(name: "X-Plex-Container-Size", value: "200")
            ])
            if let actualOffset = result.offset, actualOffset != offset { throw MediaServerError.invalidResponse }
            values.append(contentsOf: result.Metadata ?? [])
            let count = result.size ?? ((result.Metadata?.count ?? 0) + (result.Directory?.count ?? 0))
            offset += count
            guard count > 0, let total = result.totalSize, offset < total else { return values }
        }
    }

    private func page(path: String, server: MediaServerAuthenticatedServer, query: MediaServerItemQuery,
                       parameters: [URLQueryItem] = []) async throws -> MediaServerItemPage {
        let result = try await container(path: path, server: server, parameters: parameters + [
            .init(name: "X-Plex-Container-Start", value: String(query.startIndex ?? 0)),
            .init(name: "X-Plex-Container-Size", value: String(query.limit ?? 200))
        ])
        let items = try (result.Metadata ?? []).compactMap(mapItem)
        return .init(items: items, totalRecordCount: result.totalSize ?? result.size ?? items.count)
    }

    private func sortParameters(_ query: MediaServerItemQuery) -> [URLQueryItem] {
        let fields = query.sortBy.map { sort -> String in
            let field: String = switch sort {
            case .sortName: "titleSort"
            case .indexNumber: "index"
            case .dateCreated: "addedAt"
            case .datePlayed: "lastViewedAt"
            case .premiereDate: "originallyAvailableAt"
            case .communityRating: "rating"
            case .runtime: "duration"
            case .random: "random"
            }
            return field + (query.sortOrder == .descending ? ":desc" : ":asc")
        }
        return [.init(name: "sort", value: fields.joined(separator: ","))]
    }

    private func container(path: String, server: MediaServerAuthenticatedServer,
                            parameters: [URLQueryItem] = []) async throws -> PlexContainer {
        try JSONDecoder().decode(PlexEnvelope.self, from: await data(path: path, server: server, parameters: parameters)).MediaContainer
    }

    private func data(path: String, server: MediaServerAuthenticatedServer, parameters: [URLQueryItem], method: String = "GET") async throws -> Data {
        var request = URLRequest(url: try url(path: path, server: server, parameters: parameters))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientIdentity.deviceID, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(clientIdentity.name, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(clientIdentity.version, forHTTPHeaderField: "X-Plex-Version")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MediaServerError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw MediaServerError.httpStatus(response.statusCode) }
        return data
    }

    private func url(path: String, server: MediaServerAuthenticatedServer, parameters: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: server.baseAddress, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""), components.host != nil,
              let relative = URLComponents(string: path), relative.host == nil, relative.scheme == nil else {
            throw MediaServerError.invalidBaseAddress
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + relative.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.hasPrefix("/") { components.path = "/" + components.path }
        components.queryItems = (relative.queryItems ?? []) + parameters + [.init(name: "X-Plex-Token", value: server.accessToken)]
        guard let url = components.url else { throw MediaServerError.invalidBaseAddress }
        return url
    }

    private func mapItem(_ value: PlexMetadata) throws -> MediaServerLibraryItem? {
        guard let type = value.type, ["movie", "show", "season", "episode", "collection", "clip"].contains(type) else { return nil }
        guard let id = value.ratingKey, let name = value.title else { throw MediaServerError.missingRequiredField("ratingKey/title") }
        let sources = (value.Media ?? []).compactMap { media -> MediaServerMediaSourceDescription? in
            guard let id = media.id else { return nil }
            return .init(id: .init(rawValue: String(id)), displayName: mediaLabel(media), container: media.container,
                         sizeInBytes: media.Part?.first?.size, bitrate: media.bitrate.map { $0 * 1000 },
                         mediaStreams: mapStreams(media.Part?.first?.Stream ?? []))
        }
        let metadata = MediaServerItemMetadata(
            id: .init(rawValue: id), name: name,
            imageTags: .init(primary: value.thumb.map { .init(rawValue: $0) },
                             logo: value.Image?.first { $0.type == "clearLogo" }.map { .init(rawValue: $0.url) }, thumb: value.thumb.map { .init(rawValue: $0) },
                             backdrops: value.art.map { [.init(rawValue: $0)] } ?? []),
            overview: value.summary, runTimeTicks: value.duration.map { $0 * 10_000 },
            userData: .init(playbackPositionTicks: (value.viewOffset ?? 0) * 10_000, played: (value.viewCount ?? 0) > 0,
                            unplayedItemCount: value.leafCount.map { max(0, $0 - (value.viewedLeafCount ?? 0)) }),
            entityTag: value.updatedAt.map(String.init), sizeInBytes: value.Media?.first?.Part?.first?.size,
            productionYear: value.year, officialRating: value.contentRating, communityRating: value.rating,
            genres: (value.Genre ?? []).compactMap(\.tag), studios: value.studio.map { [.init(name: $0)] } ?? [],
            people: (value.Role ?? []).compactMap { person in
                guard let name = person.tag else { return nil }
                return .init(id: person.id.map { .init(rawValue: String($0)) }, name: name, role: person.role, type: "Actor",
                             primaryImageTag: person.thumb.map { .init(rawValue: $0) })
            }, productionLocations: (value.Country ?? []).compactMap(\.tag), mediaSources: sources
        )
        switch type {
        case "movie", "clip": return .movie(.init(metadata: metadata))
        case "show": return .series(.init(metadata: metadata))
        case "season":
            guard let parent = value.parentRatingKey else { throw MediaServerError.missingRequiredField("parentRatingKey") }
            return .season(.init(metadata: metadata, seriesID: .init(rawValue: parent), indexNumber: value.index))
        case "episode":
            guard let series = value.grandparentRatingKey else { throw MediaServerError.missingRequiredField("grandparentRatingKey") }
            return .episode(.init(metadata: metadata, seriesID: .init(rawValue: series),
                                  seasonID: value.parentRatingKey.map { .init(rawValue: $0) },
                                  seasonNumber: value.parentIndex, episodeNumber: value.index))
        case "collection": return .boxSet(.init(metadata: metadata))
        default: return nil
        }
    }

    private func mediaLabel(_ media: PlexMedia) -> String {
        [media.videoResolution.map { Int($0) == nil ? $0.uppercased() : "\($0)p" }, media.videoCodec?.uppercased(), media.container?.uppercased()]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func mapStreams(_ streams: [PlexStream]) -> [MediaServerMediaStream] {
        streams.compactMap { stream in
            let kind: MediaServerMediaStreamKind
            switch stream.streamType {
            case 1: kind = .video
            case 2: kind = .audio
            case 3: kind = .subtitle
            default: return nil
            }
            guard let index = stream.index ?? (stream.key != nil ? stream.id : nil) else { return nil }
            return .init(index: index, kind: kind, codec: stream.codec, language: stream.languageCode,
                         displayLanguage: stream.language, displayTitle: stream.displayTitle, channels: stream.channels,
                         width: stream.width, height: stream.height, bitRate: stream.bitrate.map { $0 * 1000 },
                         isDefault: stream.selected == true || (stream.streamType != 3 && stream.default == true &&
                            !streams.contains { $0.streamType == stream.streamType && $0.selected == true }),
                         isForced: stream.forced == true,
                         isExternal: stream.key != nil, deliveryURL: stream.key)
        }
    }
}

private struct PlexEnvelope: Decodable { let MediaContainer: PlexContainer }
private struct PlexContainer: Decodable {
    let machineIdentifier: String?
    let friendlyName: String?
    let size: Int?
    let totalSize: Int?
    let offset: Int?
    let Directory: [PlexDirectory]?
    let Metadata: [PlexMetadata]?
    let Hub: [PlexHub]?
}
private struct PlexDirectory: Decodable { let key: String?; let title: String?; let type: String? }
private struct PlexHub: Decodable { let hubIdentifier: String?; let Metadata: [PlexMetadata]? }
private struct PlexExtras: Decodable { let Metadata: [PlexMetadata]? }
private struct PlexMetadata: Decodable {
    let ratingKey: String?
    let type: String?
    let title: String?
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let parentIndex: Int?
    let index: Int?
    let summary: String?
    let thumb: String?
    let art: String?
    let duration: Int64?
    let viewOffset: Int64?
    let viewCount: Int?
    let leafCount: Int?
    let viewedLeafCount: Int?
    let updatedAt: Int64?
    let year: Int?
    let rating: Double?
    let contentRating: String?
    let studio: String?
    let Genre: [PlexTag]?
    let Country: [PlexTag]?
    let Role: [PlexTag]?
    let Media: [PlexMedia]?
    let Extras: PlexExtras?
    let primaryExtraKey: String?
    let Image: [PlexImage]?
}
private struct PlexTag: Decodable { let id: Int?; let tag: String?; let role: String?; let thumb: String? }
private struct PlexImage: Decodable { let type: String; let url: String }
private struct PlexMedia: Decodable {
    let id: Int?
    let container: String?
    let bitrate: Int?
    let videoCodec: String?
    let videoResolution: String?
    let Part: [PlexPart]?
}
private struct PlexPart: Decodable { let id: Int?; let key: String?; let size: Int64?; let Stream: [PlexStream]? }
private struct PlexStream: Decodable {
    let id: Int?
    let index: Int?
    let streamType: Int?
    let codec: String?
    let language: String?
    let languageCode: String?
    let displayTitle: String?
    let channels: Int?
    let width: Int?
    let height: Int?
    let bitrate: Int?
    let selected: Bool?
    let `default`: Bool?
    let forced: Bool?
    let key: String?
}
