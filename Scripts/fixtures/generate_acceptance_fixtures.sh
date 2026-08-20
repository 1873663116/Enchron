#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/../TestMedia/TestVectors/Enchron/PlaybackBehavior"
SELECTED_FIXTURE=""
FFMPEG="${FFMPEG:-ffmpeg}"
FFPROBE="${FFPROBE:-ffprobe}"
CC="${CC:-clang}"
PKG_CONFIG="${PKG_CONFIG:-pkg-config}"
JQ="${JQ:-jq}"
REGISTRY="$ROOT_DIR/Tests/Fixtures/fixture-registry.json"

usage() {
  cat <<'EOF'
Usage: generate_acceptance_fixtures.sh [output-directory] [--fixture fixture-name]

With no --fixture option, generates the legacy acceptance fixture set with FFmpeg 8.0.1.
The only fixture currently available for targeted generation is sdr-bframe-aggregate-30s.
EOF
}

if [[ $# -gt 0 && "$1" != --* ]]; then
  OUTPUT_DIR="$1"
  shift
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fixture)
      if [[ $# -lt 2 || -n "$SELECTED_FIXTURE" ]]; then
        usage >&2
        exit 2
      fi
      SELECTED_FIXTURE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$SELECTED_FIXTURE" in
  ""|sdr-bframe-aggregate-30s)
    ;;
  sdr-bframe-aggregate-30s.mkv)
    SELECTED_FIXTURE="sdr-bframe-aggregate-30s"
    ;;
  *)
    printf 'unsupported targeted fixture: %s\n' "$SELECTED_FIXTURE" >&2
    usage >&2
    exit 2
    ;;
esac

command -v "$FFMPEG" >/dev/null
command -v "$FFPROBE" >/dev/null
command -v "$CC" >/dev/null
command -v "$PKG_CONFIG" >/dev/null
command -v "$JQ" >/dev/null
FFMPEG_VERSION_LINE="$("$FFMPEG" -version | sed -n '1p')"
FFMPEG_VERSION="${FFMPEG_VERSION_LINE#ffmpeg version }"
FFMPEG_VERSION="${FFMPEG_VERSION%% Copyright*}"
if [[ -z "$SELECTED_FIXTURE" && "$FFMPEG_VERSION" != "8.0.1" ]]; then
  printf 'legacy acceptance fixtures require FFmpeg 8.0.1, found %s\n' \
    "$FFMPEG_VERSION" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

verify_hash() {
  local fixture_id="$1"
  local fixture="$2"
  local expected="$3"
  local actual
  actual="$(shasum -a 256 "$fixture" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    printf 'fixture hash mismatch for %s at %s: expected %s, got %s\n' \
      "$fixture_id" "$fixture" "$expected" "$actual" >&2
    exit 1
  fi
}

verify_registered_source() {
  local device_import_path="$1"
  local fixture="$OUTPUT_DIR/${device_import_path#TestVectors/Enchron/PlaybackBehavior/}"
  local fixture_id
  local expected_hash
  fixture_id="$("$JQ" -er --arg path "$device_import_path" \
    '.fixtures[] | select(.deviceImportPath == $path) | .id' "$REGISTRY")"
  expected_hash="$("$JQ" -er --arg path "$device_import_path" \
    '.fixtures[] | select(.deviceImportPath == $path) | .sha256' "$REGISTRY")"
  verify_hash "$fixture_id" "$fixture" "$expected_hash"
}

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
  local build_dir
  build_dir="$(mktemp -d "${TMPDIR:-/tmp}/enchron-subtitle-fixture.XXXXXX")"
  local bitmap="$build_dir/generated-bitmap-subtitle.mks"
  local generator="$build_dir/generate-bitmap-subtitle-fixture"
  local ffmpeg_build_flags
  read -r -a ffmpeg_build_flags <<< "$("$PKG_CONFIG" --cflags --libs libavformat libavcodec libavutil)"
  "$CC" -std=c17 -Wall -Wextra \
    "$ROOT_DIR/Scripts/fixtures/generate_bitmap_subtitle_fixture.c" \
    "${ffmpeg_build_flags[@]}" \
    -o "$generator"
  "$generator" "$bitmap"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -i "$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-30s.mp4" \
    -f srt -i "$ROOT_DIR/Scripts/fixtures/acceptance-subtitles.srt" \
    -f ass -i "$ROOT_DIR/Scripts/fixtures/acceptance-subtitles.ass" \
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
  rm -rf -- "$build_dir"
}

