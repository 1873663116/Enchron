#!/usr/bin/env python3

from __future__ import annotations

import unittest

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


if __name__ == "__main__":
    unittest.main()
