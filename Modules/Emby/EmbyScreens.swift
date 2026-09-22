import DesignSystem
import Foundation
import SwiftUI

#if DEBUG
public struct EmbyAccessibilityEvidence: Equatable, Sendable {
    public static let productDeadlineSeconds = 45
    public static let harnessLivenessDeadlineSeconds = 90

    public struct Document: Codable, Equatable, Sendable {
        public struct Account: Codable, Equatable, Sendable {
            public let serverID: String
            public let userID: String
        }

        public struct Navigation: Codable, Equatable, Sendable {
            public let destination: String
            public let pathItemIDs: [String]
        }

        public struct Library: Codable, Equatable, Sendable {
            public let id: String
            public let name: String
            public let collectionType: EmbyObservation<String>
        }

        public struct ShelfItem: Codable, Equatable, Sendable {
            public let itemID: String
            public let itemKind: String
            public let serverProgressTicks: EmbyObservation<Int64>
        }

        public struct Shelf: Codable, Equatable, Sendable {
            public let kind: String
            public let libraryID: String?
            public let title: String
            public let items: [ShelfItem]
        }

        public struct Home: Codable, Equatable, Sendable {
            public let isLoading: Bool
            public let error: EmbyObservation<String>
            public let shelves: [Shelf]
            public let activations: [EmbyHomeActivationEvidence]
        }

        public struct PreparedPlayback: Codable, Equatable, Sendable {
            public let serverID: String
            public let userID: String
            public let itemID: String
            public let mediaSourceID: String
            public let playSessionID: String
            public let requestedAction: String
            public let freshServerProgressTicks: EmbyObservation<Int64>
            public let appliedStartTicks: Int64
        }

        public struct AcceptedReport: Codable, Equatable, Sendable {
            public let event: String
            public let positionTicks: Int64
        }

        public struct PlaybackSession: Codable, Equatable, Sendable {
            public let serverID: String
            public let userID: String
            public let itemID: String
            public let mediaSourceID: String
            public let playSessionID: String
            public let acceptedReports: [AcceptedReport]
            public let totalAcceptedReportCount: Int
            public let acceptedReportsWereTruncated: Bool
            public let latestPositionTicks: Int64
            public let exitPositionTicks: EmbyObservation<Int64>
            public let serverReadbackProgressTicks: EmbyObservation<Int64>
        }

        public let schema: String
        public let account: Account
        public let navigation: Navigation
        public let libraries: [Library]
        public let home: Home
        public let detail: EmbyObservation<EmbyDetailEvidence>
        public let seasonTransitions: [EmbySeasonTransitionEvidence]
        public let preparedPlaybacks: [PreparedPlayback]
        public let playbackSessions: [PlaybackSession]
        public let artworkLoads: [EmbyArtworkEvidence]
        public let fixtureDigest: EmbyObservation<String>
        public let localViewingStateWriteCount: EmbyObservation<Int>
        public let productDeadlineSeconds: Int
        public let harnessLivenessDeadlineSeconds: Int
    }

    public let document: Document

    @MainActor
    public init(
        server: EmbyAuthenticatedServer,
        navigation: EmbyNavigationModel,
        libraries: [EmbyLibraryView],
        shelves: [EmbyHomeShelf],
        homeIsLoading: Bool,
        homeErrorMessage: String?,
        journal: EmbyEvidenceJournal
    ) {
        document = Document(
            schema: "enchron.emby.accessibility-evidence@2",
            account: Document.Account(
                serverID: server.id.rawValue,
                userID: server.userID.rawValue
            ),
            navigation: Document.Navigation(
                destination: navigation.destination.id,
                pathItemIDs: navigation.path.map { $0.metadata.id.rawValue }
            ),
            libraries: libraries.map { library in
                Document.Library(
                    id: library.id.rawValue,
                    name: library.name,
                    collectionType: library.collectionType.map(EmbyObservation.observed)
                        ?? .unavailable("server-did-not-declare-collection-type")
                )
            },
            home: Document.Home(
                isLoading: homeIsLoading,
                error: homeErrorMessage.map(EmbyObservation.observed)
                    ?? .notApplicable("home-refresh-has-no-error"),
                shelves: shelves.map(Self.shelfDocument),
                activations: journal.homeActivations
            ),
            detail: journal.detail.map(EmbyObservation.observed)
                ?? .unavailable("no-detail-refresh-observed"),
            seasonTransitions: journal.seasonTransitions,
            preparedPlaybacks: journal.preparedPlaybacks.map { evidence in
                Document.PreparedPlayback(
                    serverID: evidence.serverID.rawValue,
                    userID: evidence.userID.rawValue,
                    itemID: evidence.itemID.rawValue,
                    mediaSourceID: evidence.mediaSourceID.rawValue,
                    playSessionID: evidence.playSessionID.rawValue,
                    requestedAction: evidence.requestedAction.rawValue,
                    freshServerProgressTicks: evidence.freshServerProgressTicks
                        .map(EmbyObservation.observed)
                        ?? .unavailable("fresh-item-response-omitted-user-progress"),
                    appliedStartTicks: evidence.appliedStartTicks
                )
            },
            playbackSessions: journal.playbackSessions.map { evidence in
                Document.PlaybackSession(
                    serverID: evidence.serverID.rawValue,
                    userID: evidence.userID.rawValue,
                    itemID: evidence.itemID.rawValue,
                    mediaSourceID: evidence.mediaSourceID.rawValue,
                    playSessionID: evidence.playSessionID.rawValue,
                    acceptedReports: evidence.acceptedReports.map {
                        Document.AcceptedReport(
                            event: $0.event.rawValue,
                            positionTicks: $0.positionTicks
                        )
                    },
                    totalAcceptedReportCount: evidence.totalAcceptedReportCount,
                    acceptedReportsWereTruncated: evidence.acceptedReportsWereTruncated,
                    latestPositionTicks: evidence.latestPositionTicks,
                    exitPositionTicks: evidence.exitPositionTicks
                        .map(EmbyObservation.observed)
                        ?? .unavailable("server-has-not-accepted-stopped-report"),
                    serverReadbackProgressTicks: .unavailable(
                        "post-report-item-readback-not-observed"
                    )
                )
            },
            artworkLoads: journal.artworkLoads,
            fixtureDigest: .unavailable("fixture-identity-is-host-runner-authority"),
            localViewingStateWriteCount: .unavailable(
                "local-viewing-storage-is-outside-emby-authority"
            ),
            productDeadlineSeconds: Self.productDeadlineSeconds,
            harnessLivenessDeadlineSeconds: Self.harnessLivenessDeadlineSeconds
        )
    }

