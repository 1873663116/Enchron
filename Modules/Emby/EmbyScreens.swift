import DesignSystem
import Foundation
import SwiftUI

public struct EmbyScreen: View {
    public typealias PlayHandler = @MainActor (EmbyPlaybackSelection) async throws -> Void

    @Environment(EmbySessionViewModel.self) private var session
    @Environment(EmbyHomeViewModel.self) private var home
    @State private var destination: SidebarDestination = .home
    @State private var path: [EmbyLibraryItem] = []
    @State private var sidebarIsVisible = true

    private let onPlay: PlayHandler

    public init(onPlay: @escaping PlayHandler) {
        self.onPlay = onPlay
    }

    public var body: some View {
        Group {
            if session.server == nil {
                EmbyConnectionScreen()
            } else {
                HStack(spacing: 0) {
                    if sidebarIsVisible {
                        sidebar
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    NavigationStack(path: $path) {
                        destinationContent
                            .navigationDestination(for: EmbyLibraryItem.self) { item in
                                EmbyDetailScreen(
                                    viewModel: EmbyDetailViewModel(
                                        itemID: item.metadata.id,
                                        client: session.client,
                                        session: session
                                    ),
                                    onSelect: { path.append($0) },
                                    onPlay: onPlay
                                )
                            }
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    SidebarToggleButton(
                                        isVisible: $sidebarIsVisible,
                                        accessibilityIdentifier: "Emby-Sidebar-Toggle"
                                    )
                                }
                            }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(DesignTokens.AnimationToken.controlsTransition, value: sidebarIsVisible)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Emby-Root")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text(session.server?.name ?? "Emby")
                .font(DesignTokens.SourceSidebar.sectionTitleFont)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, DesignTokens.SourceSidebar.contentPaddingH)

            VStack(spacing: DesignTokens.SourceSidebar.rowSpacing) {
                sidebarButton(
                    title: "Home",
                    systemImage: "house.fill",
                    destination: .home,
                    identifier: "Emby-Sidebar-Home"
                )

                ForEach(home.libraries, id: \.id) { library in
                    sidebarButton(
                        title: library.name,
                        systemImage: "rectangle.stack.fill",
                        destination: .library(library.id),
                        identifier: "Emby-Sidebar-Library-\(library.id.rawValue)"
                    )
                }

                sidebarButton(
                    title: "Search",
                    systemImage: "magnifyingglass",
                    destination: .search,
                    identifier: "Emby-Sidebar-Search"
                )
            }
            .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)

            Spacer(minLength: DesignTokens.Spacing.xl)

            Button {
                Task { await session.signOut() }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignTokens.SourceSidebar.rowPaddingH)
                    .frame(height: DesignTokens.SourceSidebar.rowHeight)
            }
            .buttonStyle(.plain)
            .enchronHoverContentShape(DesignTokens.SourceSidebar.rowShape)
            .enchronHoverEffect(.highlight)
            .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)
            .accessibilityIdentifier("Emby-SignOut")
        }
        .padding(.vertical, DesignTokens.SourceSidebar.contentPaddingV)
        .frame(width: DesignTokens.SourceSidebar.width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .enchronPlateGlassBackground(in: DesignTokens.SourceSidebar.shape)
        .padding(.leading, DesignTokens.SourceSidebar.windowInset)
        .padding(.vertical, DesignTokens.SourceSidebar.windowInset)
    }

    private func sidebarButton(
        title: String,
        systemImage: String,
        destination: SidebarDestination,
        identifier: String
    ) -> some View {
        Button {
            self.destination = destination
            path = []
        } label: {
            Label(title, systemImage: systemImage)
                .font(DesignTokens.Typography.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignTokens.SourceSidebar.rowPaddingH)
                .frame(height: DesignTokens.SourceSidebar.rowHeight)
                .background(
                    self.destination == destination
                        ? DesignTokens.Surface.selected
                        : Color.clear,
                    in: DesignTokens.SourceSidebar.rowShape
                )
        }
        .buttonStyle(.plain)
        .enchronHoverContentShape(DesignTokens.SourceSidebar.rowShape)
        .enchronHoverEffect(.highlight)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch destination {
        case .home:
            EmbyHomeScreen(onSelect: { path.append($0) })
        case .library(let id):
            if let library = home.libraries.first(where: { $0.id == id }) {
                EmbyLibraryScreen(
                    viewModel: EmbyLibraryViewModel(
                        library: library,
                        client: session.client,
                        session: session
                    ),
                    onSelect: { path.append($0) }
                )
            } else {
                ContentUnavailableView("Library Unavailable", systemImage: "rectangle.stack")
            }
        case .search:
            EmbySearchScreen(onSelect: { path.append($0) })
        }
    }
}

