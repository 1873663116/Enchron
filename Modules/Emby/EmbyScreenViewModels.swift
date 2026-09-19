import DesignSystem
import Foundation
import Observation

@MainActor
@Observable
public final class EmbyNavigationModel {
    public enum Destination: Hashable, Sendable {
        case home
        case library(EmbyItemID)
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
    public var path: [EmbyLibraryItem]

    public init(destination: Destination = .home, path: [EmbyLibraryItem] = []) {
        self.destination = destination
        self.path = path
    }

    public func select(_ destination: Destination) {
        self.destination = destination
        path = []
    }

    public func open(_ item: EmbyLibraryItem) {
        path.append(item)
    }

    public func reset() {
        destination = .home
        path = []
    }
}

public struct EmbyHomeShelf: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case continueWatching
        case nextUp
        case recentlyAdded(EmbyItemID)
    }

    public let kind: Kind
    public let title: String
    public let items: [EmbyLibraryItem]

    public var id: Kind { kind }

    public init(kind: Kind, title: String, items: [EmbyLibraryItem]) {
        self.kind = kind
        self.title = title
        self.items = items
    }
}

@MainActor
@Observable
public final class EmbyHomeViewModel {
    public private(set) var libraries: [EmbyLibraryView] = []
    public private(set) var shelves: [EmbyHomeShelf] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let client: any EmbyClientProtocol
    private let session: EmbySessionViewModel