    public var accessibilityValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(document),
              let value = String(data: data, encoding: .utf8) else {
            preconditionFailure("Emby accessibility evidence must encode")
        }
        return value
    }

    private static func shelfDocument(_ shelf: EmbyHomeShelf) -> Document.Shelf {
        let kind: String
        let libraryID: String?
        switch shelf.kind {
        case .continueWatching:
            kind = "continueWatching"
            libraryID = nil
        case .nextUp:
            kind = "nextUp"
            libraryID = nil
        case .recentlyAdded(let id):
            kind = "recentlyAdded"
            libraryID = id.rawValue
        }
        return Document.Shelf(
            kind: kind,
            libraryID: libraryID,
            title: shelf.title,
            items: shelf.items.map { item in
                Document.ShelfItem(
                    itemID: item.metadata.id.rawValue,
                    itemKind: itemKind(item),
                    serverProgressTicks: (item.metadata.userData?.playbackPositionTicks)
                        .map(EmbyObservation.observed)
                        ?? .unavailable("server-item-omitted-user-progress")
                )
            }
        )
    }

    private static func itemKind(_ item: EmbyLibraryItem) -> String {
        switch item {
        case .movie: "movie"
        case .series: "series"
        case .season: "season"
        case .episode: "episode"
        case .boxSet: "boxSet"
        }
    }
}

public struct EmbyAccessibilityEvidenceSurface: View {
    private let evidence: EmbyAccessibilityEvidence

    public init(evidence: EmbyAccessibilityEvidence) {
        self.evidence = evidence
    }

    public var body: some View {
        Text("Emby evidence")
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .accessibilityLabel("Emby product evidence")
            .accessibilityValue(evidence.accessibilityValue)
            .accessibilityIdentifier("Emby-Evidence")
    }
}
#endif

#if DEBUG
@MainActor
public final class EmbyReachabilityScrollRequest {
    public enum Direction: String {
        case forward
        case backward
    }

    public let page: String
    public let direction: Direction
    public private(set) var handledPage: String?
    private let recordDelivery: @MainActor (String) -> Void

    public init(
        page: String,
        direction: Direction,
        recordDelivery: @escaping @MainActor (String) -> Void
    ) {
        self.page = page
        self.direction = direction
        self.recordDelivery = recordDelivery
    }

    public func handle(on page: String, scroll: () -> Void) {
        guard self.page == page, handledPage == nil else { return }
        scroll()
        handledPage = page
        recordDelivery(page)
    }
}

public extension Notification.Name {
    static let embyReachabilityScroll = Notification.Name(
        "app.enchron.debug.emby-reachability-scroll"
    )
}
#endif

private let embyHeaderHeight = DesignTokens.Interactive.large + DesignTokens.Spacing.xl + DesignTokens.Spacing.lg

private extension View {
    func embyPageBounds() -> some View {
        clipped()
    }
}

private struct EmbyHeroSnapBehavior: ScrollTargetBehavior {
    let travel: CGFloat
    let inset: CGFloat
    let settleFraction: CGFloat
    let isEnabled: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard isEnabled else { return }
        let measured = target.rect.origin.y + inset
        guard measured > 0, measured < travel else { return }

        let settled: CGFloat
        if context.velocity.dy > 0 {
            settled = travel
        } else if context.velocity.dy < 0 {
            settled = 0
        } else {
            settled = measured / travel > settleFraction ? travel : 0
        }
        target.rect.origin.y = settled - inset
    }
}

private struct EmbyPageHeader<Trailing: View>: View {
    let title: String
    let sidebarIsVisible: Binding<Bool>?
    @ViewBuilder let trailing: () -> Trailing

    @Environment(EmbySessionViewModel.self) private var session

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            if let sidebarIsVisible {
                SidebarToggleButton(
                    isVisible: Binding(
                        get: { sidebarIsVisible.wrappedValue },
                        set: {
#if DEBUG
                            session.recordReachability("sidebarToggle")
#endif
                            sidebarIsVisible.wrappedValue = $0
                        }
                    ),
                    accessibilityIdentifier: "Emby-Sidebar-Toggle"
                )
            }
            Text(title)
                .font(.largeTitle)
            Spacer(minLength: DesignTokens.Spacing.xl)
            trailing()
        }
        .frame(height: DesignTokens.Interactive.large)
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.top, DesignTokens.Spacing.xl)
        .padding(.bottom, DesignTokens.Spacing.lg)
    }
}

public struct EmbyScreen: View {
    public typealias PlayHandler = @MainActor (
        Result<EmbyPlaybackSelection, EmbyError>
    ) async -> Void

    @Environment(EmbySessionViewModel.self) private var session
    @Environment(EmbyHomeViewModel.self) private var home
    @Environment(EmbyNavigationModel.self) private var navigation
    @State private var sidebarIsVisible = true
    @State private var sidebarSuspended = false

    private let onPlay: PlayHandler

    public init(onPlay: @escaping PlayHandler) {
        self.onPlay = onPlay
    }

    public var body: some View {
        @Bindable var navigation = navigation
        Group {
            if session.server == nil {
                EmbyConnectionScreen()
            } else {
                SidebarSplitLayout(sidebarIsVisible: sidebarIsVisible && sidebarSuspended == false) {
                    sidebar
                } content: {
                    NavigationStack(path: $navigation.path) {
                        destinationContent
                            .levelContent(id: navigation.destination)
                            .navigationDestination(for: EmbyLibraryItem.self) { item in
                                EmbyDetailScreen(
                                    viewModel: EmbyDetailViewModel(
                                        itemID: item.metadata.id,
                                        client: session.client,
                                        session: session,
                                        knownItem: item
                                    ),
                                    onSelect: open,
                                    onPlay: onPlay
                                )
                            }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Emby-Root")
        .task(id: navigation.path.isEmpty) {
            await settleSidebar(afterPathIsEmpty: navigation.path.isEmpty)
        }
#if DEBUG
        .overlay(alignment: .bottomTrailing) {
            if let evidence = accessibilityEvidence {
                EmbyAccessibilityEvidenceSurface(evidence: evidence)
            }
        }
#endif
#if DEBUG
        .task { await openLaunchRoute() }
#endif
    }

    private func open(_ item: EmbyLibraryItem) {
        warmDetailArtwork(for: item, session: session)
        Task { @MainActor in
            if sidebarIsVisible, sidebarSuspended == false {
                sidebarSuspended = true
                try? await Task.sleep(for: .seconds(DesignTokens.EmbyDetail.sidebarHandoffDelay))
            }
            navigation.open(item)
        }
    }

    private func settleSidebar(afterPathIsEmpty isEmpty: Bool) async {
        if isEmpty {
            try? await Task.sleep(for: .seconds(DesignTokens.EmbyDetail.sidebarHandoffDelay))
            guard navigation.path.isEmpty else { return }
            sidebarSuspended = false
        } else {
            sidebarSuspended = true
        }
    }

#if DEBUG
    private var accessibilityEvidence: EmbyAccessibilityEvidence? {
        guard let server = session.server else { return nil }
        return EmbyAccessibilityEvidence(
            server: server,
            navigation: navigation,
            libraries: home.libraries,
            shelves: home.shelves,
            homeIsLoading: home.isLoading,
            homeErrorMessage: home.errorMessage,
            journal: session.evidenceJournal
        )
    }
#endif

#if DEBUG
    private func openLaunchRoute() async {
        guard let route = EmbyLaunchRoute.current else { return }
        if session.server == nil {
            guard let address = URL(string: route.address) else { return }
            try? await session.connect(
                address: address,
                username: route.username,
                password: route.password
            )
        }
        await home.refresh()
        if let libraryID = route.libraryID {
            navigation.destination = .library(libraryID)
        }
        sidebarIsVisible = route.sidebarIsVisible
        guard let itemID = route.itemID, let server = session.server else { return }
        if let item = try? await session.client.item(withID: itemID, on: server) {
            navigation.path = [item]
        }
    }
#endif

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text(session.server?.name ?? "Emby")
                .font(DesignTokens.SourceSidebar.sectionTitleFont)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, DesignTokens.SourceSidebar.contentPaddingH)

            VStack(spacing: DesignTokens.SourceSidebar.rowSpacing) {
                sidebarRow(icon: "house.fill", title: String(localized: "Home"), destination: .home)

                ForEach(home.libraries, id: \.id) { library in
                    sidebarRow(
                        icon: "rectangle.stack.fill",
                        title: library.name,
                        destination: .library(library.id)
                    )
                }

                sidebarRow(icon: "magnifyingglass", title: String(localized: "Search"), destination: .search)
            }
            .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)

            Spacer(minLength: 0)

            EditableSourceSidebarRow(
                icon: "rectangle.portrait.and.arrow.right",
                title: String(localized: "Sign Out"),
                isSelected: false,
                isEnabled: true,
                isActiveSource: false,
                isDeletable: false,
                isSelectionMode: false,
                isChecked: false,
                isAppearing: false,
                isSwipeExpanded: false,
                isDragging: false,
                rowOffset: 0,
                allowsReordering: false,
                allowsSwipe: false,
                onTap: {
#if DEBUG
                    session.recordReachability("signOut")
#endif
                    Task { await session.signOut() }
                }
            )
            .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)
            .accessibilityIdentifier("Emby-SignOut")
        }
        .padding(.vertical, DesignTokens.SourceSidebar.contentPaddingV)
        .frame(width: DesignTokens.SourceSidebar.width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .enchronSidebarSurface()
    }

