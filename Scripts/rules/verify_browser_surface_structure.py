#!/usr/bin/env python3

from pathlib import Path
import re
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VIOLATIONS: list[str] = []

LEVEL_CONTENT_SITES = {
    "Modules/MediaLibrary/Views/FilesScreen.swift": ".levelContent(id: folderIdentity)",
    "Apps/Enchron/Screens/SettingsScreen.swift": ".levelContent(id: selectedCategoryID)",
    "Modules/Emby/EmbyScreens.swift": ".levelContent(id: navigation.destination)",
}
DESIGN_SYSTEM_ONLY = (
    "DesignTokens.TransitionToken.levelReplace",
    "DesignTokens.AnimationToken.levelTransition",
    "FlowGridLayout(",
    "artworkLoadsWhenVisible, true",
)
PRODUCT_SOURCES = (
    "Modules/MediaLibrary/Views/FilesScreen.swift",
    "Apps/Enchron/Screens/SettingsScreen.swift",
    "Modules/Emby/EmbyScreens.swift",
)


def read(path: str) -> str:
    return (REPOSITORY_ROOT / path).read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        VIOLATIONS.append(message)


def region(source: str, start_marker: str, end_marker: str) -> str:
    start = source.find(start_marker)
    if start < 0:
        raise AssertionError(f"missing source region: {start_marker}")
    end = source.find(end_marker, start + len(start_marker))
    if end < 0:
        raise AssertionError(f"missing source region terminator: {end_marker}")
    return source[start:end]


def order(source: str, *markers: str) -> bool:
    position = -1
    for marker in markers:
        found = source.find(marker, position + 1)
        if found < 0:
            return False
        position = found
    return True