generate_video_only() {
  local output="$OUTPUT_DIR/sdr-bframe-video-only-15s.mp4"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -i "$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-30s.mp4" \
    -map 0:v:0 -map_metadata -1 -c:v copy -an -movflags +faststart -t 15 "$output"
}

generate_audio_codec_matrix() {
  local output="$OUTPUT_DIR/sdr-bframe-audio-codec-matrix-15s.mkv"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -i "$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-30s.mp4" \
    -f lavfi -i "$(audio_pulse 500 15)" \
    -f lavfi -i "$(audio_pulse 550 15)" \
    -f lavfi -i "$(audio_pulse 600 15)" \
    -f lavfi -i "$(audio_pulse 650 15)" \
    -f lavfi -i "$(audio_pulse 700 15)" \
    -f lavfi -i "$(audio_pulse 750 15)" \
    -f lavfi -i "$(audio_pulse 800 15)" \
    -map 0:v:0 -map 0:a:0 -map 1:a:0 -map 2:a:0 -map 3:a:0 \
    -map 4:a:0 -map 5:a:0 -map 6:a:0 -map 7:a:0 \
    -map_metadata -1 -c:v copy \
    -c:a:0 copy \
    -c:a:1 ac3 -b:a:1 192k \
    -c:a:2 eac3 -b:a:2 192k \
    -c:a:3 mp2 -b:a:3 192k \
    -c:a:4 libmp3lame -b:a:4 192k \
    -c:a:5 alac \
    -c:a:6 libopus -b:a:6 128k \
    -c:a:7 flac \
    -metadata:s:a:0 title='AAC 880 Hz sync pulse' \
    -metadata:s:a:1 title='AC-3 500 Hz sync pulse' \
    -metadata:s:a:2 title='E-AC-3 550 Hz sync pulse' \
    -metadata:s:a:3 title='MP2 600 Hz sync pulse' \
    -metadata:s:a:4 title='MP3 650 Hz sync pulse' \
    -metadata:s:a:5 title='ALAC 700 Hz sync pulse' \
    -metadata:s:a:6 title='Opus 750 Hz sync pulse' \
    -metadata:s:a:7 title='FLAC 800 Hz sync pulse' \
    -disposition:a:0 default -disposition:a:1 0 -disposition:a:2 0 -disposition:a:3 0 \
    -disposition:a:4 0 -disposition:a:5 0 -disposition:a:6 0 -disposition:a:7 0 \
    -t 15 -bitexact "$output"
}

generate_aggregate() {
  local output="$OUTPUT_DIR/sdr-bframe-aggregate-30s.mkv"
  local source_path="TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-avsync-30s.mp4"
  local build_dir
  verify_registered_source "$source_path"
  build_dir="$(mktemp -d "${TMPDIR:-/tmp}/enchron-aggregate-fixture.XXXXXX")"
  local bitmap="$build_dir/generated-bitmap-subtitle.mks"
  local generator="$build_dir/generate-bitmap-subtitle-fixture"
  local ffmpeg_build_flags
  read -r -a ffmpeg_build_flags <<< "$("$PKG_CONFIG" --cflags --libs libavformat libavcodec libavutil)"
  "$CC" -std=c17 -Wall -Wextra \
    "$ROOT_DIR/Scripts/fixtures/generate_bitmap_subtitle_fixture.c" \
    "${ffmpeg_build_flags[@]}" \
    -o "$generator"
  "$generator" "$bitmap"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -i "$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-30s.mp4" \
    -f lavfi -i "$(audio_pulse 660 30)" \
    -f lavfi -i "$(audio_pulse 440 30)" \
    -f lavfi -i "$(audio_pulse 550 30)" \
    -f srt -i "$ROOT_DIR/Scripts/fixtures/acceptance-subtitles.srt" \
    -f ass -i "$ROOT_DIR/Scripts/fixtures/acceptance-subtitles.ass" \
    -i "$bitmap" \
    -map 0:v:0 -map 0:a:0 -map 1:a:0 -map 2:a:0 -map 3:a:0 \
    -map 4:s:0 -map 5:s:0 -map 6:s:0 \
    -map_metadata -1 -c:v copy \
    -c:a:0 copy \
    -c:a:1 flac \
    -c:a:2 ac3 -b:a:2 192k \
    -c:a:3 eac3 -b:a:3 192k \
    -metadata:s:a:0 title='AAC 880 Hz sync pulse' \
    -metadata:s:a:1 title='FLAC 660 Hz sync pulse' \
    -metadata:s:a:2 title='AC-3 440 Hz sync pulse' \
    -metadata:s:a:3 title='E-AC-3 550 Hz sync pulse' \
    -disposition:a:0 default -disposition:a:1 0 \
    -disposition:a:2 0 -disposition:a:3 0 \
    -c:s:0 srt -c:s:1 ass -c:s:2 copy \
    -metadata:s:s:0 language=zho \
    -metadata:s:s:0 title='Enchron acceptance subtitles' \
    -metadata:s:s:1 language=eng \
    -metadata:s:s:1 title='Enchron styled libass proof' \
    -metadata:s:s:2 language=eng \
    -metadata:s:s:2 title='Enchron generated bitmap proof' \
    -t 30 -bitexact "$output"
  rm -rf -- "$build_dir"
}

