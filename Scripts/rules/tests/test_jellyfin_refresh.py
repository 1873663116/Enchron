import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))

import jellyfin_refresh


class JellyfinRefreshTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.state = Path(self.temporary.name)
        (self.state / "config").mkdir()
        (self.state / "config/service.local.json").write_text(json.dumps({"accessToken": "test-token"}))
        self.media = self.state / "media"
        self.media.mkdir()
        self.clip = self.media / "clip.mp4"
        self.clip.write_bytes(b"fixture")
        sources = {"mountPoint": str(self.media), "libraries": [{"name": "Movies", "locations": [str(self.media)], "knownFiles": [str(self.clip)]}]}
        (self.state / "config/refresh-sources.local.json").write_text(json.dumps(sources))

    def run_refresh(self, mount=None, state="Idle"):
        mounted = mount if mount is not None else f"localhost:/ on {self.media} (nfs, nodev, nosuid)"
        with patch.object(jellyfin_refresh.subprocess, "check_output", return_value=mounted):
            with patch.object(jellyfin_refresh, "request", return_value=[{"Name": "Scan Media Library", "State": state}]) as request:
                result = jellyfin_refresh.refresh(self.state)
        writes = [call.args[1] for call in request.call_args_list if call.kwargs.get("method", "GET") != "GET"]
        return result, writes

    def test_unmounted_cloud_does_not_scan(self):
        result, writes = self.run_refresh(mount="/dev/disk1 on / (apfs)")
        self.assertEqual(result["scanRequested"], False)
        self.assertEqual(writes, [])

    def test_empty_directory_does_not_scan(self):
        self.clip.unlink()
        result, writes = self.run_refresh()
        self.assertEqual(result["scanRequested"], False)
        self.assertEqual(writes, [])

    def test_unavailable_known_media_does_not_scan(self):
        self.clip.unlink()
        (self.media / "placeholder.txt").write_text("unmounted source")
        result, writes = self.run_refresh()
        self.assertEqual(result["scanRequested"], False)
        self.assertEqual(writes, [])

    def test_missing_source_configuration_does_not_scan(self):
        (self.state / "config/refresh-sources.local.json").unlink()
        result, writes = self.run_refresh()
        self.assertEqual(result["scanRequested"], False)
        self.assertEqual(writes, [])

    def test_running_scan_is_not_restarted(self):
        result, writes = self.run_refresh(state="Running")
        self.assertEqual(result["scanRequested"], False)
        self.assertEqual(writes, [])

    def test_ready_sources_request_one_scan(self):
        result, writes = self.run_refresh()
        self.assertEqual(result, {"scanRequested": True, "originalLibraries": 1})
        self.assertEqual(writes, ["/Library/Refresh"])


if __name__ == "__main__":
    unittest.main()
