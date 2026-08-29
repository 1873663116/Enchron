#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import replace
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts/verification"))

import regression_emby_source as emby


FIXTURE_ID = "generated-sdr-avc-bframe-aggregate-30s-v1"
FIXTURE_BYTES = bytes(range(256)) * 16
SUBTITLE_FIXTURE_ID = "generated-sdr-avc-bframe-aggregate-external-subrip-zh-cn-v1"
SUBTITLE_BYTES = b"1\n00:00:00,500 --> 00:00:29,500\nEnchron external sidecar SubRip\n"
SERVER_ID = "server-regression"
USER_ID = "user-regression"


class FakeBoundary:
    def __init__(self) -> None:
        self.actual_server_id = SERVER_ID
        self.actual_user_id = USER_ID
        self.library_id: str | None = None
        self.library_path: Path | None = None
        self.user_data = {
            "PlaybackPositionTicks": 0,
            "Played": False,
            "PlayCount": 0,
            "IsFavorite": False,
        }
        self.seed_failure: Exception | None = None
        self.restore_failure: Exception | None = None
        self.wait_failure: Exception | None = None
        self.add_count = 0
        self.remove_count = 0
        self.media_read_count = 0
        self.subtitle_read_count = 0
        self.artwork_request_count = 0
        self.user_data_write_count = 0

    def authenticate(self, credentials, *, deadline_seconds):
        self.last_credentials = credentials
        self.last_authentication_deadline = deadline_seconds
        return emby.AuthenticatedSession(
            server_id=self.actual_server_id,
            user_id=self.actual_user_id,
            access_token="boundary-token-that-must-never-leak",
        )

    def library(self, session, name):
        if self.library_id is None:
            return None
        return emby.LibraryBinding(self.library_id, name, self.library_path)

    def add_library(self, session, name, path):
        self.add_count += 1
        self.library_id = "library-regression"
        self.library_path = path
        return self.library_id

    def refresh_library(self, session):
        if self.seed_failure is not None:
            raise self.seed_failure

    def catalog(self, session, library_name, *, deadline_seconds):
        self.last_catalog_deadline = deadline_seconds
        return emby.CatalogBinding(
            library_id=self.library_id or "library-regression",
            series_id="series-regression",
            season_id="season-regression",
            episode_id="episode-regression",
            media_source_id="source-regression",
            media_path=self.library_path
            / emby.SERIES_DIRECTORY
            / emby.SEASON_DIRECTORY
            / emby.EPISODE_FILE_NAME,
            image_tag="image-tag-regression",
            external_subtitle_stream_index=9,
            external_subtitle_codec="subrip",
            external_subtitle_delivery_path="/Videos/episode-regression/Subtitles/9/Stream.srt",
        )

    def user_data_for(self, session, item_id):
        return dict(self.user_data)

    def set_user_data(self, session, item_id, value):
        self.user_data_write_count += 1
        self.user_data = dict(value)

    def media_bytes(self, session, catalog, *, deadline_seconds):
        self.last_media_deadline = deadline_seconds
        self.media_read_count += 1
        return FIXTURE_BYTES

    def external_subtitle_bytes(self, session, catalog, *, deadline_seconds):
        self.last_subtitle_deadline = deadline_seconds
        self.subtitle_read_count += 1
        return SUBTITLE_BYTES

    def request_artwork(self, session, catalog, *, deadline_seconds):
        self.last_artwork_deadline = deadline_seconds
        self.artwork_request_count += 1
        return emby.ArtworkRequestFact(
            request_path=(
                "/Items/series-regression/Images/Primary"
                "?Tag=image-tag-regression&MaxWidth=420"
            ),
            status_code=200,
            response_digest="sha256:" + hashlib.sha256(b"image").hexdigest(),
            loopback_hit_count=0,
        )

    def remove_library(self, session, library_id):
        if self.restore_failure is not None:
            raise self.restore_failure
        self.remove_count += 1
        self.library_id = None
        self.library_path = None

    def wait_until_library_absent(
        self, session, library_name, *, deadline_seconds
    ):
        self.last_restore_deadline = deadline_seconds
        if self.wait_failure is not None:
            raise self.wait_failure
        if self.library_id is not None:
            raise emby.EmbyRestoreError("owned library remained present")


