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


class UninstantiatedViewInventoryTests(unittest.TestCase):
    def test_preview_only_view_is_archived_but_production_view_remains(self) -> None:
        documents = {
            "Modules/MediaLibrary/Panels.swift": """
                struct PreviewOnlyPanel: View {
                    var body: some View {
                        Button("Dead") {}
                            .accessibilityIdentifier("FileBrowsing-PreviewOnly-dead")
                    }
                }

                struct LivePanel: View {
                    var body: some View {
                        Button("Live") {}
                            .accessibilityIdentifier("FileBrowsing-Live-action")
                    }
                }

                #Preview {
                    PreviewOnlyPanel()
                }
            """,
            "Apps/Enchron/Host.swift": """
                struct Host: View {
                    var body: some View {
                        LivePanel()
                    }
                }
            """,
        }
        identifiers = {
            template: [inventory.SourceLocation("Modules/MediaLibrary/Panels.swift", line)]
            for template, line in inventory.source_strings(documents[
                "Modules/MediaLibrary/Panels.swift"
            ])
            if template.startswith("FileBrowsing-")
        }

        archived = inventory.uninstantiated_view_identifier_owners(
            documents,
            identifiers,
        )

        self.assertEqual(
            {template: owner.name for template, owner in archived.items()},
            {"FileBrowsing-PreviewOnly-dead": "PreviewOnlyPanel"},
        )


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

    def test_certificate_decisions_are_both_operations(self) -> None:
        operations = {
            operation["id"]
            for operation in inventory.build_inventory()["operations"]
        }

        self.assertIn(
            "accessibility:FileBrowsing-CertificateTrust-trust",
            operations,
        )
        self.assertIn(
            "accessibility:FileBrowsing-CertificateTrust-cancel",
            operations,
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

    def test_settings_menu_families_are_independent_operations(self) -> None:
        expected_families = (
            "resume-strategy",
            "end-behavior",
            "default-scenic-environment",
            "default-speed",
            "controls-auto-hide",
        )

        for family in expected_families:
            operation_id = f"menu:settings:{family}"
            with self.subTest(operation_id=operation_id):
                operation = self.operations[operation_id]
                self.assertEqual(operation["proofContexts"], ["main-window-browser"])
                self.assertEqual(
                    operation["source"],
                    "Apps/Enchron/Screens/SettingsScreen.swift",
                )
                route = operation["debugEquivalent"]
                self.assertEqual(route["listVerb"], "listMenuItems")
                self.assertEqual(route["selectVerb"], "selectMenuItem")
                self.assertEqual(route["host"], "settings")
                self.assertEqual(route["families"], [family])


class RenderHostInventoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.operations = {
            operation["id"]: operation
            for operation in inventory.build_inventory()["operations"]
        }

    def test_player_panel_menu_family_is_hosted_only_by_immersive_dock_controls(self) -> None:
        for operation_id in (
            "accessibility:PlayerPanel-menu-more",
            "accessibility:PlayerPanel-menu-subtitles",
            "accessibility:PlayerPanel-menu-audio",
            "accessibility:PlayerPanel-menu-speed",
            "accessibility:PlayerPanel-menu-episodes",
            "accessibility:PlayerPanel-menu-{category}-{item.id}",
        ):
            with self.subTest(operation_id=operation_id):
                operation = self.operations[operation_id]
                self.assertEqual(operation["proofContexts"], ["panorama", "docked"])
                derivation = operation["proofContextDerivation"]
                self.assertEqual(derivation["host"], "playerControlDockControls")
                self.assertTrue(
                    any(
                        source["path"]
                        == "Modules/PlaybackPresentation/Views/PlaybackPanel.swift"
                        for source in derivation["sources"]
                    )
                )

    def test_browser_content_operations_are_hosted_only_by_browser_window(self) -> None:
        for operation_id, operation in self.operations.items():
            if operation_id.startswith(
                (
                    "accessibility:Emby-",
                    "accessibility:FileBrowsing-",
                    "accessibility:MediaLibrary-",
                    "accessibility:Navigation-",
                    "accessibility:Settings-",
                )
            ):
                with self.subTest(operation_id=operation_id):
                    self.assertEqual(
                        operation["proofContexts"], ["main-window-browser"]
                    )
                    self.assertEqual(
                        operation["proofContextDerivation"]["host"],
                        "browserWindowSurface",
                    )

    def test_unknown_product_family_fails_instead_of_defaulting_to_all_presentations(self) -> None:
        documents = {
            "Modules/PlaybackPresentation/Model/PlaybackPresentation.swift": """
                enum PlaybackPresentation {
                    var usesMainWindow: Bool { self == .window || self == .portal }
                    var usesImmersiveSpace: Bool { self == .docked || self == .panorama }
                }
            """,
        }

        with self.assertRaisesRegex(
            inventory.PresentationDerivationError,
            "cannot derive a production presentation host",
        ):
            inventory.presentation_derivation("UnknownFamily-action", documents)

    def test_playback_issue_action_identifiers_follow_their_actual_alert_locations(self) -> None:
        self.assertEqual(
            self.operations["accessibility:PlayerUI-loadFailure-secondary"][
                "proofContexts"
            ],
            ["window", "portal"],
        )
        self.assertEqual(
            self.operations["accessibility:PlayerUI-spatialFailure-secondary"][
                "proofContexts"
            ],
            ["panorama", "docked"],
        )
        self.assertNotIn(
            "accessibility:PlayerUI-playbackIssue-primary",
            self.operations,
        )
        self.assertEqual(
            self.operations[
                "accessibility:PlayerUI-presentation-conversion-dismiss"
            ]["proofContexts"],
            ["main-window-browser"],
        )


class ProofContextInventoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.operations = {
            operation["id"]: operation
            for operation in inventory.build_inventory()["operations"]
        }

    def test_browser_operations_have_one_main_window_browser_context(self) -> None:
        operation = self.operations[
            "accessibility:FileBrowsing-SourceConnection-smb-connect"
        ]

        self.assertEqual(operation["proofDomain"], "browser")
        self.assertEqual(operation["proofContexts"], ["main-window-browser"])
        self.assertEqual(
            operation["proofContextDerivation"]["host"],
            "browserWindowSurface",
        )
        self.assertNotIn("presentations", operation)

    def test_playback_operations_keep_each_rendered_presentation_context(self) -> None:
        operation = self.operations["accessibility:PlayerPanel-menu-more"]

        self.assertEqual(operation["proofDomain"], "playback")
        self.assertEqual(operation["proofContexts"], ["panorama", "docked"])
        self.assertEqual(
            operation["proofContextDerivation"]["host"],
            "playerControlDockControls",
        )

    def test_presentation_entry_controls_belong_to_the_host_that_renders_them(self) -> None:
        for operation_id in (
            "accessibility:PlayerUI-TopAction-dock",
            "accessibility:PlayerUI-DockMenu-skybox",
            "accessibility:PlayerUI-DockMenu-{$0.rawValue}",
        ):
            with self.subTest(operation_id=operation_id):
                self.assertEqual(
                    self.operations[operation_id]["proofContexts"],
                    ["window"],
                )
        self.assertEqual(
            self.operations["accessibility:PlayerUI-TopAction-resumePanorama"][
                "proofContexts"
            ],
            ["portal"],
        )

    def test_shared_menu_commands_cover_browser_and_playback_contexts(self) -> None:
        for operation_id in ("command:listMenuItems", "command:selectMenuItem"):
            with self.subTest(operation_id=operation_id):
                operation = self.operations[operation_id]
                self.assertEqual(operation["proofDomain"], "shared")
                self.assertEqual(
                    operation["proofContexts"],
                    [
                        "main-window-browser",
                        "window",
                        "portal",
                        "panorama",
                        "docked",
                    ],
                )

    def test_every_operation_has_a_nondefaulted_proof_context_derivation(self) -> None:
        for operation_id, operation in self.operations.items():
            with self.subTest(operation_id=operation_id):
                self.assertIn(operation["proofDomain"], {"browser", "playback", "shared"})
                self.assertIsInstance(operation["proofContexts"], list)
                self.assertTrue(operation["proofContexts"])
                derivation = operation["proofContextDerivation"]
                self.assertTrue(derivation["host"])
                self.assertTrue(derivation["sources"])

    def test_uninstantiated_identifiers_are_not_operations(self) -> None:
        uninstantiated = {
            record["template"]: record
            for record in inventory.build_inventory()["identifiers"]
            if record["role"] == "uninstantiated-identifier"
        }

        self.assertEqual(
            set(uninstantiated),
            {
                "FileBrowsing-Breadcrumb-button-{segment.index}",
                "FileBrowsing-FolderList-button-file-{file.id}",
                "FileBrowsing-FolderList-button-folder-{folder.id}",
                "FileBrowsing-Sidebar-row-local",
                "FileBrowsing-Sidebar-row-{ds.id}",
                "PlayerPanel-VideoFormat-CustomAngle",
                "PlayerPanel-VideoFormat-HDRFallback",
                "PlayerPanel-VideoFormat-apply",
                "PlayerPanel-VideoFormat-automatic",
                "PlayerPanel-VideoFormat-cancel",
                "PlayerPanel-VideoFormat-{title}-{label(option)}",
                "PlayerUI-playbackIssue-primary",
                "PlayerUI-playbackIssue-secondary",
            },
        )
        self.assertTrue(
            all(record["renderDerivation"]["sources"] for record in uninstantiated.values())
        )


class MatrixProofContextMigrationTests(unittest.TestCase):
    def test_migrates_browser_once_and_playback_only_where_rendered(self) -> None:
        old = {
            "schemaVersion": 1,
            "cells": [
                {
                    "operation": "accessibility:FileBrowsing-FilesScreen-search",
                    "presentation": presentation,
                    "verdict": "reachable" if presentation == "window" else "not-applicable",
                }
                for presentation in inventory.PRESENTATIONS
            ] + [
                {
                    "operation": "accessibility:PlayerPanel-menu-more",
                    "presentation": presentation,
                    "verdict": "reachable" if presentation == "panorama" else "known-defect",
                }
                for presentation in inventory.PRESENTATIONS
            ],
        }
        generated = {
            "operations": [
                {
                    "id": "accessibility:FileBrowsing-FilesScreen-search",
                    "proofContexts": ["main-window-browser"],
                    "proofDomain": "browser",
                },
                {
                    "id": "accessibility:PlayerPanel-menu-more",
                    "proofContexts": ["panorama", "docked"],
                    "proofDomain": "playback",
                },
            ],
        }

        migrated, report = inventory.migrate_matrix_baseline(old, generated)

        self.assertEqual(
            migrated["cells"],
            [
                {
                    "context": "main-window-browser",
                    "operation": "accessibility:FileBrowsing-FilesScreen-search",
                    "verdict": "reachable",
                },
                {
                    "context": "panorama",
                    "operation": "accessibility:PlayerPanel-menu-more",
                    "verdict": "reachable",
                },
                {
                    "context": "docked",
                    "operation": "accessibility:PlayerPanel-menu-more",
                    "verdict": "known-defect",
                },
            ],
        )
        self.assertEqual(report["oldCellCount"], 8)
        self.assertEqual(report["newDecisionCount"], 3)
        self.assertEqual(report["removedNotApplicableCount"], 3)
        self.assertEqual(report["mappedReachableCount"], 2)
        self.assertEqual(report["reachableRegressionCount"], 0)

    def test_rehomes_a_reachable_old_cell_from_its_wrong_target_context(self) -> None:
        old = {
            "schemaVersion": 1,
            "cells": [{
                "operation": "accessibility:PlayerUI-TopAction-more",
                "presentation": "docked",
                "verdict": "reachable",
            }],
        }
        generated = {
            "operations": [{
                "id": "accessibility:PlayerUI-TopAction-more",
                "proofContexts": ["window", "portal"],
                "proofDomain": "playback",
            }],
        }

        migrated, report = inventory.migrate_matrix_baseline(old, generated)

        self.assertEqual(
            migrated["cells"],
            [
                {
                    "context": "window",
                    "operation": "accessibility:PlayerUI-TopAction-more",
                    "verdict": "reachable",
                },
                {
                    "context": "portal",
                    "operation": "accessibility:PlayerUI-TopAction-more",
                    "verdict": "known-defect",
                },
            ],
        )
        self.assertEqual(report["mappedReachableCount"], 1)
        self.assertEqual(report["mappedReachableDecisionCount"], 1)
        self.assertEqual(report["retiredReachableCount"], 0)
        self.assertEqual(
            report["remappedReachableCells"],
            [{
                "operation": "accessibility:PlayerUI-TopAction-more",
                "presentation": "docked",
                "context": "window",
                "reason": "legacy-cell-used-target-presentation-instead-of-render-host",
            }],
        )


class MatrixBaselineExtensionTests(unittest.TestCase):
    def test_adds_only_missing_cells_as_known_defects(self) -> None:
        original_cell = {
            "operation": "accessibility:FileBrowsing-existing",
            "context": "main-window-browser",
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
                {
                    "id": "accessibility:FileBrowsing-existing",
                    "proofContexts": ["main-window-browser"],
                },
                {
                    "id": "accessibility:FileBrowsing-new",
                    "proofContexts": ["main-window-browser"],
                },
            ]
        }

        extended = inventory.extend_matrix_baseline(
            baseline,
            generated_inventory,
        )

        self.assertEqual(extended["acceptedAt"], "device-evidence-time")
        self.assertEqual(extended["acceptedFrom"], "device-results.json")
        self.assertEqual(extended["cells"][0], original_cell)
        self.assertEqual(
            extended["cells"][1],
            {
                "operation": "accessibility:FileBrowsing-new",
                "context": "main-window-browser",
                "verdict": "known-defect",
            },
        )

    def test_does_not_create_filler_for_contexts_outside_the_contract(self) -> None:
        baseline = {
            "schemaVersion": 1,
            "cells": [],
        }
        generated_inventory = {
            "operations": [
                {
                    "id": "menu:settings:resume-strategy",
                    "proofContexts": ["main-window-browser"],
                }
            ]
        }

        extended = inventory.extend_matrix_baseline(
            baseline,
            generated_inventory,
        )

        self.assertEqual(
            extended["cells"],
            [{
                "context": "main-window-browser",
                "operation": "menu:settings:resume-strategy",
                "verdict": "known-defect",
            }],
        )


