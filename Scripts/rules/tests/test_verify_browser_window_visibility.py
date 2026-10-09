from __future__ import annotations

from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import verify_browser_window_visibility as guard


def browser_source(count=4, *, conditional=False, missing=None, outer=True, helper=False):
    lines = ["private var browser: some View {", "    TabView(selection: selection) {"]
    for index in range(count):
        indent = "        "
        if conditional and index >= 2:
            lines.extend([indent + "if enabled {", indent + "    if visible {"])
            indent += "        "
        lines.append(indent + f'Tab(value: .tab{index}) {{')
        if helper:
            lines.append(indent + "    serverScreen(feature)")
        else:
            lines.append(indent + '    Text("Content { value }")')
            if index != missing:
                lines.append(indent + "        .browserTabBarVisibility(browserVisibility)")
        lines.append(indent + "}")
        if conditional and index >= 2:
            lines.extend(["            }", "        }"])
    lines.append("    }")
    if outer:
        lines.append("    .browserTabBarVisibility(browserVisibility)")
    lines.extend(["}", "", "private var browserVisibility: BrowserWindowVisibility { visibility }"])
    if helper:
        lines.extend([
            "private func serverScreen(_ feature: Feature) -> some View {",
            '    Text("Server")',
            "        .browserTabBarVisibility(browserVisibility)",
            "}",
        ])
    return "struct MainView {\n" + "\n".join("    " + line for line in lines) + "\n}"


class BrowserWindowVisibilityTests(unittest.TestCase):
    def violations(self, source):
        with patch.object(guard, "read", return_value=source), patch.object(guard, "VIOLATIONS", []):
            guard.check_every_tab_carries_the_tab_bar_modifier()
            return list(guard.VIOLATIONS)

    def test_four_tabs_pass(self):
        self.assertEqual(self.violations(browser_source(4)), [])

    def test_six_tabs_pass(self):
        self.assertEqual(self.violations(browser_source(6)), [])

    def test_nested_conditional_tabs_pass(self):
        self.assertEqual(self.violations(browser_source(6, conditional=True)), [])

    def test_helper_owned_content_visibility_passes(self):
        self.assertEqual(self.violations(browser_source(6, conditional=True, helper=True)), [])

    def test_missing_tab_modifier_fails_without_borrowing_from_its_neighbours(self):
        for count, conditional in ((4, False), (6, False), (6, True)):
            with self.subTest(count=count, conditional=conditional):
                findings = self.violations(browser_source(count, conditional=conditional, missing=2))
                self.assertEqual(len(findings), 1)
                self.assertIn("tab bar left behind", findings[0])

    def test_missing_tabview_modifier_fails_despite_every_tab_having_one(self):
        self.assertEqual(self.violations(browser_source(6, conditional=True, outer=False)), [
            "the TabView itself no longer hides the tab bar alongside its Tabs",
        ])

    def test_a_modifier_inside_a_task_does_not_cover_the_tabview(self):
        source = browser_source(4).replace(
            "        .browserTabBarVisibility(browserVisibility)\n    }",
            '        .task {\n            Text("Other").browserTabBarVisibility(browserVisibility)\n        }\n    }',
        )
        self.assertEqual(self.violations(source), [
            "the TabView itself no longer hides the tab bar alongside its Tabs",
        ])

    def test_a_modifier_string_does_not_cover_a_tab(self):
        source = browser_source(4, missing=0).replace(
            'Text("Content { value }")',
            'Text(".browserTabBarVisibility(browserVisibility)")',
            1,
        )
        findings = self.violations(source)
        self.assertEqual(len(findings), 1)
        self.assertIn("tab bar left behind", findings[0])

    def test_missing_helper_modifier_fails_each_calling_tab(self):
        source = browser_source(6, helper=True).replace(
            '        Text("Server")\n            .browserTabBarVisibility(browserVisibility)',
            '        Text("Server")',
        )
        findings = self.violations(source)
        self.assertEqual(len(findings), 6)
        self.assertTrue(all("tab bar left behind" in finding for finding in findings))

    def test_the_production_browser_carries_visibility(self):
        source = (guard.REPOSITORY_ROOT / "Apps/Enchron/MainView.swift").read_text()
        self.assertEqual(self.violations(source), [])


if __name__ == "__main__":
    unittest.main()
