#!/usr/bin/env python3

from pathlib import Path
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (REPOSITORY_ROOT / path).read_text()


def swift_sources(path: str) -> str:
    return "\n".join(
        source.read_text()
        for source in sorted((REPOSITORY_ROOT / path).rglob("*.swift"))
    )


def main() -> int:
    violations: list[str] = []

    def require(condition: bool, message: str) -> None:
        if not condition:
            violations.append(message)

    endpoint_path = REPOSITORY_ROOT / "Modules/MediaSource/MediaByteStream.swift"
    old_endpoint_path = (
        REPOSITORY_ROOT
        / "Modules/MediaLibrary/Services/HTTPRangeStreamingServer.swift"
    )
    endpoint = endpoint_path.read_text() if endpoint_path.exists() else ""
    media_library = swift_sources("Modules/MediaLibrary")
    playback_core = swift_sources("Packages/PlaybackCore/Sources")
    smb = read("Modules/MediaLibrary/Sources/SMB/SMBDataSourceAdapter.swift")
    webdav = read(
        "Modules/MediaLibrary/Sources/WebDAV/WebDAVDataSourceAdapter.swift"
    )
    local = read("Modules/MediaLibrary/Sources/Local/LocalDataSourceAdapter.swift")
    emby = swift_sources("Modules/Emby")
    playback_feature = swift_sources("Modules/Playback")
    project = read("Enchron.xcodeproj/project.pbxproj")
    architecture_inputs = read("Config/design_source_architecture_inputs.xcfilelist")

    require(endpoint_path.exists(), "MediaSource does not own MediaByteStream.swift")
    require(
        not (REPOSITORY_ROOT / "Modules/MediaSource/MediaByteStreamHandle.swift").exists(),
        "MediaSource still has a duplicate MediaByteStreamHandle.swift",
    )
    require(not old_endpoint_path.exists(), "MediaLibrary still owns the old endpoint")
    require(
        "public protocol MediaByteRangeSource" in endpoint,
        "byte-range source protocol is missing",
    )
    for property_name in ("contentLength", "supportsSeeking", "isLive", "preferredBufferDepth"):
        require(property_name in endpoint, f"MediaByteStreamAttributes lacks {property_name}")
    require("func read(in range: Range<Int64>)" in endpoint, "ranged read is missing")
    require(
        "public static let shared = MediaByteStreamServer()" in endpoint,
        "byte-stream server is not shared",
    )
    require(
        "public final class MediaByteStreamHandle" in endpoint,
        "MediaByteStreamHandle is not owned by MediaByteStream.swift",
    )

    for forbidden in (
        "HTTPRangeStreamingServer",
        "ByteRangeStreamingSource",
        "import Network",
        "NWListener",
        "NWConnection",
    ):
        require(forbidden not in media_library, f"MediaLibrary still contains {forbidden}")
    require("MediaByteSource" not in playback_core, "PlaybackCore depends on MediaSource byte types")

    for name, adapter in (("SMB", smb), ("WebDAV", webdav)):
        require(": MediaByteRangeSource" in adapter, f"{name} has no byte-range source adapter")
        require(
            "MediaByteStreamServer.shared.register(" in adapter,
            f"{name} does not use the shared byte-stream server",
        )

    require("MediaByteStreamServer" not in local, "local files enter the loopback server")
    require(
        "ResolvedMediaSource(url: try await resolveURL(for: file))" in local,
        "local playback no longer returns a resolved file URL",
    )
    require(
        "final class EmbyMediaByteSource: MediaByteRangeSource" in emby,
        "Emby lacks a byte-range source",
    )
    require(
        "MediaByteStreamServer.shared.register(" in emby,
        "Emby playback does not use the shared byte-stream server",
    )
    require(
        "source: PlaybackAddress(byteStreamHandle: byteStreamHandle)" in emby
        and "url: source.directPlayURL" not in emby,
        "Emby still hands its direct-play URL to PlaybackFeature",
    )
    require(
        "source: PlaybackAddress" in playback_feature,
        "PlaybackFeature does not require an admitted playback address",
    )
    require(
        "func beginPlayback(for url: URL)" not in playback_feature,
        "PlaybackFeature still exposes bare-URL launch",
    )
    require("MediaSource/MediaByteStream.swift" in project, "Xcode omits the MediaSource endpoint")
    require(
        "MediaSource/MediaByteStreamHandle.swift" not in project,
        "Xcode still includes the duplicate handle file",
    )
    require("Emby/EmbyMediaByteSource.swift" in project, "Xcode omits the Emby byte source")
    require(
        "MediaLibrary/Services/HTTPRangeStreamingServer.swift" not in project,
        "Xcode still references the MediaLibrary endpoint",
    )
    require(
        "Modules/MediaSource/MediaByteStream.swift" in architecture_inputs,
        "architecture checks omit the MediaSource endpoint",
    )
    require(
        "Modules/MediaSource/MediaByteStreamHandle.swift" not in architecture_inputs,
        "architecture checks still include the duplicate handle file",
    )
    require(
        "Modules/Emby/EmbyMediaByteSource.swift" in architecture_inputs,
        "architecture checks omit the Emby byte source",
    )
    require(
        "Modules/MediaLibrary/Services/HTTPRangeStreamingServer.swift"
        not in architecture_inputs,
        "architecture checks still reference the MediaLibrary endpoint",
    )

    if violations:
        for violation in violations:
            print(violation, file=sys.stderr)
        return 1
    print("Media byte stream ownership and source routing checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
