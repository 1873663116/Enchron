#!/usr/bin/env python3
"""Own and verify the reversible Emby regression library."""

from __future__ import annotations

import argparse
import base64
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile
import time
from typing import Mapping, Protocol
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ID = "generated-sdr-avc-bframe-aggregate-30s-v1"
EXTERNAL_SUBTITLE_FIXTURE_ID = (
    "generated-sdr-avc-bframe-aggregate-external-subrip-zh-cn-v1"
)
LIBRARY_NAME = "Enchron Regression Emby"
SERIES_NAME = "Enchron Regression Series"
SERIES_DIRECTORY = SERIES_NAME
SEASON_DIRECTORY = "Season 01"
EPISODE_FILE_NAME = "Enchron Regression Episode - S01E01.mkv"
EXTERNAL_SUBTITLE_FILE_NAME = "Enchron Regression Episode - S01E01.zh-CN.srt"
SECOND_SEASON_DIRECTORY = "Season 02"
SECOND_EPISODE_FILE_NAME = "Enchron Regression Episode 2 - S02E01.mkv"
SEEDED_PROGRESS_TICKS = 100_000_000
PRODUCT_DEADLINE_SECONDS = 45
HARNESS_LIVENESS_DEADLINE_SECONDS = 90
RUNTIME_IDENTITY_SCHEMA = "enchron.regression.emby-runtime-identity@1"
PREFLIGHT_REPORT_SCHEMA = "enchron.regression.emby-source-preflight@1"
SEED_RECEIPT_SCHEMA = "enchron.regression.emby-seed-receipt@2"
SHA256 = "sha256:"
ORIGINAL_PLAYBACK_STATE_FIELDS = frozenset(
    {"PlaybackPositionTicks", "Played"}
)
DEFAULT_RUNTIME_ROOT = REPOSITORY_ROOT / ".build/regression-emby-source"
DEFAULT_IDENTITY_FILE = (
    REPOSITORY_ROOT
    / "Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json"
)
DEFAULT_REGISTRY = REPOSITORY_ROOT / "Tests/Fixtures/fixture-registry.json"
DEFAULT_SOURCE_ROOT = REPOSITORY_ROOT.parent / "TestMedia"
SOURCE_PATH = Path(__file__).resolve()


class EmbySourceError(RuntimeError):
    pass


class EmbyConfigurationError(EmbySourceError):
    pass


class EmbyIdentityError(EmbySourceError):
    pass


class EmbyFixtureError(EmbySourceError):
    pass


class EmbySeedError(EmbySourceError):
    pass


class EmbyRestoreError(EmbySourceError):
    pass


@dataclass(frozen=True)
class RuntimeIdentity:
    address: str
    username: str
    password: str
    server_id: str
    user_id: str


@dataclass(frozen=True)
class AuthenticatedSession:
    server_id: str
    user_id: str
    access_token: str


@dataclass(frozen=True)
class LibraryBinding:
    identifier: str
    name: str
    path: Path | None


@dataclass(frozen=True)
class CatalogBinding:
    library_id: str
    series_id: str
    season_id: str
    episode_id: str
    media_source_id: str
    media_path: Path
    image_tag: str
    external_subtitle_stream_index: int
    external_subtitle_codec: str
    external_subtitle_delivery_path: str


@dataclass(frozen=True)
class ArtworkRequestFact:
    request_path: str
    status_code: int
    response_digest: str
    loopback_hit_count: int


@dataclass(frozen=True)
class FixtureBinding:
    identifier: str
    source: Path
    digest: str


@dataclass(frozen=True)
class EmbySourceConfiguration:
    runtime_root: Path = DEFAULT_RUNTIME_ROOT
    identity_file: Path = DEFAULT_IDENTITY_FILE
    registry_path: Path = DEFAULT_REGISTRY
    source_root: Path = DEFAULT_SOURCE_ROOT
    product_deadline_seconds: int = PRODUCT_DEADLINE_SECONDS
    harness_liveness_deadline_seconds: int = HARNESS_LIVENESS_DEADLINE_SECONDS

    def __post_init__(self) -> None:
        if self.product_deadline_seconds != PRODUCT_DEADLINE_SECONDS:
            raise EmbyConfigurationError("product deadline must be exactly 45 seconds")
        if self.harness_liveness_deadline_seconds != HARNESS_LIVENESS_DEADLINE_SECONDS:
            raise EmbyConfigurationError("harness liveness deadline must be exactly 90 seconds")

    @property
    def library_root(self) -> Path:
        return self.runtime_root / "library"

    @property
    def active_receipt_file(self) -> Path:
        return self.runtime_root / "seed-receipt.json"


DEFAULT_CONFIGURATION = EmbySourceConfiguration()


class EmbyBoundary(Protocol):
    def authenticate(
        self, credentials: RuntimeIdentity, *, deadline_seconds: int
    ) -> AuthenticatedSession: ...

    def library(
        self, session: AuthenticatedSession, name: str
    ) -> LibraryBinding | None: ...

    def add_library(
        self, session: AuthenticatedSession, name: str, path: Path
    ) -> str: ...

    def refresh_library(self, session: AuthenticatedSession) -> None: ...

    def catalog(
        self,
        session: AuthenticatedSession,
        library_name: str,
        *,
        deadline_seconds: int,
    ) -> CatalogBinding: ...

    def user_data_for(
        self, session: AuthenticatedSession, item_id: str
    ) -> dict[str, object]: ...

    def set_user_data(
        self, session: AuthenticatedSession, item_id: str, value: Mapping[str, object]
    ) -> None: ...

    def media_bytes(
        self,
        session: AuthenticatedSession,
        catalog: CatalogBinding,
        *,
        deadline_seconds: int,
    ) -> bytes: ...

    def external_subtitle_bytes(
        self,
        session: AuthenticatedSession,
        catalog: CatalogBinding,
        *,
        deadline_seconds: int,
    ) -> bytes: ...

    def request_artwork(
        self,
        session: AuthenticatedSession,
        catalog: CatalogBinding,
        *,
        deadline_seconds: int,
    ) -> ArtworkRequestFact: ...

    def remove_library(
        self, session: AuthenticatedSession, library_id: str
    ) -> None: ...

    def wait_until_library_absent(
        self,
        session: AuthenticatedSession,
        library_name: str,
        *,
        deadline_seconds: int,
    ) -> None: ...


def _file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return SHA256 + digest.hexdigest()


def implementation_identity() -> str:
    return "emby-source:" + _file_digest(SOURCE_PATH)


