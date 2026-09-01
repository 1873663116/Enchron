#!/usr/bin/env python3

"""The lane a container operation takes has to follow the target it was given."""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import enchron_target as target


class ContainerTruncateRoutesByLane(unittest.TestCase):
    """Reads were routed and writes were not.

    Clearing the probe journal went through `devicectl --device <CoreDevice>`
    whatever the target was. A simulator has no CoreDevice, so on that lane the
    clear could only fail, and a segment started on top of whatever the previous
    run had written. A panorama segment came back with four hundred and
    sixty-two journal lines carrying a session id from an earlier run, and its
    replay could verify none of its deliveries.
    """

    def test_the_simulator_branch_empties_the_file_it_was_given(self) -> None:
        with tempfile.TemporaryDirectory() as container:
            journal = Path(container) / "probe.log"
            journal.write_text("a stale session's four hundred lines\n")

            with patch.object(target, "is_simulator", return_value=True), \
                 patch.object(
                     target, "simulator_container", return_value=Path(container)
                 ):
                done = target.truncate_in_container(
                    target="simulator-udid",
                    bundle_id="com.example.app",
                    source="probe.log",
                    developer_dir="/dev/null",
                )

            self.assertEqual(done.returncode, 0)
            self.assertEqual(journal.read_text(), "")

    def test_the_device_branch_still_goes_through_devicectl(self) -> None:
        with patch.object(target, "is_simulator", return_value=False), \
             patch.object(target.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, "", "")

            target.truncate_in_container(
                target="physical-udid",
                bundle_id="com.example.app",
                source="probe.log",
                developer_dir="/dev/null",
                core_device_identifier="CORE-DEVICE",
            )

        command = run.call_args.args[0]
        self.assertIn("devicectl", command)
        self.assertIn("CORE-DEVICE", command)

    def test_an_unreadable_simulator_container_is_reported_not_assumed(self) -> None:
        with patch.object(target, "is_simulator", return_value=True), \
             patch.object(target, "simulator_container", return_value=None):
            done = target.truncate_in_container(
                target="simulator-udid",
                bundle_id="com.example.app",
                source="probe.log",
                developer_dir="/dev/null",
            )

        self.assertNotEqual(done.returncode, 0)


if __name__ == "__main__":
    unittest.main()
