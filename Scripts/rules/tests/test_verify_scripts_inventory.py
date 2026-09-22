from __future__ import annotations

import ast
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from verify_scripts_inventory import defines_test_cases


class ScriptInventoryTests(unittest.TestCase):
    def test_indirect_test_case_subclass_is_discovered(self) -> None:
        tree = ast.parse(
            """
import unittest

class SharedCase(unittest.TestCase):
    pass

class ConcreteCase(SharedCase):
    def test_contract(self):
        pass
"""
        )

        self.assertTrue(defines_test_cases(tree))

    def test_helper_without_test_methods_is_not_discovered(self) -> None:
        tree = ast.parse(
            """
import unittest

class SharedCase(unittest.TestCase):
    pass
"""
        )

        self.assertFalse(defines_test_cases(tree))


if __name__ == "__main__":
    unittest.main()