def _canonical_digest(value: object) -> str:
    encoded = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return SHA256 + hashlib.sha256(encoded).hexdigest()


def _atomic_json(path: Path, value: Mapping[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=path.name + ".", suffix=".staged", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        encoded = (
            json.dumps(dict(value), ensure_ascii=False, indent=2, sort_keys=True)
            + "\n"
        ).encode("utf-8")
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _runtime_identity(path: Path) -> RuntimeIdentity:
    try:
        mode = stat.S_IMODE(path.stat().st_mode)
    except OSError as error:
        raise EmbyIdentityError("Emby runtime identity is unavailable") from error
    if mode != 0o600:
        raise EmbyIdentityError("Emby runtime identity must use owner-only mode 0600")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EmbyIdentityError("Emby runtime identity is unreadable") from error
    required = ("address", "username", "password", "serverID", "userID")
    if not isinstance(document, dict) or document.get("schema") != RUNTIME_IDENTITY_SCHEMA:
        raise EmbyIdentityError("Emby runtime identity has an unexpected schema")
    if any(not isinstance(document.get(key), str) or not document[key] for key in required):
        raise EmbyIdentityError("Emby runtime identity is incomplete")
    return RuntimeIdentity(
        address=document["address"],
        username=document["username"],
        password=document["password"],
        server_id=document["serverID"],
        user_id=document["userID"],
    )


def _fixture(
    configuration: EmbySourceConfiguration,
    fixture_id: str = FIXTURE_ID,
) -> FixtureBinding:
    try:
        registry = json.loads(configuration.registry_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EmbyFixtureError("fixture registry is unreadable") from error
    entries = registry.get("fixtures") if isinstance(registry, dict) else None
    if registry.get("schemaVersion") != 2 or not isinstance(entries, list):
        raise EmbyFixtureError("fixture registry has an unexpected schema")
    entry = next(
        (item for item in entries if isinstance(item, dict) and item.get("id") == fixture_id),
        None,
    )
    if entry is None:
        raise EmbyFixtureError(f"registered fixture is missing: {fixture_id}")
    relative = entry.get("deviceImportPath")
    expected = entry.get("sha256")
    if not isinstance(relative, str) or not isinstance(expected, str):
        raise EmbyFixtureError(f"registered fixture binding is incomplete: {fixture_id}")
    source = configuration.source_root / relative
    if not source.is_file():
        raise EmbyFixtureError(f"registered fixture bytes are missing: {fixture_id}")
    actual = _file_digest(source)
    if actual != SHA256 + expected:
        raise EmbyFixtureError(f"registered fixture digest does not match: {fixture_id}")
    return FixtureBinding(fixture_id, source, actual)


_POSTER_BYTES = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk"
    "/wcAAusB9Y9ZrS4AAAAASUVORK5CYII="
)


def _materialize_library(
    configuration: EmbySourceConfiguration,
    fixture: FixtureBinding,
    subtitle_fixture: FixtureBinding,
) -> None:
    if configuration.library_root.exists():
        shutil.rmtree(configuration.library_root)
    configuration.runtime_root.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(prefix="library.staged-", dir=configuration.runtime_root)
    )
    try:
        series = staging / SERIES_DIRECTORY
        season = series / SEASON_DIRECTORY
        season.mkdir(parents=True)
        destination = season / EPISODE_FILE_NAME
        with fixture.source.open("rb") as source, destination.open("xb") as target:
            shutil.copyfileobj(source, target, length=1024 * 1024)
            target.flush()
            os.fsync(target.fileno())
        if _file_digest(destination) != fixture.digest:
            raise EmbyFixtureError("staged aggregate fixture digest does not match")
        subtitle_destination = season / EXTERNAL_SUBTITLE_FILE_NAME
        with subtitle_fixture.source.open("rb") as source, subtitle_destination.open(
            "xb"
        ) as target:
            shutil.copyfileobj(source, target, length=1024 * 1024)
            target.flush()
            os.fsync(target.fileno())
        if _file_digest(subtitle_destination) != subtitle_fixture.digest:
            raise EmbyFixtureError("staged external subtitle fixture digest does not match")
        (series / "tvshow.nfo").write_text(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            "<tvshow><title>Enchron Regression Series</title>"
            "<sorttitle>Enchron Regression Series</sorttitle>"
            "<uniqueid type=\"enchon\" default=\"true\">enchon-regression-series-v1</uniqueid>"
            "</tvshow>\n",
            encoding="utf-8",
        )
        (season / "Enchron Regression Episode - S01E01.nfo").write_text(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            "<episodedetails><title>Enchron Regression Episode</title>"
            "<showtitle>Enchron Regression Series</showtitle><season>1</season>"
            "<episode>1</episode><uniqueid type=\"enchon\" default=\"true\">"
            "enchon-regression-episode-v1</uniqueid></episodedetails>\n",
            encoding="utf-8",
        )
        (series / "poster.png").write_bytes(_POSTER_BYTES)
        (season / "Enchron Regression Episode - S01E01-poster.png").write_bytes(
            _POSTER_BYTES
        )
        second_season = series / SECOND_SEASON_DIRECTORY
        second_season.mkdir()
        second_destination = second_season / SECOND_EPISODE_FILE_NAME
        with fixture.source.open("rb") as source, second_destination.open("xb") as target:
            shutil.copyfileobj(source, target, length=1024 * 1024)
            target.flush()
            os.fsync(target.fileno())
        if _file_digest(second_destination) != fixture.digest:
            raise EmbyFixtureError("second-season aggregate fixture digest does not match")
        (second_season / "Enchron Regression Episode 2 - S02E01.nfo").write_text(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            "<episodedetails><title>Enchron Regression Episode 2</title>"
            "<showtitle>Enchron Regression Series</showtitle><season>2</season>"
            "<episode>1</episode><uniqueid type=\"enchon\" default=\"true\">"
            "enchon-regression-episode-2-v1</uniqueid></episodedetails>\n",
            encoding="utf-8",
        )
        (second_season / "Enchron Regression Episode 2 - S02E01-poster.png").write_bytes(
            _POSTER_BYTES
        )
        os.replace(staging, configuration.library_root)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def _receipt_id_fields(
    *,
    server_id: str,
    user_id: str,
    fixture_id: str,
    fixture_digest: str,
    subtitle_fixture_id: str,
    subtitle_fixture_digest: str,
) -> str:
    digest = _canonical_digest(
        {
            "serverID": server_id,
            "userID": user_id,
            "fixtureID": fixture_id,
            "fixtureDigest": fixture_digest,
            "externalSubtitleFixtureID": subtitle_fixture_id,
            "externalSubtitleFixtureDigest": subtitle_fixture_digest,
            "libraryName": LIBRARY_NAME,
        }
    )
    return "receipt:" + digest.removeprefix(SHA256)


def _receipt_id(
    identity: RuntimeIdentity,
    fixture: FixtureBinding,
    subtitle_fixture: FixtureBinding,
) -> str:
    return _receipt_id_fields(
        server_id=identity.server_id,
        user_id=identity.user_id,
        fixture_id=fixture.identifier,
        fixture_digest=fixture.digest,
        subtitle_fixture_id=subtitle_fixture.identifier,
        subtitle_fixture_digest=subtitle_fixture.digest,
    )


def _report(receipt: Mapping[str, object]) -> dict[str, object]:
    return {
        "schema": PREFLIGHT_REPORT_SCHEMA,
        "check": "emby-aggregate",
        "ready": True,
        "receipt": dict(receipt),
    }


def _load_receipt(configuration: EmbySourceConfiguration) -> dict[str, object] | None:
    try:
        value = json.loads(configuration.active_receipt_file.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, json.JSONDecodeError) as error:
        raise EmbySeedError("Emby seed receipt is unreadable") from error
    if not isinstance(value, dict) or value.get("schema") != SEED_RECEIPT_SCHEMA:
        raise EmbySeedError("Emby seed receipt has an unexpected schema")
    return value


def _identity_matches(identity: RuntimeIdentity, session: AuthenticatedSession) -> None:
    if session.server_id != identity.server_id:
        raise EmbyIdentityError("authenticated Emby server identity does not match")
    if session.user_id != identity.user_id:
        raise EmbyIdentityError("authenticated Emby account identity does not match")


def _is_original_playback_state(value: object) -> bool:
    if not isinstance(value, Mapping) or set(value) != ORIGINAL_PLAYBACK_STATE_FIELDS:
        return False
    position = value.get("PlaybackPositionTicks")
    played = value.get("Played")
    return type(position) is int and position >= 0 and type(played) is bool


def _project_original_playback_state(
    user_data: Mapping[str, object],
) -> dict[str, object]:
    projected = {
        "PlaybackPositionTicks": user_data.get("PlaybackPositionTicks"),
        "Played": user_data.get("Played"),
    }
    if not _is_original_playback_state(projected):
        raise EmbySeedError("Emby item user data cannot restore playback state")
    return projected


def _catalog_document(
    catalog: CatalogBinding, artwork: ArtworkRequestFact
) -> dict[str, object]:
    return {
        "libraryID": catalog.library_id,
        "seriesID": catalog.series_id,
        "seasonID": catalog.season_id,
        "episodeID": catalog.episode_id,
        "mediaSourceID": catalog.media_source_id,
        "progressTicks": SEEDED_PROGRESS_TICKS,
        "imageTag": catalog.image_tag,
        "artworkRequestPath": artwork.request_path,
        "artworkStatusCode": artwork.status_code,
        "artworkResponseDigest": artwork.response_digest,
        "loopbackHitCount": artwork.loopback_hit_count,
    }


def _external_subtitle_document(
    catalog: CatalogBinding,
    fixture: FixtureBinding,
    served_digest: str,
) -> dict[str, object]:
    return {
        "registryID": fixture.identifier,
        "fileName": EXTERNAL_SUBTITLE_FILE_NAME,
        "digest": fixture.digest,
        "streamIndex": catalog.external_subtitle_stream_index,
        "codec": catalog.external_subtitle_codec,
        "deliveryPath": catalog.external_subtitle_delivery_path,
        "servedDigest": served_digest,
    }


class EmbySourceController:
    def __init__(
        self,
        configuration: EmbySourceConfiguration = DEFAULT_CONFIGURATION,
        *,
        boundary: EmbyBoundary | None = None,
    ) -> None:
        self.configuration = configuration
        self.boundary = boundary or HTTPEmbyBoundary()

    def ensure(self) -> dict[str, object]:
        identity = _runtime_identity(self.configuration.identity_file)
        fixture = _fixture(self.configuration)
        subtitle_fixture = _fixture(
            self.configuration,
            EXTERNAL_SUBTITLE_FIXTURE_ID,
        )
        try:
            session = self.boundary.authenticate(
                identity,
                deadline_seconds=self.configuration.harness_liveness_deadline_seconds,
            )
        except EmbySourceError:
            raise
        except Exception as error:
            raise EmbyIdentityError("Emby authentication failed") from error
        _identity_matches(identity, session)
        existing_receipt = _load_receipt(self.configuration)
        if existing_receipt is not None and existing_receipt.get("status") == "active":
            self._verify_active(existing_receipt, session, fixture, subtitle_fixture)
            return _report(existing_receipt)

        mutated = False
        original_user_data: dict[str, object] | None = None
        catalog: CatalogBinding | None = None
        try:
            _materialize_library(self.configuration, fixture, subtitle_fixture)
            mutated = True
            existing = self.boundary.library(session, LIBRARY_NAME)
            if existing is not None:
                if existing.path is None or existing.path.resolve() != self.configuration.library_root.resolve():
                    raise EmbyIdentityError("owned Emby library name is bound to another path")
                library_id = existing.identifier
            else:
                library_id = self.boundary.add_library(
                    session, LIBRARY_NAME, self.configuration.library_root
                )
            self.boundary.refresh_library(session)
            catalog = self.boundary.catalog(
                session,
                LIBRARY_NAME,
                deadline_seconds=self.configuration.harness_liveness_deadline_seconds,
            )
            if catalog.library_id != library_id:
                raise EmbySeedError("seeded catalog is bound to the wrong library")
            remote_user_data = self.boundary.user_data_for(
                session, catalog.episode_id
            )
            original_playback_state = _project_original_playback_state(
                remote_user_data
            )
            original_user_data = remote_user_data
            seeded_user_data = dict(original_user_data)
            seeded_user_data.update(
                {"PlaybackPositionTicks": SEEDED_PROGRESS_TICKS, "Played": False}
            )
            self.boundary.set_user_data(session, catalog.episode_id, seeded_user_data)
            observed = self.boundary.user_data_for(session, catalog.episode_id)
            if observed.get("PlaybackPositionTicks") != SEEDED_PROGRESS_TICKS:
                raise EmbySeedError("seeded progress was not observed")
            served = self.boundary.media_bytes(
                session,
                catalog,
                deadline_seconds=self.configuration.harness_liveness_deadline_seconds,
            )
            if SHA256 + hashlib.sha256(served).hexdigest() != fixture.digest:
                raise EmbySeedError("Emby catalog bytes do not match the registered fixture")
            served_subtitle = self.boundary.external_subtitle_bytes(
                session,
                catalog,
                deadline_seconds=self.configuration.harness_liveness_deadline_seconds,
            )
            served_subtitle_digest = SHA256 + hashlib.sha256(served_subtitle).hexdigest()
            if served_subtitle_digest != subtitle_fixture.digest:
                raise EmbySeedError(
                    "Emby external subtitle bytes do not match the registered fixture"
                )
            artwork = self.boundary.request_artwork(
                session,
                catalog,
                deadline_seconds=self.configuration.harness_liveness_deadline_seconds,
            )
            if artwork.status_code != 200 or artwork.loopback_hit_count != 0:
                raise EmbySeedError("direct Emby artwork request did not satisfy its contract")
            receipt: dict[str, object] = {
                "schema": SEED_RECEIPT_SCHEMA,
                "receiptID": _receipt_id(identity, fixture, subtitle_fixture),
                "status": "active",
                "sourceIdentity": implementation_identity(),
                "runtimeIdentity": str(self.configuration.identity_file.resolve()),
                "serverID": session.server_id,
                "userID": session.user_id,
                "library": {
                    "libraryID": library_id,
                    "name": LIBRARY_NAME,
                    "pathDigest": _canonical_digest(
                        str(self.configuration.library_root.resolve())
                    ),
                },
                "fixture": {
                    "registryID": fixture.identifier,
                    "digest": fixture.digest,
                    "catalogByteDigest": fixture.digest,
                },
                "externalSubtitle": _external_subtitle_document(
                    catalog,
                    subtitle_fixture,
                    served_subtitle_digest,
                ),
                "catalog": _catalog_document(catalog, artwork),
                "originalUserData": original_playback_state,
                "deadlines": {
                    "productSeconds": PRODUCT_DEADLINE_SECONDS,
                    "harnessLivenessSeconds": HARNESS_LIVENESS_DEADLINE_SECONDS,
                },
            }
            _atomic_json(self.configuration.active_receipt_file, receipt)
            return _report(receipt)
        except (EmbyIdentityError, EmbyFixtureError):
            self._rollback(session, catalog, original_user_data, mutated)
            raise
        except Exception as error:
            self._rollback(session, catalog, original_user_data, mutated)
            raise EmbySeedError("Emby test-library seed failed") from error

    def _verify_active(
        self,
        receipt: Mapping[str, object],
        session: AuthenticatedSession,
        fixture: FixtureBinding,
        subtitle_fixture: FixtureBinding,
    ) -> None:
        if not validate_seed_receipt(
            receipt,
            runtime_file=self.configuration.identity_file,
            require_active=True,
        ):
            raise EmbySeedError("active Emby seed receipt does not match this implementation")
        library = self.boundary.library(session, LIBRARY_NAME)
        expected_library = receipt.get("library")
        if not isinstance(expected_library, Mapping) or library is None:
            raise EmbySeedError("active Emby seed library is absent")
        if library.identifier != expected_library.get("libraryID"):
            raise EmbySeedError("active Emby seed library identity drifted")
        catalog = self.boundary.catalog(
            session,
            LIBRARY_NAME,
            deadline_seconds=self.configuration.harness_liveness_deadline_seconds,
        )
        expected_catalog = receipt.get("catalog")
        if not isinstance(expected_catalog, Mapping):
            raise EmbySeedError("active Emby catalog receipt is absent")
        actual_ids = (
            catalog.library_id,
            catalog.series_id,
            catalog.season_id,
            catalog.episode_id,
            catalog.media_source_id,
            catalog.image_tag,
        )
        expected_ids = tuple(
            expected_catalog.get(key)
            for key in (
                "libraryID",
                "seriesID",
                "seasonID",
                "episodeID",
                "mediaSourceID",
                "imageTag",
            )
        )
        if actual_ids != expected_ids:
            raise EmbySeedError("active Emby catalog identity drifted")
        if _file_digest(catalog.media_path) != fixture.digest:
            raise EmbySeedError("active Emby catalog bytes drifted")
        subtitle_path = catalog.media_path.with_name(EXTERNAL_SUBTITLE_FILE_NAME)
        if _file_digest(subtitle_path) != subtitle_fixture.digest:
            raise EmbySeedError("active Emby external subtitle bytes drifted")
        expected_subtitle = receipt.get("externalSubtitle")
        if not isinstance(expected_subtitle, Mapping):
            raise EmbySeedError("active Emby external subtitle receipt is absent")
        actual_subtitle_facts = (
            catalog.external_subtitle_stream_index,
            catalog.external_subtitle_codec,
            catalog.external_subtitle_delivery_path,
        )
        expected_subtitle_facts = (
            expected_subtitle.get("streamIndex"),
            expected_subtitle.get("codec"),
            expected_subtitle.get("deliveryPath"),
        )
        if actual_subtitle_facts != expected_subtitle_facts:
            raise EmbySeedError("active Emby external subtitle catalog facts drifted")
        user_data = self.boundary.user_data_for(session, catalog.episode_id)
        if user_data.get("PlaybackPositionTicks") != SEEDED_PROGRESS_TICKS:
            raise EmbySeedError("active Emby progress drifted")
        served = self.boundary.media_bytes(
            session,
            catalog,
            deadline_seconds=self.configuration.harness_liveness_deadline_seconds,
        )
        if SHA256 + hashlib.sha256(served).hexdigest() != fixture.digest:
            raise EmbySeedError("active Emby endpoint bytes drifted")
        served_subtitle = self.boundary.external_subtitle_bytes(
            session,
            catalog,
            deadline_seconds=self.configuration.harness_liveness_deadline_seconds,
        )
        served_subtitle_digest = SHA256 + hashlib.sha256(served_subtitle).hexdigest()
        if (
            served_subtitle_digest != subtitle_fixture.digest
            or expected_subtitle.get("servedDigest") != served_subtitle_digest
        ):
            raise EmbySeedError("active Emby external subtitle endpoint bytes drifted")
        artwork = self.boundary.request_artwork(
            session,
            catalog,
            deadline_seconds=self.configuration.harness_liveness_deadline_seconds,
        )
        artwork_document = {
            "artworkRequestPath": artwork.request_path,
            "artworkStatusCode": artwork.status_code,
            "artworkResponseDigest": artwork.response_digest,
            "loopbackHitCount": artwork.loopback_hit_count,
        }
        for key, value in artwork_document.items():
            if expected_catalog.get(key) != value:
                raise EmbySeedError("active Emby artwork facts drifted")

    def _rollback(
        self,
        session: AuthenticatedSession,
        catalog: CatalogBinding | None,
        original_user_data: Mapping[str, object] | None,
        mutated: bool,
    ) -> None:
        if catalog is not None and original_user_data is not None:
            try:
                self.boundary.set_user_data(
                    session, catalog.episode_id, original_user_data
                )
            except Exception:
                pass
        if mutated:
            try:
                library = self.boundary.library(session, LIBRARY_NAME)
                if library is not None:
                    self.boundary.remove_library(session, library.identifier)
            except Exception:
                pass
        shutil.rmtree(self.configuration.library_root, ignore_errors=True)
        self.configuration.active_receipt_file.unlink(missing_ok=True)

    def restore(self, receipt_id: str) -> dict[str, object]:
        receipt = _load_receipt(self.configuration)
        if receipt is None:
            raise EmbyRestoreError("Emby seed receipt is absent")
        if receipt.get("receiptID") != receipt_id:
            raise EmbyRestoreError("Emby seed receipt identity does not match")
        if receipt.get("status") == "restored":
            return receipt
        if not validate_seed_receipt(
            receipt,
            runtime_file=self.configuration.identity_file,
            require_active=True,
        ):
            raise EmbyRestoreError("Emby seed receipt cannot authorize restore")
        identity = _runtime_identity(self.configuration.identity_file)
        try:
            session = self.boundary.authenticate(
                identity,
                deadline_seconds=self.configuration.harness_liveness_deadline_seconds,
            )
            _identity_matches(identity, session)
            catalog = receipt["catalog"]
            original = receipt["originalUserData"]
            library_receipt = receipt["library"]
            assert isinstance(catalog, Mapping) and isinstance(original, Mapping)
            assert isinstance(library_receipt, Mapping)
            library = self.boundary.library(session, LIBRARY_NAME)
            if library is not None:
                if library.identifier != library_receipt["libraryID"]:
                    raise EmbyRestoreError("owned Emby library identity drifted")
                current_user_data = self.boundary.user_data_for(
                    session, str(catalog["episodeID"])
                )
                restored_user_data = dict(current_user_data)
                restored_user_data.update(original)
                self.boundary.set_user_data(
                    session, str(catalog["episodeID"]), restored_user_data
                )
                self.boundary.remove_library(session, library.identifier)
            self.boundary.wait_until_library_absent(
                session,
                LIBRARY_NAME,
                deadline_seconds=self.configuration.harness_liveness_deadline_seconds,
            )
            if self.configuration.library_root.exists():
                shutil.rmtree(self.configuration.library_root)
            if self.configuration.library_root.exists():
                raise EmbyRestoreError("owned Emby library bytes remained present")
            restored = dict(receipt)
            restored["status"] = "restored"
            _atomic_json(self.configuration.active_receipt_file, restored)
            return restored
        except Exception as error:
            raise EmbyRestoreError("Emby test-library restore failed") from error


def validate_seed_receipt(
    receipt: object, *, runtime_file: Path, require_active: bool = True
) -> bool:
    if not isinstance(receipt, Mapping):
        return False
    required = {
        "schema",
        "receiptID",
        "status",
        "sourceIdentity",
        "runtimeIdentity",
        "serverID",
        "userID",
        "library",
        "fixture",
        "externalSubtitle",
        "catalog",
        "originalUserData",
        "deadlines",
    }
    if set(receipt) != required:
        return False
    if receipt.get("schema") != SEED_RECEIPT_SCHEMA:
        return False
    status = receipt.get("status")
    if status not in {"active", "restored"}:
        return False
    if require_active and status != "active":
        return False
    if receipt.get("sourceIdentity") != implementation_identity():
        return False
    if receipt.get("runtimeIdentity") != str(runtime_file.resolve()):
        return False
    receipt_id = receipt.get("receiptID")
    server_id = receipt.get("serverID")
    user_id = receipt.get("userID")
    if not all(isinstance(value, str) and value for value in (receipt_id, server_id, user_id)):
        return False
    fixture = receipt.get("fixture")
    external_subtitle = receipt.get("externalSubtitle")
    catalog = receipt.get("catalog")
    library = receipt.get("library")
    deadlines = receipt.get("deadlines")
    if not all(
        isinstance(value, Mapping)
        for value in (fixture, external_subtitle, catalog, library, deadlines)
    ):
        return False
    assert isinstance(fixture, Mapping)
    assert isinstance(external_subtitle, Mapping)
    assert isinstance(catalog, Mapping)
    assert isinstance(library, Mapping)
    assert isinstance(deadlines, Mapping)
    if set(fixture) != {"registryID", "digest", "catalogByteDigest"}:
        return False
    fixture_digest = fixture.get("digest")
    if (
        fixture.get("registryID") != FIXTURE_ID
        or not _is_sha256(fixture_digest)
        or fixture_digest != fixture.get("catalogByteDigest")
    ):
        return False
    if set(external_subtitle) != {
        "registryID",
        "fileName",
        "digest",
        "streamIndex",
        "codec",
        "deliveryPath",
        "servedDigest",
    }:
        return False
    subtitle_digest = external_subtitle.get("digest")
    if (
        external_subtitle.get("registryID") != EXTERNAL_SUBTITLE_FIXTURE_ID
        or external_subtitle.get("fileName") != EXTERNAL_SUBTITLE_FILE_NAME
        or not _is_sha256(subtitle_digest)
        or external_subtitle.get("servedDigest") != subtitle_digest
        or type(external_subtitle.get("streamIndex")) is not int
        or external_subtitle.get("streamIndex") < 0
        or not _is_nonempty_string(external_subtitle.get("codec"))
    ):
        return False
    delivery_path = external_subtitle.get("deliveryPath")
    if not isinstance(delivery_path, str):
        return False
    delivery_url = urlsplit(delivery_path)
    secret_query_names = {"api_key", "x-emby-token", "token", "access_token"}
    if (
        delivery_url.scheme
        or delivery_url.netloc
        or delivery_url.fragment
        or not delivery_url.path.startswith("/")
        or any(
            name.casefold() in secret_query_names
            for name, _ in parse_qsl(delivery_url.query, keep_blank_values=True)
        )
    ):
        return False
    if receipt_id != _receipt_id_fields(
        server_id=server_id,
        user_id=user_id,
        fixture_id=FIXTURE_ID,
        fixture_digest=fixture_digest,
        subtitle_fixture_id=EXTERNAL_SUBTITLE_FIXTURE_ID,
        subtitle_fixture_digest=subtitle_digest,
    ):
        return False
    if (
        set(library) != {"libraryID", "name", "pathDigest"}
        or not _is_nonempty_string(library.get("libraryID"))
        or library.get("name") != LIBRARY_NAME
        or not _is_sha256(library.get("pathDigest"))
    ):
        return False
    required_catalog = {
        "libraryID",
        "seriesID",
        "seasonID",
        "episodeID",
        "mediaSourceID",
        "progressTicks",
        "imageTag",
        "artworkRequestPath",
        "artworkStatusCode",
        "artworkResponseDigest",
        "loopbackHitCount",
    }
    if set(catalog) != required_catalog:
        return False
    if catalog.get("libraryID") != library.get("libraryID"):
        return False
    if not all(
        _is_nonempty_string(catalog.get(key))
        for key in (
            "seriesID",
            "seasonID",
            "episodeID",
            "mediaSourceID",
            "imageTag",
        )
    ):
        return False
    if type(catalog.get("progressTicks")) is not int or catalog.get(
        "progressTicks"
    ) != SEEDED_PROGRESS_TICKS:
        return False
    if (
        type(catalog.get("artworkStatusCode")) is not int
        or catalog.get("artworkStatusCode") != 200
        or not _is_sha256(catalog.get("artworkResponseDigest"))
        or type(catalog.get("loopbackHitCount")) is not int
        or catalog.get("loopbackHitCount") != 0
    ):
        return False
    artwork_path = catalog.get("artworkRequestPath")
    if not isinstance(artwork_path, str):
        return False
    artwork_url = urlsplit(artwork_path)
    if (
        artwork_url.scheme
        or artwork_url.netloc
        or artwork_url.fragment
        or artwork_url.path
        != f"/Items/{catalog['seriesID']}/Images/Primary"
        or parse_qsl(artwork_url.query, keep_blank_values=True)
        != [("Tag", catalog["imageTag"]), ("MaxWidth", "420")]
    ):
        return False
    if not _is_original_playback_state(receipt.get("originalUserData")):
        return False
    if deadlines != {
        "productSeconds": PRODUCT_DEADLINE_SECONDS,
        "harnessLivenessSeconds": HARNESS_LIVENESS_DEADLINE_SECONDS,
    }:
        return False
    return True


def _is_nonempty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value)


