import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "verify_bluray_corpus.py"
SPEC = importlib.util.spec_from_file_location("verify_bluray_corpus", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def one_clip_mpls() -> bytes:
    data = bytearray(90)
    data[:4] = b"MPLS"
    data[8:12] = (58).to_bytes(4, "big")
    data[58:62] = (28).to_bytes(4, "big")
    data[64:66] = (1).to_bytes(2, "big")
    data[68:70] = (20).to_bytes(2, "big")
    data[70:75] = b"00001"
    data[75:79] = b"M2TS"
    data[82:86] = (45_000).to_bytes(4, "big")
    data[86:90] = (90_000).to_bytes(4, "big")
    return bytes(data)


class VerifyBluRayCorpusTests(unittest.TestCase):
    def test_parse_mpls_uses_authored_playitem_ticks(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "00000.mpls"
            path.write_bytes(one_clip_mpls())
            self.assertEqual(MODULE.parse_mpls(path), {
                "duration90k": 90_000,
                "clips": [{"clipID": "00001", "startTime90k": 0,
                           "inTime90k": 90_000, "outTime90k": 180_000}],
            })

    def test_catalog_comparison_rejects_changed_product_duration(self):
        with tempfile.TemporaryDirectory() as directory:
            bdmv = Path(directory)
            playlist = bdmv / "PLAYLIST"
            stream = bdmv / "STREAM"
            playlist.mkdir()
            stream.mkdir()
            source = playlist / "00000.mpls"
            source.write_bytes(one_clip_mpls())
            (stream / "00001.m2ts").write_bytes(bytes(192))
            golden = {"playlist_count": 1, "stream_count": 1,
                      "duration90k": {0: 90_000}, "clip_ids": {0: ["00001"]},
                      "mpls_sha256": {0: MODULE.sha256(source)}}
            catalog = {"schema": "enchron.bluray.probe/v1", "titles": [{
                "playlistID": 0, "duration90k": 90_001,
                "clips": [{"clipID": "00001", "startTime90k": 0,
                           "inTime90k": 90_000, "outTime90k": 180_000,
                           "byteStart": 0, "byteEnd": 192, "streams": []}],
            }]}
            with self.assertRaisesRegex(AssertionError, "playlist 0 duration"):
                MODULE.verify_catalog(catalog, bdmv, golden, "fixture")

    def test_truncated_mpls_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "00000.mpls"
            path.write_bytes(one_clip_mpls()[:83])
            with self.assertRaisesRegex(ValueError, "section exceeds file"):
                MODULE.parse_mpls(path)


if __name__ == "__main__":
    unittest.main()
