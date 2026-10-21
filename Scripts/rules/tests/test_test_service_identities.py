#!/usr/bin/env python3

"""The registry decides which identities exist and where they may appear."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

RULES = Path(__file__).resolve().parents[1]
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import verify_test_service_identities as identities


class RegistryTests(unittest.TestCase):
    def test_a_missing_class_is_a_problem(self) -> None:
        registry = {"EMBY_NO_CLASS": {"service": "emby"}}
        self.assertEqual(len(identities.malformed_registry(registry)), 1)

    def test_an_unknown_class_is_a_problem(self) -> None:
        registry = {"EMBY_USER": {"service": "emby", "class": "mystery"}}
        self.assertEqual(len(identities.malformed_registry(registry)), 1)

    def test_a_named_service_with_a_known_class_is_accepted(self) -> None:
        registry = {"EMBY_USER": {"service": "emby", "class": "identity"}}
        self.assertEqual(identities.malformed_registry(registry), [])

    def test_the_recorded_registry_covers_every_variable_it_names(self) -> None:
        registry = identities.load_registry()
        self.assertNotEqual(registry, {})
        self.assertEqual(identities.malformed_registry(registry), [])


class ScopeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        patcher = patch.object(identities, "REPOSITORY_ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)

    def text(self, relative: str, contents: str) -> list[tuple[Path, str]]:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return [(path, contents)]

    def test_an_unregistered_variable_is_reported(self) -> None:
        registry = {"EMBY_USER": {"service": "emby", "class": "identity"}}
        name = "PLE" + "X_" + "USER"
        texts = self.text("Scripts/probe.py", f'value = os.environ.get("{name}")\n')
        found = identities.unclassified_variables(texts, registry)
        self.assertEqual(len(found), 1)
        self.assertIn(name, found[0])

    def test_a_registered_variable_is_not_reported(self) -> None:
        registry = {"EMBY_USER": {"service": "emby", "class": "identity"}}
        texts = self.text("Scripts/probe.py", 'value = os.environ.get("EMBY_USER")\n')
        self.assertEqual(identities.unclassified_variables(texts, registry), [])

    def test_a_value_in_the_tree_is_reported_without_the_value(self) -> None:
        secret = "Marmalade-Harbour-7719"
        texts = self.text("Scripts/probe.py", f'user = "{secret}"\n')
        found = identities.value_leaks(texts, {"EMBY_USER": secret})
        self.assertEqual(len(found), 1)
        self.assertNotIn(secret, found[0])
        self.assertIn("EMBY_USER", found[0])

    def test_a_placeholder_credential_url_passes(self) -> None:
        texts = self.text(
            "Tests/probe.py", 'url = "http://user:pass@example.test:8096/"\n'
        )
        self.assertEqual(identities.shape_leaks(texts), [])

    def test_a_loopback_credential_url_passes(self) -> None:
        texts = self.text(
            "Tests/probe.py", 'url = "http://probe:secret@127.0.0.1:9000/"\n'
        )
        self.assertEqual(identities.shape_leaks(texts), [])

    def test_a_templated_credential_url_passes(self) -> None:
        texts = self.text(
            "Tests/probe.py", 'url = "http://{user}:{password}@host:9000/"\n'
        )
        self.assertEqual(identities.shape_leaks(texts), [])

    def test_a_real_credential_url_is_reported(self) -> None:
        url = "http://" + "cape" + ":" + "zephyr" + "@" + "10.20.30.40" + ":8096/"
        texts = self.text("Modules/Client.swift", f'let url = "{url}"\n')
        found = identities.shape_leaks(texts)
        self.assertEqual(len(found), 1)
        self.assertIn("credential in a URL", found[0])

    def test_a_private_key_block_is_reported(self) -> None:
        marker = "-----BEGIN " + "RSA PRIVATE KEY" + "-----"
        texts = self.text("Config/key.txt", f"{marker}\nbody\n")
        found = identities.shape_leaks(texts)
        self.assertEqual(len(found), 1)
        self.assertIn("private key block", found[0])

    def test_a_file_digest_is_not_a_certificate_fingerprint(self) -> None:
        digest = "a3" * 32
        texts = self.text("evidence/manifest.json", f'{{"sha256": "{digest}"}}\n')
        self.assertEqual(identities.shape_leaks(texts), [])

    def test_a_certificate_fingerprint_is_reported(self) -> None:
        fingerprint = ":".join(["a3"] * 20)
        texts = self.text(
            "Config/pin.json", f'{{"certificate fingerprint": "{fingerprint}"}}\n'
        )
        self.assertEqual(len(identities.shape_leaks(texts)), 1)


class RecordedRegistryTests(unittest.TestCase):
    def test_the_tree_carries_no_registered_value(self) -> None:
        registry = identities.load_registry()
        values = identities.environment_values(registry)
        if not values:
            self.skipTest("no identity is present in this environment")
        self.assertEqual(identities.value_leaks(identities.scan_texts(), values), [])

    def test_the_tree_carries_no_credential_shape(self) -> None:
        self.assertEqual(identities.shape_leaks(identities.scan_texts()), [])

    def test_every_identity_shaped_variable_is_classified(self) -> None:
        registry = identities.load_registry()
        texts = identities.scan_texts()
        self.assertEqual(identities.unclassified_variables(texts, registry), [])


if __name__ == "__main__":
    unittest.main()
