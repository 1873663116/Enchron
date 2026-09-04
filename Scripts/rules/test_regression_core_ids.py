from __future__ import annotations

import ast
from pathlib import Path
import sys
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))

from regression.core.digest import (
    canonical_bytes,
    canonical_digest,
    digest_bytes,
    digest_text_file,
    normalize_text_bytes,
)
from regression.core.errors import RegressionError
from regression.core.ids import (
    CallID,
    CaseKey,
    EvidenceSchema,
    EvidenceType,
    IDENTIFIER_PATTERNS,
    StateKey,
    StateSchema,
    parse_identifier,
)


class IdentifierTests(unittest.TestCase):
    def test_every_identifier_kind_accepts_its_canonical_form(self) -> None:
        examples = {
            "promise": "promise:playback:c01",
            "journey": "journey:open-local-media",
            "scenario": "scenario:open-local-media:play-local-file",
            "obligation": "obligation:open-local-media:play-local-file:o01",
            "preparation": "preparation:installed-clean-build",
            "call": "call:open-local-media:observe-first-frame",
            "case_key": "first-frame",
            "evidence_type": "ui.screenshot",
            "evidence_schema": "ui.screenshot@1",
            "state_key": "library-ready",
            "state_schema": "enchron.state.library-ready@1",
            "operation": "operation:playback.open-local-file@1",
            "oracle": "oracle:pixel-region-match@1",
            "rubric": "rubric:playback-first-frame@1",
            "fact": "fact:media-library.has-hdr",
            "state_tag": "app.installed-build",
            "node": "node:play-local-file",
            "run": "run:20260828t140501z-a7f2",
            "lease": "lease:play-local-file-01",
            "grant": "grant:open-local-file-01",
            "sidekick": "sidekick:simulator-01",
            "review_packet": "review-packet:playback-coverage",
            "digest": "sha256:" + "a" * 64,
        }

        self.assertEqual(set(examples), set(IDENTIFIER_PATTERNS))
        for kind, value in examples.items():
            with self.subTest(kind=kind):
                parsed = parse_identifier(kind, value, "fixture")
                self.assertEqual(parsed, value)
                self.assertIsInstance(parsed, str)

    def test_promise_is_a_commitment_and_operation_has_a_major_version(self) -> None:
        invalid = (
            ("promise", "promise:playback"),
            ("promise", "promise:Playback:c01"),
            ("promise", "promise:playback:c1"),
            ("call", "observe-first-frame"),
            ("call", "call:Open:first-frame"),
            ("evidence_type", "UI.screenshot"),
            ("evidence_type", "ui/screenshot"),
            ("evidence_schema", "ui.screenshot"),
            ("evidence_schema", "ui.screenshot@0"),
            ("case_key", "First-Frame"),
            ("state_key", "library.ready"),
            ("state_schema", "enchron.state.library-ready"),
            ("state_schema", "enchron.state.library-ready@0"),
            ("state_schema", "Enchron.state.library-ready@1"),
            ("operation", "operation:playback.open-local-file"),
            ("operation", "operation:playback/open-local-file@1"),
            ("operation", "operation:playback.open-local-file@01"),
            ("oracle", "oracle:pixel-region-match"),
            ("rubric", "rubric:playback-first-frame"),
            ("state_tag", "state:installed-build"),
            ("digest", "sha256:" + "A" * 64),
        )

        for kind, value in invalid:
            with self.subTest(kind=kind, value=value):
                with self.assertRaises(RegressionError) as raised:
                    parse_identifier(kind, value, "contract.id")
                self.assertEqual(raised.exception.code, "identifier.invalid_format")
                self.assertEqual(raised.exception.location, "contract.id")

    def test_call_case_and_evidence_identifiers_are_nominal_types(self) -> None:
        call = parse_identifier("call", "call:playback:start:observe", "fixture")
        evidence_type = parse_identifier(
            "evidence_type", "ui.accessibility.snapshot", "fixture"
        )
        evidence_schema = parse_identifier(
            "evidence_schema", "ui.accessibility.snapshot@2", "fixture"
        )
        case_key = parse_identifier("case_key", "default", "fixture")

        self.assertEqual(call, "call:playback:start:observe")
        self.assertEqual(evidence_type, "ui.accessibility.snapshot")
        self.assertEqual(evidence_schema, "ui.accessibility.snapshot@2")
        self.assertEqual(case_key, "default")
        self.assertIs(CallID.__supertype__, str)
        self.assertIs(CaseKey.__supertype__, str)
        self.assertIs(EvidenceSchema.__supertype__, str)
        self.assertIs(EvidenceType.__supertype__, str)

    def test_state_keys_and_schemas_are_nominal_types(self) -> None:
        key = parse_identifier("state_key", "library-ready", "fixture")
        schema = parse_identifier(
            "state_schema", "enchron.state.library-ready@1", "fixture"
        )

        self.assertEqual(key, "library-ready")
        self.assertEqual(schema, "enchron.state.library-ready@1")
        self.assertIs(StateKey.__supertype__, str)
        self.assertIs(StateSchema.__supertype__, str)

    def test_unknown_kind_and_non_string_have_stable_error_codes(self) -> None:
        with self.assertRaises(RegressionError) as raised:
            parse_identifier("observation", "observation:first-frame", "fixture")
        self.assertEqual(raised.exception.code, "identifier.unknown_kind")

        with self.assertRaises(RegressionError) as raised:
            parse_identifier("scenario", 42, "fixture")
        self.assertEqual(raised.exception.code, "identifier.not_string")


