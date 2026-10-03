import hashlib
import importlib.util
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[3]
SCRIPT = REPO / "Scripts/fixtures/author_bluray_edition_fixture.py"


def load_author():
    spec = importlib.util.spec_from_file_location("author_bluray_edition_fixture", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def playlist_template() -> bytes:
    prefix = bytearray(58)
    prefix[:8] = b"MPLS0200"
    prefix[8:12] = struct.pack(">I", 58)
    body = bytearray(240)
    body[:9] = b"00000M2TS"
    body[10] = 1
    body[12:16] = struct.pack(">I", 600 * 45_000)
    body[16:20] = struct.pack(">I", 1_488 * 45_000)
    item = struct.pack(">H", len(body)) + body
    playlist = struct.pack(">IHHH", 6 + len(item), 0, 1, 0) + item
    mark = b"\0\x01" + struct.pack(">HIHI", 0, 600 * 45_000, 0xFFFF, 0)
    marks = struct.pack(">IH", 2 + len(mark), 1) + mark
    prefix[12:16] = struct.pack(">I", len(prefix) + len(playlist))
    return bytes(prefix) + playlist + marks


class AuthorBluRayEditionFixtureTests(unittest.TestCase):
    def setUp(self):
        self.author = load_author()

    def test_authors_literal_playitems_marks_and_durations(self):
        template = playlist_template()
        cases = {
            0: [(600, 620), (640, 660), (680, 700)],
            1: [(600, 620), (630, 655), (680, 700), (720, 730)],
            2: [(760, 770)],
        }
        expected_seconds = {0: 60, 1: 75, 2: 10}
        for playlist_id, segments in cases.items():
            authored = self.author.author_playlist(template, segments)
            parsed = self.author.parse_mpls_bytes(authored)
            self.assertEqual(parsed["duration90k"], expected_seconds[playlist_id] * 90_000)
            self.assertEqual(parsed["chapterCount"], len(segments))
            self.assertEqual(
                [(clip["inTime90k"], clip["outTime90k"]) for clip in parsed["clips"]],
                [(start * 90_000, end * 90_000) for start, end in segments],
            )
            self.assertTrue(all(clip["clipID"] == "00000" for clip in parsed["clips"]))

    def test_two_versions_share_fifty_five_seconds_in_order(self):
        reference = [(600, 620), (640, 660), (680, 700)]
        alternate = [(600, 620), (630, 655), (680, 700), (720, 730)]
        self.assertEqual(self.author.ordered_overlap_seconds(reference, alternate), 55)

    def test_movie_object_retargets_removed_immediate_playlist(self):
        header = bytearray(40)
        header[:8] = b"MOBJ0200"
        play_removed = bytes.fromhex("42820000") + struct.pack(">II", 1900, 10)
        play_register = bytes.fromhex("22000000") + struct.pack(">II", 10, 0)
        payload = b"\0\0\0\0" + struct.pack(">H", 1) + b"\x80\0" + struct.pack(">H", 2)
        payload += play_removed + play_register
        movie_object = bytes(header) + struct.pack(">I", len(payload)) + payload
        patched, count = self.author.retarget_movie_object(movie_object, 1900, 0)
        self.assertEqual(count, 1)
        self.assertEqual(int.from_bytes(patched[58:62], "big"), 0)
        self.assertEqual(patched[66:78], play_register)

    def test_existing_foreign_output_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "fixture"
            output.mkdir()
            (output / "SOURCE.json").write_text(json.dumps({"schema": "foreign/v1"}))
            with self.assertRaisesRegex(ValueError, "not an authored Sintel editions fixture"):
                self.author.validate_replaceable_output(output)

    def test_manifest_records_disclaimer_source_and_derived_hashes(self):
        files = {"00000.mpls": b"reference", "00001.mpls": b"alternate"}
        manifest = self.author.build_manifest(files, "disc-hash", "image-hash")
        self.assertFalse(manifest["officialReleaseVersions"])
        self.assertEqual(manifest["source"]["publisherMD5"], "edef70074bc275190a016f9eaeb478dd")
        self.assertEqual(manifest["derived"]["isoSHA256"], "image-hash")
        self.assertEqual(
            manifest["derived"]["files"]["00000.mpls"],
            hashlib.sha256(b"reference").hexdigest(),
        )
        self.assertEqual([item["durationSeconds"] for item in manifest["playlists"]], [60, 75, 10])


if __name__ == "__main__":
    unittest.main()
