#!/usr/bin/env python3

"""One intent -- the browser disappears while playback owns the space -- reaches
the screen through ten application points that the platform refuses to let the
app collapse into one. `toolbarVisibility(_:for:.tabBar)` binds to each Tab's
own content, `persistentSystemOverlays` binds to the scene, and the rest bind to
the gate's content. A browser that hides its screens and keeps its tab bar is
what a partial implementation looks like, and it shipped once. This guard makes
the partial version unexpressible: the modifiers name the whole set, and every
Tab has to carry the tab-bar one."""

from pathlib import Path
import re
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VISIBILITY_SOURCE = "Apps/Enchron/BrowserWindowVisibility.swift"
POLICY = "SpatialPlatformBrowserWindowVisibilityPolicy.hidesBrowser"
CONTENT_MODIFIERS = (
    ".opacity(visibility.hidesBrowser ? 0 : 1)",
    ".allowsHitTesting(visibility.hidesBrowser == false)",
    ".accessibilityHidden(visibility.hidesBrowser)",
    ".persistentSystemOverlays(visibility.systemOverlays)",
)
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


def check_every_tab_carries_the_tab_bar_modifier() -> None:
    browser = region(read("Apps/Enchron/MainView.swift"), "private var browser: some View {", "\n    private var browserVisibility")
    tabs = re.split(r"\n            Tab\(", browser)
    require(
        len(tabs) - 1 == 4,
        "the browser no longer declares four Tabs; the tab-bar coverage check "
        "reads their count from the source and has to be re-derived",
    )
    for index, tab in enumerate(tabs[1:], start=1):
        name = tab.split(",", 1)[0].strip()
        require(
            ".browserTabBarVisibility(browserVisibility)" in tab,
            "Tab " + name + " does not hide the tab bar while playback owns the "
            "space, so the browser disappears with its tab bar left behind",
        )
    require(
        browser.rstrip().count(".browserTabBarVisibility(browserVisibility)") == 5,
        "the TabView itself no longer hides the tab bar alongside its Tabs",
    )


def main() -> int:
    check_the_modifier_names_the_whole_set()
    check_the_policy_is_read_in_one_place()
    check_the_tab_bar_modifier_has_no_second_spelling()
    check_every_tab_carries_the_tab_bar_modifier()
    for violation in VIOLATIONS:
        print(violation)
    return 1 if VIOLATIONS else 0


if __name__ == "__main__":
    sys.exit(main())
