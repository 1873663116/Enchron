#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))

import reachability_matrix as matrix

EMPTY_SIDEBAR = (
    "window identifier: 'FileBrowsing-FilesScreen' "
    "row identifier: 'FileBrowsing-SourcesSidebar-source-media-library' "
    "button identifier: 'FileBrowsing-SourcesSidebar-sourceMore'"
)
CONNECTED_SIDEBAR = (
    EMPTY_SIDEBAR
    + " row identifier: 'FileBrowsing-SourcesSidebar-source-8F1C'"
)
CONNECTED_ID = "FileBrowsing-SourcesSidebar-source-8F1C"


def scripted_run(
    sidebar: str,
    *,
    form_opens: bool = True,
    connect_succeeds: bool = True,
) -> SimpleNamespace:
    calls: list[str] = []
    run = SimpleNamespace(
        calls=calls,
        events=[{"evidence": "raw/001-relaunch.json"}],
        hierarchy_identifiers=matrix.ReachabilityRun.hierarchy_identifiers,
        relaunch=lambda: calls.append("relaunch"),
        tap=lambda presentation, identifier, **kwargs: calls.append(f"tap:{identifier}") or {"success": True},
        controller=lambda action, *extra: calls.append(f"controller:{action}") or {"hierarchy": sidebar},
        open_source_connection=lambda source: calls.append(f"open:{source}") or ({"success": form_opens}, []),
        wait_for_identifier=lambda identifier, **kwargs: {"matchedElement": {"isHittable": True}},
        connect_webdav_with_environment_identity=lambda probe: calls.append("connect") or ([] if connect_succeeds else None),
        connected_remote_source_identifiers=lambda: [CONNECTED_ID] if connect_succeeds else [],
        select_browseable_remote_source=lambda presentation, identifiers, **kwargs: calls.append(f"select:{','.join(identifiers)}") or False,
        remove_connected_remote_sources=lambda presentation: calls.append("cleanup"),
    )
    run.connect_remote_source_for_browsing = (
        lambda presentation: matrix.ReachabilityRun.connect_remote_source_for_browsing(run, presentation)
    )
    return run


class RemoteBrowserConnectsSourceTests(unittest.TestCase):
    def test_fresh_install_connects_webdav_before_browsing(self) -> None:
        run = scripted_run(EMPTY_SIDEBAR)
        matrix.ReachabilityRun.remote_browser_scenario(run)
        self.assertIn("open:WebDAV", run.calls)
        self.assertIn("connect", run.calls)
        self.assertIn(f"select:{CONNECTED_ID}", run.calls)
        self.assertEqual(run.calls[-1], "cleanup")

    def test_existing_source_is_browsed_without_connecting(self) -> None:
        run = scripted_run(CONNECTED_SIDEBAR)
        matrix.ReachabilityRun.remote_browser_scenario(run)
        self.assertNotIn("connect", run.calls)
        self.assertIn(f"select:{CONNECTED_ID}", run.calls)

    def test_failed_connection_records_no_selection_and_still_cleans_up(self) -> None:
        run = scripted_run(EMPTY_SIDEBAR, connect_succeeds=False)
        matrix.ReachabilityRun.remote_browser_scenario(run)
        self.assertIn("connect", run.calls)
        self.assertFalse(any(call.startswith("select:") for call in run.calls))
        self.assertEqual(run.calls[-1], "cleanup")

    def test_unopened_form_is_a_recorded_failure(self) -> None:
        run = scripted_run(EMPTY_SIDEBAR, form_opens=False)
        matrix.ReachabilityRun.remote_browser_scenario(run)
        self.assertNotIn("connect", run.calls)
        failures = [event for event in run.events if event.get("success") is False]
        self.assertEqual(failures[-1]["action"], "remoteBrowsingSourceFormUnavailable")

    def test_round11_stays_on_the_device_lane(self) -> None:
        self.assertEqual(matrix.SCENARIO_LANES["remote-browser-round11"], "device")
        self.assertEqual(matrix.SCENARIO_LANES["source-connection-webdav"], "device")


if __name__ == "__main__":
    unittest.main()
