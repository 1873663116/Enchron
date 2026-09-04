#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

RULES = Path(__file__).resolve().parent
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import verify_regression_element_targeting as checker


SEEDER = 'LIBRARY_NAME = "Enchron Regression Emby"\nSERIES_NAME = "Enchron Regression Series"\n'
NOTES = "侧栏源条目之下，删除按钮、图标与文本共享同一个 identifier，因此会命中删除按钮。\n"


def call(identifier: str, *, labels=None, identifiers=None, operation=checker.ACTIVATE) -> dict:
    arguments = {}
    if labels is not None:
        arguments["labels"] = labels
    if identifiers is not None:
        arguments["identifiers"] = identifiers
    return {"callId": identifier, "operation": operation, "arguments": arguments}


class ElementTargetingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.write(f"{checker.VERIFICATION}/regression_emby_source.py", SEEDER)
        self.write(checker.PRODUCT_NOTES, NOTES)
        self.write(checker.GRID_CARD, 'case .poster: return "poster"\n')
        self.catalog([])

    def write(self, relative: str, contents: str) -> None:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")

    def catalog(self, operations: list[dict]) -> None:
        document = {"scenarios": [{"id": "scenario:probe", "operations": operations}]}
        self.write(checker.BLUEPRINT, json.dumps(document, ensure_ascii=False) + "\n")

    def test_a_seeded_name_passes(self) -> None:
        self.catalog([call("call:01", labels=["Enchron Regression Emby"])])

        self.assertEqual(checker.failures(), [])

    def test_a_card_label_with_its_variant_suffix_passes(self) -> None:
        self.write(
            checker.GRID_CARD,
            'private var variantKey: String {\n'
            '    switch variant {\n'
            '    case .poster: return "poster"\n'
            '    case .episode: return "episode"\n'
            '    }\n}\n',
        )
        self.catalog([call("call:01", labels=["Enchron Regression Emby, poster"])])

        self.assertEqual(checker.failures(), [])

    def test_a_card_label_with_an_unknown_variant_fails(self) -> None:
        self.write(
            checker.GRID_CARD,
            'private var variantKey: String {\n'
            '    switch variant {\n'
            '    case .poster: return "poster"\n'
            '    }\n}\n',
        )
        self.catalog([call("call:01", labels=["Enchron Regression Emby, banner"])])

        self.assertIn("nothing under", " ".join(checker.failures()))

    def test_a_name_nothing_seeds_fails(self) -> None:
        self.catalog([call("call:01", labels=["Enchron Regression Library"])])

        self.assertIn("nothing under", " ".join(checker.failures()))

    def test_a_name_seeded_only_inside_a_longer_literal_still_passes(self) -> None:
        self.write(
            f"{checker.VERIFICATION}/nfo.py",
            'body = "<title>Enchron Regression Episode</title>"\n',
        )
        self.catalog([call("call:01", labels=["Enchron Regression Episode"])])

        self.assertEqual(checker.failures(), [])

    def test_typed_text_may_name_something_no_fixture_seeds(self) -> None:
        self.catalog(
            [
                {
                    "callId": "call:01",
                    "operation": "operation:accessibility.type@2",
                    "arguments": {"text": "Enchron Regression WebDAV Draft"},
                }
            ]
        )

        self.assertEqual(checker.failures(), [])

    def test_an_unrelated_label_is_not_policed(self) -> None:
        self.catalog([call("call:01", labels=["Movies"])])

        self.assertEqual(checker.failures(), [])

    def test_activating_a_sidebar_source_container_fails(self) -> None:
        self.catalog(
            [call("call:01", identifiers=["FileBrowsing-SourcesSidebar-source-media-library"])]
        )

        self.assertIn("activates container", " ".join(checker.failures()))

    def test_selecting_the_same_source_by_label_passes(self) -> None:
        self.catalog([call("call:01", labels=["Media Library"])])

        self.assertEqual(checker.failures(), [])

    def test_another_operation_may_still_name_the_container(self) -> None:
        self.catalog(
            [
                call(
                    "call:01",
                    identifiers=["FileBrowsing-SourcesSidebar-source-media-library"],
                    operation="operation:accessibility.inspect@2",
                )
            ]
        )

        self.assertEqual(checker.failures(), [])

    def test_the_rule_fails_when_the_product_note_stops_recording_its_ground(self) -> None:
        self.write(checker.PRODUCT_NOTES, "侧栏源条目可以按 identifier 命中。\n")

        self.assertIn("lost its stated ground", " ".join(checker.failures()))


class RepositoryTests(unittest.TestCase):
    def test_the_emby_library_name_is_read_from_the_seeder(self) -> None:
        self.assertIn("Enchron Regression Emby", checker.seeded_names())

    def test_the_name_the_catalog_used_is_seeded_by_nobody(self) -> None:
        self.assertNotIn("Enchron Regression Library", checker.seeded_names())


if __name__ == "__main__":
    unittest.main()