private enum SidebarDestination: Hashable {
    case home
    case library(EmbyItemID)
    case search
}

private struct EmbyConnectionScreen: View {
    @Environment(EmbyConnectionViewModel.self) private var viewModel

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
    }
}

private struct EmbyHomeScreen: View {
    @Environment(EmbyHomeViewModel.self) private var viewModel
    @Environment(EmbySessionViewModel.self) private var session
    let onSelect: (EmbyLibraryItem) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                Text("Home")
                    .font(.largeTitle)

                ForEach(viewModel.shelves) { shelf in
                    EmbyPosterShelf(title: shelf.title) {
                        ForEach(shelf.items, id: \.metadata.id) { item in
                            posterCard(item, session: session, onSelect: onSelect)
                        }
                    }
                }

                if viewModel.shelves.isEmpty, viewModel.isLoading == false {
                    ContentUnavailableView("No Emby titles", systemImage: "film.stack")
                }
            }
            .padding(DesignTokens.Spacing.xxl)
        }
        .task { await viewModel.refresh() }
        .accessibilityIdentifier("Emby-Home")
    }
}

private struct EmbyLibraryScreen: View {
    @Environment(EmbySessionViewModel.self) private var session
    @State private var viewModel: EmbyLibraryViewModel
    let onSelect: (EmbyLibraryItem) -> Void

    init(viewModel: EmbyLibraryViewModel, onSelect: @escaping (EmbyLibraryItem) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSelect = onSelect
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            HStack {
                Text(viewModel.library.name)
                    .font(.largeTitle)
                Spacer()
                Picker("Sort", selection: Binding(
                    get: { viewModel.sort },
                    set: { value in Task { await viewModel.selectSort(value) } }
                )) {
                    ForEach(EmbyLibrarySort.allCases, id: \.self) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
                .accessibilityIdentifier("Emby-Library-Sort")
            }
            .padding(DesignTokens.Spacing.xxl)

            EmbyPosterGrid(items: viewModel.items, session: session, onSelect: onSelect)
        }
        .task { await viewModel.refresh() }
        .accessibilityIdentifier("Emby-Library-\(viewModel.library.id.rawValue)")
    }
}

private struct EmbySearchScreen: View {
    @Environment(EmbySearchViewModel.self) private var viewModel
    @Environment(EmbySessionViewModel.self) private var session
    let onSelect: (EmbyLibraryItem) -> Void

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: DesignTokens.Spacing.xl) {
            TextField("Search Emby", text: $viewModel.query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("Emby-Search-Field")
                .onSubmit { Task { await viewModel.refresh() } }
                .padding(.horizontal, DesignTokens.Spacing.xxl)
                .padding(.top, DesignTokens.Spacing.xxl)

            EmbyPosterGrid(items: viewModel.results, session: session, onSelect: onSelect)
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
        .accessibilityIdentifier("Emby-Search")
    }
}

private struct EmbyPosterGrid: View {
    let items: [EmbyLibraryItem]
    let session: EmbySessionViewModel
    let onSelect: (EmbyLibraryItem) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: DesignTokens.Card.gridMin), spacing: DesignTokens.Card.gridSpacing)],
                alignment: .leading,
                spacing: DesignTokens.Card.gridSpacing
            ) {
                ForEach(items, id: \.metadata.id) { item in
                    posterCard(item, session: session, onSelect: onSelect)
                }
            }
            .padding(DesignTokens.Spacing.xxl)
        }
    }
}