class FakeHTTPBoundary(emby.HTTPEmbyBoundary):
    def __init__(self, stream_index: int) -> None:
        super().__init__()
        self._address = "http://127.0.0.1:8096"
        self.stream_index = stream_index
        self.playback_body = None

    def library(self, session, name):
        return emby.LibraryBinding("library-regression", name, Path("/fixture"))

    def _single_item(self, session, *, parent_id, item_type, name=None):
        if item_type == "Series":
            return {
                "Id": "series-regression",
                "ImageTags": {"Primary": "image-tag-regression"},
            }
        if item_type == "Season":
            return {"Id": "season-regression"}
        if item_type == "Episode":
            return {"Id": "episode-regression"}
        raise AssertionError(item_type)

    def _json_request(
        self,
        method,
        relative_path,
        *,
        session=None,
        query=None,
        body=None,
        timeout,
        authorization=None,
        allow_empty=False,
    ):
        self.playback_body = body
        return {
            "MediaSources": [{
                "Id": "source-regression",
                "Path": "/fixture/episode.mkv",
                "MediaStreams": [{
                    "Type": "Subtitle",
                    "IsExternal": True,
                    "Index": self.stream_index,
                    "Codec": "subrip",
                    "DeliveryUrl": (
                        "http://127.0.0.1:8096/Videos/episode-regression/"
                        f"Subtitles/{self.stream_index}/Stream.srt?api_key=secret&format=srt"
                    ),
                }],
            }]
        }


class RegressionEmbySourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="emby-source-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source_root = self.root / "TestMedia"
        relative = Path("TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.mkv")
        source = self.source_root / relative
        source.parent.mkdir(parents=True)
        source.write_bytes(FIXTURE_BYTES)
        subtitle_relative = Path(
            "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.zh-CN.srt"
        )
        subtitle_source = self.source_root / subtitle_relative
        subtitle_source.write_bytes(SUBTITLE_BYTES)
        self.registry = self.root / "fixture-registry.json"
        self.registry.write_text(
            json.dumps(
                {
                    "schemaVersion": 2,
                    "deviceMediaRoot": "$WORKSPACE/TestMedia",
                    "fixtures": [
                        {
                            "id": FIXTURE_ID,
                            "deviceImportPath": relative.as_posix(),
                            "sha256": hashlib.sha256(FIXTURE_BYTES).hexdigest(),
                            "regressionSets": ["remote-aggregate"],
                        },
                        {
                            "id": SUBTITLE_FIXTURE_ID,
                            "deviceImportPath": subtitle_relative.as_posix(),
                            "sha256": hashlib.sha256(SUBTITLE_BYTES).hexdigest(),
                            "regressionSets": ["remote-aggregate"],
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        self.identity = self.root / "emby-runtime.json"
        self.identity.write_text(
            json.dumps(
                {
                    "schema": emby.RUNTIME_IDENTITY_SCHEMA,
                    "address": "http://127.0.0.1:8096",
                    "username": "regression-user",
                    "password": "runtime-password-that-must-never-leak",
                    "serverID": SERVER_ID,
                    "userID": USER_ID,
                }
            ),
            encoding="utf-8",
        )
        os.chmod(self.identity, 0o600)
        self.configuration = emby.EmbySourceConfiguration(
            runtime_root=self.root / "runtime",
            identity_file=self.identity,
            registry_path=self.registry,
            source_root=self.source_root,
        )
        self.boundary = FakeBoundary()
        self.controller = emby.EmbySourceController(
            self.configuration, boundary=self.boundary
        )

    def test_seed_receipt_binds_bytes_catalog_hierarchy_progress_and_artwork(self) -> None:
        report = self.controller.ensure()

        self.assertEqual(report["schema"], emby.PREFLIGHT_REPORT_SCHEMA)
        self.assertEqual(report["check"], "emby-aggregate")
        self.assertTrue(report["ready"])
        receipt = report["receipt"]
        self.assertEqual(receipt["schema"], emby.SEED_RECEIPT_SCHEMA)
        self.assertEqual(receipt["status"], "active")
        self.assertEqual(receipt["fixture"]["registryID"], FIXTURE_ID)
        self.assertEqual(
            receipt["fixture"]["digest"],
            "sha256:" + hashlib.sha256(FIXTURE_BYTES).hexdigest(),
        )
        self.assertEqual(
            receipt["externalSubtitle"],
            {
                "registryID": SUBTITLE_FIXTURE_ID,
                "fileName": emby.EXTERNAL_SUBTITLE_FILE_NAME,
                "digest": "sha256:" + hashlib.sha256(SUBTITLE_BYTES).hexdigest(),
                "streamIndex": 9,
                "codec": "subrip",
                "deliveryPath": "/Videos/episode-regression/Subtitles/9/Stream.srt",
                "servedDigest": "sha256:" + hashlib.sha256(SUBTITLE_BYTES).hexdigest(),
            },
        )
        self.assertEqual(
            receipt["catalog"],
            {
                "libraryID": "library-regression",
                "seriesID": "series-regression",
                "seasonID": "season-regression",
                "episodeID": "episode-regression",
                "mediaSourceID": "source-regression",
                "progressTicks": emby.SEEDED_PROGRESS_TICKS,
                "imageTag": "image-tag-regression",
                "artworkRequestPath": (
                    "/Items/series-regression/Images/Primary"
                    "?Tag=image-tag-regression&MaxWidth=420"
                ),
                "artworkStatusCode": 200,
                "artworkResponseDigest": "sha256:"
                + hashlib.sha256(b"image").hexdigest(),
                "loopbackHitCount": 0,
            },
        )
        self.assertEqual(
            receipt["originalUserData"],
            {"PlaybackPositionTicks": 0, "Played": False},
        )
        self.assertEqual(self.boundary.user_data["PlaybackPositionTicks"], emby.SEEDED_PROGRESS_TICKS)
        self.assertEqual(self.boundary.last_authentication_deadline, 90)
        self.assertEqual(self.boundary.last_catalog_deadline, 90)
        self.assertEqual(self.boundary.last_media_deadline, 90)
        self.assertEqual(self.boundary.last_subtitle_deadline, 90)
        self.assertEqual(self.boundary.last_artwork_deadline, 90)
        seeded_sidecar = (
            self.configuration.library_root
            / emby.SERIES_DIRECTORY
            / emby.SEASON_DIRECTORY
            / emby.EXTERNAL_SUBTITLE_FILE_NAME
        )
        self.assertEqual(seeded_sidecar.read_bytes(), SUBTITLE_BYTES)

    def test_secret_values_never_enter_report_receipt_or_rendered_failure(self) -> None:
        remote_sentinel = "remote-token-that-must-never-enter-evidence"
        self.boundary.user_data["AccessToken"] = remote_sentinel
        report = self.controller.ensure()
        rendered = emby.render_report(report)
        for forbidden in (
            "regression-user",
            "runtime-password-that-must-never-leak",
            "boundary-token-that-must-never-leak",
            remote_sentinel,
        ):
            self.assertNotIn(forbidden, rendered)
        self.assertNotIn("accessToken", rendered)
        self.assertNotIn("authorization", rendered.casefold())

        self.boundary.seed_failure = RuntimeError(
            "runtime-password-that-must-never-leak failed"
        )
        self.controller.restore(report["receipt"]["receiptID"])
        failed = emby.run_preflight(self.configuration, boundary=self.boundary)
        rendered_failure = emby.render_report(failed)
        self.assertFalse(failed["ready"])
        self.assertNotIn("runtime-password-that-must-never-leak", rendered_failure)

    def test_receipt_validator_rejects_noncanonical_or_credentialed_facts(self) -> None:
        report = self.controller.ensure()
        receipt = json.loads(json.dumps(report["receipt"]))
        receipt["catalog"]["artworkRequestPath"] += "&api_key=forbidden"
        self.assertFalse(
            emby.validate_seed_receipt(
                receipt,
                runtime_file=self.configuration.identity_file,
            )
        )

        receipt = json.loads(json.dumps(report["receipt"]))
        receipt["fixture"]["catalogByteDigest"] = "sha256:not-a-digest"
        self.assertFalse(
            emby.validate_seed_receipt(
                receipt,
                runtime_file=self.configuration.identity_file,
            )
        )

        receipt = json.loads(json.dumps(report["receipt"]))
        receipt["externalSubtitle"]["streamIndex"] = "9"
        self.assertFalse(
            emby.validate_seed_receipt(
                receipt,
                runtime_file=self.configuration.identity_file,
            )
        )

        receipt = json.loads(json.dumps(report["receipt"]))
        receipt["externalSubtitle"]["deliveryPath"] += "?api_key=forbidden"
        self.assertFalse(
            emby.validate_seed_receipt(
                receipt,
                runtime_file=self.configuration.identity_file,
            )
        )

        receipt = json.loads(json.dumps(report["receipt"]))
        receipt["originalUserData"]["AccessToken"] = "credential-shaped-sentinel"
        self.assertFalse(
            emby.validate_seed_receipt(
                receipt,
                runtime_file=self.configuration.identity_file,
            )
        )

    def test_receipt_validator_requires_exact_typed_original_playback_state(self) -> None:
        report = self.controller.ensure()

        for missing in ("PlaybackPositionTicks", "Played"):
            with self.subTest(missing=missing):
                receipt = json.loads(json.dumps(report["receipt"]))
                del receipt["originalUserData"][missing]
                self.assertFalse(
                    emby.validate_seed_receipt(
                        receipt,
                        runtime_file=self.configuration.identity_file,
                    )
                )

        invalid_values = {
            "PlaybackPositionTicks": (True, -1, "0", None),
            "Played": (0, "false", None),
        }
        for field, values in invalid_values.items():
            for value in values:
                with self.subTest(field=field, value=value):
                    receipt = json.loads(json.dumps(report["receipt"]))
                    receipt["originalUserData"][field] = value
                    self.assertFalse(
                        emby.validate_seed_receipt(
                            receipt,
                            runtime_file=self.configuration.identity_file,
                        )
                    )

    def test_seed_rejects_missing_or_invalid_original_playback_state(self) -> None:
        invalid_documents = (
            {"Played": False},
            {"PlaybackPositionTicks": 0},
            {"PlaybackPositionTicks": True, "Played": False},
            {"PlaybackPositionTicks": -1, "Played": False},
            {"PlaybackPositionTicks": 0, "Played": 0},
        )
        for document in invalid_documents:
            with self.subTest(document=document):
                self.boundary.user_data = dict(document)
                with self.assertRaisesRegex(emby.EmbySeedError, "seed failed"):
                    self.controller.ensure()
                self.assertEqual(self.boundary.user_data_write_count, 0)
                self.assertFalse(self.configuration.active_receipt_file.exists())
                self.assertIsNone(self.boundary.library_id)

    def test_restore_merges_only_the_original_playback_state(self) -> None:
        original = {
            "PlaybackPositionTicks": 25_000_000,
            "Played": True,
            "PlayCount": 7,
            "IsFavorite": True,
        }
        self.boundary.user_data = dict(original)
        report = self.controller.ensure()
        receipt = report["receipt"]
        self.assertEqual(
            receipt["originalUserData"],
            {"PlaybackPositionTicks": 25_000_000, "Played": True},
        )

        self.boundary.user_data["PlayCount"] = 8
        restored = self.controller.restore(receipt["receiptID"])

        self.assertEqual(restored["status"], "restored")
        self.assertEqual(
            self.boundary.user_data,
            {
                "PlaybackPositionTicks": 25_000_000,
                "Played": True,
                "PlayCount": 8,
                "IsFavorite": True,
            },
        )

    def test_wrong_runtime_server_or_user_identity_fails_before_seed(self) -> None:
        self.boundary.actual_server_id = "different-server"
        with self.assertRaisesRegex(emby.EmbyIdentityError, "server identity"):
            self.controller.ensure()
        self.assertEqual(self.boundary.add_count, 0)

        self.boundary.actual_server_id = SERVER_ID
        self.boundary.actual_user_id = "different-user"
        with self.assertRaisesRegex(emby.EmbyIdentityError, "account identity"):
            self.controller.ensure()
        self.assertEqual(self.boundary.add_count, 0)

    def test_runtime_identity_must_be_owner_only_0600(self) -> None:
        os.chmod(self.identity, 0o644)
        with self.assertRaisesRegex(emby.EmbyIdentityError, "0600"):
            self.controller.ensure()

    def test_seed_failure_rolls_back_owned_library_and_publishes_no_receipt(self) -> None:
        self.boundary.seed_failure = RuntimeError("scan failed")
        with self.assertRaisesRegex(emby.EmbySeedError, "seed failed"):
            self.controller.ensure()
        self.assertIsNone(self.boundary.library_id)
        self.assertEqual(self.boundary.remove_count, 1)
        self.assertFalse(self.configuration.active_receipt_file.exists())
        self.assertFalse(self.configuration.library_root.exists())

    def test_restore_failure_preserves_active_receipt_for_retry(self) -> None:
        report = self.controller.ensure()
        receipt_id = report["receipt"]["receiptID"]
        self.boundary.restore_failure = RuntimeError("remove failed")

        with self.assertRaisesRegex(emby.EmbyRestoreError, "restore failed"):
            self.controller.restore(receipt_id)
        active = json.loads(
            self.configuration.active_receipt_file.read_text(encoding="utf-8")
        )
        self.assertEqual(active["status"], "active")

        self.boundary.restore_failure = None
        restored = self.controller.restore(receipt_id)
        self.assertEqual(restored["status"], "restored")

    def test_restore_retry_converges_after_removal_completed_before_wait_failed(self) -> None:
        report = self.controller.ensure()
        receipt_id = report["receipt"]["receiptID"]
        self.boundary.wait_failure = RuntimeError("wait transport failed")

        with self.assertRaisesRegex(emby.EmbyRestoreError, "restore failed"):
            self.controller.restore(receipt_id)
        self.assertIsNone(self.boundary.library_id)
        active = json.loads(
            self.configuration.active_receipt_file.read_text(encoding="utf-8")
        )
        self.assertEqual(active["status"], "active")

        self.boundary.wait_failure = None
        restored = self.controller.restore(receipt_id)
        self.assertEqual(restored["status"], "restored")
        self.assertEqual(self.boundary.remove_count, 1)

    def test_ensure_and_restore_are_idempotent(self) -> None:
        first = self.controller.ensure()
        second = self.controller.ensure()
        self.assertEqual(first, second)
        self.assertEqual(self.boundary.add_count, 1)
        self.assertEqual(self.boundary.media_read_count, 2)
        self.assertEqual(self.boundary.subtitle_read_count, 2)
        self.assertEqual(self.boundary.artwork_request_count, 2)

        receipt_id = first["receipt"]["receiptID"]
        restored_first = self.controller.restore(receipt_id)
        restored_second = self.controller.restore(receipt_id)
        self.assertEqual(restored_first, restored_second)
        self.assertEqual(self.boundary.remove_count, 1)
        self.assertFalse(self.configuration.library_root.exists())

        third = self.controller.ensure()
        self.assertEqual(
            third["receipt"]["receiptID"], first["receipt"]["receiptID"]
        )
        self.assertEqual(self.boundary.add_count, 2)

    def test_fixture_digest_mismatch_fails_before_service_mutation(self) -> None:
        source = next(self.source_root.rglob("*.mkv"))
        source.write_bytes(b"changed")
        with self.assertRaisesRegex(emby.EmbyFixtureError, "digest"):
            self.controller.ensure()
        self.assertEqual(self.boundary.add_count, 0)

    def test_external_subtitle_digest_mismatch_fails_before_service_mutation(self) -> None:
        source = next(self.source_root.rglob("*.srt"))
        source.write_bytes(b"changed")
        with self.assertRaisesRegex(emby.EmbyFixtureError, "digest"):
            self.controller.ensure()
        self.assertEqual(self.boundary.add_count, 0)

    def test_product_and_harness_deadlines_are_distinct_fixed_contracts(self) -> None:
        self.assertEqual(emby.PRODUCT_DEADLINE_SECONDS, 45)
        self.assertEqual(emby.HARNESS_LIVENESS_DEADLINE_SECONDS, 90)
        self.assertLess(
            emby.PRODUCT_DEADLINE_SECONDS,
            emby.HARNESS_LIVENESS_DEADLINE_SECONDS,
        )
        with self.assertRaises(emby.EmbyConfigurationError):
            replace(
                self.configuration,
                harness_liveness_deadline_seconds=89,
            )

    def test_http_boundary_encodes_query_after_the_path(self) -> None:
        boundary = emby.HTTPEmbyBoundary()
        boundary._address = "http://127.0.0.1:8096"
        self.assertEqual(
            boundary._url(
                "/Users/user/Items",
                {"ParentId": "library", "IncludeItemTypes": "Series"},
            ),
            "http://127.0.0.1:8096/Users/user/Items?ParentId=library&IncludeItemTypes=Series",
        )

    def test_http_catalog_uses_actual_external_stream_index_and_strips_secret(self) -> None:
        boundary = FakeHTTPBoundary(stream_index=23)
        catalog = boundary.catalog(
            emby.AuthenticatedSession(SERVER_ID, USER_ID, "secret-token"),
            emby.LIBRARY_NAME,
            deadline_seconds=1,
        )

        self.assertEqual(catalog.external_subtitle_stream_index, 23)
        self.assertEqual(catalog.external_subtitle_codec, "subrip")
        self.assertEqual(
            catalog.external_subtitle_delivery_path,
            "/Videos/episode-regression/Subtitles/23/Stream.srt?format=srt",
        )
        self.assertEqual(
            boundary.playback_body,
            {
                "UserId": USER_ID,
                "EnableDirectPlay": True,
                "EnableDirectStream": False,
                "EnableTranscoding": False,
                "IsPlayback": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
