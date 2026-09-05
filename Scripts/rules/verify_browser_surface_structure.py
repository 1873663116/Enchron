#!/usr/bin/env python3

from pathlib import Path
import re
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VIOLATIONS: list[str] = []

LEVEL_TRANSITION_SITES = {
    "Modules/MediaLibrary/Views/FilesScreen.swift": ".id(folderIdentity)",
    "Apps/Enchron/Screens/SettingsScreen.swift": ".id(selectedCategoryID)",
    "Modules/Emby/EmbyScreens.swift": ".id(navigation.destination)",
}
LEVEL_TRANSITION_ANIMATIONS = {
    "Modules/MediaLibrary/Views/FilesScreen.swift":
        ".animation(DesignTokens.AnimationToken.levelTransition, value: folderIdentity)",
    "Apps/Enchron/Screens/SettingsScreen.swift":
        ".animation(DesignTokens.AnimationToken.levelTransition, value: selectedCategoryID)",
    "Modules/Emby/EmbyScreens.swift":
        "DesignTokens.AnimationToken.levelTransition,\n"
        "                                value: navigation.destination",
}


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
        "public static let levelTransition: Animation = .easeOut(duration: 0.3)" in tokens,
        "the level transition animation drifted from the calibrated 0.3 s ease-out",
    )
    require(
        order(
            tokens,
            "public enum TransitionToken {",
            "public static let levelReplaceTravel: CGFloat = 12",
            "@MainActor public static var levelReplace: AnyTransition {",
            ".opacity.combined(with: .offset(y: levelReplaceTravel))",
        ),
        "the level transition lost its vertical travel, so a folder that "
        "looks like its parent switches without any visible transition",
    )
    for path, identity in LEVEL_TRANSITION_SITES.items():
        source = read(path)
        site = f"{identity}\n"
        index = source.find(site)
        require(index >= 0, f"{path}: level content lost its identity modifier {identity}")
        if index < 0:
            continue
        following = source[index:index + 200]
        require(
            re.match(
                re.escape(identity)
                + r"\n\s+\.transition\(DesignTokens\.TransitionToken\.levelReplace\)",
                following,
            )
            is not None,
            f"{path}: level content after {identity} must use "
            "DesignTokens.TransitionToken.levelReplace",
        )
        require(
            LEVEL_TRANSITION_ANIMATIONS[path] in source,
            f"{path}: level content must animate with "
            "DesignTokens.AnimationToken.levelTransition keyed by its identity",
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
            "Text(fileSize)",
            "captionDuration(duration)",
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
            ".thumbnailTextScrim()",
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
            "GeometryReader { proxy in",
            "let textHeight = proxy.size.height",
            "let leadHeight = DesignTokens.Card.textScrimLeadHeight",
            "let scrimHeight = leadHeight + textHeight",
            "min(1, textHeight / DesignTokens.Card.textScrimRampHeight)",
            "let textOpacity = DesignTokens.Surface.textScrimOpacity",
            "(DesignTokens.Surface.textScrimDenseOpacity - textOpacity) * rampProgress",
            "LinearGradient(",
            ".black.opacity(textOpacity), location: leadHeight / scrimHeight)",
            ".black.opacity(bottomOpacity), location: 1)",
            ".frame(width: proxy.size.width, height: scrimHeight)",
            ".offset(y: textHeight - scrimHeight)",
        ),
        "the text scrim no longer scales with the caption height",
    )
    tokens = read("Modules/DesignSystem/DesignTokens.swift")
    require(
        "public static let textScrimOpacity: Double = 0.55" in tokens
        and "public static let textScrimDenseOpacity: Double = 0.9" in tokens
        and "public static let textScrimLeadHeight: CGFloat = 52" in tokens
        and "public static let textScrimRampHeight: CGFloat = 104" in tokens,
        "the text scrim drifted from the Emby-calibrated ramp: clear to 0.55 "
        "over 52 pt above the caption, 0.55 to 0.9 over 104 pt of caption",
    )
    require(
        card.count("LinearGradient(") == 1,
        "GridCard paints a gradient outside the shared text scrim",
    )


def main() -> int:
    VIOLATIONS.clear()
    check_level_transitions()
    check_grid_card_hover()
    if VIOLATIONS:
        for violation in VIOLATIONS:
            print(f"browser-surface-structure: {violation}", file=sys.stderr)
        return 1
    print("browser-surface-structure: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