private struct EmbyDetailScreen: View {
    @Environment(EmbySessionViewModel.self) private var session
    @State private var viewModel: EmbyDetailViewModel
    @State private var overviewIsExpanded = false
    @State private var playbackError: String?

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
        @Bindable var viewModel = viewModel
        ScrollView(.vertical) {
            if let item = viewModel.item {
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                    hero(item)
                    seriesContent
                    posterShelf(title: "Special Features", items: viewModel.specialFeatures)
                    posterShelf(title: "Related", items: viewModel.relatedItems)
                    castAndCrew(item.metadata.people)
                    about(item.metadata)
                }
                .padding(.bottom, DesignTokens.Spacing.xxl)
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .task { await viewModel.refresh() }
        .accessibilityIdentifier("Emby-Detail-\(viewModel.itemID.rawValue)")
    }

    /// The hero fills the panel the way the Apple TV app does: artwork behind, every piece of
    /// header content overlaid on it, scrim only where text sits.
    private func hero(_ item: EmbyLibraryItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncArtworkImage(url: backdropURL(for: item, session: session))
                .frame(maxWidth: .infinity)
                .frame(height: DesignTokens.EmbyDetail.heroHeight)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.35), .black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                titleArtwork(item)
                genreLine(item)
                overview(item.metadata)
                technicalLine(item.metadata)
                HStack(alignment: .top, spacing: DesignTokens.Spacing.xxl) {
                    actionRow(item)
                    Spacer(minLength: DesignTokens.Spacing.xl)
                    creditSummary(item.metadata.people)
                }
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: DesignTokens.EmbyDetail.heroHeight)
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
                    .lineLimit(overviewIsExpanded ? nil : 2)
                    .frame(maxWidth: DesignTokens.EmbyDetail.overviewMaxWidth, alignment: .leading)
                if overview.count > 140 {
                    Button(overviewIsExpanded ? "Less" : "More") {
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
                if isPlayable(item) {
                    if (item.metadata.userData?.playbackPositionTicks ?? 0) > 0 {
                        playButton("Resume", systemImage: "play.fill", action: .resume)
                        playButton("Play from Beginning", systemImage: "backward.end.fill", action: .fromBeginning)
                    } else {
                        playButton("Play", systemImage: "play.fill", action: .fromBeginning)
                    }
                }

                if item.metadata.mediaSources.count > 1 {
                    Picker("Version", selection: Binding(
                        get: { viewModel.selectedMediaSourceID },
                        set: { viewModel.selectedMediaSourceID = $0 }
                    )) {
                        ForEach(item.metadata.mediaSources) { source in
                            Text(source.displayName).tag(Optional(source.id))
                        }
                    }
                    .frame(width: 300)
                    .accessibilityIdentifier("Emby-Detail-Version")
                }
            }
            if let playbackError {
                Text(playbackError)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("Emby-Playback-Error")
            }
        }
    }

    private func isPlayable(_ item: EmbyLibraryItem) -> Bool {
        switch item {
        case .movie, .episode: true
        case .series, .season, .boxSet: false
        }
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
            Task {
                do {
                    try await onPlay(viewModel.playbackSelection(startAction: action))
                    playbackError = nil
                } catch {
                    playbackError = error.localizedDescription
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("Emby-Detail-\(action == .resume ? "Resume" : "PlayFromBeginning")")
    }

    @ViewBuilder
    private var seriesContent: some View {
        if viewModel.seasons.isEmpty == false {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(viewModel.seasons, id: \.metadata.id) { season in
                            Button(season.metadata.name) {
                                Task { await viewModel.selectSeason(season.metadata.id) }
                            }
                            .buttonStyle(.bordered)
                            .fontWeight(viewModel.selectedSeasonID == season.metadata.id ? .bold : .regular)
                            .accessibilityIdentifier("Emby-Season-\(season.metadata.id.rawValue)")
                        }
                    }
                }

                LazyVStack(spacing: DesignTokens.Spacing.lg) {
                    ForEach(viewModel.episodes, id: \.metadata.id) { episode in
                        Button {
                            Task {
                                do {
                                    try await onPlay(viewModel.playbackSelection(for: episode))
                                    playbackError = nil
                                } catch {
                                    playbackError = error.localizedDescription
                                }
                            }
                        } label: {
                            episodeRow(episode)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("Emby-Episode-\(episode.metadata.id.rawValue)")
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
        }
    }

    private func episodeRow(_ episode: EmbyEpisode) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
            AsyncArtworkImage(url: thumbURL(for: episode.metadata, session: session))
                .frame(width: 300, height: 169)
                .clipped()
                .clipShape(DesignTokens.ShapeToken.element)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text(episodeLabel(episode))
                    .font(DesignTokens.Typography.headline)
                if let overview = episode.metadata.overview {
                    Text(overview)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if let ticks = episode.metadata.runTimeTicks {
                    Text(runtime(ticks))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func posterShelf(title: String, items: [EmbyLibraryItem]) -> some View {
        if items.isEmpty == false {
            EmbyPosterShelf(title: title) {
                ForEach(items, id: \.metadata.id) { item in
                    posterCard(item, session: session, onSelect: onSelect)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
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
        let sections = EmbyAboutSections(metadata: metadata, source: selectedSource(metadata))
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("About").font(DesignTokens.Typography.title)

            if let overview = metadata.overview, overview.isEmpty == false {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text(metadata.name).font(DesignTokens.Typography.headline)
                    Text(overview).foregroundStyle(.secondary)
                }
                .padding(DesignTokens.Spacing.lg)
                .frame(maxWidth: DesignTokens.EmbyDetail.aboutCardWidth, alignment: .leading)
                .background(.thinMaterial, in: DesignTokens.ShapeToken.element)
            }

            HStack(alignment: .top, spacing: DesignTokens.Spacing.xxl) {
                aboutColumn("Information", sections.information)
                aboutColumn("Languages", sections.languages)
                aboutColumn("Accessibility", sections.accessibility)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .accessibilityIdentifier("Emby-Detail-About")
    }

    @ViewBuilder
    private func aboutColumn(_ title: String, _ entries: [EmbyAboutSections.Entry]) -> some View {
        if entries.isEmpty == false {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                Text(title)
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(entry.label).font(DesignTokens.Typography.metadata).foregroundStyle(.secondary)
                        Text(entry.value)
                    }
                }
            }
            .frame(maxWidth: DesignTokens.EmbyDetail.aboutColumnWidth, alignment: .leading)
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
    let watchedProgress: Double?
    if let position = metadata.userData?.playbackPositionTicks,
       let duration = metadata.runTimeTicks,
       duration > 0,
       position > 0 {
        watchedProgress = Double(position) / Double(duration)
    } else {
        watchedProgress = nil
    }
    return GridCard.poster(
        title: metadata.name,
        artworkURL: posterURL(for: item, session: session),
        watchedProgress: watchedProgress,
        unplayedCount: metadata.userData?.unplayedItemCount,
        accessibilityIdentifier: "Emby-PosterCard-\(metadata.id.rawValue)",
        action: { onSelect(item) }
    )
}

@MainActor
private func posterURL(for item: EmbyLibraryItem, session: EmbySessionViewModel) -> URL? {
    imageURL(for: item, type: .primary, session: session)
}

@MainActor
private func imageURL(
    for item: EmbyLibraryItem,
    type: EmbyImageType,
    session: EmbySessionViewModel
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
        size: nil,
        on: server
    )
}

@MainActor
private func backdropURL(for item: EmbyLibraryItem, session: EmbySessionViewModel) -> URL? {
    guard let server = session.server,
          let tag = item.metadata.imageTags.backdrops.first else { return nil }
    return try? session.client.backdropImageURL(
        for: item.metadata.id,
        index: 0,
        tag: tag,
        size: nil,
        on: server
    )
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
        size: nil,
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

private func episodeLabel(_ episode: EmbyEpisode) -> String {
    let number = episode.episodeNumber.map { "Episode \($0)" } ?? "Episode"
    return "\(number) · \(episode.metadata.name)"
}
