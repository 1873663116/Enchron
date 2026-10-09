#!/usr/bin/env python3

from pathlib import Path
import re
import sys

from check_hover_region_clipping import mask_comments_and_strings


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VISIBILITY_SOURCE = "Apps/Enchron/BrowserWindowVisibility.swift"
POLICY = "SpatialPlatformBrowserWindowVisibilityPolicy.hidesBrowser"
CONTENT_MODIFIERS = (
    ".opacity(visibility.hidesBrowser ? 0 : 1)",
    ".allowsHitTesting(visibility.hidesBrowser == false)",
    ".accessibilityHidden(visibility.hidesBrowser)",
)
WINDOW_CHROME_OWNERS = {
    "Apps/Enchron/EnchronApp.swift": "the browser scene",
    "Apps/Enchron/PlayerView.swift": "the player window's own chrome policy",
}
PRODUCT_ROOTS = ("Apps", "Modules")
VIOLATIONS: list[str] = []


def read(path: str) -> str:
    return (REPOSITORY_ROOT / path).read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        VIOLATIONS.append(message)


def product_sources() -> list[Path]:
    sources: list[Path] = []
    for root in PRODUCT_ROOTS:
        sources.extend(sorted((REPOSITORY_ROOT / root).rglob("*.swift")))
    return sources


def relative(path: Path) -> str:
    return str(path.relative_to(REPOSITORY_ROOT))


def region(source: str, start_marker: str, end_marker: str) -> str:
    start = source.find(start_marker)
    if start < 0:
        raise AssertionError(f"missing source region: {start_marker}")
    end = source.find(end_marker, start + len(start_marker))
    if end < 0:
        raise AssertionError(f"missing source region terminator: {end_marker}")
    return source[start:end]


def check_the_modifier_names_the_whole_set() -> None:
    source = read(VISIBILITY_SOURCE)
    content = region(
        source,
        "func browserWindowContentVisibility(",
        "func browserTabBarVisibility(",
    )
    for modifier in CONTENT_MODIFIERS:
        require(
            modifier.lstrip(".") in content,
            "the browser content modifier stopped applying "
            + modifier
            + ", so a hidden browser keeps a surface the wearer can still reach",
        )
    require(
        "toolbarVisibility(visibility.systemOverlays, for: .tabBar)" in source,
        "the browser tab-bar modifier no longer hides the tab bar",
    )


def check_window_chrome_is_asked_for_once_per_window() -> None:
    """persistentSystemOverlays is what visionOS reads for a WindowGroup's
    window bar and resize bar, and an outer one replaces what a child asked for.
    The browser asks at its scene, the player asks inside PlayerView from its own
    chrome policy, and nothing may ask on their shared content -- a gate that
    asks there pins whichever window it does not hide to .automatic and the
    player's own request never lands."""
    for path in product_sources():
        relative_path = relative(path)
        if relative_path in WINDOW_CHROME_OWNERS:
            continue
        require(
            ".persistentSystemOverlays(" not in path.read_text(encoding="utf-8"),
            relative_path
            + " asks for window chrome; only "
            + " and ".join(sorted(WINDOW_CHROME_OWNERS.values()))
            + " may, because an outer request replaces an inner one",
        )
    scene = read("Apps/Enchron/EnchronApp.swift")
    require(
        "        .persistentSystemOverlays(\n"
        "            BrowserWindowVisibility(\n"
        "                window: .main," in scene,
        "the browser scene no longer hides its window bar while playback owns "
        "the space",
    )


def check_the_policy_is_read_in_one_place() -> None:
    for path in product_sources():
        if relative(path) == VISIBILITY_SOURCE:
            continue
        require(
            POLICY not in path.read_text(encoding="utf-8"),
            relative(path)
            + " reads the browser visibility policy directly; every surface has "
            + "to go through BrowserWindowVisibility so none of them can answer "
            + "the question differently",
        )


def check_the_tab_bar_modifier_has_no_second_spelling() -> None:
    for path in product_sources():
        if relative(path) == VISIBILITY_SOURCE:
            continue
        require(
            "for: .tabBar" not in path.read_text(encoding="utf-8"),
            relative(path)
            + " sets tab-bar visibility by hand; browserTabBarVisibility is the "
            + "one spelling, so the set of Tabs that carry it can be checked",
        )


def closing_delimiter(source: str, opening: int) -> int:
    left = source[opening]
    right = {"(": ")", "{": "}"}[left]
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == left:
            depth += 1
        elif source[index] == right:
            depth -= 1
            if depth == 0:
                return index
    raise AssertionError("unclosed Swift delimiter")


def content_bounds(source: str, opening: int) -> tuple[int, int]:
    if source[opening] == "(":
        opening = source.find("{", closing_delimiter(source, opening) + 1)
    if opening < 0:
        raise AssertionError("missing Swift content closure")
    return opening, closing_delimiter(source, opening)


def owns_tab_bar_modifier(source: str, cursor: int) -> bool:
    while match := re.match(r"\s*\.(\w+)\s*([({])", source[cursor:]):
        opening = cursor + match.end() - 1
        closing = closing_delimiter(source, opening)
        if match.group(1) == "browserTabBarVisibility" and source[opening + 1:closing].strip() == "browserVisibility":
            return True
        cursor = closing + 1
        trailing = re.match(r"\s*\{", source[cursor:])
        if trailing:
            cursor = closing_delimiter(source, cursor + trailing.end() - 1) + 1
    return False


def check_every_tab_carries_the_tab_bar_modifier() -> None:
    source = mask_comments_and_strings(read("Apps/Enchron/MainView.swift"))
    marker = re.search(r"\bvar\s+browser\s*:\s*some\s+View\s*\{", source)
    require(marker is not None, "the browser content declaration is missing")
    if marker is None:
        return
    opening = marker.end() - 1
    browser = source[opening + 1:closing_delimiter(source, opening)]
    tabs = list(re.finditer(r"\bTab\s*\(", browser))
    require(bool(tabs), "the browser no longer declares any Tabs")
    for index, tab in enumerate(tabs, start=1):
        opening, closing = content_bounds(browser, tab.end() - 1)
        content = browser[opening + 1:closing]
        visible = ".browserTabBarVisibility(browserVisibility)" in content
        if not visible:
            call = re.match(r"\s*(?:self\.)?(\w+)\s*\(", content)
            helper = re.search(r"\bfunc\s+" + re.escape(call.group(1)) + r"\s*\(", source) if call else None
            if helper:
                start, end = content_bounds(source, helper.end() - 1)
                visible = ".browserTabBarVisibility(browserVisibility)" in source[start + 1:end]
        require(
            visible,
            f"Tab {index} does not hide the tab bar while playback owns the space, "
            "so the browser disappears with its tab bar left behind",
        )
    tabview = re.search(r"\bTabView\s*([({])", browser)
    visible = False
    if tabview:
        _, closing = content_bounds(browser, tabview.end() - 1)
        visible = owns_tab_bar_modifier(browser, closing + 1)
    require(
        visible,
        "the TabView itself no longer hides the tab bar alongside its Tabs",
    )


def main() -> int:
    check_the_modifier_names_the_whole_set()
    check_window_chrome_is_asked_for_once_per_window()
    check_the_policy_is_read_in_one_place()
    check_the_tab_bar_modifier_has_no_second_spelling()
    check_every_tab_carries_the_tab_bar_modifier()
    for violation in VIOLATIONS:
        print(violation)
    return 1 if VIOLATIONS else 0


if __name__ == "__main__":
    sys.exit(main())
