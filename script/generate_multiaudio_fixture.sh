#!/usr/bin/env bash
set -euo pipefail

OUTPUT="${1:-/tmp/playbackcore-two-audio-tracks.mp4}"
ffmpeg -hide_banner -y \
  -f lavfi -i 'testsrc2=size=640x360:rate=30:duration=12' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=12' \
  -f lavfi -i 'sine=frequency=880:sample_rate=48000:duration=12' \
  -map 0:v -map 1:a -map 2:a \
  -metadata:s:a:0 language=eng -metadata:s:a:0 title='Tone 440 Hz' \
  -metadata:s:a:1 language=jpn -metadata:s:a:1 title='Tone 880 Hz' \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$OUTPUT"
