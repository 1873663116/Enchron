import DesignSystem
import Foundation
import Observation

@MainActor
@Observable
public final class MediaServerNavigationModel {
    public enum Destination: Hashable, Sendable {
        case home
        case library(MediaServerItemID)
        case search

        var id: String {
            switch self {
            case .home: "home"
            case .library(let id): "library-\(id.rawValue)"
            case .search: "search"
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
    public var query = ""
    public private(set) var results: [MediaServerLibraryItem] = []
    public private(set) var isSearching = false
    public private(set) var errorMessage: String?

    private let client: any MediaServerClientProtocol
    private let session: MediaServerSessionViewModel

    public init(client: any MediaServerClientProtocol, session: MediaServerSessionViewModel) {
        self.client = client
        self.session = session
    }

    public func refresh() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.isEmpty == false, let server = session.server else {
            results = []
            errorMessage = nil
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await client.search(
                term,
                on: server,
                query: MediaServerItemQuery(
                    sortBy: [.sortName],
                    sortOrder: .ascending,
                    includeItemTypes: [.movie, .series, .boxSet]
                )
            ).items
            errorMessage = nil
        } catch {
            if await session.handleRequestError(error) == false {
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
    public let itemID: MediaServerItemID
    public private(set) var item: MediaServerLibraryItem?
    public private(set) var children: MediaServerDetailChildren = .none
    public private(set) var specialFeatures: [MediaServerLibraryItem] = []
    public private(set) var relatedItems: [MediaServerLibraryItem] = []
    public var selectedMediaSourceID: MediaServerMediaSourceID?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let client: any MediaServerClientProtocol
    private let session: MediaServerSessionViewModel

    public init(
        itemID: MediaServerItemID,
        client: any MediaServerClientProtocol,
        session: MediaServerSessionViewModel,
        knownItem: MediaServerLibraryItem? = nil
    ) {
        self.itemID = itemID
        self.client = client
        self.session = session
        self.item = knownItem
        self.selectedMediaSourceID = knownItem?.metadata.mediaSources.first?.id
    }

    public func refresh() async {
        guard let server = session.server else {
            clear()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let freshItem = try await client.item(withID: itemID, on: server)
            item = freshItem
            let availableSources = freshItem.metadata.mediaSources
            if availableSources.contains(where: { $0.id == selectedMediaSourceID }) == false {
                selectedMediaSourceID = availableSources.first?.id
            }

            async let features = client.capabilities.specialFeatures ? client.specialFeatures(for: itemID, on: server) : []
            async let related = client.capabilities.similarItems ? client.similarItems(to: itemID, on: server, limit: 20) : MediaServerItemPage(items: [], totalRecordCount: 0)
            let loadedChildren = try await loadChildren(of: freshItem, on: server)
            specialFeatures = try await features
            relatedItems = try await related.items
            children = loadedChildren
            errorMessage = nil
        } catch {
            if await session.handleRequestError(error) == false {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func selectSeason(_ seasonID: MediaServerItemID) async {
        guard case .seasons(let all, let selected, let shown) = children,
              selected != seasonID,
              let season = all.first(where: { $0.metadata.id == seasonID }),
              let server = session.server else { return }
        children = .seasons(all: all, selected: seasonID, episodes: shown)
        do {
            children = .seasons(
                all: all,
                selected: seasonID,
                episodes: try await episodes(of: .season(season), on: server)
            )
        } catch {
            if await session.handleRequestError(error) == false {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func playbackSelection(
        startAction: MediaServerPlaybackStartAction
    ) async throws -> MediaServerPlaybackSelection {
        guard let item else { throw MediaServerError.notAuthenticated }
        let freshItem = try await currentPlaybackItem(withID: item.metadata.id)
        self.item = freshItem
        return MediaServerPlaybackSelection(
            item: freshItem,
            mediaSourceID: selectedMediaSourceID,
            startAction: startAction
        )
    }

    public func playbackSelection(for episode: MediaServerEpisode) async throws -> MediaServerPlaybackSelection {
        guard case let .episode(freshEpisode) = try await currentPlaybackItem(withID: episode.metadata.id) else {
            throw MediaServerError.invalidResponse
        }
        return MediaServerPlaybackSelection(
            episode: freshEpisode,
            mediaSourceID: freshEpisode.metadata.mediaSources.first?.id,
            startAction: .resume,
            seasonEpisodes: children.episodes
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
        of item: MediaServerLibraryItem,
        on server: MediaServerAuthenticatedServer
    ) async throws -> MediaServerDetailChildren {
        switch item {
        case .movie, .episode:
            return .none
        case .series:
            let seasons = try await childPage(of: item, on: server, sortBy: [])
                .items
                .compactMap(\.season)
            guard let selected = seasons.first(where: { $0.metadata.id == children.selectedSeasonID })
                ?? seasons.first else {
                return .seasons(all: seasons, selected: nil, episodes: [])
            }
            return .seasons(
                all: seasons,
                selected: selected.metadata.id,
                episodes: try await episodes(of: .season(selected), on: server)
            )
        case .season:
            return .episodes(try await episodes(of: item, on: server))
        case .boxSet:
            return .collection(try await childPage(of: item, on: server).items)
        }
    }

    private func episodes(
        of season: MediaServerLibraryItem,
        on server: MediaServerAuthenticatedServer
    ) async throws -> [MediaServerEpisode] {
        try await childPage(of: season, on: server, sortBy: [])
            .items
            .compactMap(\.episode)
    }

    private func childPage(
        of parent: MediaServerLibraryItem,
        on server: MediaServerAuthenticatedServer,
        sortBy: [MediaServerItemSort] = [.sortName]
    ) async throws -> MediaServerItemPage {
        try await client.children(
            of: parent,
            on: server,
            query: MediaServerItemQuery(
                sortBy: sortBy,
                sortOrder: .ascending,
                recursive: false
            )
        )
    }

    private func clear() {
        item = nil
        children = .none
        specialFeatures = []
        relatedItems = []
        selectedMediaSourceID = nil
    }
}
