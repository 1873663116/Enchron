#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "verification"))

import ensure_test_services as services
import reachability_matrix as matrix
import regression_emby_source


class EmbySpecReadsTheGivenIdentity(unittest.TestCase):
    def test_identity_and_address_come_from_the_given_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "credentials.json"
            path.write_text(
                json.dumps({"serverID": "abc123", "address": "http://host.local:8096"}),
                encoding="utf-8",
            )
            spec = services.emby_spec(identity_file=path)
        self.assertEqual(spec.identity, "abc123")
        self.assertEqual(spec.expected, "abc123")
        self.assertEqual(spec.recorded_address, "http://host.local:8096")
        self.assertEqual(spec.port, 8096)

    def test_a_missing_file_leaves_the_identity_unknown(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            spec = services.emby_spec(identity_file=Path(directory) / "missing.json")
        self.assertEqual(spec.identity, "")
        self.assertIsNone(spec.recorded_address)


class MatrixChoosesTheIdentityFile(unittest.TestCase):
    def test_emby_credentials_argument_wins(self) -> None:
        arguments = argparse.Namespace(emby_credentials="/creds/emby.json")
        self.assertEqual(matrix.emby_identity_file(arguments), Path("/creds/emby.json"))

    def test_without_the_argument_the_repository_default_is_used(self) -> None:
        arguments = argparse.Namespace(emby_credentials=None)
        self.assertEqual(
            matrix.emby_identity_file(arguments),
            regression_emby_source.DEFAULT_IDENTITY_FILE,
        )


if __name__ == "__main__":
    unittest.main()
