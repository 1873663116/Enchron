#!/usr/bin/env python3

"""Self-tests for the tracked-identity guard.

The samples this file feeds the guard are assembled from parts rather than
written out. A guard whose own self-test carries the shapes it rejects reports
itself on every run, and the honest fix is to stop writing the shape, not to
exempt the file.
"""

from __future__ import annotations
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

RULES = Path(__file__).resolve().parent
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import check_no_literal_rfc1918 as checker

PUBLIC_ADDRESS = ".".join(("1", "2", "3", "4"))
DOCUMENTATION_ADDRESS = ".".join(("203", "0", "113", "9"))
CARRIER_GRADE_ADDRESS = ".".join(("100", "100", "100", "100"))
ROUTABLE_OUTSIDE_RFC1918 = ".".join(("172", "15", "0", "1"))
ROUTABLE_BELOW_192_168 = ".".join(("192", "167", "0", "1"))
TAILNET_NAME = ".".join(("mac-mini", "tailexample", "ts", "net"))
DEVICE_IDENTIFIER = "-".join(("00008142", "0A1B2C3D4E5F6071"))
PLACEHOLDER_IDENTIFIER = "-".join(("00008142", "000000000000000A"))
CORE_DEVICE_IDENTIFIER = "-".join(("1A2B3C4D", "5E6F", "4A7B", "8C9D", "0E1F2A3B4C5D"))
PLACEHOLDER_CORE_DEVICE = "-".join(("22222222", "2222", "4222", "8222", "222222222222"))
UNRELATED_UUID = "-".join(("7D6C5B4A", "3210", "4FED", "9BA9", "876543210FED"))
EMBY_IDENTIFIER = "".join(("9f3a7c21", "4d8be056", "17ca92f4", "6b0d38e7"))
EMBY_FIXTURE_IDENTIFIER = "0123456789abcdef" * 2
ACCOUNT_NAME = "Corti" + "sol"
EMBY_RELEASE = ".".join(("4", "9", "5", "0"))


class NoLiteralRFC1918Tests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)
        (self.repository / "Scripts/verification").mkdir(parents=True, exist_ok=True)
        (self.repository / "Scripts/regression").mkdir(parents=True, exist_ok=True)
        (self.repository / "Config").mkdir(parents=True, exist_ok=True)

    def write(self, relative: str, contents: str) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def test_clean_file_passes(self) -> None:
        self.write("Scripts/verification/clean.py", "host = \"Mac-mini.local\"\n")
        self.write("Config/example.json", "{\"host\": \"Mac-mini.local\"}")
        self.assertEqual(checker.failures(), [])

    def test_192_168_is_rejected(self) -> None:
        self.write("Scripts/verification/bad.py", "server = \"http://192.168.5.20:8096\"\n")
        found = checker.failures()
        self.assertTrue(found)
        self.assertTrue(any("bad.py" in line for line in found))

    def test_10_network_is_rejected(self) -> None:
        self.write("Scripts/regression/bad.py", "addr = \"10.0.0.5\"\n")
        found = checker.failures()
        self.assertTrue(found)
        self.assertTrue(any("bad.py" in line for line in found))

    def test_172_16_is_rejected(self) -> None:
        self.write("Config/bad.json", "{\"addr\": \"172.16.5.10\"}")
        found = checker.failures()
        self.assertTrue(found)
        self.assertTrue(any("bad.json" in line for line in found))

    def test_172_31_is_rejected(self) -> None:
        self.write("Scripts/verification/another.py", "x = \"172.31.255.1\"\n")
        self.assertTrue(checker.failures())

    def test_172_15_is_not_an_rfc1918_address(self) -> None:
        self.write("Scripts/verification/ok.py", f"x = \"{ROUTABLE_OUTSIDE_RFC1918}\"\n")
        found = checker.failures()
        self.assertFalse(any("literal RFC1918" in line for line in found))

    def test_192_167_is_not_an_rfc1918_address(self) -> None:
        self.write("Scripts/verification/ok2.py", f"x = \"{ROUTABLE_BELOW_192_168}\"\n")
        found = checker.failures()
        self.assertFalse(any("literal RFC1918" in line for line in found))

    def test_an_address_the_rfc1918_rule_allows_is_still_an_identity(self) -> None:
        """The two cases above pass a rule; they do not clear the file.

        Their samples were once moved onto `BOUNDARY_ADDRESSES`, where an
        exemption rather than the rule kept them quiet, and asserting on the
        whole report made that invisible. A routable address one block below
        RFC1918 is outside the private ranges and still names a host.
        """
        self.write("Scripts/verification/ok.py", f"x = \"{ROUTABLE_OUTSIDE_RFC1918}\"\n")
        found = checker.failures()
        self.assertFalse(any("literal RFC1918" in line for line in found))
        self.assertTrue(any("routable public IPv4 address" in line for line in found))
        self.assertNotIn(ROUTABLE_OUTSIDE_RFC1918, checker.BOUNDARY_ADDRESSES)


