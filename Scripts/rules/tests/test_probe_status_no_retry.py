#!/usr/bin/env python3
from __future__ import annotations

import sys
import types
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "verification"))

import reachability_matrix as matrix

TIMEOUT = {"success": False, "failure": {"kind": "response-timeout"}, "error": "floor 75s"}
DECODE = {"success": False, "failure": {"kind": "response-undecodable"}}
OK = {"success": True, "payload": []}


def run_over(responses):
    calls = {"n": 0}

    def app_command(verb, defer_response=True):
        index = calls["n"]
        calls["n"] += 1
        return responses[index]

    run = types.SimpleNamespace(app_command=app_command, events=[])
    run.read_probe_status = types.MethodType(matrix.ReachabilityRun.read_probe_status, run)
    return run, calls


class ProbeStatusRetryPolicy(unittest.TestCase):
    def test_a_starved_channel_is_probed_once_not_retried(self) -> None:
        run, calls = run_over([TIMEOUT])
        document = run.read_probe_status()
        self.assertEqual(calls["n"], 1)
        self.assertEqual(document["failure"]["kind"], "response-timeout")

    def test_a_decode_failure_still_gets_one_retry(self) -> None:
        run, calls = run_over([DECODE, OK])
        document = run.read_probe_status()
        self.assertEqual(calls["n"], 2)
        self.assertTrue(document["success"])

    def test_a_first_success_does_not_probe_twice(self) -> None:
        run, calls = run_over([OK])
        run.read_probe_status()
        self.assertEqual(calls["n"], 1)


if __name__ == "__main__":
    unittest.main()
