from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))

import plex_normalized_media


class PlexNormalizedMediaTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / "original"
        self.source.mkdir()
        self.clip = self.source / "第100话 星海飞驰24.mp4"
        self.clip.write_bytes(b"original media")
        self.destination = self.root / "normalized"
        self.config = self.root / "config.json"
        self.config.write_text(json.dumps({"libraries": [{"sectionID": "4", "destination": str(self.destination), "rules": [{"source": str(self.source), "series": "Show", "season": 1}]}]}))
        self.target = self.destination / "Show/Season 01/Show - S01E100 - 第100话 星海飞驰24.mp4"

    def run_update(self):
        with redirect_stdout(io.StringIO()), patch.object(plex_normalized_media, "refresh", return_value=200) as refresh:
            result = plex_normalized_media.update(self.config)
        return result, refresh.call_args_list

    def test_chinese_episode_links_to_unchanged_media(self):
        result, calls = self.run_update()
        self.assertEqual(result["errors"], [])
        self.assertEqual(result["mappings"][0]["episode"], 100)
        self.assertTrue(self.target.is_symlink())
        self.assertEqual(self.target.resolve(), self.clip)
        self.assertEqual(self.clip.read_bytes(), b"original media")
        self.assertEqual([call.args for call in calls], [("4",)])

    def test_repeated_update_does_not_duplicate_or_refresh(self):
        self.run_update()
        result, calls = self.run_update()
        self.assertEqual(result["errors"], [])
        self.assertEqual(result["changedSections"], [])
        self.assertEqual(calls, [])
        self.assertEqual(list(self.destination.rglob("*.mp4")), [self.target])

    def test_conflicting_link_is_preserved(self):
        different = self.root / "other.mp4"
        different.write_bytes(b"other media")
        self.target.parent.mkdir(parents=True)
        self.target.symlink_to(different)
        result, calls = self.run_update()
        self.assertEqual([error["reason"] for error in result["errors"]], ["existing-link-target-differs"])
        self.assertEqual(self.target.resolve(), different)
        self.assertEqual(self.clip.read_bytes(), b"original media")
        self.assertEqual(calls, [])

    def test_unknown_naming_does_not_create_an_episode(self):
        self.clip.rename(self.source / "trailer24.mp4")
        result, calls = self.run_update()
        self.assertEqual(result["mappings"], [])
        self.assertEqual(calls, [])
        self.assertFalse(self.destination.exists())


if __name__ == "__main__":
    unittest.main()
