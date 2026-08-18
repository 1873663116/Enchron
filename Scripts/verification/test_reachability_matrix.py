#!/usr/bin/env python3

from __future__ import annotations

import unittest

import reachability_matrix as matrix


class ImmersiveResidentWindowEvidenceTests(unittest.TestCase):
    def test_cleanup_response_recovers_lost_toggle_response(self) -> None:
        self.assertTrue(
            matrix.immersive_resident_window_is_hidden(
                toggle={"success": False, "error": "CoreDevice error 7000"},
                cleanup={
                    "success": True,
                    "ok": True,
                    "payload": ["false"],
                },
                no_named_node=True,
                no_new_identifier=True,
            )
        )

    def test_requires_the_window_to_remain_absent_from_accessibility(self) -> None:
        self.assertFalse(
            matrix.immersive_resident_window_is_hidden(
                toggle={"success": True},
                cleanup={"success": True, "payload": ["false"]},
                no_named_node=False,
                no_new_identifier=True,
            )
        )


if __name__ == "__main__":
    unittest.main()