def check_level_transitions() -> None:
    tokens = read("Modules/DesignSystem/DesignTokens.swift")
    require(
        "public static let levelExitDuration: Double = 0.12" in tokens
        and "public static let levelEnterDuration: Double = 0.25" in tokens
        and "public static let levelPlaceholderThreshold: Double = 0.4" in tokens,
        "the level transition drifted from the calibrated 0.12 s exit, 0.25 s "
        "entrance and 0.4 s blank window",
    )
    require(
        order(
            tokens,
            "public enum TransitionToken {",
            "@MainActor public static var levelReplace: AnyTransition {",
            ".asymmetric(",
            "insertion: .identity,",
            "removal: .opacity.animation(AnimationToken.levelExit)",
        ),
        "the level being entered fades in on the transition's own schedule "
        "again: the old level must fade out at once and the new one must be "
        "inserted transparent, so levelContent can hold it until it settles",
    )
    for path, marker in LEVEL_CONTENT_SITES.items():
        source = read(path)
        require(
            marker in source,
            f"{path}: level content must switch through .levelContent(id:), the "
            "one place that owns the level transition",
        )
    for path in PRODUCT_SOURCES:
        source = read(path)
        for marker in DESIGN_SYSTEM_ONLY:
            require(
                marker not in source,
                f"{path}: {marker} belongs to DesignSystem components; screens "
                "compose CardGrid and .levelContent(id:) instead",
            )
    level = read("Modules/DesignSystem/Components/LevelContent.swift")
    require(
        order(
            level,
            "ZStack {",
            ".id(id)",
            ".transition(DesignTokens.TransitionToken.levelReplace)",
            ".opacity(revealedID == id ? 1 : 0)",
            ".animation(DesignTokens.AnimationToken.levelTransition, value: id)",
        ),
        "LevelContent lost the ZStack that keeps the old level alive through its exit",
    )
    require(
        order(
            level,
            "static func delay(contentIsReady: Bool) -> Duration {",
            "? DesignTokens.AnimationToken.levelExitDuration",
            ": DesignTokens.AnimationToken.levelPlaceholderThreshold",
            "static func remaining(pendingFor elapsed: Duration, contentIsReady: Bool) -> Duration {",
            "max(.zero, delay(contentIsReady: contentIsReady) - elapsed)",
        )
        and order(
            level,
            "private func reveal() async {",
            "guard revealedID != id else { return }",
            "guard hasRevealedALevel else {",
            "let wait = LevelReveal.remaining(pendingFor: now - since, contentIsReady: contentIsReady)",
            "try? await Task.sleep(for: wait)",
            "withAnimation(DesignTokens.AnimationToken.levelEnter) {",
            "revealedID = id",
        ),
        "a level must stay blank until its content settles or the placeholder "
        "threshold elapses, and a listing that lands mid-wait must shorten that "
        "wait instead of restarting it",
    )
    require(
        order(
            level,
            "static func reduce(value: inout Bool, nextValue: () -> Bool) {",
            "value = value && nextValue()",
        )
        and order(
            level,
            ".onPreferenceChange(LevelReadinessKey.self) { isReady in",
            ".task(id: RevealRequest(id: id, contentIsReady: contentIsReady)) {",
        ),
        "levelContent no longer reads the readiness its level reports, so a "
        "level that is still loading counts as settled",
    )
    files = read("Modules/MediaLibrary/Views/FilesScreen.swift")
    require(
        order(
            files,
            "private var levelIsReady: Bool {",
            "isBrowsingSource ? viewModel.currentLevelHasSettled : true",
        )
        and order(
            files,
            "currentFolderContent",
            ".levelReadiness(levelIsReady)",
            ".levelContent(id: folderIdentity)",
        )
        and order(
            files,
            "private var currentFolderContent: some View {",
            "if !levelIsReady {",
            "loadingState",
        ),
        "the Files level must report whether its listing has settled and hold "
        "its own placeholder until then",
    )
    browsing = read("Modules/MediaLibrary/FileBrowsingViewModel.swift")
    require(
        order(
            browsing,
            "private func enterLevel() {",
            "settledLevel = nil",
            "files = []",
            "folders = []",
        ),
        "entering a level must drop the level being left: the listing merge "
        "keeps rows until a replacement arrives, so the level being entered "
        "would otherwise fade in over the previous level's rows",
    )
    for opening, closing in (
        ("public func navigateToFolder(", "public func navigateUp("),
        ("public func navigateUp(", "public func navigateForward("),
        ("public func navigateForward(", "public var breadcrumbSegments:"),
        ("public func navigateToBreadcrumb(", "public func selectLocalFolder("),
    ):
        require(
            order(region(browsing, opening, closing), "enterLevel()", "await loadFiles()"),
            f"{opening}) must enter the level before requesting its listing",
        )
    listing = region(
        browsing,
        "public func loadFiles() async {",
        "private func reconnectAndSurfaceFailure(",
    )
    require(
        listing.count("settleCurrentLevel()") == 2,
        "a listing must settle its level on both the remote and the local "
        "terminal, or a level whose listing failed never fades in",
    )
    grid = read("Modules/DesignSystem/Components/CardGrid.swift")
    require(
        order(
            grid,
            "FlowGridLayout(spacing: DesignTokens.Card.gridSpacing) {",
            ".frame(maxWidth: .infinity, alignment: .leading)",
            ".environment(\\.artworkLoadsWhenVisible, true)",
        ),
        "CardGrid must lay cards out with FlowGridLayout and gate their artwork on scroll visibility",
    )