class IdentityScopeTests(unittest.TestCase):
    """The four identity classes were all outside the guard's reach.

    Every one of them lived in `Tests`, `docs` or `.agents`, none of which the
    guard looked at, so a public host address, a Tailscale name and a headset
    identifier all reached version control unreported.
    """

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)

    def write(self, relative: str, contents: str) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def test_a_public_address_in_a_swift_test_is_reported(self) -> None:
        self.write(
            "Tests/MediaSourceTests/Scope.swift",
            f"let host = \"{PUBLIC_ADDRESS}\"\n",
        )
        found = checker.failures()
        self.assertEqual(len(found), 1)
        self.assertIn("Tests/MediaSourceTests/Scope.swift:1", found[0])
        self.assertIn("routable public IPv4 address", found[0])

    def test_a_public_address_in_a_document_is_reported(self) -> None:
        self.write("docs/archive/evidence/README.md", f"reached `{PUBLIC_ADDRESS}`\n")
        self.assertTrue(
            any("docs/archive/evidence/README.md" in line for line in checker.failures())
        )

    def test_a_tailscale_name_in_a_skill_reference_is_reported(self) -> None:
        self.write(".agents/skills/vp-e2e/references/device.md", f"host {TAILNET_NAME}\n")
        found = checker.failures()
        self.assertEqual(len(found), 1)
        self.assertIn("Tailscale MagicDNS name", found[0])

    def test_a_device_identifier_in_a_harness_script_is_reported(self) -> None:
        self.write(
            "Scripts/verification/enchron_target.py",
            f"DESTINATION = \"{DEVICE_IDENTIFIER}\"\n",
        )
        found = checker.failures()
        self.assertEqual(len(found), 1)
        self.assertIn("Apple device identifier", found[0])

    def test_a_device_identifier_in_a_json_fixture_is_reported(self) -> None:
        self.write("Config/target.json", f"{{\"device\": \"{DEVICE_IDENTIFIER}\"}}")
        self.assertTrue(
            any("Apple device identifier" in line for line in checker.failures())
        )

    def test_a_zero_padded_device_identifier_is_a_placeholder(self) -> None:
        self.write(
            "Scripts/rules/test_device_transfer_retry.py",
            f"DEVICE = \"{PLACEHOLDER_IDENTIFIER}\"\n",
        )
        self.assertEqual(checker.failures(), [])

    def test_a_documentation_range_address_is_allowed(self) -> None:
        self.write("Tests/MediaSourceTests/Scope.swift", f"\"{DOCUMENTATION_ADDRESS}\"\n")
        self.assertEqual(checker.failures(), [])

    def test_a_carrier_grade_nat_address_is_allowed(self) -> None:
        self.write("Tests/MediaSourceTests/Scope.swift", f"\"{CARRIER_GRADE_ADDRESS}\"\n")
        self.assertEqual(checker.failures(), [])

    def test_the_address_outside_each_reserved_block_is_a_boundary_probe(self) -> None:
        lines = "\n".join(f"(\"{edge}\", .publicAddress)," for edge in sorted(checker.BOUNDARY_ADDRESSES))
        self.write("Tests/MediaSourceTests/Scope.swift", lines + "\n")
        self.assertEqual(checker.failures(), [])

    def test_a_version_number_is_not_an_address(self) -> None:
        self.write("Tests/EmbyPackageTests/Fixtures/Info.json", f"{{\"Version\": \"{EMBY_RELEASE}\"}}")
        self.write("Modules/Emby/Decoding.swift", f"info.version == \"{EMBY_RELEASE}\"\n")
        self.assertEqual(checker.failures(), [])

    def test_a_version_word_set_beside_a_quad_by_a_dash_does_not_exempt_it(self) -> None:
        """A dash sets two things side by side; it does not bind a value to a key.

        `[^0-9A-Za-z]{0,12}` accepted any punctuation run, so `Release  - `
        introduced an address as if it were the release's own number.
        """
        self.write("docs/notes.md", f"Release  - {PUBLIC_ADDRESS} today\n")
        self.assertTrue(
            any("routable public IPv4 address" in line for line in checker.failures())
        )

    def test_a_version_word_inside_a_longer_word_does_not_exempt(self) -> None:
        """`version` without a word boundary matched the tail of any word ending in it."""
        self.write("docs/notes.md", f"subversion {PUBLIC_ADDRESS}\n")
        self.assertTrue(
            any("routable public IPv4 address" in line for line in checker.failures())
        )

    def test_a_version_word_bound_to_the_quad_still_exempts_it(self) -> None:
        self.write("Config/info.json", f"{{\"Version\": \"{EMBY_RELEASE}\"}}")
        self.write("Modules/Emby/Client.swift", f"\\\"Version\\\":\\\"{EMBY_RELEASE}\\\"\n")
        self.assertEqual(checker.failures(), [])

    def test_a_tag_in_a_url_path_is_not_an_address(self) -> None:
        self.write(
            "docs/archive/research/emby.md",
            f"https://github.com/MediaBrowser/Emby/blob/{EMBY_RELEASE}/MediaSourceManager.cs\n",
        )
        self.assertEqual(checker.failures(), [])

    def test_a_path_segment_with_no_scheme_in_front_of_it_is_not_a_url(self) -> None:
        """The exemption keyed on a bare slash, so any filesystem path carried it.

        A quad standing between two slashes is a URL path segment only when the
        line has a scheme on it; otherwise the slashes are directories.
        """
        self.write("docs/notes.md", f"/Volumes/{PUBLIC_ADDRESS}/share\n")
        self.assertTrue(
            any("routable public IPv4 address" in line for line in checker.failures())
        )

    def test_a_host_in_a_url_authority_is_still_an_address(self) -> None:
        self.write("docs/notes.md", f"http://{PUBLIC_ADDRESS}/library\n")
        self.assertTrue(checker.failures())

    def test_vendored_and_built_trees_are_not_scanned(self) -> None:
        for excluded in ("Vendor", ".build", "DerivedData", "SourcePackages", "checkouts", ".scratch"):
            self.write(f"Packages/PlaybackCore/{excluded}/notes.md", f"`{PUBLIC_ADDRESS}`\n")
        self.assertEqual(checker.failures(), [])

    def test_a_sibling_worktree_is_not_this_checkouts_material(self) -> None:
        self.write(".claude/worktrees/other/Tests/Scope.swift", f"\"{PUBLIC_ADDRESS}\"\n")
        self.write(".claude/state/messages.json", f"[\"{DEVICE_IDENTIFIER}\"]")
        self.assertEqual(checker.failures(), [])

    def test_the_local_fixture_name_no_longer_exempts_by_itself(self) -> None:
        """The exemption was keyed on `*.local.json`, wherever that name appeared.

        Nothing about the name says the file is out of version control, so a
        tracked one carrying secrets was skipped along with the untracked one
        the pattern was written for. With no git to ask, the name exempts
        nothing.
        """
        self.write(
            "Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json",
            f"{{\"address\": \"http://{PUBLIC_ADDRESS}:8096\"}}",
        )
        self.assertTrue(
            any("EmbyServerCredentials.local.json" in line for line in checker.failures())
        )

    def test_scope_survives_a_directory_that_is_not_a_git_repository(self) -> None:
        """The guard self-test harness copies the worktree out of the repository.

        `git` exits 128 there. A scope taken from `git ls-files` would cover
        nothing and the guard would pass by scanning zero files, which is how a
        checker reports green on a repository full of the thing it looks for.
        """
        self.assertFalse((self.repository / ".git").exists())
        self.write("Tests/MediaSourceTests/Scope.swift", f"\"{PUBLIC_ADDRESS}\"\n")
        self.assertTrue(checker.identity_scan_paths())
        self.assertTrue(checker.failures())

    def test_the_scan_asks_git_nothing_but_which_files_it_ignores(self) -> None:
        """Scope comes from the walk. Git answers one question and no other.

        A scope taken from `git ls-files` covers nothing where git fails, so
        the file list is never git's to give.
        """
        self.write("Tests/MediaSourceTests/Scope.swift", f"\"{PUBLIC_ADDRESS}\"\n")
        commands: list[list[str]] = []
        original = subprocess.run

        def record(arguments, *rest, **keywords):
            commands.append(list(arguments))
            return original(arguments, *rest, **keywords)

        with patch.object(checker.subprocess, "run", record):
            self.assertTrue(checker.failures())
        self.assertTrue(commands)
        for command in commands:
            self.assertEqual(command[0], "git")
            self.assertIn("check-ignore", command)

    def test_a_git_that_cannot_run_means_the_file_is_scanned(self) -> None:
        """The fallback scans. The alternative is a guard that passes on silence."""
        self.write("Tests/MediaSourceTests/Scope.swift", f"\"{PUBLIC_ADDRESS}\"\n")

        def unavailable(*arguments: object, **keywords: object) -> None:
            raise OSError("git is not on this machine")

        with patch.object(checker.subprocess, "run", unavailable):
            self.assertEqual(checker.ignored_paths([self.repository / "x"]), frozenset())
            self.assertTrue(checker.failures())

    def test_a_git_that_answers_with_an_error_code_means_the_file_is_scanned(self) -> None:
        self.write("Tests/MediaSourceTests/Scope.swift", f"\"{PUBLIC_ADDRESS}\"\n")
        outside = subprocess.CompletedProcess([], returncode=128, stdout="", stderr="")
        with patch.object(checker.subprocess, "run", return_value=outside):
            self.assertEqual(checker.ignored_paths([self.repository / "x"]), frozenset())
            self.assertTrue(checker.failures())


