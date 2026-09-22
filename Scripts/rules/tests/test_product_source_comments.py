#!/usr/bin/env python3

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import verify_product_source_comments as comments


class SwiftCommentScannerTests(unittest.TestCase):
    def test_finds_line_and_nested_block_comments(self) -> None:
        source = "let a = 1 // narration\n/* outer /* nested */ end */\n"
        self.assertEqual(
            [(item.line, item.column, item.token) for item in comments.swift_comments(source)],
            [(1, 11, "//"), (2, 1, "/*")],
        )

    def test_ignores_comment_tokens_inside_swift_strings(self) -> None:
        source = """let range = \"bytes */10\"
let url = \"https://example.invalid/path\"
let raw = #\"/* still text */\"#
let multiline = \"\"\"
// still text
\"\"\"
"""
        self.assertEqual(comments.swift_comments(source), ())

    def test_reports_comment_after_multiline_string_at_the_real_line(self) -> None:
        source = 'let value = """\na\n"""\n// forbidden\n'
        self.assertEqual(comments.swift_comments(source)[0].line, 4)

    def test_current_product_sources_are_comment_free(self) -> None:
        self.assertEqual(comments.violations(comments.product_sources()), [])


class PythonCommentScannerTests(unittest.TestCase):
    def test_finds_full_line_and_trailing_comments(self) -> None:
        source = "x = 1\n# narration\ny = 2  # trailing\n"
        self.assertEqual(
            [(item.line, item.column, item.token) for item in comments.python_comments(source)],
            [(2, 1, "#"), (3, 8, "#")],
        )

    def test_ignores_hash_inside_strings_and_the_shebang(self) -> None:
        source = (
            "#!/usr/bin/env python3\n"
            "color = '#ffffff'\n"
            'text = """\n# not a comment\n"""\n'
            "tag = f'#{color}'\n"
        )
        self.assertEqual(comments.python_comments(source), ())

    def test_shebang_only_counts_on_the_first_line(self) -> None:
        source = "x = 1\n#!/usr/bin/env python3\n"
        self.assertEqual(comments.python_comments(source)[0].line, 2)

    def test_untokenizable_source_is_reported_not_skipped(self) -> None:
        source = "x = (\n"
        found = comments.python_comments(source)
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].token.startswith("untokenizable"))

    def test_current_script_sources_are_comment_free(self) -> None:
        self.assertEqual(comments.violations(comments.script_sources()), [])


class CCommentScannerTests(unittest.TestCase):
    def test_finds_line_and_block_comments(self) -> None:
        source = "int a = 1; // narration\n/* block\nspanning */\nint b = 2;\n"
        self.assertEqual(
            [(item.line, item.column, item.token) for item in comments.c_comments(source)],
            [(1, 12, "//"), (2, 1, "/*")],
        )

    def test_ignores_comment_tokens_inside_strings_and_character_literals(self) -> None:
        source = 'const char *a = "// not a comment";\n' \
            'const char *b = "/* also not */";\n' \
            "char quote = '\"';\n" \
            'const char *c = "escaped \\" still string // here";\n'
        self.assertEqual(comments.c_comments(source), ())

    def test_reports_comment_after_a_multiline_block_at_the_real_line(self) -> None:
        source = "/* one\ntwo\nthree */\n// forbidden\n"
        self.assertEqual(comments.c_comments(source)[1].line, 4)

    def test_block_comments_do_not_nest_in_c(self) -> None:
        source = "/* outer /* inner */\nint after = 1;\n// second\n"
        found = comments.c_comments(source)
        self.assertEqual([(item.line, item.token) for item in found], [(1, "/*"), (3, "//")])

    def test_current_bridge_sources_are_comment_free(self) -> None:
        self.assertEqual(comments.violations(comments.bridge_sources()), [])


class ManifestDirectiveTests(unittest.TestCase):
    def test_swift_tools_version_on_the_first_line_is_a_directive(self) -> None:
        source = "// swift-tools-version: 6.2\nimport PackageDescription\n"
        self.assertEqual(comments.swift_comments(source), ())

    def test_swift_tools_version_below_the_first_line_is_a_comment(self) -> None:
        source = "import PackageDescription\n// swift-tools-version: 6.2\n"
        self.assertEqual(comments.swift_comments(source)[0].line, 2)

    def test_a_first_line_comment_that_is_not_the_directive_is_a_comment(self) -> None:
        source = "// swift tools are great\nimport PackageDescription\n"
        self.assertEqual(comments.swift_comments(source)[0].line, 1)

    def test_every_manifest_declares_the_directive_it_is_exempted_for(self) -> None:
        for manifest in comments.SWIFT_MANIFESTS:
            with self.subTest(manifest=manifest.name):
                first = manifest.read_text(encoding="utf-8").splitlines()[0]
                self.assertTrue(first.startswith(comments.TOOLS_VERSION))


class ScopeTests(unittest.TestCase):
    def test_no_inspected_path_crosses_an_excluded_segment(self) -> None:
        inspected = (
            comments.product_sources() + comments.bridge_sources() + comments.script_sources()
        )
        self.assertNotEqual(inspected, ())
        for path in inspected:
            relative = path.relative_to(comments.REPOSITORY_ROOT)
            self.assertEqual(comments.EXCLUDED_SEGMENTS.intersection(relative.parts), set())

    def test_vendored_headers_exist_and_are_excluded(self) -> None:
        vendored = tuple(
            (comments.REPOSITORY_ROOT / "Packages/PlaybackCore/Vendor").rglob("*.h")
        )
        self.assertNotEqual(vendored, ())
        for path in vendored:
            self.assertFalse(comments.owned(path))

    def test_scope_is_decided_without_running_a_subprocess(self) -> None:
        self.assertFalse(hasattr(comments, "subprocess"))
        source = comments.REPOSITORY_ROOT / "Scripts/rules/verify_product_source_comments.py"
        self.assertNotIn("subprocess", source.read_text(encoding="utf-8"))

    def test_an_excluded_segment_anywhere_in_the_path_disowns_the_file(self) -> None:
        for segment in sorted(comments.EXCLUDED_SEGMENTS):
            with self.subTest(segment=segment):
                buried = comments.REPOSITORY_ROOT / "Modules" / segment / "Buried.swift"
                self.assertFalse(comments.owned(buried))

    def test_the_c_bridge_and_the_probes_are_both_inspected(self) -> None:
        names = {path.name for path in comments.bridge_sources()}
        self.assertIn("PlaybackFFmpegBridge.c", names)
        self.assertIn("dolby_vision_premise_probe.c", names)


if __name__ == "__main__":
    unittest.main()
