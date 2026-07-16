#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/.verification-fixtures}"
FFMPEG="${FFMPEG:-$(command -v ffmpeg)}"

mkdir -p "$OUTPUT_DIR"

make_sdr_multitrack() {
  "$FFMPEG" -hide_banner -loglevel error -y \
    -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=30" \
    -f lavfi -i "aevalsrc=0.35*sin(2*PI*880*t)*lt(mod(t\,1)\,0.08):s=48000:d=30" \
    -f lavfi -i "aevalsrc=0.35*sin(2*PI*440*t)*lt(mod(t\,1)\,0.08):s=48000:d=30" \
    -filter_complex "[0:v]drawbox=x=0:y=0:w=iw:h=ih:color=white:t=fill:enable='lt(mod(t,1),0.08)',format=yuv420p[v];[1:a]aformat=channel_layouts=stereo[a0];[2:a]aformat=channel_layouts=stereo[a1]" \
    -map "[v]" -map "[a0]" -map "[a1]" \
    -c:v libx264 -preset medium -profile:v high -level 4.1 \
    -g 60 -keyint_min 60 -sc_threshold 0 -bf 3 \
    -x264-params "threads=1:lookahead_threads=1:sliced_threads=0:colorprim=bt709:transfer=bt709:colormatrix=bt709:range=tv" \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv \
    -c:a aac -b:a 128k -ar 48000 -ac 2 \
    -metadata:s:a:0 language=eng -metadata:s:a:0 title="880 Hz sync pulse" \
    -metadata:s:a:1 language=jpn -metadata:s:a:1 title="440 Hz sync pulse" \
    -disposition:a:0 default -disposition:a:1 0 \
    -movflags +faststart+write_colr \
    "$OUTPUT_DIR/sdr-bframe-multiaudio-avsync-30s.mp4"
}

make_hevc_hdr_signal() {
  local transfer="$1"
  local name="$2"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=10" \
    -f lavfi -i "aevalsrc=0.3*sin(2*PI*660*t)*lt(mod(t\,1)\,0.08):s=48000:d=10" \
    -filter_complex "[0:v]drawbox=x=0:y=0:w=iw:h=ih:color=white:t=fill:enable='lt(mod(t,1),0.08)',format=yuv420p10le[v];[1:a]aformat=channel_layouts=stereo[a]" \
    -map "[v]" -map "[a]" \
    -c:v libx265 -preset medium -tag:v hvc1 \
    -x265-params "pools=none:frame-threads=1:log-level=error:keyint=60:min-keyint=60:scenecut=0:bframes=4:colorprim=bt2020:transfer=$transfer:colormatrix=bt2020nc:range=limited" \
    -color_primaries bt2020 -color_trc "$transfer" -colorspace bt2020nc -color_range tv \
    -c:a aac -b:a 128k -ar 48000 -ac 2 \
    -metadata:s:a:0 language=eng -metadata:s:a:0 title="660 Hz sync pulse" \
    -movflags +faststart+write_colr \
    "$OUTPUT_DIR/$name"
}

make_sdr_multitrack
make_hevc_hdr_signal arib-std-b67 hlg-hevc-10bit-avsync-10s.mp4
make_hevc_hdr_signal smpte2084 pq-hevc-10bit-avsync-10s.mp4

for fixture in "$OUTPUT_DIR"/*.mp4; do
  shasum -a 256 "$fixture"
done