class CoreDeviceIdentifierTests(unittest.TestCase):
    """A UUID is too ordinary a shape to report on sight.

    The fourth identity class survived the first scrub because nothing looked
    for it: session ids, tree hashes and CoreDevice ids are all UUIDs, so the
    rule has to read what introduces the literal rather than the literal.
    """

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)

    def write(self, relative: str, contents: str) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def test_a_headset_identifier_in_an_evidence_header_is_reported(self) -> None:
        self.write(
            "docs/archive/acceptance/evidence/acceptance-20260815/VERIFY.md",
            f"Physical Vision Pro `{CORE_DEVICE_IDENTIFIER}`, tree `027e8cd6`\n",
        )
        found = checker.failures()
        self.assertEqual(len(found), 1)
        self.assertIn("CoreDevice identifier", found[0])

    def test_the_same_identifier_in_a_chinese_header_is_reported(self) -> None:
        self.write(
            "docs/archive/acceptance/evidence/renderer-lead-frames/README.md",
            f"物理 Vision Pro `{CORE_DEVICE_IDENTIFIER}`，片源 `180_3D.mp4`\n",
        )
        self.assertTrue(
            any("CoreDevice identifier" in line for line in checker.failures())
        )

    def test_the_same_identifier_on_a_devicectl_command_line_is_reported(self) -> None:
        self.write(
            ".agents/skills/vp-e2e/references/device.md",
            f"xcrun devicectl device info details --device {CORE_DEVICE_IDENTIFIER}\n",
        )
        self.assertTrue(
            any("CoreDevice identifier" in line for line in checker.failures())
        )

    def test_a_device_word_that_follows_the_identifier_also_labels_it(self) -> None:
        self.write(
            "docs/archive/acceptance/evidence/ui-defects/README.md",
            f"`{CORE_DEVICE_IDENTIFIER}`（CoreDevice）\n",
        )
        self.assertTrue(
            any("CoreDevice identifier" in line for line in checker.failures())
        )

    def test_the_spelling_the_pinned_constant_used_is_a_device_word(self) -> None:
        """`CoreDevice` and `Core Device` were the only separators the rule knew.

        The literal the scrub removed was a module constant in
        `Scripts/verification/reachability_matrix.py` written
        `CORE_DEVICE = "<uuid>"`, and the variable that replaced it is
        `ENCHRON_CORE_DEVICE`. Neither spelling carries the space or the
        capitalisation the rule required, so the identifier the whole class
        exists for would have come back unreported.
        """
        shapes = (
            f"CORE_DEVICE = \"{CORE_DEVICE_IDENTIFIER}\"",
            f"ENCHRON_CORE_DEVICE={CORE_DEVICE_IDENTIFIER}",
            f"core_device = \"{CORE_DEVICE_IDENTIFIER}\"",
        )
        for position, line in enumerate(shapes):
            with self.subTest(line=line):
                relative = f"Scripts/verification/pinned{position}.py"
                self.write(relative, line + "\n")
                found = checker.failures()
                self.assertTrue(
                    any("CoreDevice identifier" in entry for entry in found), line
                )
                (self.repository / relative).unlink()

    def test_the_identifier_spelling_is_a_device_word_and_not_its_own_intervening_word(self) -> None:
        """`coreDeviceIdentifier` matched on its first half and lost on its second.

        The harness passes the value as `core_device_identifier=` and the
        helpers name it `coreDeviceIdentifier`. The old pattern stopped at
        `Device`, leaving `Identifier` between the context word and the
        literal, and `is_introduced_by` read that tail as something else named
        in between - so the word rejected itself for standing next to itself.
        """
        shapes = (
            f"core_device_identifier=\"{CORE_DEVICE_IDENTIFIER}\"",
            f"coreDeviceIdentifier: \"{CORE_DEVICE_IDENTIFIER}\"",
        )
        for position, line in enumerate(shapes):
            with self.subTest(line=line):
                relative = f"Scripts/verification/passed{position}.py"
                self.write(relative, line + "\n")
                found = checker.failures()
                self.assertTrue(
                    any("CoreDevice identifier" in entry for entry in found), line
                )
                (self.repository / relative).unlink()

    def test_a_uuid_typed_out_of_a_handful_of_digits_is_a_fixture_value(self) -> None:
        """Widening the device words brought a test's own placeholder into reach.

        `Scripts/rules/test_regression_system_import.py` passes a UUID built
        out of three distinct digits to `device_identifier=` to prove a
        mismatch is refused. It is the shape the Apple-identifier and Emby
        classes already read as typed rather than issued, and a device
        identifier is no different.
        """
        self.write(
            "Scripts/rules/test_regression_system_import.py",
            f"                device_identifier=\"{PLACEHOLDER_CORE_DEVICE}\",\n",
        )
        self.assertEqual(checker.failures(), [])

    def test_a_uuid_no_device_word_introduces_is_not_a_headset(self) -> None:
        self.write(
            "docs/archive/acceptance/evidence/ui-defects/REPRO.md",
            f"session `{UNRELATED_UUID}`, build at `defaf387`\n",
        )
        self.assertEqual(checker.failures(), [])

    def test_a_device_word_does_not_reach_past_what_it_introduces(self) -> None:
        """The redacted headers put a session id within forty characters of `Vision Pro`.

        Proximity alone would report every one of them. The device word has to
        be the last thing named before the literal.
        """
        self.write(
            "docs/archive/acceptance/evidence/ui-defects/REPRO.md",
            f"Physical Vision Pro `REDACTED`, session `{UNRELATED_UUID}`,\n",
        )
        self.assertEqual(checker.failures(), [])