def check_sidebar_layout() -> None:
    for path in (
        "Modules/MediaLibrary/Views/FilesScreen.swift",
        "Modules/Emby/EmbyScreens.swift",
    ):
        source = read(path)
        require(
            "SidebarSplitLayout(sidebarIsVisible:" in source
            and ".transition(.move(edge: .leading)" not in source,
            f"{path}: the sidebar must slide through SidebarSplitLayout so both "
            "screens share one push animation",
        )
    layout = read("Modules/DesignSystem/Components/SidebarSplitLayout.swift")
    require(
        order(
            layout,
            "let contentWidth = max(0, proxy.size.width - (sidebarIsVisible ? sidebarWidth : 0))",
            ".frame(width: contentWidth, height: proxy.size.height)",
            ".offset(x: sidebarIsVisible ? sidebarWidth : 0)",
        )
        and ".animation(nil" not in layout,
        "SidebarSplitLayout must animate the content width continuously; the "
        "grids underneath keep card identity, so a snapped width only adds a jump",
    )
    for path in (
        "Modules/MediaLibrary/Views/FilesScreen.swift",
        "Modules/Emby/EmbyScreens.swift",
    ):
        source = read(path)
        require(
            "CardGrid {" in source
            and "GridItem(.adaptive(minimum: DesignTokens.Card." not in source,
            f"{path}: card grids must be CardGrid; LazyVGrid rebuilds whole rows "
            "whenever the column count changes",
        )
    emby = read("Modules/Emby/EmbyScreens.swift")
    detail = region(
        emby,
        "private struct EmbyDetailScreen: View {",
        "    private func entrancePrefetchURLs() -> [URL] {",
    )
    require(
        "Task { await runEntrance() }" not in detail
        and order(
            detail,
            ".task {",
            "await viewModel.refresh()",
            "await runEntrance()",
            "await ArtworkPrefetch.warm(entrancePrefetchURLs())",
            "while backdropLoaded == false, ContinuousClock.now < deadline {",
            "withAnimation { revealed = true }",
        )
        and order(
            emby,
            "if revealed {",
            "childrenContent",
            ".transition(entrance(5))",
            ".transition(entrance(9))",
        )
        and order(
            emby,
            "if revealed {",
            "titleArtwork(item)",
            ".transition(entrance(0))",
            "overview(item.metadata)",
            ".transition(entrance(2))",
            ".transition(entrance(4))",
        )
        and order(emby, ".background {", "if revealed {", "titleWash", ".delay(entranceDelay(0))")
        and order(emby, "maxPixelSize: nil,", "onLoad: { backdropLoaded = true }"),
        "the Emby detail page must show nothing until its data, backdrop and "
        "first card images are in, then reveal backdrop by fade and every other "
        "block with one slide-up at equal intervals, title first",
    )
    require(
        order(
            emby,
            "SidebarSplitLayout(sidebarIsVisible: sidebarIsVisible && sidebarSuspended == false)",
            "sidebarSuspended = true",
            "try? await Task.sleep(for: .seconds(DesignTokens.EmbyDetail.sidebarHandoffDelay))",
            "navigation.open(item)",
        ),
        "opening an Emby item must slide the sidebar away before the push; "
        "pushing while the width animates competes for the same frames",
    )
    require(
        order(
            emby,
            "if isLoading == false {",
            "CardGrid {",
            ".opacity(revealed ? 1 : 0)",
            ".task(id: revealKey) {",
            "revealed = false",
            "async let warmed: Void = ArtworkPrefetch.warm(posters)",
            "try? await Task.sleep(for: .seconds(DesignTokens.Card.gridRevealLayoutDelay))",
            "withAnimation(.easeOut(duration: DesignTokens.Card.gridRevealDuration)) {",
            "revealed = true",
            ".levelReadiness(isLoading == false)",
        ),
        "the Emby poster grid must stay empty until its items are in, lay out "
        "before it fades in, and report that readiness upward; awaiting the "
        "poster images here holds the page blank for as long as the slowest "
        "download takes",
    )
    require(
        order(
            emby,
            "initialRefreshCompleted = true",
            ".levelReadiness(initialRefreshCompleted)",
        ),
        "the Emby home level must report when its shelves are in, or it fades "
        "in empty and fills afterwards",
    )
    artwork = read("Modules/DesignSystem/Components/AsyncArtworkImage.swift")
    require(
        order(
            artwork,
            ".onScrollVisibilityChange(threshold: 0.01) { visible in",
            ".task(id: activeURL) {",
            "loadsWhenVisible && isVisible == false ? nil : url",
        ),
        "AsyncArtworkImage no longer gates loading on scroll visibility",
    )