def _is_sha256(value: object) -> bool:
    if not isinstance(value, str) or not value.startswith(SHA256):
        return False
    digest = value.removeprefix(SHA256)
    return len(digest) == 64 and all(character in "0123456789abcdef" for character in digest)


def validate_preflight_report(report: object, *, runtime_file: Path) -> bool:
    return (
        isinstance(report, Mapping)
        and set(report) == {"schema", "check", "ready", "receipt"}
        and report.get("schema") == PREFLIGHT_REPORT_SCHEMA
        and report.get("check") == "emby-aggregate"
        and report.get("ready") is True
        and validate_seed_receipt(
            report.get("receipt"), runtime_file=runtime_file, require_active=True
        )
    )


def _safe_failure_reason(error: BaseException) -> str:
    if isinstance(error, EmbyIdentityError):
        return "Emby runtime identity or authentication did not match"
    if isinstance(error, EmbyFixtureError):
        return "registered Emby fixture verification failed"
    if isinstance(error, EmbyRestoreError):
        return "Emby test-library restore failed"
    return "Emby test-library seed failed"


def run_preflight(
    configuration: EmbySourceConfiguration = DEFAULT_CONFIGURATION,
    *,
    boundary: EmbyBoundary | None = None,
) -> dict[str, object]:
    try:
        return EmbySourceController(configuration, boundary=boundary).ensure()
    except (EmbySourceError, OSError, HTTPError, URLError) as error:
        return {
            "schema": PREFLIGHT_REPORT_SCHEMA,
            "check": "emby-aggregate",
            "ready": False,
            "reason": _safe_failure_reason(error),
        }