class EmbyIdentityTests(unittest.TestCase):
    """The Emby identity class: the account name, and the ids issued beside it.

    The first widened scan covered three of the four classes the brief named.
    A fixture reading `{"Id": "<32 hex>", "Name": "<the account>"}` produced no
    finding at all, which is the shape the live server actually returns.
    """

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)

    def write(self, relative: str, contents: str) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def test_the_shape_the_live_server_returns_is_reported(self) -> None:
        self.write(
            "Tests/EmbyPackageTests/Fixtures/PublicUsers.json",
            f"[{{\"Id\": \"{EMBY_IDENTIFIER}\", \"Name\": \"{ACCOUNT_NAME}\"}}]",
        )
        found = checker.failures()
        self.assertTrue(any("Emby server or user identifier" in line for line in found))
        self.assertTrue(any("Emby account name" in line for line in found))

    def test_a_server_identifier_beside_its_key_is_reported(self) -> None:
        self.write(
            "Tests/EmbyPackageTests/Fixtures/PublicUsers.json",
            f"{{\"ServerId\": \"{EMBY_IDENTIFIER}\"}}",
        )
        self.assertTrue(
            any("Emby server or user identifier" in line for line in checker.failures())
        )

    def test_the_account_name_as_a_credential_value_is_reported(self) -> None:
        self.write(
            "Tests/EmbyPackageTests/EmbyClientTests.swift",
            f"            username: \"{ACCOUNT_NAME}\",\n",
        )
        found = checker.failures()
        self.assertEqual(len(found), 1)
        self.assertIn("Emby account name", found[0])

    def test_the_account_name_in_backticks_behind_a_credential_word_is_reported(self) -> None:
        """The rule wanted a quote around the name, and the leftover was in backticks.

        `docs/archive/plans/04-regression-journeys/emby-poster-wall-scroll.md`
        carried the name in a scrub note reading 「username 与卷名 `<name>`
        相同」 - the word `username` ends six characters in front of it, and no
        quote the rule recognised. Requiring the quote was a rule shaped
        around the one leak that had already been cleaned up rather than
        around what makes the name a login.
        """
        self.write(
            "docs/archive/plans/04-regression-journeys/emby-poster-wall-scroll.md",
            f"凭据的 username 与卷名 `{ACCOUNT_NAME}` 相同，命中的是文件路径\n",
        )
        found = checker.failures()
        self.assertEqual(len(found), 1)
        self.assertIn("Emby account name", found[0])

    def test_the_unquoted_name_no_credential_word_introduces_is_still_a_volume(self) -> None:
        """Dropping the quote leaves the proximity window carrying the distinction.

        The name is also the name of the volume every path in this repository
        starts from, and those occurrences outnumber the credential ones by
        an order of magnitude. None of them has a credential word beside it.
        """
        volume = "/".join(("", "Volumes", ACCOUNT_NAME))
        self.write(
            ".github/workflows/verification.yml",
            f"          WORKSPACE={volume}/DevSpace/EnchronWorkspace\n",
        )
        self.write(
            "Scripts/build/build_and_run.sh",
            f"  {volume}/Applications/Xcode.app; do\n",
        )
        self.assertEqual(checker.failures(), [])

    def test_a_patterned_identifier_is_a_fixture_value(self) -> None:
        """A server issues random hex; a fixture repeats a cycle of it."""
        self.write(
            "Tests/EmbyPackageTests/Fixtures/PublicSystemInfo.json",
            f"{{\"Id\": \"{EMBY_FIXTURE_IDENTIFIER}\"}}",
        )
        self.assertEqual(checker.failures(), [])

    def test_a_32_hex_string_no_emby_key_introduces_is_not_an_identifier(self) -> None:
        self.write("docs/notes.md", f"checksum {EMBY_IDENTIFIER}\n")
        self.assertEqual(checker.failures(), [])

    def test_the_same_word_as_a_share_name_is_not_a_credential(self) -> None:
        """The account name is also the name of a disk, and a disk is not a login."""
        self.write(
            "Scripts/rules/test_regression_smb_source.py",
            f"        return [\"{ACCOUNT_NAME}\", \"TestMedia\"]\n",
        )
        self.write("docs/notes.md", f"built under /Volumes/{ACCOUNT_NAME}/DevSpace\n")
        self.assertEqual(checker.failures(), [])

    def test_the_identifier_spelling_of_the_server_key_is_not_its_own_intervening_word(self) -> None:
        """`ServerId` matched the head of `serverIdentifier` and lost on its tail.

        This is the defect `CORE_DEVICE_CONTEXT` was fixed for, in the class
        beside it. The alternation stopped at `Id`, leaving `entifier` between
        the context word and the literal, and `is_introduced_by` read that
        tail as something else named in between - so the word rejected itself
        for standing next to itself.

        The line is the runtime identity document
        `Scripts/verification/regression_emby_source.py` writes, whose keys
        are `serverID` and `userID`, with the key spelled the long way this
        repository already spells the neighbouring one:
        `serverIdentityDigest`, `server_identity_digest`.
        """
        self.write(
            "Scripts/verification/regression_emby_source.py",
            f"            \"serverIdentifier\": \"{EMBY_IDENTIFIER}\",\n",
        )
        found = checker.failures()
        self.assertEqual(len(found), 1)
        self.assertIn("Emby server or user identifier", found[0])

    def test_the_identity_spelling_of_the_user_key_is_not_its_own_intervening_word(self) -> None:
        """The `entity` tail loses the same way the `entifier` tail does.

        `Scripts/verification/reachability_matrix.py` writes
        `serverIdentityDigest` and takes `server_identity_digest`, so this
        spelling of the key is the one already in the tree; the user half of
        the same document is `userID`.
        """
        self.write(
            "Scripts/verification/regression_emby_source.py",
            f"            \"userIdentity\": \"{EMBY_IDENTIFIER}\",\n",
        )
        found = checker.failures()
        self.assertEqual(len(found), 1)
        self.assertIn("Emby server or user identifier", found[0])

    def assert_only_the_position_reports_it(self, relative: str, line: str) -> None:
        """The name is reported, and no credential word on the line is what reports it.

        Asserting the finding alone would pass on a sample that happens to
        carry `user` or `name` somewhere in the window, which is most command
        lines. The second assertion pins the finding to the position.
        """
        self.write(relative, line + "\n")
        found = checker.failures()
        self.assertEqual(len(found), 1, line)
        self.assertIn("Emby account name", found[0])
        start = line.index(ACCOUNT_NAME)
        stop = start + len(ACCOUNT_NAME)
        window = line[max(start - checker.CONTEXT_WINDOW, 0): stop + checker.CONTEXT_WINDOW]
        self.assertIsNone(checker.ACCOUNT_NAME_CONTEXT.search(window), line)
        (self.repository / relative).unlink()

    def test_the_name_in_a_url_userinfo_position_is_a_credential(self) -> None:
        """A login in a URL has no credential word beside it; it has a position."""
        self.assert_only_the_position_reports_it(
            "Scripts/verification/probe_remote_media_reads.py",
            f"    SHARE = \"smb://{ACCOUNT_NAME}@nas.example.test/TestMedia\"",
        )

    def test_the_name_ahead_of_a_password_colon_is_a_credential(self) -> None:
        """The other end of the userinfo field: the colon that precedes the password."""
        self.assert_only_the_position_reports_it(
            "Scripts/verification/probe_remote_media_reads.py",
            f"    ADDRESS = \"http://{ACCOUNT_NAME}:secret@emby.example.test:8096/\"",
        )

    def test_the_name_behind_a_short_credential_flag_is_a_credential(self) -> None:
        """`curl` documents the flag as `-u, --user <user:password>`.

        In the short form the flag is the only label on the line, and it is
        two characters long.
        """
        self.assert_only_the_position_reports_it(
            "Scripts/verification/probe_remote_media_reads.sh",
            f"curl -sS -u {ACCOUNT_NAME} http://emby.example.test:8096/System/Info",
        )

    def test_the_name_behind_a_scheme_less_authority_is_a_credential(self) -> None:
        """The SMB tools take an authority with no scheme in front of it.

        `mount_smbfs` and `smbutil` are both documented as taking
        `//[domain;][user[:password]@]server`, so the userinfo position exists
        on a line that carries no scheme for `URL_SCHEME` to find.
        """
        self.assert_only_the_position_reports_it(
            "Scripts/verification/mount_test_share.sh",
            f"mount_smbfs //{ACCOUNT_NAME}@nas.example.test/TestMedia ./mnt",
        )

    def test_the_spelled_out_credential_flag_holds_the_same_position(self) -> None:
        """`--user` carries the word as well, so the finding proves nothing by itself.

        The position is asserted directly here, because a line carrying the
        flag also carries `user` inside it and the word window would report
        the name whether the position rule existed or not.
        """
        line = f"curl -sS --user {ACCOUNT_NAME} http://emby.example.test:8096/System/Info"
        start = line.index(ACCOUNT_NAME)
        self.assertTrue(
            checker.stands_in_a_credential_position(line, start, start + len(ACCOUNT_NAME))
        )
        self.write("Scripts/verification/probe_remote_media_reads.sh", line + "\n")
        self.assertTrue(
            any("Emby account name" in entry for entry in checker.failures())
        )

    def test_a_volume_path_on_a_line_that_carries_a_url_is_still_a_path(self) -> None:
        """The scheme is on the line, and the name is still a directory.

        The position rule reads the character after the name, not the line. A
        path segment is followed by a slash, and a quoted path by its quote,
        so neither reaches the at-sign or the colon that ends a userinfo
        field.
        """
        self.write(
            "docs/notes.md",
            f"cloned from https://github.com/example/repo into /Volumes/{ACCOUNT_NAME}/DevSpace\n",
        )
        self.write(
            "Config/paths.json",
            f"{{\"/Volumes/{ACCOUNT_NAME}\": \"https://example.test/\"}}",
        )
        self.assertEqual(checker.failures(), [])