    private func sidebarRow(
        icon: String,
        title: String,
        destination: EmbyNavigationModel.Destination
    ) -> some View {
        EditableSourceSidebarRow(
            icon: icon,
            title: title,
            isSelected: navigation.destination == destination,
            isEnabled: true,
            isActiveSource: false,
            isDeletable: false,
            isSelectionMode: false,
            isChecked: false,
            isAppearing: false,
            isSwipeExpanded: false,
            isDragging: false,
            rowOffset: 0,
            allowsReordering: false,
            allowsSwipe: false,
            onTap: {
                navigation.select(destination)
            }
        )
        .accessibilityIdentifier("Emby-Sidebar-\(destination.id)")
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch navigation.destination {
        case .home:
            EmbyHomeScreen(sidebarIsVisible: $sidebarIsVisible, onSelect: open)
        case .library(let id):
            if let library = home.libraries.first(where: { $0.id == id }) {
                EmbyLibraryScreen(
                    viewModel: EmbyLibraryViewModel(
                        library: library,
                        client: session.client,
                        session: session
                    ),
                    sidebarIsVisible: $sidebarIsVisible,
                    onSelect: open
                )
                .id(id)
            } else {
                ContentUnavailableView("Library Unavailable", systemImage: "rectangle.stack")
            }
        case .search:
            EmbySearchScreen(sidebarIsVisible: $sidebarIsVisible, onSelect: open)
        }
    }
}

private struct EmbyConnectionScreen: View {
    @Environment(EmbyConnectionViewModel.self) private var viewModel
    @Environment(EmbySessionViewModel.self) private var session

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Connect to Emby")
                    .font(DesignTokens.Typography.title)
                Text("Enter the address and account for your media server.")
                    .foregroundStyle(.secondary)
            }

            TextField("Server address", text: $viewModel.address)
                .textContentType(.URL)
                .accessibilityIdentifier("Emby-Connection-Address")
            TextField("Username", text: $viewModel.username)
                .textContentType(.username)
                .accessibilityIdentifier("Emby-Connection-Username")
            SecureField("Password", text: $viewModel.password)
                .textContentType(.password)
                .accessibilityIdentifier("Emby-Connection-Password")

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("Emby-Connection-Error")
            }

            Button {
#if DEBUG
                session.recordReachability("connection.connect")
#endif
                Task { await viewModel.connect() }
            } label: {
                if viewModel.isConnecting {
                    ProgressView()
                } else {
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isConnecting)
            .accessibilityIdentifier("Emby-Connection-Connect")
        }
        .textFieldStyle(.roundedBorder)
        .padding(DesignTokens.Spacing.xxl)
        .frame(width: 520)
        .background(.regularMaterial, in: DesignTokens.ShapeToken.panel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if DEBUG
        .onChange(of: viewModel.address) { _, _ in
            session.recordReachability("connection.address")
        }
        .onChange(of: viewModel.username) { _, _ in
            session.recordReachability("connection.username")
        }
        .onChange(of: viewModel.password) { _, _ in
            session.recordReachability("connection.password")
        }
#endif
    }
}

private struct EmbyHomeScreen: View {
    @Environment(EmbyHomeViewModel.self) private var viewModel
    @Environment(EmbySessionViewModel.self) private var session
    @Environment(EmbyNavigationModel.self) private var navigation
    let sidebarIsVisible: Binding<Bool>?
    let onSelect: (EmbyLibraryItem) -> Void
    @State private var reachabilityScrollPosition = ScrollPosition(edge: .top)
    @State private var initialRefreshCompleted = false

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                if initialRefreshCompleted {
                    ForEach(viewModel.shelves) { shelf in
                        EmbyShelf(title: shelf.title) {
                            ForEach(shelf.items, id: \.metadata.id) { item in
                                if shelf.kind == .continueWatching {
                                    stillCard(item, session: session) {
                                        select($0, from: shelf)
                                    }
                                } else {
                                    posterCard(item, session: session) {
                                        select($0, from: shelf)
                                    }
                                }
                            }
                        }
                    }
                }

                if initialRefreshCompleted,
                   viewModel.shelves.isEmpty,
                   viewModel.isLoading == false {
                    ContentUnavailableView("No Emby titles", systemImage: "film.stack")
                        .padding(.horizontal, DesignTokens.Spacing.xxl)
                }
            }
            .padding(.bottom, DesignTokens.Spacing.xxl)
        }
        .scrollPosition($reachabilityScrollPosition)
#if DEBUG
        .onReceive(
            NotificationCenter.default.publisher(for: .embyReachabilityScroll)
        ) { notification in
            guard let request = notification.object as? EmbyReachabilityScrollRequest else {
                return
            }
            request.handle(on: "home") {
                switch request.direction {
                case .forward: reachabilityScrollPosition.scrollTo(edge: .bottom)
                case .backward: reachabilityScrollPosition.scrollTo(edge: .top)
                }
            }
        }