class DigestTests(unittest.TestCase):
    def test_canonical_json_is_independent_of_key_order(self) -> None:
        left = {"z": [3, 2, 1], "a": {"enabled": True, "name": "播放"}}
        right = {"a": {"name": "播放", "enabled": True}, "z": [3, 2, 1]}

        self.assertEqual(canonical_bytes(left), canonical_bytes(right))
        self.assertEqual(canonical_digest(left), canonical_digest(right))
        self.assertTrue(canonical_digest(left).startswith("sha256:"))

    def test_canonical_json_rejects_non_finite_numbers(self) -> None:
        for value in (float("nan"), float("inf"), -float("inf")):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    canonical_bytes({"value": value})

    def test_text_digest_normalizes_crlf_and_lf(self) -> None:
        lf = b"first\nsecond\n"
        crlf = b"first\r\nsecond\r\n"

        self.assertEqual(normalize_text_bytes(crlf), lf)
        self.assertEqual(digest_bytes(normalize_text_bytes(crlf)), digest_bytes(lf))

    def test_digest_text_file_normalizes_line_endings(self) -> None:
        from tempfile import TemporaryDirectory

        with TemporaryDirectory() as directory:
            lf_path = Path(directory) / "lf.md"
            crlf_path = Path(directory) / "crlf.md"
            lf_path.write_bytes(b"alpha\nbeta\n")
            crlf_path.write_bytes(b"alpha\r\nbeta\r\n")

            self.assertEqual(digest_text_file(lf_path), digest_text_file(crlf_path))

    def test_sources_parse_with_python_3_9_grammar(self) -> None:
        paths = (
            REPOSITORY_ROOT / "Scripts/regression/core/ids.py",
            REPOSITORY_ROOT / "Scripts/regression/core/digest.py",
            REPOSITORY_ROOT / "Scripts/regression/core/frontmatter.py",
            REPOSITORY_ROOT / "Scripts/regression/core/contracts.py",
            REPOSITORY_ROOT / "Scripts/regression/core/catalog.py",
        )

        for path in paths:
            with self.subTest(path=path):
                ast.parse(path.read_text(encoding="utf-8"), feature_version=(3, 9))


if __name__ == "__main__":
    unittest.main()
