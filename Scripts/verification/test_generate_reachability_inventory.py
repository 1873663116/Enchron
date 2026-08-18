#!/usr/bin/env python3

from __future__ import annotations

import unittest

import generate_reachability_inventory as inventory


class RuntimeIdentifierExpansionTests(unittest.TestCase):
    def test_expands_component_prefix_at_each_call_site(self) -> None:
        documents = {
            "Modules/MediaLibrary/RuntimePanel.swift": """
                struct RuntimePanel: View {
                    let identifierPrefix: String

                    var body: some View {
                        Button("Submit") {}
                            .accessibilityIdentifier("\\(identifierPrefix)-submit")
                        Button("Select") {}
                            .accessibilityIdentifier(
                                "\\(identifierPrefix)-row-\\(item.id)"
                            )
                    }
                }
            """,
            "Apps/Enchron/RuntimePanelHost.swift": """
                RuntimePanel(identifierPrefix: "FileBrowsing-RuntimePanel")
            """,
        }

        templates = inventory.runtime_identifier_templates(documents)

        self.assertEqual(
            set(templates),
            {
                "FileBrowsing-RuntimePanel-row-{item.id}",
                "FileBrowsing-RuntimePanel-submit",
            },
        )

    def test_does_not_mix_prefixes_between_component_types(self) -> None:
        documents = {
            "Modules/MediaLibrary/Panels.swift": """
                struct FirstPanel: View {
                    let identifierPrefix: String
                    var body: some View {
                        Button("First") {}
                            .accessibilityIdentifier("\\(identifierPrefix)-first")
                    }
                }

                struct SecondPanel: View {
                    let identifierPrefix: String
                    var body: some View {
                        Button("Second") {}
                            .accessibilityIdentifier("\\(identifierPrefix)-second")
                    }
                }
            """,
            "Apps/Enchron/PanelsHost.swift": """
                FirstPanel(identifierPrefix: "FileBrowsing-First")
                SecondPanel(identifierPrefix: "FileBrowsing-Second")
            """,
        }

        templates = inventory.runtime_identifier_templates(documents)

        self.assertEqual(
            set(templates),
            {
                "FileBrowsing-First-first",
                "FileBrowsing-Second-second",
            },
        )

    def test_expands_a_prefix_parameter_on_a_view_modifier(self) -> None:
        documents = {
            "Modules/DesignSystem/Dialogs.swift": """
                extension View {
                    func productDialog(
                        identifierPrefix: String = "DesignPreview-dialog"
                    ) -> some View {
                        alert("Failure") {
                            Button("Retry") {}
                                .accessibilityIdentifier("\\(identifierPrefix)-primary")
                        }
                    }
                }
            """,
            "Apps/Enchron/DialogHost.swift": """
                content.productDialog(identifierPrefix: "FileBrowsing-dialog")
            """,
        }

        templates = inventory.runtime_identifier_templates(documents)

        self.assertIn("FileBrowsing-dialog-primary", templates)

    def test_rejects_an_unresolved_runtime_prefix(self) -> None:
        documents = {
            "Modules/MediaLibrary/RuntimePanel.swift": """
                struct RuntimePanel: View {
                    let identifierPrefix: String
                    var body: some View {
                        Button("Submit") {}
                            .accessibilityIdentifier("\\(identifierPrefix)-submit")
                    }
                }
            """,
        }

        with self.assertRaisesRegex(
            inventory.RuntimeIdentifierResolutionError,
            r"RuntimePanel.*identifierPrefix",
        ):
            inventory.runtime_identifier_templates(documents)

    def test_rejects_an_opaque_runtime_identifier_helper(self) -> None:
        documents = {
            "Modules/MediaLibrary/RuntimePanel.swift": """
                struct RuntimePanel: View {
                    let identifierPrefix: String
                    var body: some View {
                        Button("Submit") {}
                            .accessibilityIdentifier(identifier("submit"))
                    }
                    private func identifier(_ suffix: String) -> String {
                        "\\(identifierPrefix)-\\(suffix)"
                    }
                }
            """,
            "Apps/Enchron/RuntimePanelHost.swift": """
                RuntimePanel(identifierPrefix: "FileBrowsing-RuntimePanel")
            """,
        }

        with self.assertRaisesRegex(
            inventory.RuntimeIdentifierResolutionError,
            r"RuntimePanel.*opaque helper",
        ):
            inventory.runtime_identifier_templates(documents)