#endif
        .contentMargins(.top, embyHeaderHeight, for: .scrollContent)
        .embyPageBounds()
        .overlay(alignment: .top) {
            EmbyPageHeader(title: String(localized: "Home"), sidebarIsVisible: sidebarIsVisible) { EmptyView() }
        }
        .task(id: session.resumeCatalogRevision) {
            initialRefreshCompleted = false
            await viewModel.refresh()
            initialRefreshCompleted = true
        }
        .levelReadiness(initialRefreshCompleted)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Emby-Home")
    }

    private func select(_ item: EmbyLibraryItem, from shelf: EmbyHomeShelf) {
        onSelect(item)
#if DEBUG
        guard let resultingItemID = navigation.path.last?.metadata.id else { return }
        let surface: EmbyHomeCardSurface = switch shelf.kind {
        case .continueWatching: .continueWatching
        case .nextUp: .nextUp
        case .recentlyAdded: .poster
        }
        let cardPrefix = shelf.kind == .continueWatching
            ? "Emby-StillCard-"
            : "Emby-PosterCard-"
        session.recordHomeActivation(
            surface: surface,
            cardIdentifier: cardPrefix + item.metadata.id.rawValue,
            item: item,
            resultingItemID: resultingItemID
        )
#endif
    }
}

private struct EmbyLibraryScreen: View {
    @Environment(EmbySessionViewModel.self) private var session
    @State private var viewModel: EmbyLibraryViewModel
    let sidebarIsVisible: Binding<Bool>?
    let onSelect: (EmbyLibraryItem) -> Void

    init(
        viewModel: EmbyLibraryViewModel,
        sidebarIsVisible: Binding<Bool>?,
        onSelect: @escaping (EmbyLibraryItem) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.sidebarIsVisible = sidebarIsVisible
        self.onSelect = onSelect
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        EmbyPosterGrid(
            items: viewModel.items,
            isLoading: viewModel.isLoading,
            session: session,
            reachabilityPage: "library",
            onSelect: onSelect
        )
            .contentMargins(.top, embyHeaderHeight, for: .scrollContent)
            .embyPageBounds()
            .overlay(alignment: .top) {
                EmbyPageHeader(title: viewModel.library.name, sidebarIsVisible: sidebarIsVisible) {
                    Picker("Sort", selection: Binding(
                        get: { viewModel.sort },
                        set: { value in
                            guard viewModel.sort != value else { return }
#if DEBUG
                            session.recordReachability("library.sort.\(value)")
#endif
                            withAnimation(DesignTokens.AnimationToken.selection) {
                                viewModel.setSort(value)
                            }
                            Task { await viewModel.refresh() }
                        }
                    )) {
                        ForEach(EmbyLibrarySort.allCases, id: \.self) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 360, height: DesignTokens.Interactive.regular)
                    .enchronGlassControl()
                    .accessibilityIdentifier("Emby-Library-Sort")
                }
        }
        .task { await viewModel.refresh() }
    }
}

private struct EmbySearchScreen: View {
    @Environment(EmbySearchViewModel.self) private var viewModel
    @Environment(EmbySessionViewModel.self) private var session
    let sidebarIsVisible: Binding<Bool>?
    let onSelect: (EmbyLibraryItem) -> Void

    var body: some View {
        @Bindable var viewModel = viewModel
        EmbyPosterGrid(
            items: viewModel.results,
            isLoading: false,
            session: session,
            reachabilityPage: "search",
            onSelect: onSelect
        )
            .contentMargins(.top, embyHeaderHeight, for: .scrollContent)
            .embyPageBounds()
            .overlay(alignment: .top) {
                EmbyPageHeader(title: String(localized: "Search"), sidebarIsVisible: sidebarIsVisible) {
                    GlassSearchField(
                        text: $viewModel.query,
                        placeholder: String(localized: "Search Emby"),
                        accessibilityIdentifier: "Emby-Search-Field"
                    )
                    .frame(width: 360)
                    .onSubmit { Task { await viewModel.refresh() } }
                }
            }
        .task { await viewModel.refresh() }
        .task(id: viewModel.query) {
            guard viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                await viewModel.refresh()
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard Task.isCancelled == false else { return }
            await viewModel.refresh()
        }
#if DEBUG
        .onChange(of: viewModel.query) { _, _ in
            session.recordReachability("search.query")
        }
#endif
    }
}

private struct EmbyPosterGrid: View {
    let items: [EmbyLibraryItem]
    let isLoading: Bool
    let session: EmbySessionViewModel
    let reachabilityPage: String
    let onSelect: (EmbyLibraryItem) -> Void
    @State private var reachabilityScrollPosition = ScrollPosition(edge: .top)
    @State private var revealed = false

    private var revealKey: [EmbyItemID] {
        isLoading ? [] : items.map(\.metadata.id)
    }

    var body: some View {
        ScrollView {
            if isLoading == false {
                CardGrid {
                    ForEach(items, id: \.metadata.id) { item in
                        posterCard(item, session: session, onSelect: onSelect)
                    }
                }
                .padding(DesignTokens.Spacing.xxl)
                .opacity(revealed ? 1 : 0)
            }
        }
        .task(id: revealKey) {
            revealed = false
            guard revealKey.isEmpty == false else { return }
            let posters = items.prefix(DesignTokens.Card.gridRevealPrefetchCount)
                .compactMap { posterURL(for: $0, session: session) }
            async let warmed: Void = ArtworkPrefetch.warm(posters)
            await Task.yield()
            try? await Task.sleep(for: .seconds(DesignTokens.Card.gridRevealLayoutDelay))
            withAnimation(.easeOut(duration: DesignTokens.Card.gridRevealDuration)) {
                revealed = true
            }
            await warmed
        }
        .levelReadiness(isLoading == false)
        .scrollPosition($reachabilityScrollPosition)
#if DEBUG
        .onReceive(
            NotificationCenter.default.publisher(for: .embyReachabilityScroll)
        ) { notification in
            guard let request = notification.object as? EmbyReachabilityScrollRequest else {
                return
            }
            request.handle(on: reachabilityPage) {
                switch request.direction {
                case .forward: reachabilityScrollPosition.scrollTo(edge: .bottom)
                case .backward: reachabilityScrollPosition.scrollTo(edge: .top)
                }
            }
        }
#endif
        .accessibilityIdentifier("Emby-\(reachabilityPage)-list")
    }
}

private struct EmbyDetailScreen: View {
    @Environment(EmbySessionViewModel.self) private var session
    @State private var viewModel: EmbyDetailViewModel
    @State private var overviewIsExpanded = false
    @State private var scrollOffset: CGFloat = 0
    @State private var hasBeenScrolled = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var revealed = false
    @State private var backdropLoaded = false

    let onSelect: (EmbyLibraryItem) -> Void
    let onPlay: EmbyScreen.PlayHandler