generate_av1_flac() {
  local output="$OUTPUT_DIR/av1-flac-avsync-10s.mkv"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -f lavfi -i "testsrc2=size=640x360:rate=30:duration=10,drawbox=color=white:t=fill:enable='lt(mod(t,1),0.08)',format=yuv420p,setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709" \
    -f lavfi -i "$(audio_pulse 850 10)" \
    -map 0:v:0 -map 1:a:0 -map_metadata -1 \
    -c:v libsvtav1 -preset 11 -crf 35 -svtav1-params lp=1 -pix_fmt yuv420p -r 30 -g 60 \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv \
    -c:a flac -ar 48000 -ac 2 \
    -metadata:s:a:0 title='FLAC 850 Hz sync pulse' \
    -t 10 -bitexact "$output"
}

generate_external_subtitles() {
  cp -p "$ROOT_DIR/Scripts/fixtures/acceptance-subtitles.srt" \
    "$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-30s.zh-CN.srt"
  cp -p "$ROOT_DIR/Scripts/fixtures/acceptance-subtitles.ass" \
    "$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-30s.styled.ass"
}

generate_aggregate_external_subtitles() {
  cp -p "$ROOT_DIR/Scripts/fixtures/aggregate-external-subtitles.srt" \
    "$OUTPUT_DIR/sdr-bframe-aggregate-30s.zh-CN.srt"
  cp -p "$ROOT_DIR/Scripts/fixtures/aggregate-external-subtitles.ass" \
    "$OUTPUT_DIR/sdr-bframe-aggregate-30s.styled.ass"
}

if [[ "$SELECTED_FIXTURE" == "sdr-bframe-aggregate-30s" ]]; then
  printf 'Generating %s with FFmpeg %s\n' "$SELECTED_FIXTURE" "$FFMPEG_VERSION"
  generate_aggregate
  generate_aggregate_external_subtitles
else
  generate_sdr
  generate_long_sdr
  generate_hdr arib-std-b67 arib-std-b67 hlg-hevc-10bit-avsync-10s.mp4
  generate_hdr smpte2084 smpte2084 pq-hevc-10bit-avsync-10s.mp4
  generate_subtitle
  generate_video_only
  generate_audio_codec_matrix
  generate_av1_flac
  generate_external_subtitles
fi

while IFS=$'\t' read -r fixture_id import_path expected_hash; do
  verify_hash "$fixture_id" "$OUTPUT_DIR/${import_path#TestVectors/Enchron/PlaybackBehavior/}" "$expected_hash"
done < <(
  "$JQ" -r --arg selected "$SELECTED_FIXTURE" '
    .fixtures[]
    | select(.acceptanceEligibility == "eligible-local-generated")
    | select(
        if $selected == "sdr-bframe-aggregate-30s" then
          .deviceImportPath
          | startswith("TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.")
        else
          .deviceImportPath
          | startswith("TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.")
          | not
        end
      )
    | [.id, .deviceImportPath, .sha256]
    | @tsv
  ' "$REGISTRY"
)

for fixture in "$OUTPUT_DIR"/*.mp4 "$OUTPUT_DIR"/*.mkv; do
  hash="$(shasum -a 256 "$fixture" | awk '{print $1}')"
  duration="$($FFPROBE -v error -show_entries format=duration -of default=nw=1:nk=1 "$fixture")"
  printf '%s  duration=%s  %s\n' "$hash" "$duration" "${fixture#$ROOT_DIR/}"
done
