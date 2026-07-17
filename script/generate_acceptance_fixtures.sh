#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/.verification-fixtures}"
FFMPEG="${FFMPEG:-ffmpeg}"
FFPROBE="${FFPROBE:-ffprobe}"
CC="${CC:-clang}"
PKG_CONFIG="${PKG_CONFIG:-pkg-config}"

command -v "$FFMPEG" >/dev/null
command -v "$FFPROBE" >/dev/null
command -v "$CC" >/dev/null
command -v "$PKG_CONFIG" >/dev/null
"$FFMPEG" -version | head -n 1 | grep -q 'ffmpeg version 8\.0\.1'

mkdir -p "$OUTPUT_DIR"

audio_pulse() {
  local frequency="$1"
  local duration="$2"
  printf 'sine=frequency=%s:sample_rate=48000:duration=%s,volume=if(lt(mod(t\\,1)\\,0.08)\\,0.45\\,0):eval=frame,pan=stereo|c0=c0|c1=c0' \
    "$frequency" "$duration"
}

generate_sdr() {
  local output="$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-30s.mp4"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=30,drawbox=color=white:t=fill:enable='lt(mod(t,1),0.08)',format=yuv420p" \
    -f lavfi -i "$(audio_pulse 880 30)" \
    -f lavfi -i "$(audio_pulse 440 30)" \
    -map 0:v:0 -map 1:a:0 -map 2:a:0 \
    -c:v libx264 -threads 1 -preset medium -profile:v high -level:v 4.0 \
    -pix_fmt yuv420p -r 30 -g 60 -keyint_min 60 -sc_threshold 0 -bf 3 \
    -x264-params 'colorprim=bt709:transfer=bt709:colormatrix=bt709:range=limited' \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv \
    -c:a aac -b:a 128k -ar 48000 -ac 2 \
    -metadata:s:a:0 title='880 Hz sync pulse' \
    -metadata:s:a:1 title='440 Hz sync pulse' \
    -movflags +faststart -t 30 "$output"
}

generate_long_sdr() {
  local output="$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-120s.mp4"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -stream_loop 3 \
    -i "$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-30s.mp4" \
    -map 0 -map_metadata -1 -c copy -movflags +faststart -t 120 "$output"
}

generate_hdr() {
  local transfer="$1"
  local x265_transfer="$2"
  local output="$3"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=10,drawbox=color=white:t=fill:enable='lt(mod(t,1),0.08)',format=yuv420p10le" \
    -f lavfi -i "$(audio_pulse 660 10)" \
    -map 0:v:0 -map 1:a:0 \
    -c:v libx265 -preset medium -pix_fmt yuv420p10le -tag:v hvc1 \
    -x265-params "pools=none:frame-threads=1:repeat-headers=1:keyint=60:min-keyint=60:scenecut=0:colorprim=bt2020:transfer=$x265_transfer:colormatrix=bt2020nc:range=limited" \
    -color_primaries bt2020 -color_trc "$transfer" -colorspace bt2020nc -color_range tv \
    -c:a aac -b:a 128k -ar 48000 -ac 2 \
    -metadata:s:a:0 title='660 Hz sync pulse' \
    -movflags +faststart -t 10 "$OUTPUT_DIR/$output"
}

generate_subtitle() {
  local output="$OUTPUT_DIR/sdr-bframe-multiaudio-subtitles-30s.mkv"
  local bitmap="$OUTPUT_DIR/generated-bitmap-subtitle.mks"
  local generator="$OUTPUT_DIR/generate-bitmap-subtitle-fixture"
  local ffmpeg_build_flags
  read -r -a ffmpeg_build_flags <<< "$("$PKG_CONFIG" --cflags --libs libavformat libavcodec libavutil)"
  "$CC" -std=c17 -Wall -Wextra \
    "$ROOT_DIR/script/generate_bitmap_subtitle_fixture.c" \
    "${ffmpeg_build_flags[@]}" \
    -o "$generator"
  "$generator" "$bitmap"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -i "$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-30s.mp4" \
    -f srt -i "$ROOT_DIR/script/fixtures/acceptance-subtitles.srt" \
    -f ass -i "$ROOT_DIR/script/fixtures/acceptance-subtitles.ass" \
    -i "$bitmap" \
    -map 0:v:0 -map 0:a:0 -map 0:a:1 -map 1:s:0 -map 2:s:0 -map 3:s:0 \
    -map_metadata -1 -c copy -c:s:0 srt -c:s:1 ass -c:s:2 copy \
    -metadata:s:s:0 language=zho \
    -metadata:s:s:0 title='Enchron acceptance subtitles' \
    -metadata:s:s:1 language=eng \
    -metadata:s:s:1 title='Enchron styled libass proof' \
    -metadata:s:s:2 language=eng \
    -metadata:s:s:2 title='Enchron generated bitmap proof' \
    -t 30 -bitexact "$output"
}

generate_sdr
generate_long_sdr
generate_hdr arib-std-b67 arib-std-b67 hlg-hevc-10bit-avsync-10s.mp4
generate_hdr smpte2084 smpte2084 pq-hevc-10bit-avsync-10s.mp4
generate_subtitle

REGISTRY="$ROOT_DIR/docs/acceptance/fixture-registry.json"
verify_hash() {
  local registry_index="$1"
  local fixture="$2"
  local expected
  local actual
  expected="$(/usr/bin/plutil -extract "fixtures.$registry_index.sha256" raw "$REGISTRY")"
  actual="$(shasum -a 256 "$fixture" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    printf 'fixture hash mismatch for %s: expected %s, got %s\n' "$fixture" "$expected" "$actual" >&2
    exit 1
  fi
}

verify_hash 1 "$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-30s.mp4"
verify_hash 2 "$OUTPUT_DIR/hlg-hevc-10bit-avsync-10s.mp4"
verify_hash 3 "$OUTPUT_DIR/pq-hevc-10bit-avsync-10s.mp4"
verify_hash 4 "$OUTPUT_DIR/sdr-bframe-multiaudio-subtitles-30s.mkv"
verify_hash 5 "$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-120s.mp4"

for fixture in "$OUTPUT_DIR"/*.mp4 "$OUTPUT_DIR"/*.mkv; do
  hash="$(shasum -a 256 "$fixture" | awk '{print $1}')"
  duration="$($FFPROBE -v error -show_entries format=duration -of default=nw=1:nk=1 "$fixture")"
  printf '%s  duration=%s  %s\n' "$hash" "$duration" "${fixture#$ROOT_DIR/}"
done