def check_grid_card_hover() -> None:
    card = read("Modules/DesignSystem/Components/GridCard.swift")
    thumbnails = region(
        card,
        "private func thumbnailContent(_ shape: RoundedRectangle) -> some View {",
        "private func episodeCaption(_ episode: EpisodeState) -> some View {",
    )
    require(
        "watchedEdgeProgressVisual(" not in thumbnails
        and thumbnails.count("watchedProgressBar(watchedProgress)") == 3,
        "a grid card draws its watched progress outside the hover-revealed bar, "
        "so Files and Emby cards disagree on when progress is visible",
    )
    progress_bar = region(
        card,
        "private func watchedProgressBar(_ progress: Double) -> some View {",
        "private func thumbnailPlaceholderIcon(",
    )
    require(
        order(
            progress_bar,
            "watchedEdgeProgressVisual(progress)",
            ".enchronHoverOpacity(",
            "active: 1,",
            "inactive: 0,",
            "in: hoverRevealGroup,",
        ),
        "the watched progress bar is no longer revealed only by the card's hover group",
    )
    require(
        "videoCaption(fileSize: fileSize, duration: duration)" in thumbnails
        and "episodeCaption(episode)" in thumbnails,
        "a video or episode card no longer draws its hover caption",
    )
    episode_caption = region(
        card,
        "private func episodeCaption(_ episode: EpisodeState) -> some View {",
        "private func videoCaption(fileSize: String, duration: String) -> some View {",
    )
    require(
        order(episode_caption, "thumbnailCaption {", "ViewThatFits(in: .vertical) {")
        and "LinearGradient(" not in episode_caption,
        "the episode caption left the shared hover caption, so Emby cards "
        "and Files cards reveal different things under the gaze",
    )
    video_caption = region(
        card,
        "private func videoCaption(fileSize: String, duration: String) -> some View {",
        "private func thumbnailCaption<Content: View>(",
    )
    require(
        order(
            video_caption,
            "thumbnailCaption {",
            "captionBlock {",
            "HStack(alignment: .firstTextBaseline) {",
            "captionDuration(duration)",
            "Spacer(minLength: DesignTokens.Spacing.xs)",
            "Text(fileSize)",
        ),
        "the video card's caption left the shared hover caption, so Files cards "
        "and Emby cards reveal different things under the gaze",
    )
    require(
        "captionTitle" not in video_caption,
        "the video card's caption repeats the title that already sits below "
        "the thumbnail",
    )
    caption = region(
        card,
        "private func thumbnailCaption<Content: View>(",
        "private func episodeCaptionText(",
    )
    require(
        order(
            caption,
            ".thumbnailTextScrim(maximumHeight: thumbnailHeight)",
            ".frame(width: cardWidth, height: thumbnailHeight, alignment: .bottomLeading)",
            ".enchronHoverOpacity(",
            "active: 1,",
            "inactive: 0,",
            "in: hoverRevealGroup,",
        ),
        "the shared hover caption lost its text scrim or its hover reveal",
    )
    episode_text = region(
        card,
        "private func episodeCaptionText(",
        "private func captionBlock<Rows: View>(",
    )
    require(
        order(episode_text, "captionBlock {", "captionTitle", "captionDuration(duration)"),
        "the episode caption text left the shared caption block",
    )
    scrim = region(
        card,
        "private struct ThumbnailTextScrim: ViewModifier {",
        "extension View {",
    )
    require(
        order(
            scrim,
            "content.background {",
            "GeometryReader { proxy in",
            "let scrimHeight = maximumHeight * DesignTokens.Surface.textScrimCoverageFraction",
            "let plateauHeight = proxy.size.height * DesignTokens.Surface.textScrimPlateauFraction",
            "let leadFraction = 1 - plateauHeight / max(scrimHeight, 1)",
            "Rectangle()",
            ".fill(DesignTokens.Surface.textScrimMaterial)",
            ".mask {",
            "LinearGradient(",
            "stops: DesignTokens.Surface.textScrimStops(leadFraction: leadFraction),",
            ".frame(width: proxy.size.width, height: scrimHeight)",
            ".offset(y: proxy.size.height - scrimHeight)",
        )
        and "location:" not in scrim,
        "the text scrim no longer spans the thumbnail with a plateau sized by "
        "the caption: the fade must fill everything above half the caption",
    )
    tokens = read("Modules/DesignSystem/DesignTokens.swift")
    require(
        "public static let textScrimCoverageFraction: CGFloat = 0.8" in tokens
        and "public static let textScrimPlateauFraction: CGFloat = 0.4" in tokens
        and "public static let textScrimOpacity: Double = 1" in tokens,
        "the text scrim plateau drifted from two fifths of the caption at full material",
    )
    require(
        "public static var textScrimMaterial: Material { .ultraThickMaterial }" in tokens,
        "the text scrim is no longer the ultra-thick material that keeps captions legible without darkening",
    )
    require(
        order(
            tokens,
            "public static func textScrimKeyframes(leadFraction: Double) -> [ScrimKeyframe] {",
            "ScrimKeyframe(location: 0, opacity: 0, curve: .linear),",
            "ScrimKeyframe(location: leadFraction, opacity: textScrimOpacity, curve: .easeInOut),",
            "ScrimKeyframe(location: 1, opacity: textScrimOpacity, curve: .linear)",
            "public static func textScrimStops(leadFraction: Double) -> [Gradient.Stop] {",
            "textScrimKeyframes(leadFraction: leadFraction),",
        )
        and order(
            tokens,
            "public struct ScrimKeyframe: Sendable {",
            "public let curve: UnitCurve",
            "static func opacity(at location: Double, in keyframes: [ScrimKeyframe]) -> Double {",
            "end.curve.value(at: progress)",
        ),
        "the text scrim profile drifted from its keyframes: clear at the scrim "
        "top easing in and out to the plateau, then flat through the lower half of the caption; a curve that starts steep "
        "draws a visible line at the scrim top",
    )
    require(
        card.count("LinearGradient(") == 1,
        "GridCard paints a gradient outside the shared text scrim",
    )


