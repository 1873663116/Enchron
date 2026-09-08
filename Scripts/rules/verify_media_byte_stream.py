#!/usr/bin/env python3
"""Verify the source-level boundaries of the media byte-stream refactor."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]


def text(path: str) -> str:
    target = ROOT / path
    if not target.is_file():
        raise AssertionError(f"missing required file: {path}")
    return target.read_text()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    byte_stream = text("Modules/MediaSource/MediaByteStream.swift")
    conformance_suite = text(
        "Tests/MediaByteStreamConformance/Tests/"
        "MediaByteStreamConformanceTests/MediaByteStreamConformanceTests.swift"
    )
    playback_request = text("Modules/Playback/PlaybackLaunchRequest.swift")
    media_library = ROOT / "Modules/MediaLibrary"

    require("protocol MediaByteRangeSource" in byte_stream, "M1: byte source protocol is missing")
    require("static let shared = MediaByteStreamServer()" in byte_stream, "M2: App singleton is missing")
    require(
        not any("HTTPRangeStreamingServer" in path.read_text() for path in media_library.rglob("*.swift")),
        "M2: MediaLibrary still owns an HTTP range server",
    )
    require("Transfer-Encoding: chunked" in byte_stream, "M3: unknown-length chunking is missing")
    require(
        "func zeroLengthHintRemainsNonAuthoritative(" in conformance_suite
        and "func headUsesOnlyPreviouslyObservedSourceLength(" in conformance_suite,
        "M3: the byte-range authority contract is missing from its executable suite",
    )
    require(
        "RequestShape.allCases" in conformance_suite
        and "SourceShape.allCases" in conformance_suite,
        "M3: the request-by-source conformance matrix is missing",
    )
    raw_url_initializers = playback_request.count("public init(\n        url: URL")
    testing_initializers = playback_request.count(
        "@_spi(Testing)\n    public init(\n        url: URL"
    )
    require(
        raw_url_initializers == testing_initializers,
        "M8: a naked URL initializer is visible outside the test SPI",
    )
    require("Connection: close" not in byte_stream.split("private func sendError", 1)[0], "M9: success responses close connections")
    release_suite = text(
        "Tests/MediaByteStreamConformance/Tests/"
        "MediaByteStreamConformanceTests/MediaByteStreamReleaseTests.swift"
    )
    unregister_body = byte_stream.split("fileprivate func unregister(token: String) {", 1)[1].split("\n    }\n", 1)[0]
    require(
        "transferTokens" in unregister_body and "task?.cancel()" in unregister_body,
        "M10: releasing a registration no longer cancels its transfers",
    )
    require(
        "try Task.checkCancellation()" in byte_stream.split("while offset < requestedRange.upperBound {", 1)[1][:200],
        "M10: the ranged response loop no longer checks for cancellation before each read",
    )
    require(
        "func releasingTheHandleCancelsAnUnansweredRead(" in release_suite,
        "M10: the release-cancels-read contract is missing from its executable suite",
    )
    require("AVAssetImageGenerator" not in text("Modules/MediaSource/ArtworkStore.swift"), "A1: artwork generation remains")
    require(
        not any("AVAssetImageGenerator" in path.read_text() for path in media_library.rglob("*.swift")),
        "A1: MediaLibrary still extracts artwork",
    )

    nfs_change_files = [
        "Modules/MediaLibrary/Model/MediaSource.swift",
        "Modules/MediaLibrary/Sources/NFS/NFSDataSourceAdapter.swift",
        "Modules/MediaLibrary/FileBrowsingViewModel.swift",
    ]
    require(len(nfs_change_files) <= 3, "G3: NFS would touch more than three files")
    print("media-byte-stream structure verified")
    print("G3 NFS files: " + ", ".join(nfs_change_files))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