    init(
        viewModel: EmbyDetailViewModel,
        onSelect: @escaping (EmbyLibraryItem) -> Void,
        onPlay: @escaping EmbyScreen.PlayHandler
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelect = onSelect
        self.onPlay = onPlay
    }

    var body: some View {
        GeometryReader { proxy in
            let heroHeight = heroHeight(in: proxy.size.height)
            let topMargin = DesignTokens.EmbyDetail.topContentInset
            let bottomMargin = proxy.safeAreaInsets.top + DesignTokens.Spacing.xxl
            let travel = heroHeight + DesignTokens.Spacing.xxl
            let progress = min(max(scrollOffset / travel, 0), 1)

            ZStack(alignment: .top) {
                if let item = viewModel.item {
                    backdrop(item)
                        .opacity(1 - min(progress / DesignTokens.EmbyDetail.backdropFadeFraction, 1))
                        .opacity(revealed ? 1 : 0)
                        .animation(
                            .easeOut(duration: DesignTokens.EmbyDetail.backdropEntranceDuration),
                            value: revealed
                        )
                }

                pageContent(
                    heroHeight: heroHeight,
                    travel: travel,
                    topMargin: topMargin,
                    bottomMargin: bottomMargin,
                    progress: progress
                )
            }
        }
        .task {
            await viewModel.refresh()
#if DEBUG
            if let item = viewModel.item {
                session.recordDetail(item: item, children: viewModel.children)
            }
#endif
            await runEntrance()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Emby-Detail-\(viewModel.itemID.rawValue)")
    }

    private func heroHeight(in containerHeight: CGFloat) -> CGFloat {
        max(
            DesignTokens.EmbyDetail.heroMinimumHeight,
            containerHeight * DesignTokens.EmbyDetail.heroHeightFraction
        )
    }

    private func pageContent(
        heroHeight: CGFloat,
        travel: CGFloat,
        topMargin: CGFloat,
        bottomMargin: CGFloat,
        progress: CGFloat
    ) -> some View {
        @Bindable var viewModel = viewModel
        return ScrollView(.vertical) {
            if let item = viewModel.item {
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                    hero(item)
                        .frame(height: heroHeight, alignment: .bottom)
                        .opacity(Double(1 - progress))
                    if revealed {
                        childrenContent
                            .transition(entrance(5))
                        posterShelf(title: String(localized: "Special Features"), items: viewModel.specialFeatures)
                            .transition(entrance(6))
                        posterShelf(title: String(localized: "Related"), items: viewModel.relatedItems)
                            .transition(entrance(7))
                        castAndCrew(item.metadata.people)
                            .transition(entrance(8))
                        about(item.metadata)
                            .transition(entrance(9))
                    }
                }
                .padding(.bottom, DesignTokens.Spacing.xxl)
            }
        }
        .contentMargins(.top, topMargin, for: .scrollContent)
        .contentMargins(.bottom, bottomMargin, for: .scrollContent)
        .ignoresSafeArea(.container, edges: .top)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffset = offset
        }
        .scrollTargetBehavior(
            EmbyHeroSnapBehavior(
                travel: travel,
                inset: topMargin,
                settleFraction: DesignTokens.EmbyDetail.heroSettleFraction,
                isEnabled: hasBeenScrolled
            )
        )
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { hasBeenScrolled = true }
        }
#if DEBUG
        .onReceive(
            NotificationCenter.default.publisher(for: .embyReachabilityScroll)
        ) { notification in
            guard let request = notification.object as? EmbyReachabilityScrollRequest else {
                return
            }
            request.handle(on: "detail") {
                switch request.direction {
                case .forward: scrollPosition.scrollTo(edge: .bottom)
                case .backward: scrollPosition.scrollTo(edge: .top)
                }
            }
        }
#endif
        .accessibilityIdentifier("Emby-Detail-list")
#if DEBUG
        .task(id: viewModel.item) {
            guard let name = EmbyLaunchRoute.current?.sectionName else { return }
            try? await Task.sleep(for: .milliseconds(600))
            if let offset = Double(name) {
                scroll(to: CGFloat(offset), topMargin: topMargin)
                return
            }
            switch Section(rawValue: name) {
            case .children: scroll(to: travel, topMargin: topMargin)
            case .about: scrollPosition.scrollTo(edge: .bottom)
            case nil: break
            }
        }
