import Foundation
import Observation

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
                    title: "Continue Watching",
                    items: continueWatching
                ))
            }
            if nextUp.isEmpty == false {
                loadedShelves.append(EmbyHomeShelf(
                    kind: .nextUp,
                    title: "Next Up",
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
                        title: "Recently Added in \(library.name)",
                        items: latest
                    ))
                }
            }
            libraries = loadedLibraries
            shelves = loadedShelves
            errorMessage = nil
        } catch {
            if await session.handleRequestError(error) == false {
                errorMessage = error.localizedDescription
            }
        }
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
                EmbyItemQuery(sortBy: [.dateCreated], sortOrder: .descending)
            case .alphabetical:
                EmbyItemQuery(sortBy: [.sortName], sortOrder: .ascending)
            }
            items = try await client.items(in: library.id, on: server, query: query).items
            errorMessage = nil
        } catch {
            if await session.handleRequestError(error) == false {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func selectSort(_ sort: EmbyLibrarySort) async {
        guard self.sort != sort else { return }
        self.sort = sort
        await refresh()
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
                query: EmbyItemQuery(sortBy: [.sortName], sortOrder: .ascending)
            ).items
            errorMessage = nil
        } catch {
            if await session.handleRequestError(error) == false {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// What a detail page browses below its hero. Each Emby container kind reaches its contents
/// differently, so the page has one state to switch on instead of several arrays whose empty
/// combinations would be meaningless.
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
        session: EmbySessionViewModel
    ) {
        self.itemID = itemID
        self.client = client
        self.session = session
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
            let features = try await client.specialFeatures(for: itemID, on: server)
            let related = try await client.similarItems(
                to: itemID,
                on: server,
                limit: 20
            ).items
            let loadedChildren = try await loadChildren(of: freshItem, on: server)
            item = freshItem
            specialFeatures = features
            relatedItems = related
            children = loadedChildren
            let availableSources = freshItem.metadata.mediaSources
            if availableSources.contains(where: { $0.id == selectedMediaSourceID }) == false {
                selectedMediaSourceID = availableSources.first?.id
            }
            errorMessage = nil
        } catch {
            if await session.handleRequestError(error) == false {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func selectSeason(_ seasonID: EmbyItemID) async {
        guard case .seasons(let all, let selected, _) = children,
              selected != seasonID,
              let season = all.first(where: { $0.metadata.id == seasonID }),
              let server = session.server else { return }
        children = .seasons(all: all, selected: seasonID, episodes: [])
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
            let seasons = try await childPage(of: item, on: server).items.compactMap(\.season)
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
        try await childPage(of: season, on: server).items.compactMap(\.episode)
    }

    private func childPage(
        of parent: EmbyLibraryItem,
        on server: EmbyAuthenticatedServer
    ) async throws -> EmbyItemPage {
        try await client.children(
            of: parent,
            on: server,
            query: EmbyItemQuery(
                sortBy: [.sortName],
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
