import DesignSystem
import Foundation
import Observation

@MainActor
@Observable
public final class MediaServerNavigationModel {
    public enum Destination: Hashable, Sendable {
        case home
        case library(MediaServerItemID)

        var id: String {
            switch self {
            case .home: "home"
            case .library(let id): "library-\(id.rawValue)"
            }
        }
    }

    public var destination: Destination
    public var path: [MediaServerLibraryItem]

    public init(destination: Destination = .home, path: [MediaServerLibraryItem] = []) {
        self.destination = destination
        self.path = path
    }

    public func select(_ destination: Destination) {
        self.destination = destination
        path = []
    }

    public func open(_ item: MediaServerLibraryItem) {
        path.append(item)
    }

    public func reset() {
        destination = .home
        path = []
    }
}

public struct MediaServerHomeShelf: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case continueWatching
        case nextUp
        case recentlyAdded(MediaServerItemID)
    }

    public let kind: Kind
    public let title: String
    public let items: [MediaServerLibraryItem]

    public var id: Kind { kind }

    public init(kind: Kind, title: String, items: [MediaServerLibraryItem]) {
        self.kind = kind
        self.title = title
        self.items = items
    }
}

@MainActor
@Observable
public final class MediaServerHomeViewModel {
    public private(set) var libraries: [MediaServerLibraryView] = []
    public private(set) var shelves: [MediaServerHomeShelf] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let client: any MediaServerClientProtocol
    private let session: MediaServerSessionViewModel
    @ObservationIgnored private var libraryViewModels: [MediaServerItemID: MediaServerLibraryViewModel] = [:]

    public init(client: any MediaServerClientProtocol, session: MediaServerSessionViewModel) {
        self.client = client
        self.session = session
    }

    public func libraryViewModel(for library: MediaServerLibraryView) -> MediaServerLibraryViewModel {
        if let existing = libraryViewModels[library.id] {
            return existing
        }
        let viewModel = MediaServerLibraryViewModel(library: library, client: client, session: session)
        libraryViewModels[library.id] = viewModel
        return viewModel
    }