class GitDecidesWhatIsOutOfVersionControlTests(unittest.TestCase):
    """The exemption has to test what git does, not what a file is called.

    The exemption keyed on the name `*.local.json` skipped every file
    called that, tracked or not, so a tracked one carried whatever it
    liked past the guard.
    These cases run against a repository of their own, because the question
    only has an answer inside one.
    """

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.git("init", "-q")
        self.git("config", "user.email", "guard@example.test")
        self.git("config", "user.name", "guard")
        self.write(".gitignore", "*.local.json\n")

    def git(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", "-C", str(self.repository), *arguments],
            check=True, capture_output=True, text=True,
        )

    def write(self, relative: str, contents: str) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def test_an_ignored_fixture_is_not_scanned(self) -> None:
        self.write(
            "Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json",
            f"{{\"address\": \"http://{PUBLIC_ADDRESS}:8096\"}}",
        )
        self.assertEqual(checker.failures(), [])

    def test_a_tracked_file_with_the_ignored_name_is_scanned(self) -> None:
        """The defect stated plainly: the name is not evidence of anything."""
        relative = "Tests/EmbyPackageTests/Fixtures/whatever.local.json"
        self.write(relative, f"{{\"address\": \"http://{PUBLIC_ADDRESS}:8096\"}}")
        self.git("add", "-f", relative)
        self.assertTrue(any(relative in line for line in checker.failures()))


