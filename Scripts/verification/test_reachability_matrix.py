#!/usr/bin/env python3

from __future__ import annotations

import unittest
from pathlib import Path
from subprocess import TimeoutExpired
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch

import reachability_matrix as matrix


class ImmersiveResidentWindowEvidenceTests(unittest.TestCase):
    def test_cleanup_response_recovers_lost_toggle_response(self) -> None:
        self.assertTrue(
            matrix.immersive_resident_window_is_hidden(
                toggle={"success": False, "error": "CoreDevice error 7000"},
                cleanup={
                    "success": True,
                    "ok": True,
                    "payload": ["false"],
                },
                no_named_node=True,
                no_new_identifier=True,
            )
        )

    def test_requires_the_window_to_remain_absent_from_accessibility(self) -> None:
        self.assertFalse(
            matrix.immersive_resident_window_is_hidden(
                toggle={"success": True},
                cleanup={"success": True, "payload": ["false"]},
                no_named_node=False,
                no_new_identifier=True,
            )
        )


class MenuSelectionEvidenceTests(unittest.TestCase):
    def test_prefers_requested_current_state_item(self) -> None:
        listing = {
            "payload": ["1.0", "1.25"],
            "menuItems": [
                {"id": "1.0", "title": "1×", "isSelected": True},
                {"id": "1.25", "title": "1.25×", "isSelected": False},
            ],
        }

        self.assertEqual(
            matrix.menu_selection_target(listing, preferred=("1.25",)),
            "1.25",
        )

    def test_chooses_a_nonselected_runtime_item_without_a_preference(self) -> None:
        listing = {
            "payload": ["current", "available"],
            "menuItems": [
                {"id": "current", "title": "Current", "isSelected": True},
                {"id": "available", "title": "Available", "isSelected": False},
            ],
        }

        self.assertEqual(matrix.menu_selection_target(listing), "available")

    def test_accessibility_cell_requires_all_three_evidence_levels(self) -> None:
        cell = {
            "identifierTemplate": "PlayerPanel-menu-{category}-{item.id}",
            "existsInHierarchy": True,
            "reportsHittable": True,
            "applicationReceived": False,
        }
        self.assertFalse(matrix.reachability_evidence_is_complete(cell))

        cell["applicationReceived"] = True
        self.assertTrue(matrix.reachability_evidence_is_complete(cell))

    def test_command_cell_requires_only_application_delivery(self) -> None:
        self.assertTrue(
            matrix.reachability_evidence_is_complete(
                {
                    "identifierTemplate": None,
                    "applicationReceived": True,
                    "existsInHierarchy": False,
                    "reportsHittable": False,
                }
            )
        )