class InteractiveEvidenceTests(unittest.TestCase):
    """A control is an operation when the interaction is attached to it, not
    when one merely happens to sit nearby."""

    ATTACHED = """
struct Well: View {
    var body: some View {
        Text(name)
            .contentShape(.interaction, shape)
            .onTapGesture {
                toggleMediaInformation()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("Panel-well")
    }
}
"""

    NEARBY = """
struct Toolbar: View {
    var body: some View {
        HStack {
            Button("Done") {
                finish()
            }
            Text(countLabel)
                .accessibilityIdentifier("Toolbar-count")
        }
    }
}
"""

    def line_of(self, text: str, needle: str) -> int:
        for number, line in enumerate(text.splitlines(), start=1):
            if needle in line:
                return number
        raise AssertionError(f"{needle!r} not in the fixture")

    def test_modifier_on_the_identified_element_is_attached(self) -> None:
        line = self.line_of(self.ATTACHED, "Panel-well")

        self.assertEqual(
            inventory.interactive_evidence(self.ATTACHED, line),
            ("attached", ".onTapGesture {"),
        )

    def test_sibling_control_is_only_nearby(self) -> None:
        line = self.line_of(self.NEARBY, "Toolbar-count")
        found = inventory.interactive_evidence(self.NEARBY, line)

        self.assertIsNotNone(found)
        self.assertEqual(found[0], "nearby")

    def test_a_label_with_no_interaction_has_no_evidence(self) -> None:
        text = 'Text(name)\n    .accessibilityIdentifier("Plain-label")\n'
        line = self.line_of(text, "Plain-label")

        self.assertIsNone(inventory.interactive_evidence(text, line))

    def test_attachment_survives_a_reviewed_observation_entry(self) -> None:
        """REVIEWED_OBSERVATIONS silences the `nearby` question. It must never be
        able to silence an interaction attached to the element itself, because
        that is the one case where the source has already answered."""
        line = self.line_of(self.ATTACHED, "Panel-well")

        self.assertEqual(
            inventory.interactive_evidence(self.ATTACHED, line)[0], "attached"
        )
        self.assertNotIn("Panel-well", inventory.REVIEWED_OBSERVATIONS)


class ProductInventoryInteractiveTests(unittest.TestCase):
    def test_the_committed_inventory_files_no_attached_control_as_observation(
        self,
    ) -> None:
        built = inventory.build_inventory()
        flagged = [
            record["template"]
            for record in built["identifiers"]
            if "interactiveEvidence" in record
        ]

        self.assertEqual(flagged, [])

    def test_the_media_information_well_is_an_operation(self) -> None:
        built = inventory.build_inventory()
        roles = {record["template"]: record["role"] for record in built["identifiers"]}

        self.assertEqual(roles["PlayerPanel-media-information"], "operation")


if __name__ == "__main__":
    unittest.main()
