#!/usr/bin/env bash

set -euo pipefail

scriptDirectory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repositoryRoot="$(cd "$scriptDirectory/../.." && pwd)"
workspaceRoot="$(cd "$repositoryRoot/.." && pwd)"
mediaRoot="${1:-$workspaceRoot/TestMedia}"

if [[ "$mediaRoot" != /* ]]; then
  echo "TestMedia root must be absolute: $mediaRoot" >&2
  exit 1
fi

ffmpegBinary="$(command -v ffmpeg)"
ffprobeBinary="$(command -v ffprobe)"
expectedFFmpegVersion="N-125990-g5c395992f9"
actualFFmpegVersion="$($ffmpegBinary -version | awk 'NR == 1 { print $3 }')"

if [[ "$actualFFmpegVersion" != "$expectedFFmpegVersion" ]]; then
  echo "Expected ffmpeg $expectedFFmpegVersion, found $actualFFmpegVersion" >&2
  exit 1
fi

temporaryDirectory="$(mktemp -d "${TMPDIR:-/tmp}/enchron-regression-derivative.XXXXXX")"
trap 'rm -rf "$temporaryDirectory"' EXIT

generateDerivative() {
  local relativeOutput="$1"
  local sourceFilter="$2"
  local encoderTag="$3"
  local output="$mediaRoot/$relativeOutput"
  local temporaryOutput="$temporaryDirectory/$(basename "$relativeOutput")"

  mkdir -p "$(dirname "$output")"
  "$ffmpegBinary" \
    -hide_banner \
    -loglevel error \
    -y \
    -f lavfi \
    -i "$sourceFilter" \
    -map 0:v:0 \
    -an \
    -c:v libx264 \
    -preset veryslow \
    -crf 35 \
    -profile:v main \
    -pix_fmt yuv420p \
    -color_range tv \
    -colorspace bt709 \
    -color_trc bt709 \
    -color_primaries bt709 \
    -x264-params "threads=1:keyint=30:min-keyint=30:scenecut=0:bframes=2:ref=3:colorprim=bt709:transfer=bt709:colormatrix=bt709:fullrange=off" \
    -metadata creation_time="1970-01-01T00:00:00Z" \
    -metadata encoder="$encoderTag" \
    -movflags +faststart \
    "$temporaryOutput"

  local duration
  local codec
  local dimensions
  local frameRate
  local colorRange
  local colorSpace
  local colorTransfer
  local colorPrimaries
  local audioStreams
  duration="$($ffprobeBinary -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$temporaryOutput")"
  codec="$($ffprobeBinary -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$temporaryOutput")"
  dimensions="$($ffprobeBinary -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$temporaryOutput")"
  frameRate="$($ffprobeBinary -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$temporaryOutput")"
  colorRange="$($ffprobeBinary -v error -select_streams v:0 -show_entries stream=color_range -of default=noprint_wrappers=1:nokey=1 "$temporaryOutput")"
  colorSpace="$($ffprobeBinary -v error -select_streams v:0 -show_entries stream=color_space -of default=noprint_wrappers=1:nokey=1 "$temporaryOutput")"
  colorTransfer="$($ffprobeBinary -v error -select_streams v:0 -show_entries stream=color_transfer -of default=noprint_wrappers=1:nokey=1 "$temporaryOutput")"
  colorPrimaries="$($ffprobeBinary -v error -select_streams v:0 -show_entries stream=color_primaries -of default=noprint_wrappers=1:nokey=1 "$temporaryOutput")"
  audioStreams="$($ffprobeBinary -v error -select_streams a -show_entries stream=index -of csv=p=0 "$temporaryOutput" | wc -l | tr -d ' ')"

  if [[ "$duration" != "961.000000" || "$codec" != "h264" || "$dimensions" != "160x90" || "$frameRate" != "1/1" || "$colorRange" != "tv" || "$colorSpace" != "bt709" || "$colorTransfer" != "bt709" || "$colorPrimaries" != "bt709" || "$audioStreams" != "0" ]]; then
    echo "Generated derivative failed its media contract: $relativeOutput" >&2
    exit 1
  fi

  install -m 0644 "$temporaryOutput" "$output"
  local digest
  local byteLength
  digest="$(shasum -a 256 "$output" | awk '{ print $1 }')"
  byteLength="$(stat -f '%z' "$output")"
  printf '%s\n' \
    "path=$relativeOutput" \
    "durationSeconds=$duration" \
    "byteLength=$byteLength" \
    "sha256=$digest" \
    "ffmpegVersion=$actualFFmpegVersion"
}

# The audio-only regression set is built from upstream FATE clips, and the
# longest of them runs 11.9 s. secondary-menu-pins-audio-controls has to open a
# secondary menu, wait out an 8 s controls auto-hide window and then read the
# control plane, which is three controller round trips away from the tap, so no
# FATE clip can still be Playing when the reading is taken. This derivative is
# the audio-only asset that outlasts that window. It carries no video stream at
# all -- not even an attached picture -- because PlaybackFFmpegBridge assigns a
# stream's category from codec_type alone and never reads its disposition, so a
# cover-art picture is admitted as video and MediaSourceInformation reports
# mediaKind video for the file that carries one.
generateAudioDerivative() {
  local relativeOutput="$1"
  local sourceFilter="$2"
  local encoderTag="$3"
  local expectedDuration="$4"
  local output="$mediaRoot/$relativeOutput"
  local temporaryOutput="$temporaryDirectory/$(basename "$relativeOutput")"

  mkdir -p "$(dirname "$output")"
  "$ffmpegBinary" \
    -hide_banner \
    -loglevel error \
    -y \
    -f lavfi \
    -i "$sourceFilter" \
    -map 0:a:0 \
    -vn \
    -c:a aac \
    -b:a 64k \
    -ar 48000 \
    -ac 2 \
    -metadata creation_time="1970-01-01T00:00:00Z" \
    -metadata encoder="$encoderTag" \
    -movflags +faststart \
    "$temporaryOutput"

  local duration
  local codec
  local sampleRate
  local channels
  local videoStreams
  duration="$($ffprobeBinary -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$temporaryOutput")"
  codec="$($ffprobeBinary -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$temporaryOutput")"
  sampleRate="$($ffprobeBinary -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$temporaryOutput")"
  channels="$($ffprobeBinary -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$temporaryOutput")"
  videoStreams="$($ffprobeBinary -v error -select_streams v -show_entries stream=index -of csv=p=0 "$temporaryOutput" | wc -l | tr -d ' ')"

  if [[ "$duration" != "$expectedDuration" || "$codec" != "aac" || "$sampleRate" != "48000" || "$channels" != "2" || "$videoStreams" != "0" ]]; then
    echo "Generated derivative failed its media contract: $relativeOutput" >&2
    exit 1
  fi

  install -m 0644 "$temporaryOutput" "$output"
  local digest
  local byteLength
  digest="$(shasum -a 256 "$output" | awk '{ print $1 }')"
  byteLength="$(stat -f '%z' "$output")"
  printf '%s\n' \
    "path=$relativeOutput" \
    "durationSeconds=$duration" \
    "byteLength=$byteLength" \
    "sha256=$digest" \
    "ffmpegVersion=$actualFFmpegVersion"
}

generateDerivative \
  "TestVectors/Enchron/PlaybackBehavior/viewing-storage-16m01s.mp4" \
  "testsrc2=size=160x90:rate=1:duration=961" \
  "Enchron regression derivative v1"
generateDerivative \
  "TestVectors/Enchron/PlaybackBehavior/viewing-storage-16m01s-b.mp4" \
  "testsrc=size=160x90:rate=1:duration=961" \
  "Enchron regression derivative v1 alternate"
generateAudioDerivative \
  "TestVectors/Enchron/PlaybackBehavior/audio-only-aac-stereo-181s.m4a" \
  "sine=frequency=440:sample_rate=48000:duration=181,pan=stereo|c0=c0|c1=c0" \
  "Enchron regression audio-only derivative v1" \
  "181.000000"