class ReachabilityScenarioSequencingTests(unittest.TestCase):
    def test_probe_precedes_control_reveal_and_immediate_tap(self) -> None:
        actions: list[str] = []
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.copy_probe = Mock(
            side_effect=lambda _: actions.append("probe") or ["before"]
        )
        run.show_controls = Mock(
            side_effect=lambda: actions.append("controls") or {"success": True}
        )
        run.tap = Mock(
            side_effect=lambda *_: actions.append("tap") or {"success": True}
        )

        result, probe = run.tap_with_fresh_controls(
            "window",
            "PlayerUI-TopAction-more",
            probe_label="window-top-menu-before",
        )

        self.assertEqual(actions, ["probe", "controls", "tap"])
        self.assertEqual(result, {"success": True})
        self.assertEqual(probe, ["before"])

    def test_video_format_open_requires_a_new_product_probe(self) -> None:
        probe = [
            "old reachability topActions delivered action=videoFormat.open",
            "new reachability topActions delivered action=videoFormat.open",
        ]

        self.assertTrue(matrix.video_format_open_was_delivered(probe, offset=1))
        self.assertFalse(matrix.video_format_open_was_delivered(probe, offset=2))

    def test_reset_requests_a_deterministic_library_folder_fixture(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.app_command = Mock(return_value={"success": True})

        result = run.reset_reachability_state()

        self.assertEqual(result, {"success": True})
        run.app_command.assert_called_once_with(
            "resetState",
            libraryFolder=matrix.REACHABILITY_LIBRARY_FOLDER,
        )

    def test_segment_probe_copy_enforces_the_120_second_continuity_deadline(self) -> None:
        with TemporaryDirectory() as directory:
            run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
            run.segment = {"id": "panorama"}
            run.channel_failures = []
            run.events = []
            run.raw = Path(directory)
            run.sequence = 0

            with patch.object(
                matrix.subprocess,
                "run",
                side_effect=TimeoutExpired("devicectl", 120),
            ) as subprocess_run:
                self.assertEqual(run.copy_probe("segment-after-surface"), [])

            self.assertEqual(subprocess_run.call_args.kwargs["timeout"], 120)
            self.assertEqual(run.channel_failures[0]["action"], "copyProbe")
            self.assertIn("120.0 seconds", run.channel_failures[0]["error"])

    def test_controller_enforces_the_120_second_continuity_deadline_by_default(self) -> None:
        with TemporaryDirectory() as directory:
            run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
            run.segment = {"id": "panorama"}
            run.channel_failures = []
            run.events = []
            run.raw = Path(directory)
            run.sequence = 0
            run.controller_output = Path(directory)
            run.arguments = Mock(derived_data_path=Path(directory))

            with patch.object(
                matrix.subprocess,
                "run",
                side_effect=TimeoutExpired("controller", 120),
            ) as subprocess_run:
                result = run.controller("snapshot", "--no-screenshot")

            self.assertEqual(subprocess_run.call_args.kwargs["timeout"], 120)
            self.assertFalse(result["success"])
            self.assertEqual(run.channel_failures[0]["action"], "snapshot")
            self.assertIn("120.0 seconds", run.channel_failures[0]["error"])

    def test_window_seek_precedes_transport_controls(self) -> None:
        actions: list[str] = []
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = [{"evidence": "raw/controls.json"}]
        run.open_media = Mock(return_value={"success": True})
        run.ensure_window_projection = Mock(return_value=True)
        run.show_controls = Mock(return_value={"success": True})
        run.wait_for_identifier = Mock(
            return_value={"matchedElement": {"identifier": "PlayerPanel-controls"}}
        )
        run.delivered = Mock()
        run.video_format_editor_scenario = Mock()
        run.observe = Mock()
        run.seek_scenario = Mock(
            side_effect=lambda *_: actions.append("seek")
        )
        run.transport_scenario = Mock(
            side_effect=lambda *_: actions.append("transport")
        )
        run.top_menu_scenario = Mock()
        run.resume_decision_scenario = Mock()

        run.window_scenario()

        self.assertEqual(actions, ["seek", "transport"])

    def test_menu_listing_retries_one_file_node_transport_failure(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = [{"evidence": "raw/menu-command.json"}]
        run.delivered = Mock()
        run.app_command = Mock(side_effect=[
            {
                "success": False,
                "error": "Failed to retrieve the file node for Documents/test-command.json",
            },
            {"success": True, "payload": ["off"]},
            {"success": True, "payload": ["off"]},
        ])

        target, listing, selected = run.select_debug_menu_item(
            presentation="window",
            host="playerUI",
            family="subtitles",
            preferred=("off",),
        )

        self.assertEqual(target, "off")
        self.assertTrue(listing["success"])
        self.assertTrue(selected["success"])
        self.assertEqual(run.app_command.call_count, 3)

    def test_open_media_retries_import_and_waits_for_the_card_before_label_tap(self) -> None:
        actions: list[str] = []
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = [{"evidence": "raw/open-media.json"}]
        run.relaunch = Mock(side_effect=lambda: actions.append("relaunch"))
        run.tap = Mock(side_effect=lambda *_: actions.append("files") or {"success": True})
        run.copy_probe = Mock(return_value=[])
        run.app_command = Mock(
            side_effect=[
                {"success": True, "payload": []},
                {
                    "success": False,
                    "error": "Failed to retrieve the file node for Documents/test-command.json",
                },
                {"success": True, "payload": ["furyroad-stripped.mkv"]},
                {"success": True, "payload": ["furyroad-stripped.mkv"]},
            ]
        )
        run.controller = Mock(
            side_effect=lambda action, *_args, **_kwargs: actions.append(action)
            or {"success": True}
        )
        run.wait_for_identifier = Mock(
            side_effect=lambda *_args, **_kwargs: actions.append("wait-card")
            or {"matchedElement": {"identifier": "MediaLibrary-grid-video-furyroad-stripped.mkv"}}
        )
        run.tap_label = Mock(
            side_effect=lambda *_args, **_kwargs: actions.append("tap-label")
            or {"success": True}
        )
        run.wait_for_probe = Mock(
            return_value=["reachability files delivered action=library.video"]
        )
        run.delivered = Mock()

        with patch.object(matrix.time, "sleep"):
            result = run.open_media(
                "MediaLibrary-grid-video-furyroad-stripped.mkv"
            )

        self.assertTrue(result["success"])
        self.assertEqual(
            run.app_command.call_args_list,
            [
                unittest.mock.call("listLibrary"),
                unittest.mock.call("importMedia", file="furyroad-stripped.mkv"),
                unittest.mock.call("importMedia", file="furyroad-stripped.mkv"),
                unittest.mock.call("listLibrary"),
            ],
        )
        self.assertLess(actions.index("activate"), actions.index("wait-card"))
        self.assertLess(actions.index("wait-card"), actions.index("tap-label"))


class PartialBaselineAcceptanceTests(unittest.TestCase):
    def test_unselected_presentations_keep_their_accepted_verdicts(self) -> None:
        baseline = [
            {
                "presentation": "window",
                "operation": "accessibility:fixture",
                "verdict": "known-defect",
            },
            {
                "presentation": "portal",
                "operation": "accessibility:fixture",
                "verdict": "reachable",
            },
        ]
        current = [
            {
                "presentation": "window",
                "operation": "accessibility:fixture",
                "verdict": "reachable",
            },
            {
                "presentation": "portal",
                "operation": "accessibility:fixture",
                "verdict": "known-defect",
            },
        ]

        merged = matrix.merge_selected_cells_into_baseline(
            baseline,
            current,
            selected={"window"},
        )

        self.assertEqual(
            merged,
            [
                {
                    "presentation": "window",
                    "operation": "accessibility:fixture",
                    "verdict": "reachable",
                },
                {
                    "presentation": "portal",
                    "operation": "accessibility:fixture",
                    "verdict": "reachable",
                },
            ],
        )


class SegmentedDeliveryTests(unittest.TestCase):
    baseline = [
        {
            "presentation": "window",
            "operation": "accessibility:old-reachable",
            "verdict": "reachable",
        },
        {
            "presentation": "window",
            "operation": "accessibility:candidate",
            "verdict": "known-defect",
        },
        {
            "presentation": "portal",
            "operation": "accessibility:uncovered",
            "verdict": "reachable",
        },
    ]

    @staticmethod
    def segment(
        *,
        name: str,
        operation: str,
        verdict: str,
        before_passed: bool = True,
        after_passed: bool = True,
        continuity_passed: bool = True,
    ) -> dict:
        return {
            "schemaVersion": 2,
            "segment": name,
            "status": "complete",
            "sessionID": f"session-{name}",
            "channelHealth": {
                "before": {
                    "passed": before_passed,
                    "sessionID": f"session-{name}",
                },
                "after": {
                    "passed": after_passed,
                    "sessionID": f"session-{name}",
                },
            },
            "channelContinuity": {
                "passed": continuity_passed,
                "failures": [] if continuity_passed else ["controller-timeout"],
            },
            "drivenCells": [
                {"presentation": "window", "operation": operation}
            ],
            "cells": [
                {
                    "presentation": "window",
                    "operation": operation,
                    "verdict": verdict,
                }
            ],
        }

    def test_only_valid_driven_cells_update_the_candidate(self) -> None:
        valid = self.segment(
            name="valid",
            operation="accessibility:candidate",
            verdict="reachable",
        )
        invalid = self.segment(
            name="invalid",
            operation="accessibility:old-reachable",
            verdict="known-defect",
            after_passed=False,
        )

        delivery = matrix.merge_segment_delivery(self.baseline, [valid, invalid])

        verdicts = {
            (cell["presentation"], cell["operation"]): cell["verdict"]
            for cell in delivery["candidateCells"]
        }
        self.assertTrue(delivery["accepted"])
        self.assertEqual(delivery["acceptedSegments"], ["valid"])
        self.assertEqual(delivery["rejectedSegments"], ["invalid"])
        self.assertEqual(
            verdicts[("window", "accessibility:candidate")], "reachable"
        )
        self.assertEqual(
            verdicts[("window", "accessibility:old-reachable")], "reachable"
        )
        self.assertEqual(
            verdicts[("portal", "accessibility:uncovered")], "reachable"
        )

    def test_driven_old_reachable_cell_must_be_reproved(self) -> None:
        regression = self.segment(
            name="regression",
            operation="accessibility:old-reachable",
            verdict="known-defect",
        )

        delivery = matrix.merge_segment_delivery(self.baseline, [regression])

        self.assertFalse(delivery["accepted"])
        self.assertEqual(
            delivery["failures"],
            [
                {
                    "presentation": "window",
                    "operation": "accessibility:old-reachable",
                    "reason": "driven-old-reachable-not-reproved",
                }
            ],
        )
        self.assertEqual(
            delivery["candidateCells"][0]["verdict"], "known-defect"
        )

    def test_segment_with_an_interior_transport_break_is_rejected(self) -> None:
        interrupted = self.segment(
            name="interrupted",
            operation="accessibility:candidate",
            verdict="reachable",
            continuity_passed=False,
        )

        delivery = matrix.merge_segment_delivery(self.baseline, [interrupted])

        self.assertFalse(delivery["accepted"])
        self.assertEqual(delivery["acceptedSegments"], [])
        self.assertEqual(delivery["rejectedSegments"], ["interrupted"])
        self.assertEqual(
            delivery["candidateCells"][1]["verdict"], "known-defect"
        )

    def test_segment_plan_rejects_unknown_and_duplicate_entries(self) -> None:
        plan = {
            "schemaVersion": 1,
            "segments": [
                {
                    "id": "window-a",
                    "presentation": "window",
                    "expectedMaximumSteps": 100,
                    "scenarios": ["sources-smb"],
                    "operations": ["accessibility:candidate"],
                },
                {
                    "id": "window-a",
                    "presentation": "wrong",
                    "expectedMaximumSteps": 100,
                    "scenarios": ["missing"],
                    "operations": ["accessibility:missing"],
                },
            ],
        }

        errors = matrix.validate_segment_plan(
            plan,
            operation_ids={"accessibility:candidate"},
            scenario_names={"sources-smb"},
        )

        self.assertEqual(
            errors,
            [
                "segment window-a is duplicated",
                "segment window-a has unknown presentation wrong",
                "segment window-a has unknown scenario missing",
                "segment window-a has unknown operation accessibility:missing",
            ],
        )

    def test_segment_plan_rejects_a_step_budget_over_one_hundred(self) -> None:
        plan = {
            "schemaVersion": 1,
            "segments": [
                {
                    "id": "docked-too-large",
                    "presentation": "docked",
                    "expectedMaximumSteps": 101,
                    "scenarios": ["docked-placement"],
                    "operations": ["accessibility:candidate"],
                }
            ],
        }

        errors = matrix.validate_segment_plan(
            plan,
            operation_ids={"accessibility:candidate"},
            scenario_names={"docked-placement"},
        )

        self.assertEqual(
            errors,
            ["segment docked-too-large expectedMaximumSteps must be between 1 and 100"],
        )


if __name__ == "__main__":
    unittest.main()
