import DesignSystem
import Foundation
import SwiftUI

/// Height of a page's header row. The toggle, the page title and the page's own control all sit on
/// this one line, and the page's content scrolls underneath it, so nothing is cut by a row above.
private let embyHeaderHeight = DesignTokens.Interactive.large + DesignTokens.Spacing.xl + DesignTokens.Spacing.lg

private extension View {
    /// Bounds a page's rendering to the page. A scroll view on visionOS otherwise paints its cells
    /// past the window's edge as they leave the viewport.
    func embyPageBounds() -> some View {
        clipped()
    }
}

/// The two positions a detail page has: showing its picture, or showing its sections under the art
/// title. Everything between them is a place the page passes through, not one it stops in.
///
/// This is the system's own hand-off point for deciding where a scroll ends. Adjusting the target
/// here means the page decelerates into position on the system's curve, instead of being scrolled
/// out from under a gesture that is still running.
private struct EmbyHeroSnapBehavior: ScrollTargetBehavior {
    /// Distance from rest at which the sections reach the top.
    let travel: CGFloat
    /// The margin held open for the art title. Scroll targets count from the content's top edge,
    /// which sits that much higher than rest.
    let inset: CGFloat
    /// How far up the page has to be going for the sections to win over the picture.
    let settleFraction: CGFloat
    /// Whether the wearer has scrolled this page yet.
    ///
    /// The system asks this type where a scroll should end whenever it resolves a target, not only
    /// when a gesture on this page finishes. A page pushed from a shelf the wearer had just been
    /// scrolling is resolved while that upward motion is still in hand, and answering it sends a
    /// page that nobody has touched straight past its picture. Until this page has been scrolled,
    /// wherever it is is where it belongs.
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

/// One page header: the sidebar toggle, the title, and whatever the page puts on its trailing edge.
private struct EmbyPageHeader<Trailing: View>: View {
    let title: String
    let sidebarIsVisible: Binding<Bool>?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            if let sidebarIsVisible {
                SidebarToggleButton(
                    isVisible: sidebarIsVisible,
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
                    // A detail page navigates with its own back control, so the sidebar and the
                    // control that hides it are both gone there: the sidebar only ever browses.
                    if path.isEmpty, sidebarIsVisible {
                        sidebar
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    NavigationStack(path: $path) {
                        // Sidebar destinations are siblings with no direction between them, so they
                        // cross-fade the way the Settings detail cross-fades categories. The ZStack
                        // is what carries the animation: a modifier attached above the changing
                        // `.id` is rebuilt along with it and animates nothing.
                        ZStack {
                            destinationContent
                                .id(destination)
                                .transition(.opacity)
                        }
                            .animation(DesignTokens.AnimationToken.controlsTransition, value: destination)
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
                .animation(DesignTokens.AnimationToken.controlsTransition, value: sidebarIsVisible)
                .animation(DesignTokens.AnimationToken.controlsTransition, value: path.isEmpty)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Emby-Root")
#if DEBUG
        .task { await openLaunchRoute() }
#endif
    }

    /// Every route into a detail page comes through here, so the page's backdrop and art title start
    /// loading as the push begins rather than after it lands.
    private func open(_ item: EmbyLibraryItem) {
        warmDetailArtwork(for: item, session: session)
        path.append(item)
    }

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
            destination = .library(libraryID)
        }
        sidebarIsVisible = route.sidebarIsVisible
        guard let itemID = route.itemID, let server = session.server else { return }
        if let item = try? await session.client.item(withID: itemID, on: server) {
            path = [item]
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
                sidebarRow(icon: "house.fill", title: "Home", destination: .home)

                ForEach(home.libraries, id: \.id) { library in
                    sidebarRow(
                        icon: "rectangle.stack.fill",
                        title: library.name,
                        destination: .library(library.id)
                    )
                }

                sidebarRow(icon: "magnifyingglass", title: "Search", destination: .search)
            }
            .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)

            Spacer(minLength: 0)

            EditableSourceSidebarRow(
                icon: "rectangle.portrait.and.arrow.right",
                title: "Sign Out",
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
                onTap: { Task { await session.signOut() } }
            )
            .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)
            .accessibilityIdentifier("Emby-SignOut")
        }
        .padding(.vertical, DesignTokens.SourceSidebar.contentPaddingV)
        .frame(width: DesignTokens.SourceSidebar.width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .enchronSidebarSurface()
        .accessibilityIdentifier("Emby-Sidebar")
    }

