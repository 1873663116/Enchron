#!/usr/bin/env python3

"""Hold the agent-harness guards to the same standard as the repository's own.

The hooks under `.claude/` were outside every verification layer, which is how
one of them shipped a probe that fed the gate a content block where a
transcript record belonged and passed while testing nothing. Running the
mutation harness here puts the guards inside the structure layer: each one is
inverted, and the probe that must turn red has to turn red.
"""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HARNESS = REPOSITORY_ROOT / ".claude/tools/verify_mutations.py"


class AgentHarnessMutations(unittest.TestCase):
    def test_every_guard_has_a_probe_that_turns_red_when_it_is_inverted(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(HARNESS)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            completed.returncode,
            0,
            completed.stdout + completed.stderr,
        )
        self.assertIn("mutations:", completed.stdout)


if __name__ == "__main__":
    unittest.main()
