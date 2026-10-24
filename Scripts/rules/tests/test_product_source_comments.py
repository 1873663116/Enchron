#!/usr/bin/env python3

from __future__ import annotations

import sys
import tempfile
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

    def test_current_first_party_files_are_comment_free(self) -> None:
        paths = comments.first_party_files()
        self.assertGreater(len(paths), 1000)
        self.assertEqual(comments.violations(paths), [])

    def test_no_first_party_file_carries_an_unregistered_license_header(self) -> None:
        self.assertEqual(comments.unregistered_license_headers(comments.first_party_files()), [])


class ShellCommentTests(unittest.TestCase):
    def test_finds_full_line_and_trailing_comments(self) -> None:
        source = "#!/bin/sh\necho hi\n# note\necho ok  # beside\n"
        found = comments.shell_comments(source)
        self.assertEqual([(c.line, c.column) for c in found], [(3, 1), (4, 10)])

    def test_the_shebang_is_a_machine_instruction(self) -> None:
        self.assertEqual(comments.shell_comments("#!/bin/zsh\necho ok\n"), ())

    def test_a_parameter_expansion_is_not_a_comment(self) -> None:
        source = 'value=${name#prefix}\ncount=${#items[@]}\n'
        self.assertEqual(comments.shell_comments(source), ())

    def test_a_hash_inside_quotes_is_text(self) -> None:
        self.assertEqual(comments.shell_comments('echo "a # b"\n'), ())


class YamlCommentTests(unittest.TestCase):
    def test_finds_a_comment_only_after_whitespace(self) -> None:
        self.assertEqual(len(comments.yaml_comments("key: value # note\n")), 1)
        self.assertEqual(comments.yaml_comments("key: a#b\n"), ())

    def test_a_block_scalar_body_is_not_a_comment(self) -> None:
        source = "script: |\n  echo one\n  # this is text\nnext: value\n"
        self.assertEqual(comments.yaml_comments(source), ())


class JsonCommentTests(unittest.TestCase):
    def test_finds_a_line_comment_outside_a_string(self) -> None:
        self.assertEqual(len(comments.json_comments('{"a": 1} // note\n')), 1)

    def test_a_url_inside_a_string_is_not_a_comment(self) -> None:
        self.assertEqual(comments.json_comments('{"url": "https://example.invalid/a"}\n'), ())


class PlistCommentTests(unittest.TestCase):
    def test_finds_an_xml_comment(self) -> None:
        self.assertEqual(len(comments.xml_comments("<plist>\n<!-- note -->\n</plist>\n")), 1)


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
        manifests = tuple(
            path for path in comments.first_party_files() if path.name == "Package.swift"
        )
        self.assertGreaterEqual(len(manifests), 5)
        for manifest in manifests:
            with self.subTest(manifest=manifest.name):
                first = manifest.read_text(encoding="utf-8").splitlines()[0]
                self.assertTrue(first.startswith(comments.TOOLS_VERSION))


class ScopeTests(unittest.TestCase):
    def test_every_inspected_file_is_first_party_text(self) -> None:
        inspected = comments.first_party_files()
        self.assertGreater(len(inspected), 1000)
        prefixes = comments.third_party_prefixes()
        self.assertNotEqual(prefixes, ())
        for path in inspected:
            relative = path.relative_to(comments.REPOSITORY_ROOT).as_posix()
            self.assertIn(path.suffix, comments.SCANNED_SUFFIXES)
            self.assertFalse(
                any(relative.startswith(prefix) for prefix in prefixes), relative
            )

    def test_vendored_headers_exist_and_are_excluded(self) -> None:
        vendored = tuple(
            (comments.REPOSITORY_ROOT / "Packages/PlaybackCore/Vendor").rglob("*.h")
        )
        self.assertNotEqual(vendored, ())
        inspected = set(comments.first_party_files())
        for path in vendored:
            self.assertNotIn(path, inspected)

    def test_scope_is_decided_without_running_a_subprocess(self) -> None:
        self.assertFalse(hasattr(comments, "subprocess"))
        source = comments.REPOSITORY_ROOT / "Scripts/rules/verify_product_source_comments.py"
        self.assertNotIn("subprocess", source.read_text(encoding="utf-8"))

    def test_generated_artifacts_are_excluded(self) -> None:
        inspected = {path.as_posix() for path in comments.first_party_files()}
        self.assertFalse(any("/TestEvidence/" in path for path in inspected))
        self.assertFalse(any("/catalog-root/" in path for path in inspected))

    def test_the_c_bridge_and_the_probes_are_both_inspected(self) -> None:
        names = {path.name for path in comments.first_party_files()}
        self.assertIn("PlaybackFFmpegBridge.c", names)
        self.assertIn("dolby_vision_premise_probe.c", names)

    def test_a_new_directory_is_scanned_without_being_registered(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            scene = Path(directory) / "Scene.swift"
            scene.write_text("let value = 1\n", encoding="utf-8")
            self.assertEqual(comments.swift_comments(scene.read_text(encoding="utf-8")), ())


if __name__ == "__main__":
    unittest.main()