#endif
    }

    private func runEntrance() async {
        await ArtworkPrefetch.warm(entrancePrefetchURLs())
        let deadline = ContinuousClock.now.advanced(
            by: .seconds(DesignTokens.EmbyDetail.backdropWaitLimit)
        )
        while backdropLoaded == false, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .seconds(DesignTokens.EmbyDetail.backdropPollInterval))
        }
        withAnimation { revealed = true }
    }

    private func entrancePrefetchURLs() -> [URL] {
        var urls: [URL] = []
        switch viewModel.children {
        case .none:
            break
        case let .seasons(_, _, episodes):
            urls += episodes.map { thumbURL(for: $0.metadata, session: session) }.compactMap { $0 }
        case let .episodes(episodes):
            urls += episodes.map { thumbURL(for: $0.metadata, session: session) }.compactMap { $0 }
        case let .collection(members):
            urls += members.compactMap { posterURL(for: $0, session: session) }
        }
        urls += viewModel.specialFeatures.compactMap { posterURL(for: $0, session: session) }
        urls += viewModel.relatedItems.compactMap { posterURL(for: $0, session: session) }
        return Array(urls.prefix(DesignTokens.EmbyDetail.entrancePrefetchCount))
    }

    private func entranceDelay(_ index: Int) -> Double {
        DesignTokens.EmbyDetail.backdropEntranceDuration
            + DesignTokens.EmbyDetail.heroEntranceDelay
            + Double(index) * DesignTokens.EmbyDetail.entranceStagger
    }

    private func entrance(_ index: Int) -> AnyTransition {
        .opacity
            .combined(with: .offset(y: DesignTokens.EmbyDetail.entranceTravel))
            .animation(
                .easeOut(duration: DesignTokens.EmbyDetail.entranceDuration)
                    .delay(entranceDelay(index))
            )
    }

    private func scroll(to offset: CGFloat, topMargin: CGFloat) {
        scrollPosition.scrollTo(y: offset - topMargin)
    }

    private func backdrop(_ item: EmbyLibraryItem) -> some View {
        AsyncArtworkImage(
            url: heroArtworkURL(for: item, session: session),
            maxPixelSize: nil,
            onLoad: { backdropLoaded = true }
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    enum Section: String, Hashable {
        case children
        case about
    }

    private func hero(_ item: EmbyLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            if revealed {
                titleArtwork(item)
                    .transition(entrance(0))
                genreLine(item)
                    .transition(entrance(1))
                overview(item.metadata)
                    .transition(entrance(2))
                technicalLine(item.metadata)
                    .transition(entrance(3))
                HStack(alignment: .top, spacing: DesignTokens.Spacing.xxl) {
                    actionRow(item)
                    Spacer(minLength: DesignTokens.Spacing.xl)
                    creditSummary(item.metadata.people)
                }
                .transition(entrance(4))
            }
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if revealed {
                titleWash
                    .transition(
                        .opacity.animation(
                            .easeOut(duration: DesignTokens.EmbyDetail.entranceDuration)
                                .delay(entranceDelay(0))
                        )
                    )
            }
        }
    }

    private var titleWash: some View {
        GeometryReader { proxy in
            let spread = DesignTokens.EmbyDetail.titleWashSpread
            EllipticalGradient(
                stops: [
                    .init(color: .black.opacity(DesignTokens.EmbyDetail.titleWashStrength), location: 0),
                    .init(color: .black.opacity(DesignTokens.EmbyDetail.titleWashStrength * 0.45), location: 0.5),
                    .init(color: .clear, location: 1)
                ],
                center: .center,
                startRadiusFraction: 0,
                endRadiusFraction: 0.5
            )
            .frame(
                width: proxy.size.width * spread,
                height: proxy.size.height * spread
            )
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .blendMode(.multiply)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func titleArtwork(_ item: EmbyLibraryItem) -> some View {
        if let logoURL = imageURL(for: item, type: .logo, session: session) {
            AsyncArtworkImage(url: logoURL, contentMode: .fit)
                .frame(
                    maxWidth: DesignTokens.EmbyDetail.logoMaxWidth,
                    maxHeight: DesignTokens.EmbyDetail.logoMaxHeight,
                    alignment: .leading
                )
        } else {
            Text(item.metadata.name)
                .font(.system(size: 56, weight: .heavy, design: .default))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
    }

    private func genreLine(_ item: EmbyLibraryItem) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(kindLabel(item))
            ForEach(item.metadata.genres.prefix(3), id: \.self) { genre in
                Text("·")
                Text(genre)
            }
            if let rating = item.metadata.officialRating, rating.isEmpty == false {
                Text(rating)
                    .font(DesignTokens.Typography.badge)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .overlay(
                        DesignTokens.ShapeToken.element
                            .stroke(.secondary, lineWidth: DesignTokens.Stroke.regular)
                    )
            }
        }
        .font(DesignTokens.Typography.headline)
    }

    private func technicalLine(_ metadata: EmbyItemMetadata) -> some View {
        let badges = EmbyTechnicalBadges(source: selectedSource(metadata))
        return HStack(spacing: DesignTokens.Spacing.md) {
            if let year = metadata.productionYear { Text(String(year)) }
            if let ticks = metadata.runTimeTicks { Text(runtime(ticks)) }
            if let rating = metadata.communityRating {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
            }
            ForEach(badges.labels, id: \.self) { label in
                Text(label)
                    .font(DesignTokens.Typography.badge)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .enchronGlassBadge()
            }
        }
        .font(DesignTokens.Typography.metadata)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("Emby-Detail-TechnicalLine")
    }

    @ViewBuilder
    private func overview(_ metadata: EmbyItemMetadata) -> some View {
        if let overview = metadata.overview, overview.isEmpty == false {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(overview)
                    .font(.body)
                    .lineLimit(overviewIsExpanded ? nil : 3)
                    .frame(maxWidth: DesignTokens.EmbyDetail.overviewMaxWidth, alignment: .leading)
                if overview.count > 140 {
                    Button(overviewIsExpanded ? "Show Less" : "Show More") {
#if DEBUG
                        session.recordReachability("detail.overview.toggle")
#endif
                        overviewIsExpanded.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(DesignTokens.Typography.metadata)
                    .accessibilityIdentifier("Emby-Detail-Overview-Expand")
                }
            }
        }
    }

    @ViewBuilder
    private func creditSummary(_ people: [EmbyPerson]) -> some View {
        let cast = people.filter { $0.type?.caseInsensitiveCompare("Actor") == .orderedSame }
        let directors = people.filter { $0.type?.caseInsensitiveCompare("Director") == .orderedSame }
        if cast.isEmpty == false || directors.isEmpty == false {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                if cast.isEmpty == false {
                    creditLine("Starring", cast.prefix(3).map(\.name))
                }
                if directors.isEmpty == false {
                    creditLine("Directed by", directors.prefix(2).map(\.name))
                }
            }
            .frame(maxWidth: DesignTokens.EmbyDetail.creditMaxWidth, alignment: .leading)
        }
    }

    private func creditLine(_ label: String, _ names: [String]) -> some View {
        (Text(label).foregroundStyle(.secondary) + Text(" ") + Text(names.joined(separator: ", ")))
            .font(DesignTokens.Typography.metadata)
            .lineLimit(2)
    }

    private func actionRow(_ item: EmbyLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.md) {
                if item.isPlayable {
                    playButton("Play", systemImage: "play.fill", action: .resume)
                }

                if item.metadata.mediaSources.count > 1 {
                    Picker("Version", selection: mediaSourceSelection) {
                        ForEach(item.metadata.mediaSources) { source in
                            Text(versionSummary(source)).tag(Optional(source.id))
                        }
                    }
                    .labelsHidden()
                    .lineLimit(1)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Version")
                    .accessibilityIdentifier("Emby-Detail-Version")
                }
            }
        }
#if DEBUG
        .onReceive(
            NotificationCenter.default.publisher(for: .debugMenuSelection)
        ) { notification in
            guard let request = notification.object as? DebugMenuSelectionRequest,
                  item.metadata.mediaSources.count > 1,
                  request.family == .version else {
                return
            }
            request.handle(
                host: .emby,
                family: .version,
                items: item.metadata.mediaSources.map { source in
                    DebugMenuSelectionItem(
                        id: source.id.rawValue,
                        title: versionSummary(source),
                        isSelected: viewModel.selectedMediaSourceID == source.id,
                        select: { mediaSourceSelection.wrappedValue = source.id }
                    )
                }
            )
        }