class ConnectionFormInventoryTests(unittest.TestCase):
    def test_each_supported_source_has_each_interactive_child(self) -> None:
        operations = {
            operation["id"]
            for operation in inventory.build_inventory()["operations"]
        }
        expected = {
            f"accessibility:FileBrowsing-SourceConnection-{source}-{control}"
            for source, controls in {
                "smb": (
                    "name",
                    "address",
                    "username",
                    "password",
                    "guest",
                    "cancel",
                    "connect",
                ),
                "webDAV": (
                    "name",
                    "address",
                    "username",
                    "password",
                    "cancel",
                    "connect",
                ),
            }.items()
            for control in controls
        }

        self.assertEqual(
            {operation for operation in operations if "SourceConnection" in operation},
            expected,
        )


class DebugMenuEquivalentInventoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.operations = {
            operation["id"]: operation
            for operation in inventory.build_inventory()["operations"]
        }

    def test_declares_both_menu_command_verbs(self) -> None:
        self.assertIn("command:listMenuItems", self.operations)
        self.assertIn("command:selectMenuItem", self.operations)

    def test_player_item_route_names_parent_and_runtime_families(self) -> None:
        route = self.operations[
            "accessibility:PlayerPanel-menu-{category}-{item.id}"
        ]["debugEquivalent"]

        self.assertEqual(route["listVerb"], "listMenuItems")
        self.assertEqual(route["selectVerb"], "selectMenuItem")
        self.assertEqual(route["host"], "playerPanel")
        self.assertEqual(
            route["families"],
            ["subtitles", "audio", "speed", "episodes"],
        )
        self.assertEqual(
            route["parentOperation"],
            "accessibility:PlayerPanel-menu-more",
        )

    def test_nonplayer_system_pickers_use_the_same_route_shape(self) -> None:
        for operation_id in (
            "accessibility:FileBrowsing-FilesScreen-sort",
            "accessibility:Emby-Detail-Version",
            "accessibility:Emby-Season-Picker",
            "accessibility:MediaLibrary-Breadcrumb-current",
            "accessibility:FileBrowsing-SourcesSidebar-delete",
        ):
            with self.subTest(operation_id=operation_id):
                route = self.operations[operation_id]["debugEquivalent"]
                self.assertEqual(route["listVerb"], "listMenuItems")
                self.assertEqual(route["selectVerb"], "selectMenuItem")
                self.assertIn("parentOperation", route)


class MatrixBaselineExtensionTests(unittest.TestCase):
    def test_adds_only_missing_cells_as_known_defects(self) -> None:
        original_cell = {
            "operation": "accessibility:FileBrowsing-existing",
            "presentation": "window",
            "verdict": "reachable",
        }
        baseline = {
            "acceptedAt": "device-evidence-time",
            "acceptedFrom": "device-results.json",
            "schemaVersion": 1,
            "cells": [original_cell.copy()],
        }
        generated_inventory = {
            "operations": [
                {"id": "accessibility:FileBrowsing-existing"},
                {"id": "accessibility:FileBrowsing-new"},
            ]
        }

        extended = inventory.extend_matrix_baseline(
            baseline,
            generated_inventory,
            presentations=("window",),
        )

        self.assertEqual(extended["acceptedAt"], "device-evidence-time")
        self.assertEqual(extended["acceptedFrom"], "device-results.json")
        self.assertEqual(extended["cells"][0], original_cell)
        self.assertEqual(
            extended["cells"][1],
            {
                "operation": "accessibility:FileBrowsing-new",
                "presentation": "window",
                "verdict": "known-defect",
            },
        )


if __name__ == "__main__":
    unittest.main()