    public init(client: any EmbyClientProtocol, session: EmbySessionViewModel) {
        self.client = client
        self.session = session
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
                query: EmbyItemQuery(
                    sortBy: [.dateCreated],
                    sortOrder: .descending,
                    limit: 20
                )
            ).items
            let nextUp = try await client.nextUp(
                on: server,
                seriesID: nil,
                startIndex: nil,
                limit: 20
            ).items
            var loadedShelves: [EmbyHomeShelf] = []
            if continueWatching.isEmpty == false {
                loadedShelves.append(EmbyHomeShelf(
                    kind: .continueWatching,
                    title: String(localized: "Continue Watching"),
                    items: continueWatching
                ))
            }
            if nextUp.isEmpty == false {
                loadedShelves.append(EmbyHomeShelf(
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
                    loadedShelves.append(EmbyHomeShelf(
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

    private func warmArtwork(of shelves: [EmbyHomeShelf], on server: EmbyAuthenticatedServer) async {
#if DEBUG
        let requests = shelves.flatMap { shelf -> [EmbyArtworkLoadRequest] in
            let isStill = shelf.kind == .continueWatching
            let width = Int((isStill ? DesignTokens.Card.stillWidth : DesignTokens.Card.posterWidth) * 2)
            return shelf.items.compactMap { item -> EmbyArtworkLoadRequest? in
                let metadata = item.metadata
                let type: EmbyImageType = isStill && metadata.imageTags.thumb != nil ? .thumb : .primary
                let tag = type == .thumb ? metadata.imageTags.thumb : metadata.imageTags.primary
                guard let tag,
                      let url = try? client.imageURL(
                    for: metadata.id,
                    type: type,
                    tag: tag,
                    size: try? EmbyImageSize.width(width),
                    on: server
                      ) else { return nil }
                return EmbyArtworkLoadRequest(
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
                let type: EmbyImageType = isStill && metadata.imageTags.thumb != nil ? .thumb : .primary
                let tag = type == .thumb ? metadata.imageTags.thumb : metadata.imageTags.primary
                guard tag != nil else { return nil }
                return try? client.imageURL(
                    for: metadata.id,
                    type: type,
                    tag: tag,
                    size: try? EmbyImageSize.width(width),
                    on: server
                )
            }
        }
        await ArtworkPrefetch.warm(urls)
#endif
    }
}

public enum EmbyLibrarySort: String, CaseIterable, Sendable {
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
public final class EmbyLibraryViewModel {
    public let library: EmbyLibraryView
    public private(set) var items: [EmbyLibraryItem] = []
    public private(set) var sort: EmbyLibrarySort = .recentlyAdded
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let client: any EmbyClientProtocol
    private let session: EmbySessionViewModel

    public init(
        library: EmbyLibraryView,
        client: any EmbyClientProtocol,
        session: EmbySessionViewModel
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
                EmbyItemQuery(
                    sortBy: [.dateCreated],
                    sortOrder: .descending,
                    includeItemTypes: library.topLevelItemKinds
                )
            case .alphabetical:
                EmbyItemQuery(
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

    public func setSort(_ sort: EmbyLibrarySort) {
        self.sort = sort
    }
}

@MainActor
@Observable
public final class EmbySearchViewModel {
    public var query = ""
    public private(set) var results: [EmbyLibraryItem] = []
    public private(set) var isSearching = false
    public private(set) var errorMessage: String?

    private let client: any EmbyClientProtocol
    private let session: EmbySessionViewModel

    public init(client: any EmbyClientProtocol, session: EmbySessionViewModel) {
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
                query: EmbyItemQuery(
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

public enum EmbyDetailChildren: Equatable, Sendable {
    case none
    case seasons(all: [EmbySeason], selected: EmbyItemID?, episodes: [EmbyEpisode])
    case episodes([EmbyEpisode])
    case collection([EmbyLibraryItem])

    public var episodes: [EmbyEpisode] {
        switch self {
        case .seasons(_, _, let episodes): episodes
        case .episodes(let episodes): episodes
        case .none, .collection: []
        }
    }

    var selectedSeasonID: EmbyItemID? {
        guard case .seasons(_, let selected, _) = self else { return nil }
        return selected
    }
}

@MainActor
@Observable
public final class EmbyDetailViewModel {
    public let itemID: EmbyItemID
    public private(set) var item: EmbyLibraryItem?
    public private(set) var children: EmbyDetailChildren = .none
    public private(set) var specialFeatures: [EmbyLibraryItem] = []
    public private(set) var relatedItems: [EmbyLibraryItem] = []
    public var selectedMediaSourceID: EmbyMediaSourceID?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let client: any EmbyClientProtocol
    private let session: EmbySessionViewModel

    public init(
        itemID: EmbyItemID,
        client: any EmbyClientProtocol,
        session: EmbySessionViewModel,
        knownItem: EmbyLibraryItem? = nil
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

            async let features = client.specialFeatures(for: itemID, on: server)
            async let related = client.similarItems(to: itemID, on: server, limit: 20)
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

    public func selectSeason(_ seasonID: EmbyItemID) async {
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
        startAction: EmbyPlaybackStartAction
    ) throws -> EmbyPlaybackSelection {
        guard let item else { throw EmbyError.notAuthenticated }
        return EmbyPlaybackSelection(
            item: item,
            mediaSourceID: selectedMediaSourceID,
            startAction: startAction
        )
    }

    public func playbackSelection(for episode: EmbyEpisode) -> EmbyPlaybackSelection {
        EmbyPlaybackSelection(
            episode: episode,
            mediaSourceID: episode.metadata.mediaSources.first?.id,
            startAction: .resume,
            seasonEpisodes: children.episodes
        )
    }

    private func loadChildren(
        of item: EmbyLibraryItem,
        on server: EmbyAuthenticatedServer
    ) async throws -> EmbyDetailChildren {
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
        of season: EmbyLibraryItem,
        on server: EmbyAuthenticatedServer
    ) async throws -> [EmbyEpisode] {
        try await childPage(of: season, on: server, sortBy: [])
            .items
            .compactMap(\.episode)
    }

    private func childPage(
        of parent: EmbyLibraryItem,
        on server: EmbyAuthenticatedServer,
        sortBy: [EmbyItemSort] = [.sortName]
    ) async throws -> EmbyItemPage {
        try await client.children(
            of: parent,
            on: server,
            query: EmbyItemQuery(
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
