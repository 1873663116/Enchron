#!/usr/bin/env python3

from __future__ import annotations

import unittest

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


if __name__ == "__main__":
    unittest.main()
