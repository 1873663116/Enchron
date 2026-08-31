#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

RULES = Path(__file__).resolve().parent
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import verify_release_test_channel_absent as checker  # noqa: E402


GUARDED_CHANNEL = """#if DEBUG
import Foundation

final class TestCommandChannel {
    #if os(visionOS)
    let platform = "visionOS"
    #endif
}

#endif
"""

GUARDED_INSTALL = """import Foundation

extension EnchronApplication {
    convenience init() {
        self.init(environment: [:])
        #if DEBUG
            installTestCommandChannelIfEnabled(environment: [:])
        #endif
    }
}
"""

RELEASE_WITHOUT_DEBUG = """
\t\t1111 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t};
\t\t\tname = Release;
\t\t};
"""


class ReleaseTestChannelAbsentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.write(checker.CHANNEL_SOURCE, GUARDED_CHANNEL)
        self.write(checker.INSTALL_SITE, GUARDED_INSTALL)
        self.write(checker.PROJECT_FILE, RELEASE_WITHOUT_DEBUG)

    def write(self, relative: str, contents: str) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def test_a_fully_guarded_channel_passes(self) -> None:
        self.assertEqual(checker.failures(), [])

    def test_channel_code_outside_the_debug_guard_fails(self) -> None:
        self.write(
            checker.CHANNEL_SOURCE,
            GUARDED_CHANNEL.replace("\n#endif\n", "\n#endif\n\nlet leaked = 1\n"),
        )

        self.assertIn("must close the #if DEBUG", " ".join(checker.failures()))

    def test_a_channel_that_reopens_after_its_guard_fails(self) -> None:
        self.write(
            checker.CHANNEL_SOURCE,
            "#if DEBUG\nlet a = 1\n#endif\n#if os(visionOS)\nlet b = 2\n#endif\n",
        )

        self.assertIn(
            "leaves the file's #if DEBUG", " ".join(checker.failures())
        )

    def test_an_unguarded_channel_fails(self) -> None:
        self.write(checker.CHANNEL_SOURCE, "import Foundation\nlet a = 1\n")

        self.assertIn("must open with #if DEBUG", " ".join(checker.failures()))

    def test_an_unguarded_install_call_fails(self) -> None:
        self.write(
            checker.INSTALL_SITE,
            GUARDED_INSTALL.replace("        #if DEBUG\n", "").replace(
                "        #endif\n", ""
            ),
        )

        self.assertIn("reachable outside #if DEBUG", " ".join(checker.failures()))

    def test_a_release_configuration_that_defines_debug_fails(self) -> None:
        self.write(
            checker.PROJECT_FILE,
            RELEASE_WITHOUT_DEBUG.replace(
                'SWIFT_OPTIMIZATION_LEVEL = "-O";',
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
            ),
        )

        self.assertIn("defines DEBUG", " ".join(checker.failures()))

    def test_a_release_configuration_that_defines_the_debug_macro_fails(self) -> None:
        self.write(
            checker.PROJECT_FILE,
            RELEASE_WITHOUT_DEBUG.replace(
                'SWIFT_OPTIMIZATION_LEVEL = "-O";',
                'GCC_PREPROCESSOR_DEFINITIONS = "DEBUG=1";',
            ),
        )

        self.assertIn("defines DEBUG", " ".join(checker.failures()))

    def test_a_project_without_a_release_configuration_fails(self) -> None:
        self.write(checker.PROJECT_FILE, "// no configurations\n")

        self.assertIn(
            "no Release build configuration", " ".join(checker.failures())
        )


class RepositoryTests(unittest.TestCase):
    def test_this_repository_keeps_the_channel_out_of_release(self) -> None:
        self.assertEqual(checker.failures(), [])


if __name__ == "__main__":
    unittest.main()
