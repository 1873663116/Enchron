from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "services"))

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

    def test_explicit_season_folder_and_end_episode(self):
        self.clip.unlink()
        folder = self.source / 'Season 02'
        folder.mkdir()
        clip = folder / 'Show - 10 END (720p).mp4'
        clip.write_bytes(b'episode ten')
        config = json.loads(self.config.read_text())
        config['libraries'][0]['rules'][0]['mode'] = 'seasoned'
        self.config.write_text(json.dumps(config))
        result, _ = self.run_update()
        self.assertEqual([(x['season'], x['episode']) for x in result['mappings']], [(2, 10)])
        self.assertEqual(Path(result['mappings'][0]['link']).read_bytes(), b'episode ten')

    def test_unproven_season_is_not_invented(self):
        self.clip.rename(self.source / 'Show - 10 END (720p).mp4')
        config = json.loads(self.config.read_text())
        config['libraries'][0]['rules'][0]['mode'] = 'seasoned'
        self.config.write_text(json.dumps(config))
        result, calls = self.run_update()
        self.assertEqual(result['mappings'], [])
        self.assertEqual(calls, [])

    def test_unavailable_view_source_preserves_links_and_does_not_refresh(self):
        view = self.root / 'view'
        view.mkdir()
        retained = view / 'Show'
        retained.symlink_to(self.source)
        config = json.loads(self.config.read_text())
        config['libraries'][0].update({'sourceView': str(view), 'sourceRoot': str(self.root / 'unmounted'), 'excludedDirectories': ['Show']})
        self.config.write_text(json.dumps(config))
        result, calls = self.run_update()
        self.assertTrue(retained.is_symlink())
        self.assertEqual(retained.resolve(), self.source)
        self.assertEqual(calls, [])
        self.assertEqual(result['errors'][0]['reason'], 'FileNotFoundError')

    def test_same_name_extras_report_conflict_and_preserve_first(self):
        self.clip.unlink()
        for name in ['one', 'two']:
            folder = self.source / name
            folder.mkdir()
            (folder / 'NCOP.mp4').write_bytes(name.encode())
        config = json.loads(self.config.read_text())
        config['libraries'][0]['rules'][0]['mode'] = 'extras'
        self.config.write_text(json.dumps(config))
        result, _ = self.run_update()
        self.assertEqual(len(result['mappings']), 1)
        self.assertEqual([x['reason'] for x in result['errors']], ['existing-link-target-differs'])
        self.assertIn((self.destination / 'Show/Other/NCOP.mp4').read_bytes(), [b'one', b'two'])

    def test_same_name_videos_report_conflict_and_preserve_first(self):
        self.clip.unlink()
        for name in ['one', 'two']:
            folder = self.source / name
            folder.mkdir()
            (folder / 'movie.mp4').write_bytes(name.encode())
        config = json.loads(self.config.read_text())
        config['libraries'][0]['rules'][0]['mode'] = 'videos'
        self.config.write_text(json.dumps(config))
        result, _ = self.run_update()
        self.assertEqual(len(result['mappings']), 1)
        self.assertEqual([x['reason'] for x in result['errors']], ['existing-link-target-differs'])
        self.assertIn((self.destination / 'Show/movie/movie.mp4').read_bytes(), [b'one', b'two'])

    def test_new_unknown_media_fallback_preserves_subdirectories_and_is_idempotent(self):
        self.clip.unlink()
        for name in ['one', 'two']:
            folder = self.source / name
            folder.mkdir()
            (folder / 'unknown.mp4').write_bytes(name.encode())
        self.config.write_text(json.dumps({'libraries': [{'sectionID': '8', 'destination': str(self.destination), 'fallbackSources': [{'source': str(self.source), 'primarySectionIDs': ['5']}]}]}))
        with patch.object(plex_normalized_media, 'primary_files', return_value=set()):
            first, calls = self.run_update()
            second, repeated_calls = self.run_update()
        self.assertEqual(first['errors'], [])
        self.assertEqual(len(first['mappings']), 2)
        self.assertEqual({Path(x['link']).read_bytes() for x in first['mappings']}, {b'one', b'two'})
        self.assertEqual([x.args for x in calls], [('8',)])
        self.assertEqual(repeated_calls, [])
        self.assertEqual(second['mappings'], first['mappings'])

    def test_fallback_is_removed_when_primary_import_becomes_available(self):
        self.config.write_text(json.dumps({'libraries': [{'sectionID': '8', 'destination': str(self.destination), 'fallbackSources': [{'source': str(self.source), 'primarySectionIDs': ['5']}]}]}))
        with patch.object(plex_normalized_media, 'primary_files', return_value=set()):
            first, _ = self.run_update()
        target = Path(first['mappings'][0]['link'])
        with patch.object(plex_normalized_media, 'primary_files', return_value={str(self.clip)}):
            second, calls = self.run_update()
        self.assertEqual(second['mappings'], [])
        self.assertFalse(target.is_symlink())
        self.assertEqual(self.clip.read_bytes(), b'original media')
        self.assertEqual([x.args for x in calls], [('8',)])

    def test_unavailable_fallback_preserves_links_without_refresh(self):
        config = {'libraries': [{'sectionID': '8', 'destination': str(self.destination), 'fallbackSources': [{'source': str(self.source), 'primarySectionIDs': ['5']}]}]}
        self.config.write_text(json.dumps(config))
        with patch.object(plex_normalized_media, 'primary_files', return_value=set()):
            first, _ = self.run_update()
        target = Path(first['mappings'][0]['link'])
        self.source.rename(self.root / 'unmounted')
        second, calls = self.run_update()
        self.assertTrue(target.is_symlink())
        self.assertEqual(second['mappings'], first['mappings'])
        self.assertEqual(second['errors'][0]['operation'], 'fallback-inventory')
        self.assertEqual(calls, [])

    def test_primary_inventory_paginates_and_includes_nested_extras(self):
        pages = [
            {'MediaContainer': {'totalSize': 2, 'Metadata': [{'Media': [{'Part': [{'file': str(self.clip)}]}]}]}},
            {'MediaContainer': {'totalSize': 2, 'Metadata': [{'Extras': {'Metadata': [{'Media': [{'Part': [{'file': str(self.root / 'extra.mp4')}]}]}]}}]}},
            {'MediaContainer': {'size': 0}},
        ]
        with patch.object(plex_normalized_media, 'plex_request', side_effect=[(200, x) for x in pages]) as api:
            paths = plex_normalized_media.primary_files(['5'])
        self.assertEqual(paths, {str(self.clip), str(self.root / 'extra.mp4')})
        self.assertEqual([(x.args[1]['type'], x.args[1]['X-Plex-Container-Start']) for x in api.call_args_list], [(4, 0), (4, 1), (12, 0)])


if __name__ == "__main__":
    unittest.main()
