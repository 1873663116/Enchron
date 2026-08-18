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
    emby = read("Modules/Emby/EmbyPlaybackBridge.swift")
    project = read("Enchron.xcodeproj/project.pbxproj")
    architecture_inputs = read("Config/design_source_architecture_inputs.xcfilelist")

    require(endpoint_path.exists(), "MediaSource does not own MediaByteStream.swift")
    require(not old_endpoint_path.exists(), "MediaLibrary still owns the old endpoint")
    require("public nonisolated protocol MediaByteSource" in endpoint, "byte-source protocol is missing")
    for property_name in (
        "totalLength",
        "seekability",
        "liveness",
        "suggestedBufferDepth",
    ):
        require(property_name in endpoint, f"MediaByteSource lacks {property_name}")
    require("func read(in range: Range<Int64>)" in endpoint, "ranged read is missing")
    require("public static let shared = MediaByteStreamEndpoint()" in endpoint, "endpoint is not shared")
    require("private init()" in endpoint, "callers can construct extra endpoints")

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
        require(": MediaByteSource" in adapter, f"{name} has no byte-source adapter")
        require(
            "MediaByteStreamEndpoint.shared.resolve(" in adapter,
            f"{name} does not use the shared endpoint",
        )

    require("MediaByteStreamEndpoint" not in local, "local files enter the loopback endpoint")
    require(
        "ResolvedMediaSource(url: try await resolveURL(for: file))" in local,
        "local playback no longer returns its file URL directly",
    )
    require("url: source.directPlayURL" in emby, "Emby no longer uses its direct-play URL")
    require("MediaSource/MediaByteStream.swift" in project, "Xcode omits the MediaSource endpoint")
    require(
        "MediaLibrary/Services/HTTPRangeStreamingServer.swift" not in project,
        "Xcode still references the MediaLibrary endpoint",
    )
    require(
        "Modules/MediaSource/MediaByteStream.swift" in architecture_inputs,
        "architecture checks omit the MediaSource endpoint",
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
