from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import regression_operation_adapter as adapter


class GatewayBindingTests(unittest.TestCase):
    def test_controller_command_receives_its_exact_execution_input(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            frozen = root / "execution-input.json"
            context = adapter.OperationContext(
                "simulator", "SIM-UDID", root, root / "controller",
                "com.xiongzhipeng.Enchron.debug", frozen,
            )
            backend = adapter.ResidentOperationBackend()
            with (
                mock.patch.object(backend, "_developer_dir", return_value="/Developer"),
                mock.patch.object(adapter.enchron_target, "core_device", return_value="CORE"),
            ):
                command = backend._harness_instruments(context).controller.command_prefix
            self.assertEqual(command[-2:], ["--execution-input", str(frozen)])

    def test_relative_execution_input_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            with self.assertRaisesRegex(adapter.OperationAdapterError, "absolute"):
                adapter.OperationContext(
                    "simulator", "SIM-UDID", root, root / "controller",
                    "com.xiongzhipeng.Enchron.debug", Path("execution-input.json"),
                )


if __name__ == "__main__":
    unittest.main()