    /// The same row the Media Library sidebar uses, with reordering and swipe-to-delete switched off.
    private func sidebarRow(
        icon: String,
        title: String,
        destination: SidebarDestination
    ) -> some View {
        EditableSourceSidebarRow(
            icon: icon,
            title: title,
            isSelected: self.destination == destination,
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
                self.destination = destination
                path = []
            }
        )
        .accessibilityIdentifier("Emby-Sidebar-\(destination.id)")
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch destination {
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
                // Each library is its own screen. Without this, switching between two libraries
                // reuses the view and keeps the previous library's view model in `@State`.
                .id(id)
            } else {
                ContentUnavailableView("Library Unavailable", systemImage: "rectangle.stack")
            }
        case .search:
            EmbySearchScreen(sidebarIsVisible: $sidebarIsVisible, onSelect: open)
        }
    }
}

private enum SidebarDestination: Hashable {
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

    init?(id: String) {
        switch id {
        case "home": self = .home
        case "search": self = .search
        default:
            guard id.hasPrefix("library-") else { return nil }
            self = .library(EmbyItemID(rawValue: String(id.dropFirst("library-".count))))
        }
    }
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
    let sidebarIsVisible: Binding<Bool>?
    let onSelect: (EmbyLibraryItem) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                ForEach(viewModel.shelves) { shelf in
                    EmbyShelf(title: shelf.title) {
                        ForEach(shelf.items, id: \.metadata.id) { item in
                            // Continue Watching is about the frame you stopped on, so it uses the
                            // same landscape still card a season's episodes use.
                            if shelf.kind == .continueWatching {
                                stillCard(item, session: session, onSelect: onSelect)
                            } else {
                                posterCard(item, session: session, onSelect: onSelect)
                            }
                        }
                    }
                }

