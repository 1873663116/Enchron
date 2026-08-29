#!/usr/bin/env python3

from __future__ import annotations

import ast
from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.contracts import BoundLane
from regression.core.errors import RegressionError
from regression.core.ids import Digest, NodeID, StateKey, StateSchema, StateTag
from regression.core.state import EpochTable, StateHandle, TagEpoch, capture_state_handle


class EpochTableTests(unittest.TestCase):
    def test_only_declared_tags_advance_once(self) -> None:
        initial = EpochTable.from_mapping(
            {StateTag("library.content"): 4, StateTag("playback.session"): 2}
        )
        transition = initial.advance(
            (StateTag("library.content"), StateTag("library.content"))
        )
        self.assertEqual(5, transition.table.value(StateTag("library.content")))
        self.assertEqual(2, transition.table.value(StateTag("playback.session")))
        self.assertEqual(1, len(transition.advances))

    def test_unknown_tag_starts_at_zero_and_advances_to_one(self) -> None:
        transition = EpochTable().advance((StateTag("playback.session"),))
        self.assertEqual(1, transition.table.value(StateTag("playback.session")))
        self.assertEqual((0, 1), (transition.advances[0].before, transition.advances[0].after))

    def test_epoch_table_rejects_duplicate_and_unsorted_tags(self) -> None:
        with self.assertRaises(RegressionError) as duplicate:
            EpochTable(
                (
                    TagEpoch(StateTag("app.process"), 0),
                    TagEpoch(StateTag("app.process"), 1),
                )
            )
        self.assertEqual("epoch.duplicate_tag", duplicate.exception.code)
        with self.assertRaises(RegressionError) as unsorted:
            EpochTable(
                (
                    TagEpoch(StateTag("state.z"), 0),
                    TagEpoch(StateTag("state.a"), 0),
                )
            )
        self.assertEqual("epoch.unsorted_tags", unsorted.exception.code)

    def test_epoch_rejects_boolean_negative_and_non_integer_values(self) -> None:
        for value in (True, -1, 1.5):
            with self.subTest(value=value), self.assertRaises(RegressionError) as found:
                TagEpoch(StateTag("app.process"), value)
            self.assertEqual("epoch.invalid_value", found.exception.code)


class StateHandleTests(unittest.TestCase):
    key = StateKey("library-ready")
    schema = StateSchema("enchron.library-ready@1")
    node = NodeID("node:preparation:library-ready")

    def test_related_advance_invalidates_handle(self) -> None:
        initial = EpochTable.from_mapping(
            {StateTag("library.content"): 3, StateTag("playback.session"): 8}
        )
        handle = capture_state_handle(
            self.key,
            self.schema,
            BoundLane.SIMULATOR,
            self.node,
            initial,
            (StateTag("library.content"),),
            Digest("sha256:" + "a" * 64),
        )
        changed = initial.advance((StateTag("library.content"),)).table
        self.assertFalse(
            handle.is_valid(self.key, self.schema, BoundLane.SIMULATOR, changed)
        )

    def test_unrelated_advance_preserves_handle(self) -> None:
        initial = EpochTable.from_mapping(
            {StateTag("library.content"): 3, StateTag("playback.session"): 8}
        )
        handle = capture_state_handle(
            self.key,
            self.schema,
            BoundLane.SIMULATOR,
            self.node,
            initial,
            (StateTag("library.content"),),
            Digest("sha256:" + "b" * 64),
        )
        changed = initial.advance((StateTag("playback.session"),)).table
        self.assertTrue(
            handle.is_valid(self.key, self.schema, BoundLane.SIMULATOR, changed)
        )

    def test_handle_never_crosses_lanes(self) -> None:
        handle = StateHandle(
            self.key,
            self.schema,
            BoundLane.DEVICE,
            self.node,
            EpochTable.from_mapping({StateTag("library.content"): 0}),
            Digest("sha256:" + "c" * 64),
        )
        self.assertFalse(
            handle.is_valid(
                self.key,
                self.schema,
                BoundLane.SIMULATOR,
                EpochTable(),
            )
        )

    def test_key_schema_and_producer_are_bound_into_handle(self) -> None:
        handle = capture_state_handle(
            self.key,
            self.schema,
            BoundLane.SIMULATOR,
            self.node,
            EpochTable(),
            (StateTag("library.content"),),
            Digest("sha256:" + "d" * 64),
        )
        self.assertEqual(self.node, handle.produced_by_node)
        self.assertFalse(
            handle.is_valid(
                StateKey("different-state"),
                self.schema,
                BoundLane.SIMULATOR,
                EpochTable(),
            )
        )
        self.assertFalse(
            handle.is_valid(
                self.key,
                StateSchema("enchron.library-ready@2"),
                BoundLane.SIMULATOR,
                EpochTable(),
            )
        )

    def test_state_handle_rejects_empty_dependencies_and_bad_digest(self) -> None:
        with self.assertRaises(RegressionError) as empty:
            StateHandle(
                self.key,
                self.schema,
                BoundLane.SIMULATOR,
                self.node,
                EpochTable(),
                Digest("sha256:" + "e" * 64),
            )
        self.assertEqual("state.empty_dependencies", empty.exception.code)

        with self.assertRaises(RegressionError) as digest_error:
            StateHandle(
                self.key,
                self.schema,
                BoundLane.SIMULATOR,
                self.node,
                EpochTable.from_mapping({StateTag("library.content"): 0}),
                Digest("not-a-digest"),
            )
        self.assertEqual("identifier.invalid_format", digest_error.exception.code)

    def test_state_module_parses_as_python_39(self) -> None:
        path = SCRIPTS / "regression/core/state.py"
        ast.parse(path.read_text(encoding="utf-8"), feature_version=(3, 9))


if __name__ == "__main__":
    unittest.main()
