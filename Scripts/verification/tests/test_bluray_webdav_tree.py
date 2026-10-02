from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bluray_webdav_tree import BluRayWebDAVTree
import regression_remote_source as remote


class BluRayWebDAVTreeTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        disc = self.root / "Samples/DiscImages/AVS/Disc"
        (disc / "BDMV/PLAYLIST").mkdir(parents=True)
        (disc / "BDMV/index.bdmv").write_bytes(b"index")
        (disc / "BDMV/PLAYLIST/00099.mpls").write_bytes(b"playlist")
        (disc.parent / "Disc.iso").write_bytes(b"image")
        self.registry = self.root / "registry.json"
        self.registry.write_text(json.dumps({
            "schemaVersion": 1,
            "discs": [
                {"id": "bluray-directory", "kind": "directory", "relativePath": "Samples/DiscImages/AVS/Disc"},
                {"id": "bluray-iso", "kind": "iso", "relativePath": "Samples/DiscImages/AVS/Disc.iso"},
            ],
        }))

    def test_only_registered_tree_is_visible(self) -> None:
        (self.root / "Samples/DiscImages/AVS/unregistered.txt").write_bytes(b"secret")
        tree = BluRayWebDAVTree(self.root, self.registry)
        self.assertEqual(tree.children("DiscImages/AVS"), [
            "DiscImages/AVS/Disc", "DiscImages/AVS/Disc.iso"
        ])
        self.assertEqual(tree.file("DiscImages/AVS/Disc/BDMV/index.bdmv").read_bytes(), b"index")
        self.assertIsNone(tree.file("DiscImages/AVS/unregistered.txt"))
        self.assertFalse(tree.contains("DiscImages/AVS/unregistered.txt"))

    def test_registered_directory_symlink_is_rejected(self) -> None:
        disc = self.root / "Samples/DiscImages/AVS/Disc"
        (disc / "outside.txt").symlink_to(self.root / "Samples/DiscImages/AVS/Disc.iso")
        with self.assertRaisesRegex(ValueError, "symlink"):
            BluRayWebDAVTree(self.root, self.registry)

    def test_webdav_propfind_and_range_are_bounded_to_registered_paths(self) -> None:
        service = object.__new__(remote.RemoteSourceService)
        service._bluray = BluRayWebDAVTree(self.root, self.registry)
        service._base_path = remote.BASE_PATH
        listing = service._bluray_response_locked(
            "PROPFIND", "DiscImages/AVS", {"Depth": "1"}, b""
        )
        self.assertEqual(listing.status, 207)
        self.assertIn(b"Disc.iso", listing.body)
        ranged = service._bluray_response_locked(
            "GET", "DiscImages/AVS/Disc.iso", {"Range": "bytes=1-3"}, None
        )
        self.assertEqual((ranged.status, ranged.body), (206, b"mag"))
        self.assertEqual(ranged.headers["Content-Range"], "bytes 1-3/5")
        self.assertEqual(service._bluray_response_locked(
            "GET", "DiscImages/AVS/Disc.iso", {}, None
        ).status, 416)
        self.assertEqual(service._bluray_response_locked(
            "GET", "DiscImages/AVS/not-registered.iso", {"Range": "bytes=0-1"}, None
        ).status, 404)
        self.assertEqual(service._parse_target_locked(
            "/dav/regression/DiscImages/AVS/%2e%2e/Disc.iso"
        )[0], "rejected")


if __name__ == "__main__":
    unittest.main()