                if viewModel.shelves.isEmpty, viewModel.isLoading == false {
                    ContentUnavailableView("No Emby titles", systemImage: "film.stack")
                        .padding(.horizontal, DesignTokens.Spacing.xxl)
                }
            }
            .padding(.bottom, DesignTokens.Spacing.xxl)
        }
        .contentMargins(.top, embyHeaderHeight, for: .scrollContent)
        .embyPageBounds()
        .overlay(alignment: .top) {
            EmbyPageHeader(title: "Home", sidebarIsVisible: sidebarIsVisible) { EmptyView() }
        }
        .task { await viewModel.refresh() }
        .accessibilityIdentifier("Emby-Home")
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
        EmbyPosterGrid(items: viewModel.items, session: session, onSelect: onSelect)
            .contentMargins(.top, embyHeaderHeight, for: .scrollContent)
            .embyPageBounds()
            .overlay(alignment: .top) {
                EmbyPageHeader(title: viewModel.library.name, sidebarIsVisible: sidebarIsVisible) {
                    Picker("Sort", selection: Binding(
                        get: { viewModel.sort },
                        // The indicator moves with the tap. Only the reload waits on the server.
                        set: { value in
                            guard viewModel.sort != value else { return }
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
        .accessibilityIdentifier("Emby-Library-\(viewModel.library.id.rawValue)")
    }
}

private struct EmbySearchScreen: View {
    @Environment(EmbySearchViewModel.self) private var viewModel
    @Environment(EmbySessionViewModel.self) private var session
    let sidebarIsVisible: Binding<Bool>?
    let onSelect: (EmbyLibraryItem) -> Void

    var body: some View {
        @Bindable var viewModel = viewModel
        EmbyPosterGrid(items: viewModel.results, session: session, onSelect: onSelect)
            .contentMargins(.top, embyHeaderHeight, for: .scrollContent)
            .embyPageBounds()
            .overlay(alignment: .top) {
                EmbyPageHeader(title: "Search", sidebarIsVisible: sidebarIsVisible) {
                    GlassSearchField(
                        text: $viewModel.query,
                        placeholder: "Search Emby",
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
                columns: [GridItem(.adaptive(minimum: DesignTokens.Card.posterWidth), spacing: DesignTokens.Card.gridSpacing)],
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
    @State private var scrollOffset: CGFloat = 0
    /// Set once the wearer has taken hold of this page, which is what lets it start settling to one
    /// of its two positions. Each detail page carries its own, so arriving at one always starts over.
    @State private var hasBeenScrolled = false
    /// Configured to the top edge rather than left unset. A page arrives in pieces: the item, then
    /// its episodes, then its features, related titles and credits, and each arrival makes the
    /// content taller. SwiftUI only undertakes to hold a scroll position steady across a change of
    /// content size when the position says what it is, and an unset one says nothing, which lets the
    /// page drift down as it fills. Once the wearer scrolls, SwiftUI writes their position here and
    /// this no longer applies.
    @State private var scrollPosition = ScrollPosition(edge: .top)

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
            // The page runs to the window's own top edge, under the navigation bar, so the room it
            // holds open clears the back control. What the scroll view borrows from above it has to
            // be given back below, or the last of the page cannot be reached.
            let topMargin = DesignTokens.EmbyDetail.topContentInset
            let bottomMargin = proxy.safeAreaInsets.top + DesignTokens.Spacing.xxl
            // What the page travels before the sections reach the top: the hero's own height plus
            // the gap under it. Measured from the hero rather than from the window, so the picture
            // finishes leaving exactly as the sections arrive.
            let travel = heroHeight + DesignTokens.Spacing.xxl
            let progress = min(max(scrollOffset / travel, 0), 1)

            ZStack(alignment: .top) {
                if let item = viewModel.item {
                    backdrop(item)
                        .opacity(1 - min(progress / DesignTokens.EmbyDetail.backdropFadeFraction, 1))
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
        .task { await viewModel.refresh() }
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
                        // The header leaves with the picture it was written on, rather than
                        // riding up over the bare page.
                        .opacity(Double(1 - progress))
                    childrenContent
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
        // Room at the top for the settled art title and the back control, so the sections come
        // to rest under them instead of across them.
        .contentMargins(.top, topMargin, for: .scrollContent)
        .contentMargins(.bottom, bottomMargin, for: .scrollContent)
        // The page runs to the window's top edge the way the Apple TV app does: the back control and
        // the art title float on the page, and everything passes under them.
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
        // Drives the page from the same offset the product does, so what a screenshot shows is a
        // position the page can actually come to rest in.
        .task(id: viewModel.item) {
            guard let name = EmbyLaunchRoute.current?.sectionName else { return }
            try? await Task.sleep(for: .milliseconds(600))
            // A number is a distance from rest, which is how a page position between the two settled
            // ones is reached: the only way to photograph artwork passing under the blurred band.
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

    /// Scroll positions are given in the same units the page measures its own travel in: distance
    /// from rest. The scroll view counts from its content's top edge, which sits one top margin
    /// higher because of the room held open for the art title.
    private func scroll(to offset: CGFloat, topMargin: CGFloat) {
        scrollPosition.scrollTo(y: offset - topMargin)
    }

    /// The picture behind the whole page. It is not part of the scrolling content: it stands still
    /// and fades out, so the sections rise over it rather than dragging it up with them.
    ///
    /// It reaches every window edge at full strength. Fading its alpha at the edges does not soften
    /// anything: it lets the page's own light surface through, and the picture ends up ringed in
    /// white. The window's rounded corners are the only edge it needs.
    private func backdrop(_ item: EmbyLibraryItem) -> some View {
        AsyncArtworkImage(url: heroArtworkURL(for: item, session: session))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    enum Section: String, Hashable {
        case children
        case about
    }

    /// The header the page opens on. It carries no artwork of its own: the picture is the page's
    /// background, and this is what stands on it.
    private func hero(_ item: EmbyLibraryItem) -> some View {
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
        .background { titleWash }
    }

    /// A soft darkening of the picture under the header, multiplied into it rather than laid over it.
    /// Wide and weak on purpose: it has to lift white text off a bright still without ever reading as
    /// a panel, so it reaches well past the text and has no edge to find.
    private var titleWash: some View {
        GeometryReader { proxy in
            let spread = DesignTokens.EmbyDetail.titleWashSpread
            // Elliptical rather than radial: a radial gradient fades out at one radius in every
            // direction, and in a frame far wider than it is tall that leaves it still opaque where
            // the frame ends, which draws a straight line across the picture.
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

    /// What one version of a title is worth saying out loud: how big the picture is, how it is coded,
    /// and whether it carries wide colour. The server's own name for a source is the file's name on
    /// disk, which is a release group's release string and is both unreadable and far too long for a
    /// control standing next to Play.
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

    /// What the About block describes. A title that plays describes itself; a series or a season
    /// has no streams of its own, so it is described by the episodes that are loaded under it.
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
        .accessibilityIdentifier("Emby-Detail-\(action == .resume ? "Resume" : "PlayFromBeginning")")
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
                // The row cross-fades from one season to the next. Its identity follows the episodes
                // that are actually on screen rather than the season the menu has selected, so the
                // fade happens when the new episodes arrive and the old row stands until then.
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
            episodeShelf(episodes, title: "Episodes")
        case let .collection(members):
            posterShelf(title: "In This Collection", items: members)
        }
    }

    /// One capsule naming the current season, opening a menu of the rest. A row of season tabs
    /// would not survive a show with a dozen seasons inside one detail page.
    private func seasonPicker(_ seasons: [EmbySeason], selected: EmbyItemID?) -> some View {
        Menu {
            // A Picker marks the current row with the system checkmark on the trailing edge, which
            // is the native menu idiom. A hand-built `Label(systemImage: "checkmark")` puts the mark
            // in front of the title instead and pushes every title right.
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
    }

    private func seasonSelection(_ selected: EmbyItemID?) -> Binding<EmbyItemID?> {
        Binding(
            get: { selected },
            set: { value in
                guard let value, value != selected else { return }
                Task { await viewModel.selectSeason(value) }
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

            // A grid rather than a row: the columns differ in length, and a grid keeps every one of
            // them starting on the same left edge and the same baseline however many the page has
            // room for.
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
                // A column with more rows than its room becomes one surface that opens, rather than
                // running down the page and setting the height of every column beside it.
                CollapsibleBlock(title: title) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                        // Indexed, because a release can carry two tracks that describe themselves
                        // identically and the pair would otherwise share one identity.
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
        action: { onSelect(item) }
    )
}

/// The landscape still card, shared by Continue Watching and by a season's episodes.
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
        action: { onSelect(item) }
    )
}

@MainActor
private func posterURL(for item: EmbyLibraryItem, session: EmbySessionViewModel) -> URL? {
    imageURL(for: item, type: .primary, session: session, maxWidth: DesignTokens.Card.posterWidth)
}

@MainActor
/// `maxWidth` is the card's width in points; the server is asked for that many pixels at 2×, so the
/// decode and the bitmap it produces are sized for the card instead of for the original artwork.
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

/// Not every title carries a backdrop. A season usually has only its poster, so the hero falls back
/// through the wide images before it settles for one that will crop.
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

/// Fetches and decodes what a detail page opens on, before it is asked for. Called as the page is
/// pushed, so the picture and the art title travel with the navigation rather than landing after it.
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
