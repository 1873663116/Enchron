#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[2]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.ids import IDENTIFIER_PATTERNS, SignatureID
from regression.tools import pixel_heuristics
from regression.tools.signatures import (
    ALL_BLACK,
    REGISTERED,
    SIGNATURES,
    AdjudicationTier,
    SignatureError,
    signature,
)


class SignatureRegistryTests(unittest.TestCase):
    """A verdict names the failure it matched by identifier. Free text would put
    a name nobody can look up into an append-only ledger, so the registry is the
    only place an identifier comes from."""

    def test_every_registered_identifier_parses_as_one(self) -> None:
        pattern = IDENTIFIER_PATTERNS["signature"]
        for item in REGISTERED:
            self.assertRegex(item.id, pattern)

    def test_every_registered_signature_states_its_criterion_and_tier(self) -> None:
        for item in REGISTERED:
            self.assertIsInstance(item.tier, AdjudicationTier)
            self.assertGreater(len(item.criterion), 40)

    def test_the_table_holds_one_entry_per_identifier(self) -> None:
        self.assertEqual(len(REGISTERED), len(SIGNATURES))

    def test_an_unregistered_identifier_is_refused_with_the_registered_ones(
        self,
    ) -> None:
        with self.assertRaises(SignatureError) as raised:
            signature(SignatureID("signature:blank-frame"))

        for item in REGISTERED:
            self.assertIn(str(item.id), str(raised.exception))

    def test_a_registered_identifier_returns_its_entry(self) -> None:
        self.assertIs(SIGNATURES[ALL_BLACK], signature(ALL_BLACK))

    def test_the_pixel_heuristics_mint_registered_identifiers(self) -> None:
        self.assertIs(signature(pixel_heuristics.ALL_BLACK).id, ALL_BLACK)
        self.assertIsNotNone(signature(pixel_heuristics.CAPTURE_FAILED))


if __name__ == "__main__":
    unittest.main()
