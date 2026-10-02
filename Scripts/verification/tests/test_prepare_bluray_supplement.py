from __future__ import annotations

from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "Scripts"))
from Scripts.regression.core.catalog import load_catalog
from Scripts.verification.prepare_bluray_supplement import prepare


class BluRaySupplementTests(unittest.TestCase):
    def test_supplement_is_separate_and_catalog_loads_with_eight_simulator_cases(self) -> None:
        scratch = ROOT / ".scratch"
        scratch.mkdir(exist_ok=True)
        with TemporaryDirectory(prefix="bluray-supplement-test-", dir=scratch) as temporary:
            output = Path(temporary) / "catalog"
            result = prepare(output)
            catalog = load_catalog(output)
            self.assertEqual(result["scenarios"], 8)
            self.assertEqual(len(catalog.promises), 2)
            self.assertEqual(len(catalog.scenarios), 8)
            self.assertEqual({item.lane.value for item in catalog.scenarios}, {"simulator"})
            self.assertFalse((ROOT / "Regression" / "bluray-disc").exists())


if __name__ == "__main__":
    unittest.main()
