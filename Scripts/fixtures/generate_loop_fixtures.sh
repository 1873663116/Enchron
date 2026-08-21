#!/bin/zsh
# Ten-minute loop copies of the spatial clips, for the transition paths that
# need playback to keep running while the presentation changes underneath it.
# The originals end after about a minute, which ends the session mid-cycle.
set -euo pipefail

repository_root=${0:a:h:h:h}
source "$repository_root/Scripts/verification/enchron_artifact_paths.sh"

test_media=${ENCHRON_TEST_MEDIA:-${repository_root:h}/TestMedia/Samples}
out=$artifact_root/loop-fixtures
minutes=${1:-10}

if [[ ! -d $test_media ]]; then
    echo "TestMedia not found at $test_media; set ENCHRON_TEST_MEDIA" >&2
    exit 1
fi

for relative in Spatial/Stereo180/180_3D Spatial/Stereo180/180_3D_TB Spatial/Panorama/360; do
    source_clip=$test_media/$relative.mp4
    target=$out/$relative:h/${relative:t}_loop$minutes.mp4
    [[ -f $source_clip ]] || { echo "missing $source_clip" >&2; exit 1; }
    mkdir -p "${target:h}"
    ffmpeg -nostdin -y -stream_loop -1 -i "$source_clip" \
        -t $((minutes * 60)) -c copy "$target"
done

echo "loop fixtures in $out"
