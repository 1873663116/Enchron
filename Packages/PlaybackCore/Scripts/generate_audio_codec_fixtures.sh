#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
workspace_dir=${script_dir:h:h:h}
test_media_root=${1:-${workspace_dir:h}/TestMedia}
output_dir=${test_media_root}/TestVectors/Enchron/CodecContainer/Audio
ffmpeg_bin=${FFMPEG_BIN:-/opt/homebrew/bin/ffmpeg}
ffprobe_bin=${FFPROBE_BIN:-/opt/homebrew/bin/ffprobe}

fixture_tmp=$(mktemp -d /tmp/enchron-audio-fixtures.XXXXXX)
trap 'rm -r "$fixture_tmp"' EXIT
mkdir -p "$output_dir"

# Four HE-AAC output packets are enough to cover encoder priming and expose
# stable packet duration without turning structural fixtures into listening tests.
"$ffmpeg_bin" -v error \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000' \
  -filter_complex '[0:a]pan=stereo|c0=c0|c1=c0[a]' \
  -map '[a]' -frames:a 8192 -c:a pcm_s16le \
  "$fixture_tmp/source-stereo.wav"

afconvert "$fixture_tmp/source-stereo.wav" \
  -o "$output_dir/he-aac-v1-apple-audio-toolbox.m4a" \
  -f m4af -d aach -b 64000

afconvert "$fixture_tmp/source-stereo.wav" \
  -o "$output_dir/he-aac-v2-apple-audio-toolbox.m4a" \
  -f m4af -d aacp -b 32000

for fixture in "$output_dir"/*.m4a; do
  "$ffprobe_bin" -v error -select_streams a:0 \
    -show_entries stream=codec_name,profile,codec_tag_string,sample_rate,channels,channel_layout,extradata_size \
    -of default=noprint_wrappers=1 "$fixture"
  shasum -a 256 "$fixture"
done