    public func refresh() async {
        guard let server = session.server else {
            libraries = []
            shelves = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedLibraries = try await client.views(on: server)
            let continueWatching = try await client.resumeItems(
                on: server,
                query: MediaServerItemQuery(
                    sortBy: [.datePlayed],
                    sortOrder: .descending,
                    limit: 20
                )
            ).items
            let nextUp = client.capabilities.nextUp ? try await client.nextUp(
                on: server,
                seriesID: nil,
                startIndex: nil,
                limit: 20
            ).items : []
            var loadedShelves: [MediaServerHomeShelf] = []
            if continueWatching.isEmpty == false {
                loadedShelves.append(MediaServerHomeShelf(
                    kind: .continueWatching,
                    title: String(localized: "Continue Watching"),
                    items: continueWatching
                ))
            }
            if nextUp.isEmpty == false {
                loadedShelves.append(MediaServerHomeShelf(
                    kind: .nextUp,
                    title: String(localized: "Next Up"),
                    items: nextUp
                ))
            }
            for library in loadedLibraries {
                let latest = try await client.latestItems(
                    in: library.id,
                    on: server,
                    limit: 20
                )
                if latest.isEmpty == false {
                    loadedShelves.append(MediaServerHomeShelf(
                        kind: .recentlyAdded(library.id),
                        title: String(localized: "Recently Added in \(library.name)"),
                        items: latest
                    ))
                }
            }
            libraries = loadedLibraries
            shelves = loadedShelves
            errorMessage = nil
            await warmArtwork(of: loadedShelves, on: server)
        } catch {
            if await session.handleRequestError(error) == false {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func warmArtwork(of shelves: [MediaServerHomeShelf], on server: MediaServerAuthenticatedServer) async {
#if DEBUG
        let requests = shelves.flatMap { shelf -> [MediaServerArtworkLoadRequest] in
            let isStill = shelf.kind == .continueWatching
            let width = Int((isStill ? DesignTokens.Card.stillWidth : DesignTokens.Card.posterWidth) * 2)
            return shelf.items.compactMap { item -> MediaServerArtworkLoadRequest? in
                let metadata = item.metadata
                let type: MediaServerImageType = isStill && metadata.imageTags.thumb != nil ? .thumb : .primary
                let tag = type == .thumb ? metadata.imageTags.thumb : metadata.imageTags.primary
                guard let tag,
                      let url = try? client.imageURL(
                    for: metadata.id,
                    type: type,
                    tag: tag,
                    size: try? MediaServerImageSize.width(width),
                    on: server
                      ) else { return nil }
                return MediaServerArtworkLoadRequest(
                    itemID: metadata.id,
                    imageType: type,
                    imageTag: tag,
                    url: url
                )
            }
        }
        await session.warmArtwork(requests)
#else
        let urls = shelves.flatMap { shelf -> [URL] in
            let isStill = shelf.kind == .continueWatching
            let width = Int((isStill ? DesignTokens.Card.stillWidth : DesignTokens.Card.posterWidth) * 2)
            return shelf.items.compactMap { item -> URL? in
                let metadata = item.metadata
                let type: MediaServerImageType = isStill && metadata.imageTags.thumb != nil ? .thumb : .primary
                let tag = type == .thumb ? metadata.imageTags.thumb : metadata.imageTags.primary
                guard tag != nil else { return nil }
                return try? client.imageURL(
                    for: metadata.id,
                    type: type,
                    tag: tag,
                    size: try? MediaServerImageSize.width(width),
                    on: server
                )
            }
        }
        await ArtworkPrefetch.warm(urls)
#endif
    }
}

public enum MediaServerLibrarySort: String, CaseIterable, Sendable {
    case recentlyAdded
    case alphabetical

    public var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .alphabetical: "Alphabetical"
        }
    }
}

@MainActor
@Observable
public final class MediaServerLibraryViewModel {
    public let library: MediaServerLibraryView
    public private(set) var items: [MediaServerLibraryItem] = []
    public private(set) var sort: MediaServerLibrarySort = .recentlyAdded
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let client: any MediaServerClientProtocol
    private let session: MediaServerSessionViewModel

    public init(
        library: MediaServerLibraryView,
        client: any MediaServerClientProtocol,
        session: MediaServerSessionViewModel
    ) {
        self.library = library
        self.client = client
        self.session = session
    }