def check_level_ordering() -> None:
    browsing = read("Modules/MediaLibrary/FileBrowsingViewModel.swift")
    require(
        order(
            browsing,
            "private func applySortToLevel() {",
            "files = criteria.sorted(files)",
            "folders = criteria.sorted(folders)",
        )
        and "applySortToFiles" not in browsing,
        "the sort control must order the whole level: a level whose folders "
        "keep the order the source listed them in does not visibly react to "
        "the control at all while its folders fill the page",
    )
    require(
        browsing.count("applySortToLevel()") == 4,
        "every listing terminal and the sort observer must re-order the level, "
        "or a listing that lands after the sort keeps the source's order",
    )
    domain = read("Modules/MediaLibrary/Model/MediaBrowsing.swift")
    require(
        order(
            domain,
            "public func sorted(_ folders: [FileBrowsingDomain.MediaFolder]) -> [FileBrowsingDomain.MediaFolder] {",
            "$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending",
            "case .descending:",
            "return Array(byName.reversed())",
        ),
        "a folder has no size of its own and reading one would mean crawling "
        "its subtree, so under the size key folders order by name and only "
        "follow the ascending or descending choice",
    )
    require(
        order(
            domain,
            "public func sorted(_ folders: [FileBrowsingDomain.MediaFolder]) -> [FileBrowsingDomain.MediaFolder] {",
            "if key == .modifiedDate {",
            "return SortCriteria.dated(byName, order: order) { $0.modifiedAt }",
        )
        and order(
            domain,
            "public static func dated<Element>(",
            "let undated = indexed.filter { date($0.element) == nil }.map(\\.element)",
            "guard leading != trailing else { return left.offset < right.offset }",
            "return dated + undated",
        ),
        "a folder whose source reported a modification time must order by it, "
        "with undated folders at the end and ties left in name order in both "
        "directions",
    )
    for path, opening, closing, expression in (
        (
            "Modules/MediaLibrary/Sources/WebDAV/WebDAVDataSourceAdapter.swift",
            "public func listFolders(at path: String)",
            "public func listFiles(",
            "modifiedAt: parseHTTPDate(responseItem.lastModified)",
        ),
        (
            "Modules/MediaLibrary/Sources/SMB/SMBDataSourceAdapter.swift",
            "public func listFolders(at path: String)",
            "public func listFiles(",
            "modifiedAt: item.modifiedAt",
        ),
        (
            "Modules/MediaLibrary/Sources/Local/LocalDataSourceAdapter.swift",
            "public func listFolders(at path: String)",
            "public func resolveURL(",
            "modifiedAt: values?.contentModificationDate\n",
        ),
    ):
        require(
            expression in region(read(path), opening, closing),
            f"{path}: this source stopped reporting the modification time of "
            "the folders it lists, which silently removes the date key from "
            "every folder-only level it serves",
        )
    require(
        order(
            domain,
            "public struct SortKeyAvailability: Sendable, Equatable {",
            "orderableByDate = datedItemCount > 0",
            "orderableBySize = sizedItemCount > 0",
            "public func canOrder(by key: SortCriteria.Key) -> Bool {",
            "case .name:",
            "return true",
        ),
        "the rule that a key nothing in the level can answer is offered as "
        "disabled must live in one place; name is always answerable",
    )
    files = read("Modules/MediaLibrary/Views/FilesScreen.swift")
    require(
        order(
            files,
            "private var displayedLibraryFolders: [FileBrowsingDomain.LibraryFolder] {",
            "if criteria.key == .modifiedDate {",
            "return FileBrowsingDomain.SortCriteria.dated(byName, order: criteria.order) { $0.createdAt }",
            "return criteria.order == .ascending ? byName : Array(byName.reversed())",
        ),
        "the library level's folders ignore the sort control that its files "
        "obey, so one screen answers the same control two ways",
    )
    require(
        order(
            files,
            "private var sortKeyAvailability: FileBrowsingDomain.SortKeyAvailability {",
            "sizedItemCount: viewModel.displayedFiles.count",
            "sizedItemCount: displayedLibraryReferences.count",
        )
        and order(
            files,
            "private var unavailableSortKeys: Set<SortMenuKey> {",
            "keys.insert(.modifiedDate)",
            "keys.insert(.size)",
        )
        and order(
            files,
            "SortMenuButton(",
            "unavailableKeys: unavailableSortKeys,",
        ),
        "a sort key the level cannot answer must reach the menu as disabled; "
        "a control that visibly changes nothing when pressed reads as broken",
    )
    toolbar = read("Modules/MediaLibrary/Views/LibraryToolbarComponents.swift")
    require(
        ".disabled(unavailableKeys.contains(key))" in toolbar
        and ".filter { unavailableKeys.contains($0.0) == false }" in toolbar,
        "the sort menu and the debug selection channel disagree on which keys "
        "are offered, so automation can pick a row the screen forbids",
    )
    require(
        order(
            files,
            ".disabled(isBrowsingSource)",
            '.accessibilityIdentifier("FileBrowsing-Manage-button")',
        )
        and order(
            files,
            "case (.files, .manage):",
            "guard isBrowsingSource == false else {",
            "request.handle(host: .files, family: .manage, items: [])",
            "$0 != .selectMultiple || displayedLibraryReferences.isEmpty == false",
        ),
        "every entry in the manage menu acts on the media library, so while a "
        "source is being browsed the button must be disabled and the debug "
        "channel must offer nothing; leaving it live builds folders and "
        "imports files into a place the screen is not showing",
    )
    webdav = read("Modules/MediaLibrary/Sources/WebDAV/WebDAVDataSourceAdapter.swift")
    require(
        order(
            webdav,
            "if isSelfOnlyResponse(primaryResult.responses, requestURL: url) {",
            "let retryURL = directoryURL(for: url)",
            "if isSelfOnlyResponse(retryResult.responses, requestURL: retryURL) == false {",
            "return retryResult.responses",
            "return []",
        )
        and "emptyDirectoryListing" not in webdav,
        "a collection that answers with nothing but itself is an empty "
        "directory once the trailing-slash retry has also come back empty; "
        "raising it as a failure puts an error on every empty leaf folder",
    )
    progress = region(
        read("Modules/MediaLibrary/FileBrowsingViewModel.swift"),
        "private func loadProgressForFiles() {",
        "private func probeDuration(",
    )
    require(
        progress.count("Set(self.files.map(\\.id)) == Set(currentFiles.map(\\.id))") == 2,
        "viewing states and probed durations are matched to the level by "
        "identity, not by position; re-sorting a level while they are in "
        "flight must not discard them",
    )


def main() -> int:
    VIOLATIONS.clear()
    check_level_transitions()
    check_level_ordering()
    check_sidebar_layout()
    check_grid_card_hover()
    if VIOLATIONS:
        for violation in VIOLATIONS:
            print(f"browser-surface-structure: {violation}", file=sys.stderr)
        return 1
    print("browser-surface-structure: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
