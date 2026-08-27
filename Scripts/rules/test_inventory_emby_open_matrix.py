import unittest
from unittest.mock import patch

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import inventory_emby_open_matrix as inventory


class EmbyVersionInventoryTests(unittest.TestCase):
    def test_catalog_paginates_through_all_128_items(self) -> None:
        items = [
            {
                "Id": f"item-{index}",
                "Type": "Movie",
                "MediaSources": [{"Id": f"source-{index}"}],
            }
            for index in range(128)
        ]

        def page(_address, _path, *, token, query):
            self.assertEqual(token, "token")
            start = int(query["StartIndex"])
            limit = int(query["Limit"])
            return {
                "Items": items[start:start + limit],
                "TotalRecordCount": len(items),
            }

        with patch.object(inventory, "request", side_effect=page) as mocked:
            catalog = inventory.catalog_sources(
                "https://example.invalid", "token", "user", page_size=50
            )

        self.assertEqual(len(catalog), 128)
        self.assertEqual(inventory.summarize_version_inventory(catalog)["itemCount"], 128)
        self.assertEqual(mocked.call_count, 3)

    def test_summary_counts_all_items_without_exposing_catalog_values(self) -> None:
        catalog = [
            {
                "item": {"Id": "item-a", "Name": "Private A", "Type": "Movie"},
                "source": {"Id": "source-a1", "Path": "/private/a1"},
            },
            {
                "item": {"Id": "item-a", "Name": "Private A", "Type": "Movie"},
                "source": {"Id": "source-a2", "Path": "/private/a2"},
            },
            {
                "item": {"Id": "item-b", "Name": "Private B", "Type": "Episode"},
                "source": {"Id": "source-b1", "Path": "/private/b1"},
            },
            {
                "item": {"Id": "item-c", "Name": "Private C", "Type": "Video"},
                "source": None,
            },
        ]

        summary = inventory.summarize_version_inventory(catalog)
        serialized = str(summary)

        self.assertEqual(summary["itemCount"], 3)
        self.assertEqual(summary["mediaSourceCount"], 3)
        self.assertEqual(summary["itemsWithMultipleMediaSources"], 1)
        self.assertEqual(summary["maxMediaSourcesPerItem"], 2)
        self.assertEqual(summary["mediaSourcesPerItem"], {"0": 1, "1": 1, "2": 1})
        self.assertEqual(len(summary["multipleMediaSourceItemDigests"]), 1)
        self.assertNotIn("Private", serialized)
        self.assertNotIn("/private", serialized)
        self.assertNotIn("item-a", serialized)


if __name__ == "__main__":
    unittest.main()
