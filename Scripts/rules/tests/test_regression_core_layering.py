#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts/rules"))

from verify_regression_core_layering import check_tree


class RegressionCoreLayeringTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.regression_root = Path(self.temporary.name) / "regression"
        self.core_root = self.regression_root / "core"
        self.core_root.mkdir(parents=True)
        self.write_core("errors", "class RegressionError(Exception):\n    pass\n")
        self.write_core("ids", "from .errors import RegressionError\n")

    def write_core(self, module: str, source: str) -> None:
        (self.core_root / f"{module}.py").write_text(source, encoding="utf-8")

    def write_adapter(self, area: str, source: str) -> None:
        path = self.regression_root / area / "adapter.py"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source, encoding="utf-8")

    def check(self) -> list[str]:
        return check_tree(self.core_root)

    def test_accepts_stdlib_declared_dependencies_and_public_adapter_imports(self) -> None:
        self.write_core(
            "digest",
            "import hashlib\nimport json\nfrom pathlib import Path\nfrom .ids import Digest\n",
        )
        self.write_adapter(
            "operations",
            "from regression.core.contracts import OperationRole\n"
            "from regression.core.ids import OperationID\n"
            "from regression.core.digest import canonical_digest\n",
        )

        self.assertEqual(self.check(), [])

    def test_rejects_third_party_import_from_core(self) -> None:
        self.write_core("errors", "import yaml\n")

        self.assertEqual(
            self.check(),
            [
                "core/errors.py:1: error: [non-stdlib-import] "
                "core module 'errors' imports non-stdlib module 'yaml'"
            ],
        )

    def test_rejects_verification_and_adapter_imports_from_core(self) -> None:
        self.write_core(
            "errors",
            "from Scripts.verification import regression_operation_adapter\n"
            "from regression.operations import playback\n"
            "from regression.oracles import visible\n",
        )

        self.assertEqual(
            self.check(),
            [
                "core/errors.py:1: error: [forbidden-core-import] "
                "core module 'errors' imports 'Scripts.verification'",
                "core/errors.py:2: error: [forbidden-core-import] "
                "core module 'errors' imports 'regression.operations'",
                "core/errors.py:3: error: [forbidden-core-import] "
                "core module 'errors' imports 'regression.oracles'",
            ],
        )

    def test_rejects_undeclared_reverse_dependency(self) -> None:
        self.write_core("errors", "from .digest import canonical_digest\n")

        self.assertEqual(
            self.check(),
            [
                "core/errors.py:1: error: [undeclared-core-import] "
                "core module 'errors' may not import core module 'digest'"
            ],
        )

    def test_accepts_replay_to_runview_and_runtime_to_runview_edges(self) -> None:
        self.write_core(
            "runview",
            "from .events import EventType\n"
            "from .state import EpochTable\n",
        )
        self.write_core("replay", "from .runview import RunView\n")
        self.write_core("runtime", "from .runview import RunView\n")

        self.assertEqual(self.check(), [])

    def test_reports_a_concrete_core_import_cycle(self) -> None:
        self.write_core("errors", "from .ids import Digest\n")

        self.assertEqual(
            self.check(),
            [
                "core/errors.py:1: error: [undeclared-core-import] "
                "core module 'errors' may not import core module 'ids'",
                "core: error: [core-import-cycle] errors -> ids -> errors",
            ],
        )

    def test_rejects_private_core_imports_from_adapters(self) -> None:
        self.write_adapter(
            "operations",
            "from regression.core.ledger import append_event\n"
            "from regression.core.replay import replay\n",
        )
        self.write_adapter(
            "oracles",
            "from regression.core.runtime import MainRun\n",
        )

        self.assertEqual(
            self.check(),
            [
                "operations/adapter.py:1: error: [private-core-import] "
                "adapter may import only core contracts, digest, and ids; found 'ledger'",
                "operations/adapter.py:2: error: [private-core-import] "
                "adapter may import only core contracts, digest, and ids; found 'replay'",
                "oracles/adapter.py:1: error: [private-core-import] "
                "adapter may import only core contracts, digest, and ids; found 'runtime'",
            ],
        )

    def test_real_regression_tree_obeys_the_boundary(self) -> None:
        regression_root = REPOSITORY_ROOT / "Scripts/regression"

        self.assertEqual(
            check_tree(regression_root / "core", regression_root),
            [],
        )

    def test_cli_checks_the_repository_tree_without_arguments(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(
                    REPOSITORY_ROOT
                    / "Scripts/rules/verify_regression_core_layering.py"
                ),
            ],
            cwd=REPOSITORY_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0)
        self.assertEqual(
            completed.stdout,
            "Regression core layering verification passed\n",
        )
        self.assertEqual(completed.stderr, "")


if __name__ == "__main__":
    unittest.main()
