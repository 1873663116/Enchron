#!/usr/bin/env python3

from __future__ import annotations

import unittest
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import Mock, patch

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import reachability_matrix as matrix


def immediate_tools(seconds: float = 120.0) -> SimpleNamespace:
    return SimpleNamespace(
        call=lambda verb, action: action(matrix.Budget(seconds, "test budget"))
    )


def arm_recovery(run: matrix.ReachabilityRun) -> None:
    run.policy = matrix.RecoveryPolicy()
    run.history = []
    run.halted = False


class SensitiveEvidenceTests(unittest.TestCase):
    def test_redacts_every_sensitive_value_from_later_hierarchies(self) -> None:
        document = {
            "hierarchy": "address=http://private.test username=private-user",
            "matchedElement": {"value": "private-user"},
        }

        redacted = matrix.redact_sensitive_values(
            document,
            ("http://private.test", "private-user"),
        )

        encoded = json.dumps(redacted)
        self.assertNotIn("http://private.test", encoded)
        self.assertNotIn("private-user", encoded)


class ProofContextAxisTests(unittest.TestCase):
    def test_runner_uses_only_inventory_proof_contexts(self) -> None:
        self.assertEqual(
            matrix.product_proof_contexts({
                "proofContexts": ["main-window-browser"],
            }),
            ("main-window-browser",),
        )

    def test_missing_proof_context_contract_fails_loudly(self) -> None:
        with self.assertRaisesRegex(ValueError, "has no proofContexts"):
            matrix.product_proof_contexts({"id": "accessibility:missing"})


class ImmersiveResidentWindowEvidenceTests(unittest.TestCase):
    def test_system_scene_identity_is_not_an_addressable_product_target(self) -> None:
        document = {
            "hierarchy": "\n".join(
                (
                    "identifier: 'com.xiongzhipeng.XrPlayer:SFBSystemService-1234'",
                    "identifier: 'PlayerUI-product-target'",
                )
            )
        }

        self.assertEqual(
            matrix.product_accessibility_identifiers(document),
            {"PlayerUI-product-target"},
        )

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


class DrivenCellRegistrationTests(unittest.TestCase):
    def test_complete_three_level_evidence_registers_the_cell_as_driven(self) -> None:
        operation = "accessibility:target"
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.operations = {operation: {}}
        run.driven_cells = set()
        run.segment = None
        run.cells = {
            ("portal", operation): {
                "applicationReceived": False,
                "evidence": [],
                "existsInHierarchy": False,
                "reportsHittable": False,
                "verdict": "known-defect",
            }
        }

        run.mark_observation(
            "portal",
            operation,
            exists=True,
            hittable=True,
            received=True,
            evidence="raw/proof.json",
            reason="Complete product evidence.",
        )

        self.assertEqual(run.driven_cells, {("portal", operation)})

    def test_show_controls_uses_the_actual_playback_context(self) -> None:
        operation = "command:toggleControls"
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = {"id": "resume", "context": "main-window-browser"}
        run.cells = {("window", operation): {}}
        run.app_command = Mock(return_value={"success": True})
        run.events = [{"evidence": "raw/toggle.json"}]
        run.delivered = Mock()

        result = run.show_controls("window")

        self.assertTrue(result["success"])
        run.delivered.assert_called_once_with(
            "window",
            operation,
            "raw/toggle.json",
            "The DEBUG command reached the product control-visibility handler and returned success.",
            has_accessibility_target=False,
        )


