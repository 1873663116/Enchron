import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


WORKTREE = Path(__file__).resolve().parents[1]
QUEUE = WORKTREE / "script" / "validation_queue.py"


class ValidationQueueTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.database = Path(self.temporary_directory.name) / "queue.sqlite3"
        self.invoke("init")

    def tearDown(self):
        self.temporary_directory.cleanup()

    def invoke(self, *arguments, expected_code=0):
        result = subprocess.run(
            [sys.executable, str(QUEUE), "--db", str(self.database), "--json", *arguments],
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, expected_code, result.stderr or result.stdout)
        return json.loads(result.stdout)

    def submit(self, task_id):
        return self.invoke(
            "submit",
            task_id,
            "--summary",
            task_id,
            "--worktree",
            str(WORKTREE),
            "--requested-by",
            "bug-worker-a",
            "--review-after-minutes",
            "5",
        )

    def test_single_slot_releases_only_after_terminal_completion(self):
        self.submit("first")
        self.submit("second")
        claimed = self.invoke("claim", "--worker", "validator-a")
        self.assertEqual(claimed["task"]["task_id"], "first")
        denied = self.invoke("claim", "--worker", "validator-b", expected_code=2)
        self.assertIn("held by first", denied["error"])
        self.invoke("complete", "first", "--outcome", "passed", "--evidence", "proof/first")
        claimed = self.invoke("claim", "--worker", "validator-b")
        self.assertEqual(claimed["task"]["task_id"], "second")

    def test_review_deadline_emits_attention_without_releasing_slot(self):
        self.submit("deadline")
        self.invoke("claim", "--worker", "validator-a")
        with sqlite3.connect(self.database) as connection:
            connection.execute(
                "UPDATE validation_tasks SET review_at = '2000-01-01T00:00:00+00:00' WHERE task_id = 'deadline'"
            )
        status = self.invoke("status")
        self.assertEqual(status["active"]["state"], "running")
        self.assertTrue(status["active"]["review_due"])
        self.assertTrue(status["notifications"])
        denied = self.invoke("claim", "--worker", "validator-b", expected_code=2)
        self.assertIn("held by deadline", denied["error"])

    def test_live_process_prevents_automatic_release(self):
        self.submit("live-process")
        self.invoke("claim", "--worker", "validator-a")
        self.invoke("record-process", "live-process", "--pid", str(os.getpid()))
        denied = self.invoke(
            "complete",
            "live-process",
            "--outcome",
            "failed",
            "--evidence",
            "proof/failure",
            expected_code=2,
        )
        self.assertIn("still alive", denied["error"])


if __name__ == "__main__":
    unittest.main()