class SuffixScopeTests(unittest.TestCase):
    """What to open is a denylist now, because an allowlist skips the unforeseen.

    Nineteen extensions were named, so `.toml`, `.mdc`, `.usda`, `.tsv`,
    `.resolved`, `.log`, `.xcworkspacedata` and every extensionless file went
    unopened. A denylist fails toward scanning, and a NUL byte in the first
    block keeps the binaries out whatever they are called.
    """

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)

    def write(self, relative: str, contents: str) -> Path:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def test_every_extension_the_allowlist_never_named_is_scanned(self) -> None:
        unopened = (
            "pyproject.toml",
            ".cursor/rules/verification.mdc",
            "Packages/RealityKitContent/Scene.usda",
            "Config/inventory.tsv",
            "Package.resolved",
            "docs/archive/acceptance/evidence/run.log",
            "Enchron.xcworkspace/contents.xcworkspacedata",
            "Makefile",
        )
        for relative in unopened:
            with self.subTest(path=relative):
                self.write(relative, f"host {PUBLIC_ADDRESS}\n")
                self.assertTrue(
                    any(relative in line for line in checker.failures()),
                    relative,
                )
                (self.repository / relative).unlink()

    def test_a_media_file_is_not_opened(self) -> None:
        self.write("docs/archive/acceptance/evidence/frame.png", f"{PUBLIC_ADDRESS}\n")
        self.assertEqual(checker.failures(), [])

    def test_a_file_carrying_a_nul_byte_is_binary_whatever_it_is_called(self) -> None:
        path = self.repository / "docs/opaque.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"\x00" + PUBLIC_ADDRESS.encode("utf-8") + b"\n")
        self.assertEqual(checker.failures(), [])


class RealRepositoryTests(unittest.TestCase):
    """The guard runs against this repository, not against a temporary copy of one.

    Both earlier "real repository" cases ran inside a fixture whose
    `REPOSITORY_ROOT` was patched to an empty directory, so they asserted that
    an empty directory is clean.
    """

    def test_the_repository_has_no_tracked_identity(self) -> None:
        self.assertEqual(checker.failures(), [])

    def test_the_scan_reaches_the_trees_the_identities_lived_in(self) -> None:
        scanned = {path.relative_to(checker.REPOSITORY_ROOT).parts[0] for path in checker.identity_scan_paths()}
        for tree in ("Tests", "docs", "Scripts", ".agents", "Modules"):
            self.assertIn(tree, scanned)


if __name__ == "__main__":
    unittest.main()