class MenuSelectionEvidenceTests(unittest.TestCase):
    def test_deferred_player_panel_families_have_runtime_safe_targets(self) -> None:
        self.assertEqual(
            matrix.DEFERRED_MENU_TARGETS[("playerPanel", "audio")],
            "__firstUnselected",
        )
        self.assertEqual(
            matrix.DEFERRED_MENU_TARGETS[("playerPanel", "episodes")],
            "__firstAvailable",
        )

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

    def test_deferred_menu_target_requires_the_resolved_product_item_probe(self) -> None:
        self.assertEqual(
            matrix.menu_delivery_probe_needle("__firstUnselected"),
            "reachability playerPanel delivered action=menu.item.",
        )
        self.assertEqual(
            matrix.menu_delivery_probe_needle("2"),
            "reachability playerPanel delivered action=menu.item.2",
        )

    def test_native_menu_is_not_opened_through_an_immersive_attachment(self) -> None:
        self.assertTrue(matrix.should_open_player_panel_system_menu("window"))
        self.assertTrue(matrix.should_open_player_panel_system_menu("portal"))
        self.assertFalse(matrix.should_open_player_panel_system_menu("panorama"))
        self.assertFalse(matrix.should_open_player_panel_system_menu("docked"))

    def test_immersive_menu_refreshes_controls_before_every_family(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = [{"evidence": "raw/menu.json"}]
        run.show_controls = Mock()
        run.await_controls = Mock(return_value=True)
        run.wait_for_identifier = Mock(return_value={})
        run.copy_probe = Mock(return_value=[])
        run.select_debug_menu_item = Mock(
            return_value=(None, {"success": True}, {"success": False})
        )

        run.player_panel_menu_scenario("panorama")

        self.assertEqual(run.show_controls.call_count, 5)

    def test_segmented_menu_drives_only_its_planned_families(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = {
            "context": "panorama",
            "decisions": [
                {
                    "context": "panorama",
                    "operation": "accessibility:PlayerPanel-menu-speed",
                },
                {
                    "context": "panorama",
                    "operation": "accessibility:PlayerPanel-menu-subtitles",
                },
            ],
        }
        run.events = [{"evidence": "raw/menu.json"}]
        run.show_controls = Mock()
        run.await_controls = Mock(return_value=True)
        run.wait_for_identifier = Mock(return_value={})
        run.copy_probe = Mock(return_value=[])
        run.select_debug_menu_item = Mock(
            return_value=(None, {"success": True}, {"success": False})
        )

        run.player_panel_menu_scenario("panorama")

        self.assertEqual(run.show_controls.call_count, 3)
        self.assertEqual(
            [call.kwargs["family"] for call in run.select_debug_menu_item.call_args_list],
            ["speed", "subtitles"],
        )

    def test_prior_accessibility_fact_requires_a_complete_healthy_segment(self) -> None:
        document = {
            "status": "complete",
            "channelContinuity": {"passed": True},
            "probeJournal": {"passed": True},
            "cells": [{
                "context": "docked",
                "operation": "accessibility:PlayerPanel-menu-more",
                "existsInHierarchy": True,
                "reportsHittable": True,
                "applicationReceived": True,
                "verdict": "reachable",
            }],
        }

        self.assertIsNotNone(matrix.validated_reachable_cell(
            document,
            context="docked",
            operation="accessibility:PlayerPanel-menu-more",
        ))
        document["channelContinuity"]["passed"] = False
        self.assertIsNone(matrix.validated_reachable_cell(
            document,
            context="docked",
            operation="accessibility:PlayerPanel-menu-more",
        ))

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
    def test_the_media_information_open_is_credited_not_only_the_close(self) -> None:
        """Opening the panel is a delivery of its own.

        The scenario waits for the close button to appear, which only happens
        because the open tap ran, and the panel appends mediaInformation.open.
        Crediting only the close left the open cell known-defect in all four
        placements, with a probe journal that names the delivery twice.
        """
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = [{"evidence": "raw/063-tap.json"}]
        run.show_controls = Mock()
        run.tap = Mock(return_value={"success": True})
        run.wait_for_identifier = Mock(
            return_value={"matchedElement": {"identifier": "close"}}
        )
        opened = "reachability playerPanel delivered action=mediaInformation.open"
        closed = "reachability playerPanel delivered action=mediaInformation.close"
        run.copy_probe = Mock(side_effect=[[], [opened], [opened, closed]])
        run.delivered = Mock()

        run.player_panel_media_information_scenario("panorama")

        credited = [call.args[1] for call in run.delivered.call_args_list]
        self.assertIn("accessibility:PlayerPanel-media-information", credited)
        self.assertIn("accessibility:PlayerPanel-media-information-close", credited)

    def test_an_open_the_panel_never_reported_is_not_credited(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = [{"evidence": "raw/063-tap.json"}]
        run.show_controls = Mock()
        run.tap = Mock(return_value={"success": True})
        run.wait_for_identifier = Mock(
            return_value={"matchedElement": {"identifier": "close"}}
        )
        other = "reachability playerPanel delivered action=somethingElse"
        closed = "reachability playerPanel delivered action=mediaInformation.close"
        run.copy_probe = Mock(side_effect=[[], [other], [other, closed]])
        run.delivered = Mock()

        run.player_panel_media_information_scenario("panorama")

        credited = [call.args[1] for call in run.delivered.call_args_list]
        self.assertNotIn("accessibility:PlayerPanel-media-information", credited)
        self.assertIn("accessibility:PlayerPanel-media-information-close", credited)

    def test_the_top_menu_drives_every_family_the_inventory_derives(self) -> None:
        """Subtitles proved the route; the other three were never asked.

        audio, speed and episodes sat as known defects in both window and
        portal while PlayerUI-menu-subtitles, reached by the identical DEBUG
        equivalent through the identical parent, was reachable.
        """
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = None
        run.events = [{"evidence": "raw/top-menu.json"}]
        run.tap_with_fresh_controls = Mock(return_value=({"success": True}, []))
        run.copy_probe = Mock(return_value=[])
        run.controller = Mock(return_value={"success": False})
        run.delivered = Mock()
        run.delivered_by_debug_menu_selection = Mock(return_value=True)
        run.select_debug_menu_item = Mock(
            return_value=(None, {"success": True}, {"success": False})
        )

        run.top_menu_scenario("window")

        self.assertEqual(
            [call.kwargs["family"] for call in run.select_debug_menu_item.call_args_list],
            ["speed", "subtitles", "audio", "episodes"],
        )

    def test_a_segment_drives_only_the_top_menu_families_it_plans(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = {
            "context": "portal",
            "decisions": [
                {"context": "portal", "operation": "accessibility:PlayerUI-menu-audio"},
            ],
        }
        run.events = [{"evidence": "raw/top-menu.json"}]
        run.tap_with_fresh_controls = Mock(return_value=({"success": True}, []))
        run.copy_probe = Mock(return_value=[])
        run.controller = Mock(return_value={"success": False})
        run.delivered = Mock()
        run.delivered_by_debug_menu_selection = Mock(return_value=True)
        run.select_debug_menu_item = Mock(
            return_value=(None, {"success": True}, {"success": False})
        )

        run.top_menu_scenario("portal")

        self.assertEqual(
            [call.kwargs["family"] for call in run.select_debug_menu_item.call_args_list],
            ["audio"],
        )

    def test_a_placeholder_target_looks_for_the_item_the_product_chose(self) -> None:
        """__firstUnselected names no item, so no line can end with it."""
        self.assertEqual(
            matrix.top_menu_delivery_probe_needle("__firstUnselected"),
            "reachability top actions delivered action=menu.item.",
        )
        self.assertEqual(
            matrix.top_menu_delivery_probe_needle("off"),
            "reachability top actions delivered action=menu.item.off",
        )

    def test_remote_source_selection_skips_the_delete_child(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = [{"evidence": "raw/source.json"}]
        run.copy_probe = Mock(side_effect=[
            [],
            ["reachability files delivered action=sidebar.select.remote"],
        ])
        run.mark_driven = Mock()
        run.mark_observation = Mock()
        run.hierarchy_identifiers = Mock(
            return_value={"FileBrowsing-grid-folder-root"}
        )
        run.controller = Mock(side_effect=[
            {
                "success": True,
                "matchedElement": {"isHittable": True},
            },
            {"success": True, "hierarchy": "remote"},
        ])

        selected = run.select_browseable_remote_source(
            "main-window-browser",
            ["FileBrowsing-SourcesSidebar-source-remote"],
            evidence_prefix="test",
        )

        self.assertTrue(selected)
        run.controller.assert_any_call(
            "tap",
            "--identifier",
            "FileBrowsing-SourcesSidebar-source-remote",
            "--index",
            "1",
            "--no-screenshot",
        )

    def test_docked_content_collects_menu_facts_before_removing_expanded_media(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        events: list[str] = []
        run.enter_docked_playback = Mock(return_value=True)
        run.player_panel_menu_scenario = Mock(
            side_effect=lambda _: events.append("menu")
        )
        run.player_panel_media_information_scenario = Mock(
            side_effect=lambda _: events.append("media")
        )

        run.docked_content_scenario()

        self.assertEqual(events, ["menu", "media"])

    def test_spatial_exit_requires_interactive_controls_and_terminal_window_state(
        self,
    ) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = [{"evidence": "raw/exit.json"}]
        run.show_controls = Mock(return_value={"success": True})
        run.wait_for_identifier_value = Mock(side_effect=[
            {
                "matchedElement": {
                    "value": ";".join((
                        "presentation=panorama",
                        "transition=none",
                        "controls=shown",
                        "controlsInteractive=true",
                    ))
                }
            },
            {
                "matchedElement": {
                    "value": ";".join((
                        "presentation=portal",
                        "transition=none",
                        "pendingSpatialEffect=none",
                        "attached=portal",
                    ))
                }
            },
        ])
        run.wait_for_identifier = Mock(side_effect=[
            {
                "matchedElement": {
                    "identifier": "PlayerPanel-button-exit-spatial",
                    "isHittable": True,
                }
            },
        ])
        run.mark_driven = Mock()
        run.mark_observation = Mock()
        run.copy_probe = Mock(side_effect=[
            [],
            ["testcmd exitSpatial delivered target=portal"],
        ])
        run.app_command = Mock(return_value={"success": True})
        run.controller = Mock(return_value={"success": True})

        run.exit_spatial_with_product_command("panorama", "portal")

        run.show_controls.assert_called_once_with()
        self.assertEqual(
            [call.args[0] for call in run.wait_for_identifier_value.call_args_list],
            [
                "PlayerUI-spatial-state",
                "PlayerUI-window-control-plane",
            ],
        )
        run.wait_for_identifier.assert_called_once_with(
            "PlayerPanel-button-exit-spatial"
        )
        self.assertTrue(
            any(
                call.kwargs.get("received") is True
                for call in run.mark_observation.call_args_list
            )
        )

    def test_tap_without_delivery_evaluation_is_not_a_driven_defect(self) -> None:
        operation = "accessibility:Emby-Navigation-Tab"
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.operations = {operation: {}}
        run.driven_cells = set()
        run.tapped_cells = set()
        run.cells = {
            ("main-window-browser", operation): {
                "context": "main-window-browser",
                "operation": operation,
                "identifierTemplate": "Emby-Navigation-Tab",
                "existsInHierarchy": False,
                "reportsHittable": False,
                "applicationReceived": False,
                "verdict": "known-defect",
                "evidence": [],
            }
        }
        run.events = [{"evidence": "raw/001-tap.json"}]
        run.controller = Mock(return_value={
            "success": True,
            "matchedElement": {
                "identifier": "Emby-Navigation-Tab",
                "isHittable": True,
            },
        })

        run.tap("main-window-browser", "Emby-Navigation-Tab")

        self.assertEqual(run.driven_cells, set())
        cell = run.cells[("main-window-browser", operation)]
        self.assertTrue(cell["existsInHierarchy"])
        self.assertTrue(cell["reportsHittable"])
        self.assertFalse(cell["applicationReceived"])

    def test_tap_passes_an_explicit_index_to_the_controller(self) -> None:
        operation = "accessibility:Settings-category-{item.id}"
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.operations = {operation: {}}
        run.driven_cells = set()
        run.tapped_cells = set()
        run.cells = {
            ("main-window-browser", operation): {
                "context": "main-window-browser",
                "operation": operation,
                "identifierTemplate": "Settings-category-{item.id}",
                "existsInHierarchy": False,
                "reportsHittable": False,
                "applicationReceived": False,
                "verdict": "known-defect",
                "evidence": [],
            }
        }
        run.events = [{"evidence": "raw/indexed-tap.json"}]
        run.silent_taps = []
        run.copy_timings = []
        run.controller = Mock(return_value={"success": False})

        run.tap(
            "main-window-browser",
            "Settings-category-storagePrivacy",
            operation_id=operation,
            index=2,
        )

        run.controller.assert_called_once_with(
            "tap",
            "--identifier",
            "Settings-category-storagePrivacy",
            "--index",
            "2",
            "--no-screenshot",
        )

    def test_a_target_xctest_cannot_find_is_named_not_counted(self) -> None:
        """A tap that matched nothing has to leave the identifier behind.

        Neither branch of mark_observation fires without a matched element, so
        the cell keeps the first-run reason and the only trace is
        summary["unmeasured"] going up by one. Nine taps failed that way in one
        segment and the evidence files record the answer, never the request.
        """
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.operations = {}
        run.driven_cells = set()
        run.tapped_cells = set()
        run.cells = {}
        run.events = [{"evidence": "raw/107-tap.json"}]
        run.silent_taps = []
        run.copy_timings = []
        run.controller = Mock(return_value={
            "success": False,
            "message": "No current element matches the requested identifier and index.",
        })

        run.tap("main-window-browser", "MediaLibrary-grid-folder-Reachability Round 2")

        self.assertEqual(len(run.silent_taps), 1)
        silent = run.silent_taps[0]
        self.assertEqual(silent["why"], "absent")
        self.assertEqual(
            silent["identifier"], "MediaLibrary-grid-folder-Reachability Round 2"
        )
        self.assertEqual(silent["evidence"], "raw/107-tap.json")
        self.assertIn("No current element matches", silent["message"])

    def test_a_tap_on_a_disabled_control_is_named_not_read_as_hittable(self) -> None:
        """A disabled button answers "Element tapped." and runs no action.

        XCTest reports isHittable true for it, so mark_observation records a
        hittable control that never delivered - indistinguishable from a button
        whose handler is broken. isEnabled is already in the response and was
        being dropped.
        """
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.operations = {}
        run.driven_cells = set()
        run.tapped_cells = set()
        run.cells = {}
        run.events = [{"evidence": "raw/108-tap.json"}]
        run.silent_taps = []
        run.copy_timings = []
        run.controller = Mock(return_value={
            "success": True,
            "message": "Element tapped.",
            "matchedElement": {
                "identifier": "FileBrowsing-FilesScreen-navBackForward-back",
                "isHittable": True,
                "isEnabled": False,
            },
        })

        run.tap("main-window-browser", "FileBrowsing-FilesScreen-navBackForward-back")

        self.assertEqual(len(run.silent_taps), 1)
        self.assertEqual(run.silent_taps[0]["why"], "disabled")
        self.assertEqual(
            run.silent_taps[0]["identifier"],
            "FileBrowsing-FilesScreen-navBackForward-back",
        )

    def test_a_tap_that_reached_an_enabled_control_is_not_recorded_as_silent(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.operations = {}
        run.driven_cells = set()
        run.tapped_cells = set()
        run.cells = {}
        run.events = [{"evidence": "raw/064-tap.json"}]
        run.silent_taps = []
        run.copy_timings = []
        run.controller = Mock(return_value={
            "success": True,
            "matchedElement": {
                "identifier": "x",
                "isHittable": True,
                "isEnabled": True,
            },
        })

        run.tap("main-window-browser", "x")

        self.assertEqual(run.silent_taps, [])

    def test_probe_precedes_control_reveal_and_immediate_tap(self) -> None:
        actions: list[str] = []
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.copy_probe = Mock(
            side_effect=lambda _: actions.append("probe") or ["before"]
        )
        run.show_controls = Mock(
            side_effect=lambda _: actions.append("controls") or {"success": True}
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

    def test_delivered_action_matches_whichever_host_wrote_the_probe(self) -> None:
        probe = [
            "reachability top actions delivered action=enterPanorama",
            "reachability playerPanel delivered action=videoFormat.apply",
            "reachability topActions delivered action=dock.open",
        ]

        for index, action in enumerate(
            ("enterPanorama", "videoFormat.apply", "dock.open")
        ):
            self.assertTrue(
                matrix.reachability_action_was_delivered(
                    probe, action, offset=index
                )
            )
            self.assertFalse(
                matrix.reachability_action_was_delivered(
                    probe, action, offset=index + 1
                )
            )

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

    def test_segment_probe_archive_turns_a_hung_listing_into_a_typed_fault(self) -> None:
        with TemporaryDirectory() as directory:
            run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
            run.segment = {"id": "panorama"}
            run.channel_failures = []
            run.events = []
            run.raw = Path(directory)
            run.sequence = 0
            run.direct_transfer_calls = 0
            run.evidence_retrieval_transfer_calls = 0
            run.segment_evidence_started = False
            run.copy_timings = []
            arm_recovery(run)

            def hung(verb: str, action: object) -> None:
                raise matrix.InstrumentFault(
                    "transport-timeout",
                    {"verb": verb},
                    matrix.Budget(120.0, "provisional 120s"),
                )

            run.tools = SimpleNamespace(call=hung)

            self.assertEqual(
                run.archive_probe_chunk("segment-after-surface"), []
            )

            self.assertEqual(run.channel_failures[0]["action"], "probe-size")
            self.assertEqual(run.channel_failures[0]["kind"], "transport-timeout")
            self.assertIn("provisional 120s", run.channel_failures[0]["error"])
            self.assertFalse(run.events[-1]["success"])

    def test_probe_clear_retries_a_transient_destination_exists_error(self) -> None:
        with TemporaryDirectory() as directory:
            run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
            run.segment = {"id": "window-dv-format"}
            run.events = []
            run.channel_failures = []
            run.raw = Path(directory)
            run.direct_transfer_calls = 0
            run.copy_timings = []
            run.tools = immediate_tools()
            arm_recovery(run)
            destination_exists = Mock(
                returncode=1,
                stderr="NSPOSIXErrorDomain error 17",
                stdout="",
            )
            cleared = Mock(returncode=0, stderr="", stdout="File Size: Zero KB")

            with patch.object(
                matrix.enchron_target,
                "truncate_in_container",
                side_effect=(destination_exists, cleared),
            ) as truncate:
                self.assertTrue(run.clear_probe_after_archive())

            self.assertEqual(truncate.call_count, 2)
            self.assertEqual(run.events[-1]["attemptCount"], 2)
            self.assertTrue(run.events[-1]["success"])

    def test_a_controller_transport_timeout_is_a_typed_instrument_fault(self) -> None:
        with TemporaryDirectory() as directory:
            run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
            run.segment = {"id": "panorama"}
            run.channel_failures = []
            run.events = []
            run.raw = Path(directory)
            run.sequence = 0
            run.sensitive_values = ()
            run.last_controller_document = {}
            arm_recovery(run)

            def invoke(action: str, arguments: list[str]) -> None:
                raise matrix.InstrumentFault(
                    "transport-timeout",
                    {"verb": action},
                    matrix.Budget(20.0, "p95 13.50s × 1.5, lane=simulator, n=20"),
                )

            run.client = SimpleNamespace(invoke=invoke)

            result = run.controller("snapshot", "--no-screenshot")

            self.assertFalse(result["success"])
            self.assertEqual(result["failure"]["kind"], "transport-timeout")
            self.assertEqual(run.channel_failures[0]["action"], "snapshot")
            self.assertEqual(run.channel_failures[0]["kind"], "transport-timeout")
            self.assertIn("lane=simulator", run.channel_failures[0]["error"])

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
        run.hold = Mock()

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

    def test_segment_open_media_queues_import_without_needing_its_payload(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = {"id": "docked-01-panel", "context": "docked"}
        run.events = [{"evidence": "raw/deferred-evidence-replay.json"}]
        run.relaunch = Mock()
        run.tap = Mock(return_value={"success": True})
        run.copy_probe = Mock(return_value=[])
        run.app_command = Mock(return_value={"success": True, "deferred": True})
        run.controller = Mock(return_value={"success": True})
        run.wait_for_identifier = Mock(return_value={
            "matchedElement": {
                "identifier": "MediaLibrary-grid-video-furyroad-stripped.mkv"
            }
        })
        run.tap_label = Mock(return_value={"success": True})
        run.wait_for_probe = Mock(return_value=[
            "reachability files delivered action=library.video"
        ])
        run.delivered = Mock()
        run.hold = Mock()

        result = run.open_media(
            "MediaLibrary-grid-video-furyroad-stripped.mkv"
        )

        self.assertTrue(result["success"])
        run.app_command.assert_called_once_with(
            "importMedia", file="furyroad-stripped.mkv"
        )
        self.assertEqual(run.relaunch.call_count, 1)

    def test_docked_route_records_window_owned_top_actions_in_window_context(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = [
            {"evidence": "raw/route-action.json"},
            {"evidence": "raw/spatial-state.json"},
            {"evidence": "raw/deferred-evidence-replay.json"},
        ]
        run.open_media = Mock(return_value={"success": True})
        run.ensure_window_projection = Mock(return_value=True)
        run.show_controls = Mock()
        run.copy_probe = Mock(side_effect=[
            [],
            [
                "reachability top actions delivered action=dock.open",
                "reachability top actions delivered action=dock.select"
                " environment=skybox effect=none",
                "worldLoad event=completed anchor=PlaybackSurfaceAnchor",
            ],
        ])
        run.controller = Mock(return_value={"success": True})
        run.wait_for_identifier = Mock(return_value={
            "matchedElement": {"value": ";".join((
                "presentation=docked",
                "transition=none",
                "surfacePreparation=surfaceAttached",
                "lifecycle=Playing",
                "attached=docked",
                "rendererConsumer=docked",
                "displayedPixel=true",
                "surfaceRenderingReady=true",
                "surfaceSettled=true",
            ))}
        })
        run.mark_observation = Mock()
        run.delivered = Mock()

        self.assertTrue(run.enter_docked_playback())
        self.assertTrue(run.mark_observation.call_args_list)
        self.assertTrue(all(
            call.args[0] == "window"
            for call in run.mark_observation.call_args_list
        ))


class DeferredSegmentEvidenceTests(unittest.TestCase):
    def test_system_alert_field_uses_debug_binding_without_claiming_a_target(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.mark_driven = Mock()
        run.app_command = Mock(return_value={"success": True})
        run.copy_probe = Mock(side_effect=[
            [],
            ["reachability files delivered action=newFolder.name"],
        ])
        run.delivered = Mock()
        run.events = [{"evidence": "raw/alert-field.json"}]

        run.set_file_browser_alert_field(
            presentation="main-window-browser",
            operation="accessibility:MediaLibrary-NewFolder-name",
            field="newFolderName",
            value="Round 13",
            evidence_label="new-folder-name",
        )

        run.app_command.assert_called_once_with(
            "setFileBrowserAlertField",
            field="newFolderName",
            value="Round 13",
        )
        self.assertFalse(
            run.delivered.call_args.kwargs["has_accessibility_target"]
        )

    def test_deferred_probe_markers_never_read_or_clear_the_device_file(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = {"id": "portal-issues", "context": "portal"}
        run.events = []
        run.deferred_probe_requirements = []
        run.probe_markers = {}
        run.next_probe_marker = 2
        run.query_probe_size = Mock()
        run.archive_probe_chunk = Mock()

        run.copy_probe("after-first-portal-entry")

        run.query_probe_size.assert_not_called()
        run.archive_probe_chunk.assert_not_called()
        self.assertEqual(run.events[-1]["action"], "deferProbeRead")
        self.assertEqual(
            run.events[-1]["evidence"], "raw/deferred-evidence-replay.json"
        )

    def test_probe_status_gate_accepts_only_a_healthy_product_journal(self) -> None:
        healthy = matrix.parse_probe_status_response({
            "success": True,
            "ok": True,
            "payload": [
                "byteLimit=196608",
                "fileBytes=88201",
                "peakFileBytes=131043",
                "compactionCount=4",
                "evidenceOverflowed=false",
                "writeFailed=false",
            ],
        })
        overflowed = matrix.parse_probe_status_response({
            "success": False,
            "ok": False,
            "payload": [
                "byteLimit=196608",
                "fileBytes=1000",
                "peakFileBytes=196000",
                "compactionCount=8",
                "evidenceOverflowed=true",
                "writeFailed=false",
            ],
        })

        self.assertTrue(healthy["passed"])
        self.assertEqual(healthy["byteLimit"], 196_608)
        self.assertEqual(healthy["fileBytes"], 88_201)
        self.assertFalse(overflowed["passed"])
        self.assertTrue(overflowed["evidenceOverflowed"])

    def test_bounded_segment_probe_uses_one_device_copy(self) -> None:
        with TemporaryDirectory() as directory:
            run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
            run.raw = Path(directory)
            run.events = []
            run.channel_failures = []
            run.direct_transfer_calls = 0
            run.copy_timings = []
            run.evidence_retrieval_transfer_calls = 0
            run.probe_retrieval_count = 0
            run.tools = immediate_tools()
            run.hold = Mock()
            arm_recovery(run)

            def copy_probe(**kwargs: object) -> Mock:
                destination = Path(str(kwargs["destination"]))
                destination.write_text(
                    "2026-08-19T00:00:00Z probeSequence=1 "
                    "probeRetention=evidence proof\n",
                    encoding="utf-8",
                )
                return Mock(returncode=0, stderr="", stdout="")

            with patch.object(
                matrix.enchron_target,
                "copy_from_container",
                side_effect=copy_probe,
            ) as device_read:
                lines = run.retrieve_bounded_probe(
                    "segment-after-surface",
                    byte_limit=196_608,
                )

            self.assertEqual(lines, [
                "2026-08-19T00:00:00Z probeSequence=1 "
                "probeRetention=evidence proof"
            ])
            self.assertEqual(device_read.call_count, 1)
            self.assertEqual(run.probe_retrieval_count, 1)
            self.assertEqual(run.evidence_retrieval_transfer_calls, 1)
            self.assertTrue(run.events[-1]["success"])

    def test_replay_gate_rejects_aligned_but_unverified_deliveries(self) -> None:
        reason = matrix.deferred_replay_failure_reason({
            "passed": False,
            "sessionAligned": True,
            "sequenceOrdered": True,
            "deliveryCount": 17,
            "verifiedDeliveryCount": 2,
        })

        self.assertEqual(
            reason,
            "Deferred evidence replay left 15 delivery facts unverified.",
        )

    def test_replay_gate_accepts_a_fully_verified_replay(self) -> None:
        self.assertIsNone(matrix.deferred_replay_failure_reason({
            "passed": True,
            "sessionAligned": True,
            "sequenceOrdered": True,
            "deliveryCount": 2,
            "verifiedDeliveryCount": 2,
        }))

    def test_segment_probe_reads_are_deferred_without_devicectl(self) -> None:
        operation = "accessibility:PlayerPanel-button-forward"
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = {"id": "docked-transport", "context": "docked"}
        run.sequence = 4
        run.events = []
        run.channel_failures = []
        run.deferred_deliveries = []
        run.deferred_probe_requirements = []
        run.probe_markers = {0: "2026-08-18T01:00:00Z"}
        run.next_probe_marker = 1
        run.last_deferred_command_id = None
        run.cells = {
            ("docked", operation): {
                "context": "docked",
                "operation": operation,
                "identifierTemplate": "PlayerPanel-button-forward",
                "existsInHierarchy": True,
                "reportsHittable": True,
                "applicationReceived": False,
                "verdict": "known-defect",
                "evidence": [],
            }
        }
        run.operations = {operation: {}}
        run.driven_cells = set()

        with patch.object(
            matrix.enchron_target, "copy_from_container"
        ) as device_read, patch.object(
            matrix, "utc_now", return_value="2026-08-18T01:00:02Z"
        ):
            probe = run.copy_probe("after-forward")
            delivered = any(
                "playback control delivered action=forward" in line
                for line in probe[0:]
            )
            if delivered:
                run.delivered(
                    "docked",
                    operation,
                    "raw/deferred.json",
                    "Deferred product delivery.",
                )

        device_read.assert_not_called()
        self.assertEqual(
            run.events[-1]["evidence"],
            "raw/deferred-evidence-replay.json",
        )
        self.assertFalse(run.cells[("docked", operation)]["applicationReceived"])
        self.assertEqual(
            run.deferred_deliveries[0]["probeRequirements"][0]["needles"],
            ["playback control delivered action=forward"],
        )

    def test_segment_app_command_defers_its_response_and_tags_the_session(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = {"id": "panorama", "context": "panorama"}
        run.session_id = "session-10"
        run.operations = {"command:toggleControls": {}}
        run.cells = {("panorama", "command:toggleControls"): {}}
        run.driven_cells = set()
        run.deferred_command_ids = set()
        run.last_deferred_command_id = None
        run.controller = Mock(return_value={
            "success": True,
            "deferred": True,
            "id": "toggle-command",
        })

        result = run.app_command("toggleControls", visible="true")

        self.assertTrue(result["success"])
        self.assertEqual(run.deferred_command_ids, {"toggle-command"})
        run.controller.assert_called_once_with(
            "app-command",
            "--verb",
            "toggleControls",
            "--no-screenshot",
            "--defer-response",
            "--arg",
            "evidenceSession=session-10",
            "--arg",
            "visible=true",
        )

    def test_setup_app_command_does_not_register_an_unrelated_context(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = {"id": "resume", "context": "main-window-browser"}
        run.session_id = "session-11"
        run.operations = {"command:seekNormalized": {}}
        run.cells = {("window", "command:seekNormalized"): {}}
        run.driven_cells = set()
        run.deferred_command_ids = set()
        run.last_deferred_command_id = None
        run.controller = Mock(return_value={
            "success": True,
            "deferred": True,
            "id": "seek-command",
        })

        result = run.app_command(
            "seekNormalized",
            position="0.25",
            track_reachability=False,
        )

        self.assertTrue(result["success"])
        self.assertEqual(run.driven_cells, set())
        self.assertEqual(run.deferred_command_ids, {"seek-command"})

    def test_replay_failure_carries_the_app_s_own_reason(self) -> None:
        cells = {("window", "command:setEndBehavior"): {
            "evidence": [], "verdict": "known-defect",
        }}
        replay = matrix.replay_deferred_evidence(
            cells=cells,
            deliveries=[{
                "context": "window",
                "operation": "command:setEndBehavior",
                "probeRequirements": [],
                "commandIDs": ["cmd-1", "cmd-2"],
            }],
            probe_lines=["2026-08-31T00:00:00Z reachability evidence session=s1 seq=1"],
            responses={"cmd-1": {
                "id": "cmd-1", "ok": False,
                "detail": "settings.end-behavior has no target=Stop; available=stop,repeatOne.",
            }},
            session_id="s1",
            started_at="2026-08-30T00:00:00+00:00",
            ended_at="2026-09-01T00:00:00+00:00",
            evidence="raw/probe.log",
        )
        failure = replay["failures"][0]
        self.assertIn(
            "settings.end-behavior has no target=Stop; available=stop,repeatOne.",
            failure["commandDetails"],
        )
        self.assertEqual(failure["missingResponseIDs"], ["cmd-2"])

    def test_ensure_session_retires_a_stale_runner_before_giving_up(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = []
        run.session_id = None
        run.channel_failures = [{"action": "ensure-session", "error": "timed out"}]
        run.tools = immediate_tools()
        arm_recovery(run)
        run.controller = Mock(side_effect=[
            {"success": False, "error": "instrument fault transport-timeout"},
            {"success": True, "sessionID": "session-2"},
        ])
        removal = Mock(return_value=SimpleNamespace(returncode=0, stdout="App uninstalled.", stderr=""))

        with patch.object(matrix.enchron_target, "uninstall_app", removal):
            self.assertTrue(run.ensure_session())

        self.assertEqual(run.session_id, "session-2")
        self.assertEqual(run.controller.call_count, 2)
        self.assertEqual(
            removal.call_args.kwargs["bundle_id"],
            matrix.ReachabilityRun.UI_TEST_RUNNER_BUNDLE,
        )

    def test_retiring_the_runner_clears_what_blocks_the_retry(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = []
        run.channel_failures = [{"action": "ensure-session", "error": "timed out"}]
        run.tools = immediate_tools()
        arm_recovery(run)
        run.halted = True
        removal = Mock(return_value=SimpleNamespace(returncode=0, stdout="", stderr=""))

        with patch.object(matrix.enchron_target, "uninstall_app", removal):
            run.retire_stale_test_runner()

        self.assertEqual(run.channel_failures, [])
        self.assertFalse(run.halted)
        self.assertEqual(run.history, [])

    def test_ensure_session_gives_up_when_the_clean_device_also_fails(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = []
        run.session_id = None
        run.channel_failures = []
        run.tools = immediate_tools()
        arm_recovery(run)
        run.controller = Mock(return_value={"success": False, "error": "timed out"})
        removal = Mock(return_value=SimpleNamespace(returncode=0, stdout="", stderr=""))

        with patch.object(matrix.enchron_target, "uninstall_app", removal):
            self.assertFalse(run.ensure_session())

        self.assertEqual(run.controller.call_count, 2)

    def test_deferred_probe_records_the_suffix_a_predicate_anchors_on(self) -> None:
        requirement = {"needles": []}
        line = matrix.DeferredProbeLine(requirement)

        delivered = matrix.reachability_action_was_delivered(
            [line], "enterPanorama", offset=0
        )

        self.assertTrue(delivered)
        self.assertIn(" delivered action=enterPanorama", requirement["needles"])
        self.assertIn("reachability ", requirement["needles"])

    def test_container_copy_takes_a_whole_directory_on_the_simulator(self) -> None:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            container = root / "container"
            (container / "Documents/test-responses").mkdir(parents=True)
            for name in ("a.json", "b.json"):
                (container / "Documents/test-responses" / name).write_text("{}", encoding="utf-8")
            destination = root / "batch"

            with patch.object(matrix.enchron_target, "is_simulator", return_value=True), \
                 patch.object(matrix.enchron_target, "simulator_container", return_value=container):
                result = matrix.enchron_target.copy_from_container(
                    target="sim-udid",
                    bundle_id="com.example.app",
                    source="Documents/test-responses",
                    destination=destination,
                    developer_dir="/Applications/Xcode.app/Contents/Developer",
                )

            self.assertEqual(result.returncode, 0)
            self.assertEqual(
                sorted(path.name for path in destination.iterdir()),
                ["a.json", "b.json"],
            )

    def _timing_out_run(self, raw: Path):
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.sequence = 0
        run.segment = None
        run.sensitive_values = ()
        run.events = []
        run.channel_failures = []
        run.raw = raw
        run.last_controller_document = {}
        arm_recovery(run)
        return run

    @staticmethod
    def _scripted_client(answers: list[object]) -> SimpleNamespace:
        remaining = list(answers)

        def invoke(action: str, arguments: list[str]) -> SimpleNamespace:
            answer = remaining.pop(0)
            if isinstance(answer, matrix.InstrumentFault):
                raise answer
            return SimpleNamespace(document=answer, failure=None)

        return SimpleNamespace(invoke=invoke)

    @staticmethod
    def _silence() -> matrix.InstrumentFault:
        return matrix.InstrumentFault(
            "response-timeout",
            {"diagnosis": "The runner did not answer tap within its budget."},
        )

    def test_two_identical_faults_in_a_row_quarantine_the_channel(self) -> None:
        with TemporaryDirectory() as directory:
            run = self._timing_out_run(Path(directory))
            run.client = self._scripted_client([
                self._silence(), self._silence(),
            ])

            run.controller("tap", "--identifier", "x")
            run.controller("tap", "--identifier", "x")
            refused = run.controller("tap", "--identifier", "x")

        self.assertTrue(run.halted)
        self.assertFalse(refused["success"])
        self.assertEqual(len(run.channel_failures), 1)
        halt = run.channel_failures[0]["halt"]
        self.assertIn("twice in a row", halt["reason"])
        self.assertEqual(halt["faultReport"]["instrumentFaults"], 2)
        self.assertEqual(len(run.events), 3)

    def test_a_runner_that_stopped_answering_ends_the_run(self) -> None:
        with TemporaryDirectory() as directory:
            run = self._timing_out_run(Path(directory))
            run.client = self._scripted_client([
                self._silence(), self._silence(),
            ])

            run.controller("tap", "--identifier", "x")
            run.controller("tap", "--identifier", "x")

        self.assertTrue(run.halted)
        self.assertTrue(run.channel_refuses("tap"))
        self.assertFalse(run.channel_refuses("halt"))

    def test_scattered_silences_are_not_a_run_of_silence(self) -> None:
        with TemporaryDirectory() as directory:
            run = self._timing_out_run(Path(directory))
            run.client = self._scripted_client([
                self._silence(),
                {"success": True},
                self._silence(),
                {"success": True},
                self._silence(),
            ])

            for _ in range(5):
                run.controller("tap", "--identifier", "x")

        self.assertFalse(run.halted)
        self.assertEqual(len(run.history), 1)
        self.assertEqual(run.policy.fault_count, 3)

    def test_a_recovery_that_goes_unanswered_is_not_a_second_fault(self) -> None:
        with TemporaryDirectory() as directory:
            run = self._timing_out_run(Path(directory))
            run.client = self._scripted_client([
                self._silence(),
                matrix.InstrumentFault(
                    "response-timeout",
                    {"diagnosis": "The runner did not answer relaunch."},
                ),
            ])

            run.controller("tap", "--identifier", "x")
            run.controller("relaunch", "--no-screenshot")

        self.assertFalse(run.halted)
        self.assertEqual(
            [record.location for record in run.history], ["tap", "relaunch"]
        )

    def test_a_product_refusal_does_not_end_the_run(self) -> None:
        refused = {
            "success": False,
            "message": "settings.end-behavior has no target=Stop; available=stop.",
            "failure": {
                "class": "product",
                "kind": "assertion-mismatch",
                "evidence": {},
            },
        }
        with TemporaryDirectory() as directory:
            run = self._timing_out_run(Path(directory))
            run.client = self._scripted_client([refused] * 5)

            for _ in range(5):
                run.controller("app-command", "--verb", "selectMenuItem")

        self.assertFalse(run.halted)
        self.assertEqual(run.policy.fault_count, 0)
        self.assertEqual(run.history, [])

    def test_one_timeout_is_a_bad_step_not_a_dead_run(self) -> None:
        with TemporaryDirectory() as directory:
            run = self._timing_out_run(Path(directory))
            run.client = self._scripted_client([
                matrix.InstrumentFault("transport-timeout", {"verb": "tap"}),
                {"success": True},
            ])

            run.controller("tap", "--identifier", "x")
            run.controller("tap", "--identifier", "y")

        self.assertFalse(run.halted)
        self.assertEqual(run.history, [])

    def test_observe_ignores_an_operation_this_context_cannot_prove(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = {"id": "window-01", "context": "window"}
        run.operations = {
            "accessibility:Emby-Navigation-Tab": {
                "identifierTemplate": "Emby-Navigation-Tab", "kind": "activate",
            },
            "accessibility:PlayerUI-play": {
                "identifierTemplate": "PlayerUI-play", "kind": "activate",
            },
        }
        run.cells = {
            ("window", "accessibility:PlayerUI-play"): {
                "existsInHierarchy": False, "reportsHittable": False,
                "applicationReceived": False, "verdict": "known-defect",
                "reason": "", "evidence": [],
            },
        }
        run.inventory = {"identifierFamilies": ["Emby", "PlayerUI"]}
        run.events = [{"evidence": "raw/001-snapshot.json"}]
        run.tapped_cells = set()
        run.last_controller_document = {
            "success": True,
            "hierarchy": (
                "identifier: 'Emby-Navigation-Tab'\n"
                "identifier: 'PlayerUI-play'"
            ),
        }
        run.controller = Mock(return_value=run.last_controller_document)

        run.observe("window", "window playback")

        self.assertTrue(run.cells[("window", "accessibility:PlayerUI-play")]["existsInHierarchy"])

    def test_marking_outside_a_derived_context_is_counted_not_raised(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.cells = {}
        run.out_of_context_observations = {}

        run.mark_observation(
            "docked",
            "accessibility:PlayerUI-loadFailure-primary",
            exists=True,
            evidence="raw/001-tap.json",
            reason="the alert was over the docked panel",
        )

        self.assertEqual(
            run.out_of_context_observations,
            {("docked", "accessibility:PlayerUI-loadFailure-primary"): 1},
        )

    def test_marking_inside_the_derived_context_still_records(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        cell = {
            "existsInHierarchy": False, "reportsHittable": False,
            "applicationReceived": False, "verdict": "known-defect",
            "reason": "", "evidence": [],
        }
        run.cells = {("docked", "accessibility:PlayerPanel-play"): cell}
        run.out_of_context_observations = {}

        run.mark_observation(
            "docked", "accessibility:PlayerPanel-play",
            exists=True, evidence="raw/001-tap.json", reason="tapped",
        )

        self.assertTrue(cell["existsInHierarchy"])
        self.assertEqual(run.out_of_context_observations, {})

    def test_a_menu_whose_parent_is_out_of_context_delivers_nothing(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.cells = {}
        run.out_of_context_observations = {}

        delivered = run.delivered_by_debug_menu_selection(
            "docked",
            "accessibility:PlayerUI-menu-audio-1",
            "accessibility:PlayerUI-TopAction-more",
            evidence="raw/001-app-command.json",
            reason="the top action menu answered",
        )

        self.assertFalse(delivered)
        self.assertEqual(
            run.out_of_context_observations,
            {("docked", "accessibility:PlayerUI-TopAction-more"): 1},
        )

    def _copying_run(self):
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = []
        run.direct_transfer_calls = 0
        run.copy_timings = []
        run.tools = immediate_tools()
        run.hold = Mock()
        arm_recovery(run)
        return run

    def test_every_copy_records_what_it_cost(self) -> None:
        run = self._copying_run()
        completed = SimpleNamespace(returncode=0, stdout="", stderr="")

        with TemporaryDirectory() as directory, patch.object(
            matrix.enchron_target, "copy_from_container", return_value=completed
        ) as copy_call:
            run.device_copy_from(
                matrix.PROBE_REMOTE_PATH,
                Path(directory) / "probe.log",
                label="probeChunk",
            )

        self.assertEqual(len(run.copy_timings), 1)
        self.assertEqual(run.copy_timings[0]["label"], "probeChunk")
        self.assertIsInstance(run.copy_timings[0]["elapsedSeconds"], float)
        self.assertEqual(copy_call.call_args.kwargs["budget_seconds"], 120.0)

    def test_a_transient_transfer_error_is_retried(self) -> None:
        run = self._copying_run()
        flaky = SimpleNamespace(
            returncode=1, stdout="",
            stderr="ERROR: The specified file could not be transferred. "
                   "(com.apple.dt.CoreDeviceError error 7000)",
        )
        answers = [flaky, SimpleNamespace(returncode=0, stdout="", stderr="")]

        with TemporaryDirectory() as directory, patch.object(
            matrix.enchron_target, "copy_from_container", side_effect=answers
        ):
            result = run.device_copy_from(
                matrix.PROBE_REMOTE_PATH,
                Path(directory) / "probe.log",
                label="probe",
            )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(run.direct_transfer_calls, 2)
        self.assertEqual(run.events[0]["action"], "retryDeviceCopy")

    def test_a_real_transfer_error_is_not_retried(self) -> None:
        run = self._copying_run()
        refused = SimpleNamespace(
            returncode=1, stdout="", stderr="ERROR: No such application on the device.",
        )

        with TemporaryDirectory() as directory, patch.object(
            matrix.enchron_target, "copy_from_container", return_value=refused
        ):
            result = run.device_copy_from(
                matrix.PROBE_REMOTE_PATH,
                Path(directory) / "probe.log",
                label="probe",
            )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(run.direct_transfer_calls, 1)

    def test_the_transfer_gives_up_after_the_backoff(self) -> None:
        run = self._copying_run()
        flaky = SimpleNamespace(
            returncode=1, stdout="",
            stderr="com.apple.dt.CoreDeviceError error -1 (0xFFFFFFFF)",
        )

        with TemporaryDirectory() as directory, patch.object(
            matrix.enchron_target, "copy_from_container", return_value=flaky
        ):
            result = run.device_copy_from(
                matrix.PROBE_REMOTE_PATH,
                Path(directory) / "probe.log",
                label="probe",
            )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(run.direct_transfer_calls, len(matrix.TRANSFER_ATTEMPTS))

    def test_a_summon_waits_for_the_panel_to_reach_the_hierarchy(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        absent = {"success": True, "hierarchy": "identifier: 'PlayerUI-play'"}
        present = {
            "success": True,
            "hierarchy": "identifier: 'PlayerPanel-controls'",
        }
        run.controller = Mock(side_effect=[absent, present])

        self.assertTrue(run.await_controls())
        self.assertEqual(run.controller.call_count, 2)

    def test_a_summon_that_never_arrives_is_reported(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.controller = Mock(return_value={
            "success": True, "hierarchy": "identifier: 'PlayerUI-play'",
        })

        self.assertFalse(run.await_controls())
        self.assertEqual(
            run.controller.call_count, matrix.ReachabilityRun.CONTROLS_VISIBLE_SAMPLES
        )

    def test_transport_accepts_the_panel_s_own_spelling_of_the_fact(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.copy_probe = Mock(side_effect=[
            [],
            ["reachability playerPanel delivered action=rewind"],
            ["reachability playerPanel delivered action=rewind",
             "reachability playerPanel delivered action=forward"],
            ["reachability playerPanel delivered action=rewind",
             "reachability playerPanel delivered action=forward",
             "reachability playerPanel delivered action=playPause"],
        ])
        run.tap_control = Mock(return_value={"success": True})
        run.events = [{"evidence": "raw/001-tap.json"}]
        run.delivered = Mock()

        run.transport_scenario("docked")

        recorded = [call.args[1] for call in run.delivered.call_args_list]
        self.assertEqual(
            recorded,
            [
                "accessibility:PlayerPanel-button-rewind",
                "accessibility:PlayerPanel-button-forward",
                "accessibility:PlayerPanel-button-play",
            ],
        )

    def test_app_command_retries_the_lost_command_file_race(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = None
        run.session_id = None
        run.operations = {}
        run.cells = {}
        run.driven_cells = set()
        run.deferred_command_ids = set()
        run.last_deferred_command_id = None
        run.arguments = SimpleNamespace(contexts=[])
        lost = {
            "success": False,
            "error": "ERROR: Failed to retrieve the file node for "
                     "Documents/test-command.json (com.apple.dt.CoreDeviceError error 7000)",
        }
        run.controller = Mock(side_effect=[lost, lost, {"success": True}])
        run.hold = Mock()

        result = run.app_command("resetState", track_reachability=False)

        self.assertTrue(result["success"])
        self.assertEqual(run.controller.call_count, 3)

    def test_app_command_gives_up_after_the_backoff_is_spent(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = None
        run.session_id = None
        run.operations = {}
        run.cells = {}
        run.driven_cells = set()
        run.deferred_command_ids = set()
        run.last_deferred_command_id = None
        run.arguments = SimpleNamespace(contexts=[])
        lost = {
            "success": False,
            "error": "ERROR: Failed to retrieve the file node for "
                     "Documents/test-command.json (com.apple.dt.CoreDeviceError error 7000)",
        }
        run.controller = Mock(return_value=lost)
        run.hold = Mock()

        result = run.app_command("resetState", track_reachability=False)

        self.assertFalse(result["success"])
        self.assertEqual(run.controller.call_count, 4)

    def test_app_command_does_not_retry_a_product_failure(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = None
        run.session_id = None
        run.operations = {}
        run.cells = {}
        run.driven_cells = set()
        run.deferred_command_ids = set()
        run.last_deferred_command_id = None
        run.arguments = SimpleNamespace(contexts=[])
        run.controller = Mock(return_value={
            "success": False, "error": "importMedia rejected the reference"
        })

        result = run.app_command("importMedia", track_reachability=False)

        self.assertFalse(result["success"])
        self.assertEqual(run.controller.call_count, 1)

    def test_app_command_ignores_an_operation_owned_by_another_context(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = {"id": "resume", "context": "main-window-browser"}
        run.session_id = "session-12"
        run.operations = {"command:toggleControls": {}}
        run.cells = {("window", "command:toggleControls"): {}}
        run.driven_cells = set()
        run.deferred_command_ids = set()
        run.last_deferred_command_id = None
        run.controller = Mock(return_value={"success": True})

        result = run.app_command("toggleControls", visible="true")

        self.assertTrue(result["success"])
        self.assertEqual(run.driven_cells, set())

    def test_segment_observation_reuses_the_latest_hierarchy(self) -> None:
        operation = "accessibility:Navigation-Ornament-tab-files"
        hierarchy = "identifier: 'Navigation-Ornament-tab-files'"
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.segment = {"id": "browser", "context": "main-window-browser"}
        run.last_controller_document = {"success": True, "hierarchy": hierarchy}
        run.events = [{"evidence": "raw/004-tap.json"}]
        run.controller = Mock()
        run.inventory = {"identifierFamilies": ["Navigation"]}
        run.operations = {
            operation: {"identifierTemplate": "Navigation-Ornament-tab-files"}
        }
        run.cells = {
            ("main-window-browser", operation): {
                "context": "main-window-browser",
                "operation": operation,
                "identifierTemplate": "Navigation-Ornament-tab-files",
                "existsInHierarchy": False,
                "reportsHittable": False,
                "applicationReceived": False,
                "verdict": "known-defect",
                "evidence": [],
            }
        }

        document = run.observe("main-window-browser", "after tab tap")

        self.assertEqual(document["hierarchy"], hierarchy)
        run.controller.assert_not_called()
        self.assertTrue(
            run.cells[("main-window-browser", operation)]["existsInHierarchy"]
        )

    def test_offline_replay_matches_the_online_three_level_verdict(self) -> None:
        operation = "accessibility:PlayerPanel-button-forward"
        online = {
            ("docked", operation): {
                "context": "docked",
                "operation": operation,
                "identifierTemplate": "PlayerPanel-button-forward",
                "existsInHierarchy": True,
                "reportsHittable": True,
                "applicationReceived": True,
                "verdict": "reachable",
                "evidence": ["raw/online.json"],
            }
        }
        deferred = {
            ("docked", operation): {
                **online[("docked", operation)],
                "applicationReceived": False,
                "verdict": "known-defect",
                "evidence": ["raw/action.json"],
            }
        }

        replay = matrix.replay_deferred_evidence(
            cells=deferred,
            deliveries=[{
                "context": "docked",
                "operation": operation,
                "probeRequirements": [{
                    "after": "2026-08-18T01:00:01Z",
                    "needles": ["playback control delivered action=forward"],
                }],
                "commandIDs": ["command-forward"],
            }],
            probe_lines=[
                "2026-08-18T01:00:00Z probeSequence=40 "
                "reachability evidence session=session-10",
                "2026-08-18T01:00:02Z probeSequence=41 "
                "playback control delivered action=forward",
            ],
            responses={
                "command-forward": {"id": "command-forward", "ok": True}
            },
            session_id="session-10",
            started_at="2026-08-18T01:00:00Z",
            ended_at="2026-08-18T01:01:00Z",
            evidence="raw/segment-probe.log",
        )

        self.assertTrue(replay["passed"])
        self.assertEqual(
            deferred[("docked", operation)]["verdict"],
            online[("docked", operation)]["verdict"],
        )
        self.assertTrue(
            deferred[("docked", operation)]["applicationReceived"]
        )

    def test_offline_replay_rejects_a_response_from_no_matching_session(self) -> None:
        operation = "command:toggleControls"
        cells = {
            ("panorama", operation): {
                "context": "panorama",
                "operation": operation,
                "identifierTemplate": None,
                "existsInHierarchy": False,
                "reportsHittable": False,
                "applicationReceived": False,
                "verdict": "known-defect",
                "evidence": [],
            }
        }

        replay = matrix.replay_deferred_evidence(
            cells=cells,
            deliveries=[{
                "context": "panorama",
                "operation": operation,
                "probeRequirements": [],
                "commandIDs": ["toggle"],
            }],
            probe_lines=[
                "2026-08-18T01:00:00Z probeSequence=40 "
                "reachability evidence session=older-session"
            ],
            responses={"toggle": {"id": "toggle", "ok": True}},
            session_id="session-10",
            started_at="2026-08-18T01:00:00Z",
            ended_at="2026-08-18T01:01:00Z",
            evidence="raw/segment-probe.log",
        )

        self.assertFalse(replay["passed"])
        self.assertFalse(cells[("panorama", operation)]["applicationReceived"])

    def test_offline_replay_rejects_reordered_probe_records(self) -> None:
        operation = "command:toggleControls"
        cells = {
            ("panorama", operation): {
                "context": "panorama",
                "operation": operation,
                "identifierTemplate": None,
                "existsInHierarchy": False,
                "reportsHittable": False,
                "applicationReceived": False,
                "verdict": "known-defect",
                "evidence": [],
            }
        }

        replay = matrix.replay_deferred_evidence(
            cells=cells,
            deliveries=[{
                "context": "panorama",
                "operation": operation,
                "probeRequirements": [],
                "commandIDs": ["toggle"],
            }],
            probe_lines=[
                "2026-08-18T01:00:01Z probeSequence=42 testcmd toggle ok",
                "2026-08-18T01:00:00Z probeSequence=41 "
                "reachability evidence session=session-10",
            ],
            responses={"toggle": {"id": "toggle", "ok": True}},
            session_id="session-10",
            started_at="2026-08-18T01:00:00Z",
            ended_at="2026-08-18T01:01:00Z",
            evidence="raw/segment-probe.log",
        )

        self.assertFalse(replay["passed"])
        self.assertFalse(replay["sequenceOrdered"])
        self.assertFalse(cells[("panorama", operation)]["applicationReceived"])

    def test_batched_response_loader_accepts_flat_or_source_named_copy(self) -> None:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            nested = root / "test-responses"
            nested.mkdir()
            (nested / "wanted.json").write_text(
                json.dumps({"id": "wanted", "ok": True}), encoding="utf-8"
            )
            (root / "stale.json").write_text(
                json.dumps({"id": "stale", "ok": True}), encoding="utf-8"
            )

            responses = matrix.load_batched_app_responses(
                root, expected_ids={"wanted"}
            )

        self.assertEqual(responses, {"wanted": {"id": "wanted", "ok": True}})

    def test_probe_size_is_read_from_device_file_listing_json(self) -> None:
        listing = {
            "result": {
                "files": [{
                    "name": "surface-tap-probe.log",
                    "path": "Documents/surface-tap-probe.log",
                    "size": 599_999,
                }]
            }
        }

        self.assertEqual(
            matrix.device_file_size(
                listing, "Documents/surface-tap-probe.log"
            ),
            599_999,
        )

    def test_probe_size_matches_the_xcode_27_beta_5_listing_shape(self) -> None:
        listing = {
            "result": {
                "files": [{
                    "name": "surface-tap-probe.log",
                    "relativePath": "surface-tap-probe.log",
                    "metadata": {"size": 123_456},
                }]
            }
        }

        self.assertEqual(
            matrix.device_file_size(
                listing, "Documents/surface-tap-probe.log"
            ),
            123_456,
        )


class ProbeStatusRetryTests(unittest.TestCase):
    """One unanswered command must not cost the segment its whole journal.

    probeStatus names the byte limit the bounded copy needs. Unanswered, every
    field is null, the copy is skipped, and the replay runs against nothing -
    81 and 53 delivery facts reported unverified in one run, after every
    scenario had already finished.
    """

    def run_with(self, answers: list[dict]) -> tuple[matrix.ReachabilityRun, Mock]:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.events = []
        run.app_command = Mock(side_effect=answers)
        run.ensure_session = Mock(return_value=True)
        return run, run.app_command

    def test_the_retry_never_restores_the_session(self) -> None:
        """Recovering the session to get an answer destroys the answer.

        ensure-session starts a new test session and the app returns with an
        empty journal and an empty response batch. A portal segment retried at
        07:38:44 and copied a journal of three lines, all written after the
        recovery, in place of the fifty-nine deliveries it had spent a quarter
        of an hour producing.
        """
        run, app_command = self.run_with([
            {"success": False, "message": "App command probeStatus did not respond."},
            {"success": False, "message": "App command probeStatus did not respond."},
        ])

        document = run.read_probe_status()

        self.assertIs(document["success"], False)
        self.assertEqual(app_command.call_count, 2)
        run.ensure_session.assert_not_called()

    def test_an_unanswered_probe_status_is_asked_again(self) -> None:
        answered = {"success": True, "payload": ["byteLimit=196608"]}
        run, app_command = self.run_with([
            {"success": False, "message": "App command probeStatus did not respond."},
            answered,
        ])

        document = run.read_probe_status()

        self.assertEqual(document, answered)
        self.assertEqual(app_command.call_count, 2)
        run.ensure_session.assert_not_called()
        self.assertEqual(
            [event["action"] for event in run.events], ["probeStatusRetry"]
        )

    def test_an_answered_probe_status_is_not_asked_twice(self) -> None:
        answered = {"success": True, "payload": ["byteLimit=196608"]}
        run, app_command = self.run_with([answered])

        document = run.read_probe_status()

        self.assertEqual(document, answered)
        self.assertEqual(app_command.call_count, 1)
        run.ensure_session.assert_not_called()
        self.assertEqual(run.events, [])

    def test_the_retry_records_whether_the_second_ask_was_answered(self) -> None:
        run, _ = self.run_with([
            {"success": False, "message": "App command probeStatus did not respond."},
            {"success": False, "message": "App command probeStatus did not respond."},
        ])

        run.read_probe_status()

        self.assertIs(run.events[0]["success"], False)


class MissingProbeJournalTests(unittest.TestCase):
    """A journal that was never read is not evidence of anything.

    Two of three segments in one run lost every deferred delivery this way:
    probeStatus went unanswered, so byteLimit was null, so the retrieval was
    skipped without a word, and the replay ran against an empty journal and
    reported 81 and 53 delivery facts as unverified. Read from the results that
    is indistinguishable from the product refusing all of them.
    """

    def test_a_journal_that_was_never_retrieved_says_so(self) -> None:
        reason = matrix.deferred_replay_failure_reason({
            "journalRetrieved": False,
            "sessionAligned": False,
            "sequenceOrdered": False,
            "passed": False,
            "deliveryCount": 81,
            "verifiedDeliveryCount": 0,
        })

        self.assertIsNotNone(reason)
        self.assertIn("never retrieved", reason)
        self.assertNotIn("session marker", reason)

    def test_a_journal_that_was_read_still_reports_the_missing_marker(self) -> None:
        reason = matrix.deferred_replay_failure_reason({
            "journalRetrieved": True,
            "sessionAligned": False,
            "sequenceOrdered": True,
            "passed": False,
            "deliveryCount": 4,
            "verifiedDeliveryCount": 0,
        })

        self.assertEqual(reason, "The segment probe has no matching session marker.")

    def test_the_replay_records_whether_it_had_a_journal(self) -> None:
        replay = matrix.replay_deferred_evidence(
            cells={},
            deliveries=[],
            probe_lines=[],
            responses={},
            session_id="A68360F6-0B5E-441B-A5E7-5AA007D2D4FA",
            started_at="2026-09-01T01:00:00+00:00",
            ended_at="2026-09-01T02:00:00+00:00",
            evidence="raw/segment-after-surface-probe.log",
            journal_retrieved=False,
        )

        self.assertIs(replay["journalRetrieved"], False)


class PartialBaselineAcceptanceTests(unittest.TestCase):
    def test_unselected_contexts_keep_their_accepted_verdicts(self) -> None:
        baseline = [
            {
                "context": "main-window-browser",
                "operation": "accessibility:fixture",
                "verdict": "known-defect",
            },
            {
                "context": "portal",
                "operation": "accessibility:fixture",
                "verdict": "reachable",
            },
        ]
        current = [
            {
                "context": "main-window-browser",
                "operation": "accessibility:fixture",
                "verdict": "reachable",
            },
            {
                "context": "portal",
                "operation": "accessibility:fixture",
                "verdict": "known-defect",
            },
        ]

        merged = matrix.merge_selected_cells_into_baseline(
            baseline,
            current,
            selected={"main-window-browser"},
        )

        self.assertEqual(
            merged,
            [
                {
                    "context": "main-window-browser",
                    "operation": "accessibility:fixture",
                    "verdict": "reachable",
                },
                {
                    "context": "portal",
                    "operation": "accessibility:fixture",
                    "verdict": "reachable",
                },
            ],
        )


class SegmentedDeliveryTests(unittest.TestCase):
    baseline = [
        {
            "context": "main-window-browser",
            "operation": "accessibility:old-reachable",
            "verdict": "reachable",
        },
        {
            "context": "main-window-browser",
            "operation": "accessibility:candidate",
            "verdict": "known-defect",
        },
        {
            "context": "portal",
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
                {"context": "main-window-browser", "operation": operation}
            ],
            "cells": [
                {
                    "context": "main-window-browser",
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
            (cell["context"], cell["operation"]): cell["verdict"]
            for cell in delivery["candidateCells"]
        }
        self.assertTrue(delivery["accepted"])
        self.assertEqual(delivery["acceptedSegments"], ["valid"])
        self.assertEqual(delivery["rejectedSegments"], ["invalid"])
        self.assertEqual(
            verdicts[("main-window-browser", "accessibility:candidate")], "reachable"
        )
        self.assertEqual(
            verdicts[("main-window-browser", "accessibility:old-reachable")], "reachable"
        )

    def test_explicit_complete_facts_are_driven_after_deferred_replay(self) -> None:
        replayed = self.segment(
            name="replayed",
            operation="accessibility:candidate",
            verdict="reachable",
        )
        replayed["deliveryAssessmentModel"] = "explicit-v1"
        replayed["drivenCells"] = []
        replayed["cells"][0].update({
            "applicationReceived": True,
            "existsInHierarchy": True,
            "kind": "activate",
            "reportsHittable": True,
        })

        delivery = matrix.merge_segment_delivery(self.baseline, [replayed])

        self.assertIn(
            {
                "context": "main-window-browser",
                "operation": "accessibility:candidate",
            },
            delivery["drivenCells"],
        )
        self.assertEqual(
            delivery["candidateCells"][1]["verdict"],
            "reachable",
        )

    def test_reachable_evidence_is_not_overwritten_by_a_later_defect_segment(self) -> None:
        proved = self.segment(
            name="proved",
            operation="accessibility:old-reachable",
            verdict="reachable",
        )
        later_unproved = self.segment(
            name="later-unproved",
            operation="accessibility:old-reachable",
            verdict="known-defect",
        )

        delivery = matrix.merge_segment_delivery(
            self.baseline, [proved, later_unproved]
        )

        verdicts = {
            (cell["context"], cell["operation"]): cell["verdict"]
            for cell in delivery["candidateCells"]
        }
        self.assertTrue(delivery["accepted"])
        self.assertEqual(
            verdicts[("main-window-browser", "accessibility:old-reachable")],
            "reachable",
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
                    "context": "main-window-browser",
                    "operation": "accessibility:old-reachable",
                    "reason": "driven-old-reachable-not-reproved",
                }
            ],
        )
        self.assertEqual(
            delivery["candidateCells"][0]["verdict"], "known-defect"
        )

    def test_legacy_tap_without_delivery_assessment_does_not_trigger_regression(self) -> None:
        legacy = self.segment(
            name="legacy",
            operation="accessibility:candidate",
            verdict="reachable",
        )
        legacy["schemaVersion"] = 3
        legacy["drivenCells"].append({
            "context": "main-window-browser",
            "operation": "accessibility:old-reachable",
        })
        legacy["cells"].append({
            "context": "main-window-browser",
            "operation": "accessibility:old-reachable",
            "applicationReceived": False,
            "verdict": "known-defect",
        })
        legacy["cells"][0]["applicationReceived"] = True
        legacy["deferredEvidence"] = {
            "deliveries": [{
                "context": "main-window-browser",
                "operation": "accessibility:candidate",
                "probeRequirements": [],
                "commandIDs": [],
            }]
        }

        delivery = matrix.merge_segment_delivery(self.baseline, [legacy])

        self.assertTrue(delivery["accepted"])
        self.assertEqual(delivery["failures"], [])
        self.assertEqual(
            delivery["unassessedLegacyDrivenCells"],
            [{
                "segment": "legacy",
                "context": "main-window-browser",
                "operation": "accessibility:old-reachable",
            }],
        )
        verdicts = {
            (cell["context"], cell["operation"]): cell["verdict"]
            for cell in delivery["candidateCells"]
        }
        self.assertEqual(
            verdicts[("main-window-browser", "accessibility:old-reachable")],
            "reachable",
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

    def test_required_baseline_coverage_rejects_an_undriven_reachable_cell(
        self,
    ) -> None:
        candidate = self.segment(
            name="candidate",
            operation="accessibility:candidate",
            verdict="reachable",
        )

        delivery = matrix.merge_segment_delivery(
            self.baseline,
            [candidate],
            require_baseline_coverage=True,
        )

        self.assertFalse(delivery["accepted"])
        self.assertEqual(
            delivery["uncoveredReachableCells"],
            [
                {
                    "context": "main-window-browser",
                    "operation": "accessibility:old-reachable",
                },
                {
                    "context": "portal",
                    "operation": "accessibility:uncovered",
                },
            ],
        )
        self.assertTrue(all(
            failure["reason"] == "old-reachable-not-driven"
            for failure in delivery["failures"]
        ))

    def test_no_regression_evidence_covers_an_undriven_baseline_cell(self) -> None:
        candidate = self.segment(
            name="candidate",
            operation="accessibility:old-reachable",
            verdict="reachable",
        )

        delivery = matrix.merge_segment_delivery(
            self.baseline,
            [candidate],
            require_baseline_coverage=True,
            no_regression_cells={
                ("portal", "accessibility:uncovered"),
            },
        )

        self.assertTrue(delivery["accepted"])
        self.assertEqual(delivery["uncoveredReachableCells"], [])
        self.assertEqual(
            delivery["noRegressionCoveredCells"],
            [{"context": "portal", "operation": "accessibility:uncovered"}],
        )

    def test_no_regression_evidence_cannot_hide_device_defect_evidence(self) -> None:
        regression = self.segment(
            name="regression",
            operation="accessibility:old-reachable",
            verdict="known-defect",
        )
        regression["cells"][0]["evidence"] = ["raw/defect.json"]

        delivery = matrix.merge_segment_delivery(
            self.baseline,
            [regression],
            no_regression_cells={
                ("main-window-browser", "accessibility:old-reachable"),
            },
        )

        self.assertFalse(delivery["accepted"])
        self.assertIn(
            {
                "context": "main-window-browser",
                "operation": "accessibility:old-reachable",
                "reason": "no-regression-evidence-conflicts-with-device-evidence",
            },
            delivery["failures"],
        )

    def test_segment_plan_rejects_unknown_and_duplicate_entries(self) -> None:
        plan = {
            "schemaVersion": 1,
            "segments": [
                {
                    "id": "window-a",
                    "context": "main-window-browser",
                    "expectedMaximumSteps": 100,
                    "scenarios": ["sources-smb"],
                    "decisions": [{
                        "context": "main-window-browser",
                        "operation": "accessibility:candidate",
                    }],
                },
                {
                    "id": "window-a",
                    "context": "wrong",
                    "expectedMaximumSteps": 100,
                    "scenarios": ["missing"],
                    "decisions": [{
                        "context": "wrong",
                        "operation": "accessibility:missing",
                    }],
                },
            ],
        }

        errors = matrix.validate_segment_plan(
            plan,
            operation_contexts={
                "accessibility:candidate": {"main-window-browser"},
            },
            scenario_names={"sources-smb"},
        )

        self.assertEqual(
            errors,
            [
                "segment window-a is duplicated",
                "segment window-a has unknown proof context wrong",
                "segment window-a has unknown scenario missing",
                "segment window-a decision has unknown proof context wrong",
                "segment window-a has unknown operation accessibility:missing",
            ],
        )

    def test_segment_plan_rejects_a_step_budget_over_one_hundred(self) -> None:
        plan = {
            "schemaVersion": 1,
            "segments": [
                {
                    "id": "docked-too-large",
                    "context": "docked",
                    "expectedMaximumSteps": 101,
                    "scenarios": ["docked-placement"],
                    "decisions": [{
                        "context": "docked",
                        "operation": "accessibility:candidate",
                    }],
                }
            ],
        }

        errors = matrix.validate_segment_plan(
            plan,
            operation_contexts={"accessibility:candidate": {"docked"}},
            scenario_names={"docked-placement"},
        )

        self.assertEqual(
            errors,
            ["segment docked-too-large expectedMaximumSteps must be between 1 and 100"],
        )

    def test_segment_plan_rejects_an_operation_outside_its_derived_contexts(self) -> None:
        plan = {
            "schemaVersion": 2,
            "segments": [{
                "id": "wrong-host",
                "context": "docked",
                "expectedMaximumSteps": 20,
                "scenarios": ["docked-placement"],
                "decisions": [{
                    "context": "docked",
                    "operation": "accessibility:browser-only",
                }],
            }],
        }

        errors = matrix.validate_segment_plan(
            plan,
            operation_contexts={
                "accessibility:browser-only": {"main-window-browser"},
            },
            scenario_names={"docked-placement"},
        )

        self.assertEqual(
            errors,
            [
                "segment wrong-host operation accessibility:browser-only "
                "is not derived for proof context docked"
            ],
        )


class DetachedRunTests(unittest.TestCase):
    def test_refuses_to_drive_the_device_once_orphaned(self) -> None:
        with patch.object(matrix.os, "getppid", return_value=1):
            with self.assertRaises(SystemExit) as raised:
                matrix.refuse_when_detached()

        self.assertIn("started detached", str(raised.exception))

    def test_allows_a_run_whose_launching_shell_is_still_present(self) -> None:
        with patch.object(matrix.os, "getppid", return_value=4242):
            matrix.refuse_when_detached()


class CompletionHonestyTests(unittest.TestCase):
    def test_a_cell_the_run_never_visited_denies_the_complete_status(self) -> None:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.output = Path(self.enterDirectory())
        run.arguments = Mock(contexts=list(matrix.PROOF_CONTEXTS))
        run.events = []
        run.silent_taps = []
        run.copy_timings = []
        run.channel_failures = []
        arm_recovery(run)
        run.cells = {
            ("main-window-browser", "accessibility:measured"): {
                "context": "main-window-browser",
                "operation": "accessibility:measured",
                "verdict": "reachable",
                "reason": "Delivery observed.",
            },
            ("docked", "accessibility:never-visited"): {
                "context": "docked",
                "operation": "accessibility:never-visited",
                "verdict": "unmeasured",
                "reason": matrix.UNMEASURED_REASON,
            },
        }
        run.operations = {
            "accessibility:measured": {},
            "accessibility:never-visited": {},
        }

        run.finish("complete")

        written = json.loads((run.output / "results.json").read_text(encoding="utf-8"))
        self.assertEqual(written["status"], "incomplete")
        self.assertEqual(written["summary"]["unmeasured"], 1)
        self.assertEqual(written["summary"]["known-defect"], 0)

    def enterDirectory(self) -> str:
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        return directory.name



class WaitExpiryVerdictTests(unittest.TestCase):
    def waiting_run(self, directory: Path) -> matrix.ReachabilityRun:
        run = matrix.ReachabilityRun.__new__(matrix.ReachabilityRun)
        run.raw = directory
        run.sequence = 0
        run.segment = None
        run.events = []
        run.channel_failures = []
        run.last_controller_document = {}
        run.lane = "device"
        run.budgets = SimpleNamespace(
            budget=lambda lane, verb: matrix.Budget(0.05, "test wait budget"),
            record_sample=Mock(),
        )
        arm_recovery(run)
        return run

    def cell_under_judgment(
        self, run: matrix.ReachabilityRun, context: str, operation: str
    ) -> dict:
        run.operations = {operation: {}}
        run.driven_cells = set()
        run.cells = {
            (context, operation): {
                "context": context,
                "operation": operation,
                "identifierTemplate": operation.removeprefix("accessibility:"),
                "existsInHierarchy": False,
                "reportsHittable": False,
                "applicationReceived": False,
                "verdict": "unmeasured",
                "reason": matrix.UNMEASURED_REASON,
                "evidence": [],
            }
        }
        return run.cells[(context, operation)]

    def test_expiry_over_healthy_snapshots_is_evidence_backed_absence(self) -> None:
        with TemporaryDirectory() as directory:
            run = self.waiting_run(Path(directory))
            snapshot = {
                "success": True,
                "hierarchy": (
                    "identifier: 'PlayerUI-play'\n"
                    "identifier: 'PlayerPanel-controls'"
                ),
            }
            run.controller = Mock(return_value=snapshot)
            run.last_controller_document = snapshot

            outcome = run.wait_for_identifier("Missing-target")

            self.assertTrue(outcome["waitExpired"])
            self.assertTrue(outcome["evidenceBackedExpiry"])
            self.assertNotIn("instrumentFault", outcome)
            self.assertNotIn("matchedElement", outcome)
            self.assertIn(
                ["PlayerPanel-controls", "PlayerUI-play"],
                outcome["observations"],
            )
            self.assertEqual(run.history, [])
            self.assertEqual(run.channel_failures, [])
            self.assertEqual(run.events[-1]["action"], "waitExpired")
            self.assertEqual(run.events[-1]["evidence"], outcome["evidence"])

            operation = "accessibility:Missing-target"
            cell = self.cell_under_judgment(run, "window", operation)
            run.mark_observation(
                "window",
                operation,
                exists=False,
                evidence=run.events[-1]["evidence"],
                reason="The control never appeared before the wait expired.",
            )

            self.assertEqual(cell["verdict"], "known-defect")
            self.assertEqual(cell["evidence"], [outcome["evidence"]])
            written = json.loads(
                (Path(directory) / Path(outcome["evidence"]).name).read_text(
                    encoding="utf-8"
                )
            )
            self.assertTrue(written["evidenceBackedExpiry"])
            self.assertIn(
                ["PlayerPanel-controls", "PlayerUI-play"],
                written["observations"],
            )
            self.assertEqual(
                written["polls"][-1]["identifiers"],
                ["PlayerPanel-controls", "PlayerUI-play"],
            )

    def test_a_controller_fault_during_a_wait_never_becomes_known_defect(self) -> None:
        with TemporaryDirectory() as directory:
            run = self.waiting_run(Path(directory))
            run.segment = {"id": "panorama", "context": "panorama"}
            faulted = {
                "success": False,
                "error": "instrument fault transport-timeout",
                "failure": {
                    "class": "instrument",
                    "kind": "transport-timeout",
                    "evidence": {},
                },
            }
            run.controller = Mock(return_value=faulted)
            run.last_controller_document = faulted

            outcome = run.wait_for_identifier("PlayerPanel-controls")

            self.assertTrue(outcome["waitExpired"])
            self.assertTrue(outcome["instrumentFault"])
            self.assertNotIn("evidenceBackedExpiry", outcome)
            self.assertEqual(run.history[-1].kind, "wait-expired")
            self.assertEqual(
                run.channel_failures[-1]["kind"], "wait-expired"
            )

            operation = "accessibility:PlayerPanel-menu-more"
            cell = self.cell_under_judgment(run, "panorama", operation)
            run.mark_observation(
                "panorama",
                operation,
                exists=False,
                evidence=run.events[-1]["evidence"],
                reason="The wait ended in an instrument fault.",
            )

            self.assertEqual(cell["verdict"], "unmeasured")
            self.assertIn("instrument silence", cell["reason"])

    def test_a_quarantined_wait_is_an_instrument_marker_not_absence(self) -> None:
        with TemporaryDirectory() as directory:
            run = self.waiting_run(Path(directory))
            run.halted = True
            run.controller = Mock()

            outcome = run.wait_for_identifier("PlayerPanel-controls")

            self.assertTrue(outcome["instrumentFault"])
            self.assertTrue(outcome["quarantined"])
            run.controller.assert_not_called()

            operation = "accessibility:PlayerPanel-controls"
            cell = self.cell_under_judgment(run, "panorama", operation)
            run.mark_observation(
                "panorama",
                operation,
                exists=False,
                evidence="raw/quarantined.json",
                reason="The channel was quarantined before the wait ran.",
            )

            self.assertEqual(cell["verdict"], "unmeasured")


class ReachabilityActionMatching(unittest.TestCase):
    def test_a_longer_action_does_not_answer_for_a_shorter_one(self) -> None:
        probe = ["reachability top actions delivered action=dock.openMenu"]
        self.assertFalse(
            matrix.reachability_action_was_delivered(
                probe, "dock.open", offset=0
            )
        )

    def test_a_nested_name_does_not_answer_for_its_parent(self) -> None:
        probe = ["reachability player panel delivered action=menu.item.abc"]
        self.assertFalse(
            matrix.reachability_action_was_delivered(
                probe, "menu.item", offset=0
            )
        )

if __name__ == "__main__":
    unittest.main()
