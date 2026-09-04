from __future__ import annotations

from dataclasses import FrozenInstanceError
from pathlib import Path
import sys
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))

from regression.core.errors import RegressionError
from regression.core.frontmatter import parse_frontmatter


class FrontMatterTests(unittest.TestCase):
    def assert_error_code(self, source: str, expected: str) -> None:
        with self.assertRaises(RegressionError) as raised:
            parse_frontmatter(source, "fixture.md")
        self.assertEqual(raised.exception.code, expected)
        self.assertEqual(raised.exception.location, "fixture.md")

    def test_parses_json_object_and_preserves_normalized_body(self) -> None:
        source = (
            "---\r\n"
            "{\"id\":\"scenario:play-local-file\",\"lanes\":[\"simulator\"]}\r\n"
            "---\r\n"
            "# Play a local file\r\n\r\n"
            "Body text.\r\n"
        )

        document = parse_frontmatter(source, "scenario.md")

        self.assertEqual(
            document.metadata,
            {"id": "scenario:play-local-file", "lanes": ("simulator",)},
        )
        self.assertEqual(document.body, "# Play a local file\n\nBody text.\n")
        self.assertTrue(document.source_digest.startswith("sha256:"))
        with self.assertRaises(FrozenInstanceError):
            document.body = "changed"
        with self.assertRaises(TypeError):
            document.metadata["id"] = "changed"

    def test_lf_and_crlf_sources_have_the_same_digest(self) -> None:
        lf = "---\n{\"id\":\"fact:hdr-capable\"}\n---\nBody\n"
        crlf = lf.replace("\n", "\r\n")

        self.assertEqual(
            parse_frontmatter(lf, "lf.md").source_digest,
            parse_frontmatter(crlf, "crlf.md").source_digest,
        )

    def test_duplicate_keys_are_rejected_at_any_object_depth(self) -> None:
        self.assert_error_code(
            '---\n{"id":"first","nested":{"key":1,"key":2}}\n---\n',
            "frontmatter.duplicate_key",
        )

    def test_yaml_missing_boundaries_and_non_objects_are_rejected(self) -> None:
        cases = (
            ("id: scenario:yaml\n", "frontmatter.missing_opening_boundary"),
            ("---\n{\"id\":\"scenario:missing-close\"}\n", "frontmatter.missing_closing_boundary"),
            ("---\nid: scenario:yaml\n---\n", "frontmatter.invalid_json"),
            ("---\n[1,2,3]\n---\n", "frontmatter.not_object"),
        )

        for source, expected in cases:
            with self.subTest(expected=expected):
                self.assert_error_code(source, expected)

    def test_a_second_front_matter_block_is_rejected(self) -> None:
        self.assert_error_code(
            "---\n{\"id\":\"scenario:first\"}\n---\n"
            "---\n{\"id\":\"scenario:second\"}\n---\nBody\n",
            "frontmatter.multiple_blocks",
        )


if __name__ == "__main__":
    unittest.main()