def render_report(report: Mapping[str, object]) -> str:
    return json.dumps(dict(report), ensure_ascii=False, indent=2, sort_keys=True) + "\n"


class HTTPEmbyBoundary:
    def __init__(self) -> None:
        self._address: str | None = None

    def authenticate(
        self, credentials: RuntimeIdentity, *, deadline_seconds: int
    ) -> AuthenticatedSession:
        split = urlsplit(credentials.address)
        if split.scheme not in {"http", "https"} or not split.hostname or split.username or split.password:
            raise EmbyIdentityError("Emby runtime address is invalid")
        self._address = urlunsplit((split.scheme, split.netloc, split.path.rstrip("/"), "", ""))
        body = {
            "Username": credentials.username,
            "Pw": credentials.password,
        }
        result = self._json_request(
            "POST",
            "/Users/AuthenticateByName",
            body=body,
            timeout=deadline_seconds,
            authorization=(
                'Emby Client="Enchron Regression", Device="Host Harness", '
                'DeviceId="enchron-regression-emby-source", Version="1"'
            ),
        )
        user = result.get("User") if isinstance(result, dict) else None
        token = result.get("AccessToken") if isinstance(result, dict) else None
        server_id = result.get("ServerId") if isinstance(result, dict) else None
        user_id = user.get("Id") if isinstance(user, dict) else None
        if not all(isinstance(value, str) and value for value in (token, server_id, user_id)):
            raise EmbyIdentityError("Emby authentication response is incomplete")
        return AuthenticatedSession(server_id, user_id, token)

    def library(
        self, session: AuthenticatedSession, name: str
    ) -> LibraryBinding | None:
        result = self._json_request(
            "GET", "/Library/VirtualFolders/Query", session=session, timeout=15
        )
        entries = result.get("Items", []) if isinstance(result, dict) else []
        matches = [
            item
            for item in entries
            if isinstance(item, dict) and item.get("Name") == name
        ]
        if not matches:
            return None
        if len(matches) != 1:
            raise EmbyIdentityError("owned Emby library name is not unique")
        item = matches[0]
        identifier = item.get("ItemId") or item.get("Id")
        locations = item.get("Locations")
        path = Path(locations[0]) if isinstance(locations, list) and len(locations) == 1 else None
        if not isinstance(identifier, str) or not identifier:
            raise EmbyIdentityError("owned Emby library has no stable identity")
        return LibraryBinding(identifier, name, path)

    def add_library(
        self, session: AuthenticatedSession, name: str, path: Path
    ) -> str:
        self._json_request(
            "POST",
            "/Library/VirtualFolders",
            session=session,
            body={
                "Name": name,
                "CollectionType": "tvshows",
                "RefreshLibrary": True,
                "Paths": [str(path.resolve())],
                "LibraryOptions": {},
            },
            timeout=30,
            allow_empty=True,
        )
        binding = self.library(session, name)
        if binding is None:
            raise EmbySeedError("Emby did not publish the owned library")
        return binding.identifier

    def refresh_library(self, session: AuthenticatedSession) -> None:
        self._json_request(
            "POST",
            "/Library/Refresh",
            session=session,
            timeout=15,
            allow_empty=True,
        )

    def catalog(
        self,
        session: AuthenticatedSession,
        library_name: str,
        *,
        deadline_seconds: int,
    ) -> CatalogBinding:
        deadline = time.monotonic() + deadline_seconds
        while time.monotonic() < deadline:
            library = self.library(session, library_name)
            if library is not None:
                series = self._single_item(
                    session,
                    parent_id=library.identifier,
                    item_type="Series",
                    name=SERIES_NAME,
                )
                if series is not None:
                    season = self._single_item(
                        session,
                        parent_id=str(series["Id"]),
                        item_type="Season",
                        name="Season 1",
                    )
                    if season is not None:
                        episode = self._single_item(
                            session,
                            parent_id=str(season["Id"]),
                            item_type="Episode",
                        )
                        if episode is not None:
                            tags = series.get("ImageTags")
                            playback = self._json_request(
                                "POST",
                                f"/Items/{episode['Id']}/PlaybackInfo",
                                session=session,
                                body={
                                    "UserId": session.user_id,
                                    "EnableDirectPlay": True,
                                    "EnableDirectStream": False,
                                    "EnableTranscoding": False,
                                    "IsPlayback": True,
                                },
                                timeout=15,
                            )
                            sources = playback.get("MediaSources")
                            source = (
                                sources[0]
                                if isinstance(sources, list) and len(sources) == 1
                                else None
                            )
                            image_tag = tags.get("Primary") if isinstance(tags, dict) else None
                            if (
                                isinstance(source, dict)
                                and isinstance(source.get("Id"), str)
                                and isinstance(source.get("Path"), str)
                                and isinstance(image_tag, str)
                                and image_tag
                            ):
                                streams = source.get("MediaStreams")
                                external_subtitles = [
                                    stream
                                    for stream in streams
                                    if isinstance(stream, dict)
                                    and stream.get("Type") == "Subtitle"
                                    and stream.get("IsExternal") is True
                                    and type(stream.get("Index")) is int
                                    and stream.get("Index") >= 0
                                    and isinstance(stream.get("Codec"), str)
                                    and bool(stream.get("Codec"))
                                    and isinstance(stream.get("DeliveryUrl"), str)
                                    and bool(stream.get("DeliveryUrl"))
                                ] if isinstance(streams, list) else []
                                if len(external_subtitles) != 1:
                                    time.sleep(0.5)
                                    continue
                                subtitle = external_subtitles[0]
                                delivery_path = self._sanitized_delivery_path(
                                    str(subtitle["DeliveryUrl"])
                                )
                                return CatalogBinding(
                                    library.identifier,
                                    str(series["Id"]),
                                    str(season["Id"]),
                                    str(episode["Id"]),
                                    source["Id"],
                                    Path(source["Path"]),
                                    image_tag,
                                    int(subtitle["Index"]),
                                    str(subtitle["Codec"]),
                                    delivery_path,
                                )
            time.sleep(0.5)
        raise EmbySeedError("Emby catalog did not converge before the liveness deadline")

    def _sanitized_delivery_path(self, value: str) -> str:
        delivery = urlsplit(value)
        if delivery.fragment or not delivery.path.startswith("/"):
            raise EmbySeedError("Emby external subtitle delivery route is invalid")
        if delivery.scheme or delivery.netloc:
            if self._address is None:
                raise EmbyIdentityError("Emby boundary is not authenticated")
            authority = urlsplit(self._address)
            if (
                delivery.scheme.casefold() != authority.scheme.casefold()
                or delivery.netloc.casefold() != authority.netloc.casefold()
            ):
                raise EmbySeedError(
                    "Emby external subtitle delivery route changed authority"
                )
        secret_names = {"api_key", "x-emby-token", "token", "access_token"}
        safe_query = [
            (name, query_value)
            for name, query_value in parse_qsl(
                delivery.query,
                keep_blank_values=True,
            )
            if name.casefold() not in secret_names
        ]
        return urlunsplit(("", "", delivery.path, urlencode(safe_query), ""))

    def _single_item(
        self,
        session: AuthenticatedSession,
        *,
        parent_id: str,
        item_type: str,
        name: str | None = None,
    ) -> dict[str, object] | None:
        query = {
            "ParentId": parent_id,
            "IncludeItemTypes": item_type,
            "Recursive": "false",
            "Fields": "MediaSources",
            "EnableImages": "true",
            "EnableUserData": "true",
        }
        result = self._json_request(
            "GET",
            f"/Users/{session.user_id}/Items",
            session=session,
            query=query,
            timeout=15,
        )
        entries = result.get("Items", []) if isinstance(result, dict) else []
        matches = [
            item
            for item in entries
            if isinstance(item, dict) and (name is None or item.get("Name") == name)
        ]
        return matches[0] if len(matches) == 1 else None

    def user_data_for(
        self, session: AuthenticatedSession, item_id: str
    ) -> dict[str, object]:
        item = self._json_request(
            "GET",
            f"/Users/{session.user_id}/Items/{item_id}",
            session=session,
            query={"EnableUserData": "true"},
            timeout=15,
        )
        value = item.get("UserData") if isinstance(item, dict) else None
        if not isinstance(value, dict):
            raise EmbySeedError("Emby item user data is absent")
        return dict(value)

    def set_user_data(
        self, session: AuthenticatedSession, item_id: str, value: Mapping[str, object]
    ) -> None:
        self._json_request(
            "POST",
            f"/Users/{session.user_id}/Items/{item_id}/UserData",
            session=session,
            body=dict(value),
            timeout=15,
            allow_empty=True,
        )

    def media_bytes(
        self,
        session: AuthenticatedSession,
        catalog: CatalogBinding,
        *,
        deadline_seconds: int,
    ) -> bytes:
        return self._bytes_request(
            "GET",
            f"/Items/{catalog.episode_id}/File",
            session=session,
            timeout=deadline_seconds,
        )[1]

    def external_subtitle_bytes(
        self,
        session: AuthenticatedSession,
        catalog: CatalogBinding,
        *,
        deadline_seconds: int,
    ) -> bytes:
        return self._bytes_request(
            "GET",
            catalog.external_subtitle_delivery_path,
            session=session,
            timeout=deadline_seconds,
        )[1]

    def request_artwork(
        self,
        session: AuthenticatedSession,
        catalog: CatalogBinding,
        *,
        deadline_seconds: int,
    ) -> ArtworkRequestFact:
        request_path = (
            f"/Items/{catalog.series_id}/Images/Primary?"
            + urlencode({"Tag": catalog.image_tag, "MaxWidth": 420})
        )
        status, data = self._bytes_request(
            "GET", request_path, session=session, timeout=deadline_seconds
        )
        return ArtworkRequestFact(
            request_path=request_path,
            status_code=status,
            response_digest=SHA256 + hashlib.sha256(data).hexdigest(),
            loopback_hit_count=0,
        )

    def remove_library(
        self, session: AuthenticatedSession, library_id: str
    ) -> None:
        self._json_request(
            "POST",
            "/Library/VirtualFolders/Delete",
            session=session,
            body={"Id": library_id, "RefreshLibrary": True},
            timeout=30,
            allow_empty=True,
        )

    def wait_until_library_absent(
        self,
        session: AuthenticatedSession,
        library_name: str,
        *,
        deadline_seconds: int,
    ) -> None:
        deadline = time.monotonic() + deadline_seconds
        while time.monotonic() < deadline:
            if self.library(session, library_name) is None:
                return
            time.sleep(0.5)
        raise EmbyRestoreError("owned Emby library remained present")

    def _url(self, relative_path: str, query: Mapping[str, object] | None) -> str:
        if self._address is None:
            raise EmbyIdentityError("Emby boundary is not authenticated")
        path, _, embedded_query = relative_path.partition("?")
        encoded_query = embedded_query
        if query:
            encoded_query = urlencode(query)
        return self._address + path + ("?" + encoded_query if encoded_query else "")

    def _json_request(
        self,
        method: str,
        relative_path: str,
        *,
        session: AuthenticatedSession | None = None,
        query: Mapping[str, object] | None = None,
        body: Mapping[str, object] | None = None,
        timeout: int,
        authorization: str | None = None,
        allow_empty: bool = False,
    ) -> dict[str, object]:
        encoded = json.dumps(dict(body)).encode("utf-8") if body is not None else None
        headers = {"Accept": "application/json"}
        if encoded is not None:
            headers["Content-Type"] = "application/json"
        if session is not None:
            headers["X-Emby-Token"] = session.access_token
        if authorization is not None:
            headers["X-Emby-Authorization"] = authorization
        request = Request(
            self._url(relative_path, query),
            data=encoded,
            method=method,
            headers=headers,
        )
        with urlopen(request, timeout=timeout) as response:
            data = response.read()
        if not data and allow_empty:
            return {}
        value = json.loads(data)
        if not isinstance(value, dict):
            raise EmbySourceError("Emby returned a non-object response")
        return value

    def _bytes_request(
        self,
        method: str,
        relative_path: str,
        *,
        session: AuthenticatedSession,
        timeout: int,
    ) -> tuple[int, bytes]:
        request = Request(
            self._url(relative_path, None),
            method=method,
            headers={"X-Emby-Token": session.access_token},
        )
        with urlopen(request, timeout=timeout) as response:
            return response.status, response.read()