    public func refresh() async {
        guard let server = session.server else {
            items = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let query = switch sort {
            case .recentlyAdded:
                MediaServerItemQuery(
                    sortBy: [.dateCreated],
                    sortOrder: .descending,
                    includeItemTypes: library.topLevelItemKinds
                )
            case .alphabetical:
                MediaServerItemQuery(
                    sortBy: [.sortName],
                    sortOrder: .ascending,
                    includeItemTypes: library.topLevelItemKinds
                )
            }
            items = try await client.items(in: library.id, on: server, query: query).items
            errorMessage = nil
        } catch {
            if await session.handleRequestError(error) == false {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func setSort(_ sort: MediaServerLibrarySort) {
        self.sort = sort
    }
}

@MainActor
@Observable
public final class MediaServerSearchViewModel {
    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            requestID = UUID()
            loadedQuery = nil
            results = []
            errorMessage = nil
            isSearching = hasQuery && session.server != nil
        }
    }
    public var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public private(set) var results: [MediaServerLibraryItem] = []
    public private(set) var isSearching = false
    public private(set) var errorMessage: String?

    private let client: any MediaServerClientProtocol
    private let session: MediaServerSessionViewModel
    private var requestID = UUID()
    private var loadedQuery: String?

    public init(client: any MediaServerClientProtocol, session: MediaServerSessionViewModel) {
        self.client = client
        self.session = session
    }

    public func refreshIfNeeded() async {
        guard loadedQuery != query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        await refresh()
    }

    public func refresh() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.isEmpty == false, let server = session.server else {
            requestID = UUID()
            results = []
            errorMessage = nil
            isSearching = false
            return
        }
        let requestID = UUID()
        self.requestID = requestID
        isSearching = true
        defer {
            if self.requestID == requestID { isSearching = false }
        }
        do {
            let response = try await client.search(
                term,
                on: server,
                query: MediaServerItemQuery(
                    sortBy: [.sortName],
                    sortOrder: .ascending,
                    includeItemTypes: [.movie, .series, .boxSet]
                )
            ).items
            guard self.requestID == requestID, session.server == server,
                  !Task.isCancelled else { return }
            results = response
            loadedQuery = term
            errorMessage = nil
        } catch {
            guard self.requestID == requestID, session.server == server,
                  !Task.isCancelled, !(error is CancellationError) else { return }
            if await session.handleRequestError(error) == false {
                guard self.requestID == requestID else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

public enum MediaServerDetailChildren: Equatable, Sendable {
    case none
    case seasons(all: [MediaServerSeason], selected: MediaServerItemID?, episodes: [MediaServerEpisode])
    case episodes([MediaServerEpisode])
    case collection([MediaServerLibraryItem])

    public var episodes: [MediaServerEpisode] {
        switch self {
        case .seasons(_, _, let episodes): episodes
        case .episodes(let episodes): episodes
        case .none, .collection: []
        }
    }

    var selectedSeasonID: MediaServerItemID? {
        guard case .seasons(_, let selected, _) = self else { return nil }
        return selected
    }
}

@MainActor
@Observable
public final class MediaServerDetailViewModel {
    private enum Context {
        case item(MediaServerLibraryItem)
        case series(MediaServerSeries, resumeEpisode: MediaServerEpisode)

        var item: MediaServerLibraryItem {
            switch self {
            case .item(let item): item
            case .series(let series, _): .series(series)
            }
        }

        var primaryPlaybackItem: MediaServerLibraryItem? {
            switch self {
            case .item(let item): item.isPlayable ? item : nil
            case .series(_, let episode): .episode(episode)
            }
        }
    }

    public let itemID: MediaServerItemID
    public var item: MediaServerLibraryItem? { context?.item }
    public var primaryPlaybackItem: MediaServerLibraryItem? { context?.primaryPlaybackItem }
    public var seasonSelectionID: MediaServerItemID? { preferredSeasonID ?? children.selectedSeasonID }
    public var initialEpisodeID: MediaServerItemID? {
        guard case let .series(_, episode) = context,
              children.episodes.contains(where: { $0.metadata.id == episode.metadata.id }) else { return nil }
        return episode.metadata.id
    }
    public private(set) var children: MediaServerDetailChildren = .none
    public private(set) var specialFeatures: [MediaServerLibraryItem] = []
    public private(set) var relatedItems: [MediaServerLibraryItem] = []
    public var selectedMediaSourceID: MediaServerMediaSourceID?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let client: any MediaServerClientProtocol
    private let session: MediaServerSessionViewModel
    private var context: Context?
    private var requestID = UUID()
    private var preferredSeasonID: MediaServerItemID?

    public init(
        itemID: MediaServerItemID,
        client: any MediaServerClientProtocol,
        session: MediaServerSessionViewModel,
        knownItem: MediaServerLibraryItem? = nil
    ) {
        self.itemID = itemID
        self.client = client
        self.session = session
        if let knownItem, knownItem.episode == nil {
            context = .item(knownItem)
        }
        selectedMediaSourceID = knownItem?.metadata.mediaSources.first?.id
    }

    public func refresh() async {
        let request = UUID()
        requestID = request
        guard let server = session.server else {
            clear()
            return
        }
        let preferredSeasonID = preferredSeasonID
        isLoading = true
        defer { if requestID == request { isLoading = false } }
        do {
            let freshItem = try await client.item(withID: itemID, on: server)
            let loadedContext: Context
            if case let .episode(episode) = freshItem {
                guard case let .series(series) = try await client.item(withID: episode.seriesID, on: server) else {
                    throw MediaServerError.invalidResponse
                }
                loadedContext = .series(series, resumeEpisode: episode)
            } else {
                loadedContext = .item(freshItem)
            }
            let displayID = loadedContext.item.metadata.id
            async let features = client.capabilities.specialFeatures ? client.specialFeatures(for: displayID, on: server) : []
            async let related = client.capabilities.similarItems ? client.similarItems(to: displayID, on: server, limit: 20) : MediaServerItemPage(items: [], totalRecordCount: 0)
            let loadedChildren = try await loadChildren(of: loadedContext, preferredSeasonID: preferredSeasonID, on: server)
            let loadedFeatures = try await features
            let loadedRelated = try await related.items
            try Task.checkCancellation()
            guard requestID == request, session.server == server else { return }
            context = loadedContext
            children = loadedChildren
            self.preferredSeasonID = loadedChildren.selectedSeasonID
            specialFeatures = loadedFeatures
            relatedItems = loadedRelated
            let availableSources = primaryPlaybackItem?.metadata.mediaSources ?? []
            if availableSources.contains(where: { $0.id == selectedMediaSourceID }) == false {
                selectedMediaSourceID = availableSources.first?.id
            }
            errorMessage = nil
        } catch {
            guard requestID == request, session.server == server, !(error is CancellationError) else { return }
            if await session.handleRequestError(error) == false, requestID == request {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func selectSeason(_ seasonID: MediaServerItemID) async {
        guard case .seasons(let all, let selected, _) = children,
              selected != seasonID || preferredSeasonID != seasonID,
              let season = all.first(where: { $0.metadata.id == seasonID }),
              let server = session.server else { return }
        let request = UUID()
        requestID = request
        preferredSeasonID = seasonID
        isLoading = true
        defer { if requestID == request { isLoading = false } }
        do {
            let loadedEpisodes = try await episodes(of: season, on: server)
            try Task.checkCancellation()
            guard requestID == request, session.server == server else { return }
            children = .seasons(all: all, selected: seasonID, episodes: loadedEpisodes)
            errorMessage = nil
        } catch {
            guard requestID == request, session.server == server, !(error is CancellationError) else { return }
            if await session.handleRequestError(error) == false, requestID == request {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func playbackSelection(
        startAction: MediaServerPlaybackStartAction
    ) async throws -> MediaServerPlaybackSelection {
        guard let primaryPlaybackItem else { throw MediaServerError.notAuthenticated }
        let freshItem = try await currentPlaybackItem(withID: primaryPlaybackItem.metadata.id)
        switch context {
        case .series(let series, _):
            guard case let .episode(episode) = freshItem else { throw MediaServerError.invalidResponse }
            context = .series(series, resumeEpisode: episode)
        case .item:
            context = .item(freshItem)
        case nil:
            throw MediaServerError.notAuthenticated
        }
        return MediaServerPlaybackSelection(
            item: freshItem,
            mediaSourceID: selectedMediaSourceID,
            startAction: startAction
        )
    }

    public func playbackSelection(for episode: MediaServerEpisode) async throws -> MediaServerPlaybackSelection {
        let seasonEpisodes = children.episodes
        guard case let .episode(freshEpisode) = try await currentPlaybackItem(withID: episode.metadata.id) else {
            throw MediaServerError.invalidResponse
        }
        let playableEpisode = MediaServerEpisode(
            metadata: freshEpisode.metadata,
            seriesID: freshEpisode.seriesID,
            seasonID: freshEpisode.seasonID ?? episode.seasonID,
            seasonNumber: freshEpisode.seasonNumber,
            episodeNumber: freshEpisode.episodeNumber
        )
        return MediaServerPlaybackSelection(
            episode: playableEpisode,
            mediaSourceID: freshEpisode.metadata.mediaSources.first?.id,
            startAction: .resume,
            seasonEpisodes: seasonEpisodes
        )
    }

    private func currentPlaybackItem(withID itemID: MediaServerItemID) async throws -> MediaServerLibraryItem {
        guard let server = session.server else { throw MediaServerError.notAuthenticated }
        do {
            let item = try await client.item(withID: itemID, on: server)
            try Task.checkCancellation()
            guard session.server == server else { throw MediaServerError.notAuthenticated }
            return item
        } catch {
            if session.server == server {
                _ = await session.handleRequestError(error)
            }
            throw error
        }
    }

    private func loadChildren(
        of context: Context,
        preferredSeasonID: MediaServerItemID?,
        on server: MediaServerAuthenticatedServer
    ) async throws -> MediaServerDetailChildren {
        let item = context.item
        switch item {
        case .movie, .episode:
            return .none
        case .series:
            let seasons = ordered(
                try await childPage(of: item, on: server, sortBy: []).items.compactMap(\.season),
                number: \.indexNumber, name: \.metadata.name
            )
            if let preferred = seasons.first(where: { $0.metadata.id == preferredSeasonID }) {
                return .seasons(all: seasons, selected: preferred.metadata.id, episodes: try await episodes(of: preferred, on: server))
            }
            if case let .series(_, episode) = context {
                let candidates = seasons.sorted { left, right in
                    let leftRank = left.metadata.id == episode.seasonID ? 0 : left.indexNumber == episode.seasonNumber && episode.seasonNumber != nil ? 1 : 2
                    let rightRank = right.metadata.id == episode.seasonID ? 0 : right.indexNumber == episode.seasonNumber && episode.seasonNumber != nil ? 1 : 2
                    return leftRank < rightRank
                }
                for season in candidates {
                    let shown = try await episodes(of: season, on: server)
                    if shown.contains(where: { $0.metadata.id == episode.metadata.id }) {
                        return .seasons(all: seasons, selected: season.metadata.id, episodes: shown)
                    }
                }
                throw MediaServerError.childrenUnavailable(episode.metadata.id)
            }
            guard let first = seasons.first else { return .seasons(all: [], selected: nil, episodes: []) }
            return .seasons(all: seasons, selected: first.metadata.id, episodes: try await episodes(of: first, on: server))
        case .season(let season):
            return .episodes(try await episodes(of: season, on: server))
        case .boxSet:
            return .collection(try await childPage(of: item, on: server).items)
        }
    }

    private func episodes(
        of season: MediaServerSeason,
        on server: MediaServerAuthenticatedServer
    ) async throws -> [MediaServerEpisode] {
        let episodes = try await childPage(of: .season(season), on: server, sortBy: []).items.compactMap(\.episode)
            .map { episode in
                MediaServerEpisode(
                    metadata: episode.metadata,
                    seriesID: episode.seriesID,
                    seasonID: episode.seasonID ?? season.metadata.id,
                    seasonNumber: episode.seasonNumber,
                    episodeNumber: episode.episodeNumber
                )
            }
        return ordered(episodes, number: \.episodeNumber, name: \.metadata.name)
    }

    private func ordered<Value>(
        _ values: [Value],
        number: KeyPath<Value, Int?>,
        name: KeyPath<Value, String>
    ) -> [Value] {
        let numbered = values.enumerated().compactMap { index, value in
            value[keyPath: number].map { (index: index, number: $0, value: value) }
        }
        if numbered.isEmpty {
            return values.enumerated().sorted { left, right in
                let result = left.element[keyPath: name].localizedStandardCompare(right.element[keyPath: name])
                return result == .orderedSame ? left.offset < right.offset : result == .orderedAscending
            }.map(\.element)
        }
        let sorted = numbered.sorted { left, right in
            left.number == right.number ? left.index < right.index : left.number < right.number
        }
        var next = 0
        return values.map { value in
            guard value[keyPath: number] != nil else { return value }
            defer { next += 1 }
            return sorted[next].value
        }
    }

    private func childPage(
        of parent: MediaServerLibraryItem,
        on server: MediaServerAuthenticatedServer,
        sortBy: [MediaServerItemSort] = [.sortName]
    ) async throws -> MediaServerItemPage {
        try await client.children(
            of: parent,
            on: server,
            query: MediaServerItemQuery(sortBy: sortBy, sortOrder: .ascending, recursive: false)
        )
    }

    private func clear() {
        context = nil
        children = .none
        specialFeatures = []
        relatedItems = []
        selectedMediaSourceID = nil
        preferredSeasonID = nil
        isLoading = false
    }
}
