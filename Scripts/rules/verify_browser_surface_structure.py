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
        and "public static let levelEnterDuration: Double = 0.25" in tokens,
        "the level transition animation drifted from the calibrated 0.12 s exit and 0.25 s entrance",
    )
    require(
        order(
            tokens,
            "public enum TransitionToken {",
            "@MainActor public static var levelReplace: AnyTransition {",
            ".asymmetric(",
            "insertion: .opacity.animation(",
            ".easeOut(duration: AnimationToken.levelEnterDuration)",
            ".delay(AnimationToken.levelExitDuration)",
            "removal: .opacity.animation(",
            ".easeIn(duration: AnimationToken.levelExitDuration)",
        ),
        "the level transition overlaps the old and new levels again: the old "
        "level must fade out fully before the new one fades in, or similar "
        "levels crossfade into a ghost",
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
            ".animation(DesignTokens.AnimationToken.levelTransition, value: id)",
        ),
        "LevelContent lost the ZStack that keeps the old level alive through its exit",
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
            "await ArtworkPrefetch.warm(",
            "withAnimation(.easeOut(duration: DesignTokens.Card.gridRevealDuration)) {",
        ),
        "the Emby poster grid must stay empty until its items are in and lay out "
        "before it fades in; fading while the grid is built stutters",
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


def main() -> int:
    VIOLATIONS.clear()
    check_level_transitions()
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