#endif
    }

    private var mediaSourceSelection: Binding<EmbyMediaSourceID?> {
        Binding(
            get: { viewModel.selectedMediaSourceID },
            set: {
#if DEBUG
                session.recordReachability("detail.version.select")
#endif
                viewModel.selectedMediaSourceID = $0
            }
        )
    }

    private func kindLabel(_ item: EmbyLibraryItem) -> String {
        switch item {
        case .movie: "Movie"
        case .series: "Series"
        case .season: "Season"
        case .episode: "Episode"
        case .boxSet: "Collection"
        }
    }

    private func versionSummary(_ source: EmbyMediaSourceDescription) -> String {
        let video = source.mediaStreams.first { $0.kind == .video }
        var parts: [String] = []
        if let height = video?.height {
            parts.append("\(height)p")
        }
        if let codec = video?.codec, codec.isEmpty == false {
            parts.append(codec.uppercased())
        }
        if let range = video?.videoRange,
           range.isEmpty == false,
           range.caseInsensitiveCompare("SDR") != .orderedSame {
            parts.append(range.uppercased())
        }
        if parts.isEmpty, let container = source.container, container.isEmpty == false {
            parts.append(container.uppercased())
        }
        return parts.isEmpty ? source.displayName : parts.joined(separator: " · ")
    }

    private func aboutSources(_ metadata: EmbyItemMetadata) -> [EmbyMediaSourceDescription] {
        if metadata.mediaSources.isEmpty == false {
            return [selectedSource(metadata)].compactMap { $0 }
        }
        return viewModel.children.episodes.flatMap(\.metadata.mediaSources)
    }

    private func selectedSource(_ metadata: EmbyItemMetadata) -> EmbyMediaSourceDescription? {
        metadata.mediaSources.first { $0.id == viewModel.selectedMediaSourceID }
            ?? metadata.mediaSources.first
    }

    private func playButton(
        _ title: String,
        systemImage: String,
        action: EmbyPlaybackStartAction
    ) -> some View {
        Button {
#if DEBUG
            session.recordReachability("detail.play.\(action)")
#endif
            Task {
                do {
                    await onPlay(.success(try viewModel.playbackSelection(startAction: action)))
                } catch let error as EmbyError {
                    await onPlay(.failure(error))
                } catch {
                    await onPlay(.failure(.invalidResponse))
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("Emby-Detail-Play")
    }

    @ViewBuilder
    private var childrenContent: some View {
        switch viewModel.children {
        case .none:
            EmptyView()
        case let .seasons(all, selected, episodes):
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                if all.count > 1 {
                    seasonPicker(all, selected: selected)
                        .padding(.horizontal, DesignTokens.Spacing.xxl)
                }
                ZStack {
                    episodeShelf(episodes, title: all.count > 1 ? nil : "Episodes")
                        .id(episodes.first?.metadata.id)
                        .transition(.opacity)
                }
                .animation(
                    DesignTokens.AnimationToken.controlsTransition,
                    value: episodes.first?.metadata.id
                )
            }
        case let .episodes(episodes):
            episodeShelf(episodes, title: String(localized: "Episodes"))
        case let .collection(members):
            posterShelf(title: String(localized: "In This Collection"), items: members)
        }
    }

    private func seasonPicker(_ seasons: [EmbySeason], selected: EmbyItemID?) -> some View {
        Menu {
            Picker("Season", selection: seasonSelection(selected)) {
                ForEach(seasons, id: \.metadata.id) { season in
                    Text(season.metadata.name)
                        .tag(Optional(season.metadata.id))
                        .accessibilityIdentifier("Emby-Season-\(season.metadata.id.rawValue)")
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(seasons.first { $0.metadata.id == selected }?.metadata.name ?? "Seasons")
                Image(systemName: "chevron.down")
                    .font(DesignTokens.SymbolSize.label)
            }
            .font(DesignTokens.Typography.headline)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .frame(height: DesignTokens.Interactive.regular)
            .background(DesignTokens.Surface.selected, in: Capsule())
            .enchronHoverContentShape(Capsule())
            .enchronHoverEffect(.highlight)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityIdentifier("Emby-Season-Picker")
#if DEBUG
        .onReceive(
            NotificationCenter.default.publisher(for: .debugMenuSelection)
        ) { notification in
            guard let request = notification.object as? DebugMenuSelectionRequest,
                  request.family == .season else {
                return
            }
            request.handle(
                host: .emby,
                family: .season,
                items: seasons.map { season in
                    DebugMenuSelectionItem(
                        id: season.metadata.id.rawValue,
                        title: season.metadata.name,
                        isSelected: season.metadata.id == selected,
                        select: {
                            seasonSelection(selected).wrappedValue = season.metadata.id
                        }
                    )
                }
            )
        }
#endif
    }

    private func seasonSelection(_ selected: EmbyItemID?) -> Binding<EmbyItemID?> {
        Binding(
            get: { selected },
            set: { value in
                guard let value, value != selected else { return }
#if DEBUG
                session.recordReachability("season.select.\(value.rawValue)")
#endif
                Task {
#if DEBUG
                    let before = viewModel.children
#endif
                    await viewModel.selectSeason(value)
#if DEBUG
                    guard let item = viewModel.item else { return }
                    session.recordDetail(item: item, children: viewModel.children)
                    guard case .series = item,
                          case .seasons(
                              let declaredSeasons,
                              let beforeSelectedSeasonID,
                              let beforeEpisodes
                          ) = before,
                          case .seasons(
                              _,
                              let afterSelectedSeasonID,
                              let afterEpisodes
                          ) = viewModel.children else { return }
                    session.recordSeasonTransition(
                        seriesID: item.metadata.id,
                        declaredSeasons: declaredSeasons,
                        requestedSeasonID: value,
                        beforeSelectedSeasonID: beforeSelectedSeasonID,
                        beforeEpisodes: beforeEpisodes,
                        afterSelectedSeasonID: afterSelectedSeasonID,
                        afterEpisodes: afterEpisodes
                    )
#endif
                }
            }
        )
    }

    @ViewBuilder
    private func episodeShelf(_ episodes: [EmbyEpisode], title: String?) -> some View {
        if episodes.isEmpty == false {
            EmbyShelf(title: title) {
                ForEach(episodes, id: \.metadata.id) { episode in
                    episodeCard(episode)
                }
            }
        }
    }

    private func episodeCard(_ episode: EmbyEpisode) -> GridCard {
        let metadata = episode.metadata
        return GridCard.episode(
            title: metadata.name,
            numberLabel: episode.episodeNumber.map { String(format: "%02d", $0) },
            overview: metadata.overview,
            duration: metadata.runTimeTicks.map(runtime),
            artworkURL: thumbURL(for: metadata, session: session),
            watchedProgress: watchedProgress(metadata),
            accessibilityIdentifier: "Emby-Episode-\(metadata.id.rawValue)",
            action: {
#if DEBUG
                session.recordReachability("episode.select.\(metadata.id.rawValue)")
#endif
                Task {
                    await onPlay(.success(viewModel.playbackSelection(for: episode)))
                }
            }
        )
    }

    @ViewBuilder
    private func posterShelf(title: String, items: [EmbyLibraryItem]) -> some View {
        if items.isEmpty == false {
            EmbyShelf(title: title) {
                ForEach(items, id: \.metadata.id) { item in
                    posterCard(item, session: session, onSelect: onSelect)
                }
            }
        }
    }

    @ViewBuilder
    private func castAndCrew(_ people: [EmbyPerson]) -> some View {
        if people.isEmpty == false {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                Text("Cast & Crew").font(DesignTokens.Typography.title)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.xl) {
                        ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                            VStack(spacing: DesignTokens.Spacing.sm) {
                                AsyncArtworkImage(url: personURL(person, session: session))
                                    .frame(width: 132, height: 132)
                                    .clipShape(Circle())
                                Text(person.name)
                                    .font(DesignTokens.Typography.headline)
                                    .multilineTextAlignment(.center)
                                if let role = person.role ?? person.type {
                                    Text(role)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(width: 150)
                        }
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
        }
    }

    private func about(_ metadata: EmbyItemMetadata) -> some View {
        let sections = EmbyAboutSections(metadata: metadata, sources: aboutSources(metadata))
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("About").font(DesignTokens.Typography.title)

            if let overview = metadata.overview, overview.isEmpty == false {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(metadata.name).font(DesignTokens.Typography.headline)
                        if metadata.genres.isEmpty == false {
                            Text(metadata.genres.joined(separator: ", "))
                                .font(DesignTokens.Typography.sectionHeader)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                    }
                    Text(overview).foregroundStyle(.secondary)
                }
                .padding(DesignTokens.Spacing.lg)
                .frame(maxWidth: DesignTokens.EmbyDetail.aboutCardWidth, alignment: .leading)
                .background(.thinMaterial, in: DesignTokens.ShapeToken.element)
            }

            LazyVGrid(
                columns: [GridItem(
                    .adaptive(minimum: DesignTokens.EmbyDetail.aboutColumnWidth),
                    spacing: DesignTokens.Spacing.xxl,
                    alignment: .topLeading
                )],
                alignment: .leading,
                spacing: DesignTokens.Spacing.xxl
            ) {
                aboutColumn("Information", sections.information)
                aboutColumn("Languages", sections.languages)
                aboutColumn("Video", sections.video)
                aboutColumn("Audio", sections.audio)
                aboutColumn("Subtitles", sections.subtitles)
                aboutColumn("File", sections.file)
                aboutColumn("Accessibility", sections.accessibility, labelsAreBadges: true)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .accessibilityIdentifier("Emby-Detail-About")
    }

    @ViewBuilder
    private func aboutColumn(
        _ title: String,
        _ entries: [EmbyAboutSections.Entry],
        labelsAreBadges: Bool = false
    ) -> some View {
        if entries.isEmpty == false {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                Text(title)
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                CollapsibleBlock(title: title) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                                if labelsAreBadges {
                                    Text(entry.label)
                                        .font(DesignTokens.Typography.badge)
                                        .padding(.horizontal, DesignTokens.Spacing.xs)
                                        .padding(.vertical, DesignTokens.Spacing.xxs)
                                        .enchronGlassBadge()
                                } else {
                                    Text(entry.label)
                                        .font(DesignTokens.Typography.metadata)
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.value)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

@MainActor
private func posterCard(
    _ item: EmbyLibraryItem,
    session: EmbySessionViewModel,
    onSelect: @escaping (EmbyLibraryItem) -> Void
) -> GridCard {
    let metadata = item.metadata
    return GridCard.poster(
        title: metadata.name,
        artworkURL: posterURL(for: item, session: session),
        watchedProgress: watchedProgress(metadata),
        unplayedCount: metadata.userData?.unplayedItemCount,
        accessibilityIdentifier: "Emby-PosterCard-\(metadata.id.rawValue)",
        action: {
#if DEBUG
            session.recordReachability("posterCard.select.\(metadata.id.rawValue)")
#endif
            onSelect(item)
        }
    )
}

@MainActor
private func stillCard(
    _ item: EmbyLibraryItem,
    session: EmbySessionViewModel,
    onSelect: @escaping (EmbyLibraryItem) -> Void
) -> GridCard {
    let metadata = item.metadata
    return GridCard.episode(
        title: metadata.name,
        numberLabel: item.episode?.episodeNumber.map { String(format: "%02d", $0) },
        overview: metadata.overview,
        duration: metadata.runTimeTicks.map(runtime),
        artworkURL: thumbURL(for: metadata, session: session),
        watchedProgress: watchedProgress(metadata),
        accessibilityIdentifier: "Emby-StillCard-\(metadata.id.rawValue)",
        action: {
#if DEBUG
            session.recordReachability("stillCard.select.\(metadata.id.rawValue)")
#endif
            onSelect(item)
        }
    )
}

@MainActor
private func posterURL(for item: EmbyLibraryItem, session: EmbySessionViewModel) -> URL? {
    imageURL(for: item, type: .primary, session: session, maxWidth: DesignTokens.Card.posterWidth)
}

@MainActor
private func imageURL(
    for item: EmbyLibraryItem,
    type: EmbyImageType,
    session: EmbySessionViewModel,
    maxWidth: CGFloat? = nil
) -> URL? {
    guard let server = session.server else { return nil }
    let tag: EmbyImageTag? = switch type {
    case .primary: item.metadata.imageTags.primary
    case .logo: item.metadata.imageTags.logo
    case .thumb: item.metadata.imageTags.thumb
    case .backdrop: item.metadata.imageTags.backdrops.first
    }
    guard tag != nil else { return nil }
    return try? session.client.imageURL(
        for: item.metadata.id,
        type: type,
        tag: tag,
        size: maxWidth.flatMap { try? EmbyImageSize.width(Int($0 * 2)) },
        on: server
    )
}

@MainActor
private func heroArtworkURL(for item: EmbyLibraryItem, session: EmbySessionViewModel) -> URL? {
    guard let server = session.server else { return nil }
    if let tag = item.metadata.imageTags.backdrops.first,
       let url = try? session.client.backdropImageURL(
           for: item.metadata.id,
           index: 0,
           tag: tag,
           size: try? EmbyImageSize.width(DesignTokens.EmbyDetail.backdropRequestWidth),
           on: server
       ) {
        return url
    }
    return imageURL(for: item, type: .thumb, session: session)
        ?? imageURL(for: item, type: .primary, session: session)
}

@MainActor
func warmDetailArtwork(for item: EmbyLibraryItem, session: EmbySessionViewModel) {
    let urls = [
        heroArtworkURL(for: item, session: session),
        imageURL(for: item, type: .logo, session: session)
    ].compactMap { $0 }
    guard urls.isEmpty == false else { return }
    Task { await ArtworkPrefetch.warm(urls) }
}

@MainActor
private func thumbURL(for metadata: EmbyItemMetadata, session: EmbySessionViewModel) -> URL? {
    guard let server = session.server else { return nil }
    let type: EmbyImageType = metadata.imageTags.thumb == nil ? .primary : .thumb
    let tag = metadata.imageTags.thumb ?? metadata.imageTags.primary
    guard let tag else { return nil }
    return try? session.client.imageURL(
        for: metadata.id,
        type: type,
        tag: tag,
        size: try? EmbyImageSize.width(Int(DesignTokens.Card.stillWidth * 2)),
        on: server
    )
}

@MainActor
private func personURL(_ person: EmbyPerson, session: EmbySessionViewModel) -> URL? {
    guard let server = session.server,
          let id = person.id,
          let tag = person.primaryImageTag else { return nil }
    return try? session.client.imageURL(
        for: id,
        type: .primary,
        tag: tag,
        size: nil,
        on: server
    )
}

private func runtime(_ ticks: Int64) -> String {
    let totalMinutes = max(0, ticks / 10_000_000 / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
}

private func watchedProgress(_ metadata: EmbyItemMetadata) -> Double? {
    guard let position = metadata.userData?.playbackPositionTicks,
          let duration = metadata.runTimeTicks,
          duration > 0,
          position > 0 else { return nil }
    return Double(position) / Double(duration)
}
