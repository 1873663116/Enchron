#!/usr/bin/env python3
"""Verify the source-to-demux buffer policy wiring and observable limits."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    target = ROOT / path
    if not target.is_file():
        raise AssertionError(f"missing required file: {path}")
    return target.read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    bridge = read(
        "Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c"
    )
    buffering = read(
        "Packages/PlaybackCore/Sources/PlaybackCore/PlaybackDemuxBuffering.swift"
    )
    byte_stream = read("Modules/MediaSource/MediaByteStream.swift")
    runtime = read("Modules/PlaybackFeature/PlaybackRuntime.swift")
    launch = read("Modules/PlaybackFeature/PlaybackLaunchRequest.swift")
    diagnostics = read("Apps/Enchron/MainView.swift")

    require(
        "150LL * 1024 * 1024" in bridge
        and "50LL * 1024 * 1024" in bridge
        and "1000.0 * 60 * 60" in bridge,
        "mpv demux_conf byte and cache-duration defaults drifted",
    )
    require(
        "PB_DEMUX_PREFETCH_DURATION_MICROSECONDS" not in bridge,
        "the fixed six-second prefetch watermark returned",
    )
    require(
        "forwardBufferedByteCount >=" in bridge
        and "bufferedDurationMicroseconds <" in bridge,
        "the read loop no longer combines byte and duration stopping conditions",
    )
    require(
        "preferredBufferDepth" not in byte_stream.split(
            "public struct MediaByteStreamAttributes", 1
        )[1].split("public struct MediaByteRangeRead", 1)[0],
        "a generic byte source still declares a demux policy it may never consume",
    )
    require(
        "preferredBufferDepth: MediaByteBufferDepth = .none" in byte_stream,
        "the playable byte-stream registration no longer carries its policy",
    )
    for path in (
        "Modules/MediaLibrary/Sources/SMB/SMBDataSourceAdapter.swift",
        "Modules/MediaLibrary/Sources/WebDAV/WebDAVDataSourceAdapter.swift",
        "Modules/Emby/EmbyPlaybackBridge.swift",
    ):
        require(
            "preferredBufferDepth: .automatic" in read(path),
            f"network playback does not request automatic buffering: {path}",
        )
    require(
        "byteStreamHandle?.preferredBufferDepth ?? (remote ? .automatic : .none)"
        in launch,
        "local and remote playback defaults are no longer distinct",
    )
    require(
        runtime.count("sourceTransport: request.source.playbackCoreTransport") == 2,
        "one PlaybackRuntime open path bypasses the demux policy",
    )
    require(
        "ENCHRON_DEMUX_FORWARD_BUFFER_BYTES" in buffering
        and "ENCHRON_DEMUX_BACKWARD_BUFFER_BYTES" in buffering
        and "ENCHRON_DEMUX_NON_CACHE_SECONDS" in buffering
        and "ENCHRON_DEMUX_CACHE_SECONDS" in buffering,
        "device-regression overrides are incomplete",
    )
    for field in (
        "demuxBufferedSeconds",
        "demuxTargetSeconds",
        "demuxForwardBytes",
        "demuxForwardLimitBytes",
        "demuxBackwardBytes",
        "demuxBackwardLimitBytes",
        "demuxReconnects",
        "demuxReadFrames",
    ):
        require(field in diagnostics, f"diagnostics omit {field}")

    print("demux buffer policy wiring verified")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