def provision_runtime_identity(
    configuration: EmbySourceConfiguration = DEFAULT_CONFIGURATION,
) -> dict[str, object]:
    path = configuration.identity_file
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EmbyIdentityError("Emby credential input is unreadable") from error
    if not isinstance(document, dict):
        raise EmbyIdentityError("Emby credential input has an unexpected schema")
    for key in ("address", "username", "password"):
        if not isinstance(document.get(key), str) or not document[key]:
            raise EmbyIdentityError("Emby credential input is incomplete")
    os.chmod(path, 0o600)
    provisional = RuntimeIdentity(
        str(document["address"]),
        str(document["username"]),
        str(document["password"]),
        str(document.get("serverID", "pending")),
        str(document.get("userID", "pending")),
    )
    session = HTTPEmbyBoundary().authenticate(
        provisional, deadline_seconds=HARNESS_LIVENESS_DEADLINE_SECONDS
    )
    provisioned = {
        "schema": RUNTIME_IDENTITY_SCHEMA,
        "address": provisional.address,
        "username": provisional.username,
        "password": provisional.password,
        "serverID": session.server_id,
        "userID": session.user_id,
    }
    _atomic_json(path, provisioned)
    return {
        "schema": RUNTIME_IDENTITY_SCHEMA,
        "runtimeIdentity": str(path.resolve()),
        "serverID": session.server_id,
        "userID": session.user_id,
        "mode": "0600",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("ensure", "restore", "provision-identity"))
    parser.add_argument("--receipt-id")
    parser.add_argument("--runtime-root", type=Path, default=DEFAULT_RUNTIME_ROOT)
    parser.add_argument("--identity-file", type=Path, default=DEFAULT_IDENTITY_FILE)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument("--source-root", type=Path, default=DEFAULT_SOURCE_ROOT)
    arguments = parser.parse_args(argv)
    configuration = EmbySourceConfiguration(
        runtime_root=arguments.runtime_root,
        identity_file=arguments.identity_file,
        registry_path=arguments.registry,
        source_root=arguments.source_root,
    )
    try:
        if arguments.action == "provision-identity":
            report = provision_runtime_identity(configuration)
        elif arguments.action == "ensure":
            report = run_preflight(configuration)
        else:
            if not arguments.receipt_id:
                raise EmbyRestoreError("restore requires --receipt-id")
            report = EmbySourceController(configuration).restore(arguments.receipt_id)
    except EmbySourceError as error:
        report = {"ready": False, "reason": _safe_failure_reason(error)}
    print(render_report(report), end="")
    return 0 if report.get("ready", arguments.action != "ensure") is True else 1


if __name__ == "__main__":
    raise SystemExit(main())
