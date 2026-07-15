#!/bin/zsh
set -euo pipefail

repo=${0:A:h:h}
device=${SIMULATOR_UDID:-booted}
destination="platform=visionOS Simulator,id=$device"
if [[ $device == booted ]]; then
    destination='platform=visionOS Simulator,name=Apple Vision Pro,OS=latest'
fi
bundle_id=com.xiongzhipeng.XrPlayer
media_container=${MEDIA_CONTAINER:-mp4}
[[ $media_container == mp4 || $media_container == mkv ]] || {
    print -u2 "MEDIA_CONTAINER must be mp4 or mkv"
    exit 1
}
media_route=${MEDIA_ROUTE:-ffmpeg}
[[ $media_route == ffmpeg || $media_route == apple || $media_route == http ]] || {
    print -u2 "MEDIA_ROUTE must be ffmpeg, apple, or http"
    exit 1
}
expected_provider=FFmpegCompressed
use_asset=0
if [[ $media_route == apple ]]; then
    expected_provider=AVAssetReaderOutput.Provider
    use_asset=1
fi
work=${TMPDIR:-/tmp}/EnchronRealMediaVerification-$media_container-$media_route
derived_data=$work/DerivedData
fixture=$work/fixture.$media_container
first_frame=$work/frame-1.png
second_frame=$work/frame-2.png
runtime_log=$work/runtime.log
snapshot_evidence=$work/snapshot.json
build_log=$work/build.log
pid=''
server_pid=''
http_username=enchrolab
http_password=verification
http_port=${HTTP_PORT:-18736}
server_log=$work/http-server.log
minimum_video_samples=${MINIMUM_VIDEO_SAMPLES:-30}
minimum_audio_samples=${MINIMUM_AUDIO_SAMPLES:-30}

cleanup() {
    if [[ -n $pid ]]; then
        xcrun simctl terminate $device $bundle_id >/dev/null 2>&1 || true
    fi
    if [[ -n $server_pid ]]; then
        kill $server_pid >/dev/null 2>&1 || true
        wait $server_pid >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

for tool in xcodebuild xcrun ffmpeg rg awk jq python3 curl; do
    command -v $tool >/dev/null || { print -u2 "Missing required tool: $tool"; exit 1 }
done

mkdir -p $work
rm -f $first_frame $second_frame $runtime_log $snapshot_evidence $build_log $server_log
mux_options=()
if [[ $media_container == mp4 ]]; then
    mux_options=(-movflags +faststart)
fi
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i 'testsrc2=size=640x360:rate=30,hue=H=PI*t/2:s=1' \
    -f lavfi -i 'sine=frequency=440:sample_rate=48000' \
    -t 30 -c:v libx264 -preset ultrafast -g 30 -pix_fmt yuv420p \
    -c:a aac -b:a 128k $mux_options $fixture

xcodebuild build -quiet \
    -project $repo/XrPlayer.xcodeproj \
    -scheme XrPlayer \
    -destination $destination \
    -derivedDataPath $derived_data >$build_log

app=$derived_data/Build/Products/Debug-xrsimulator/XrPlayer.app
xcrun simctl install $device $app
if [[ $media_route == http ]]; then
    python3 $repo/scripts/range-http-server.py \
        --directory $work \
        --port $http_port \
        --username $http_username \
        --password $http_password >$server_log 2>&1 &
    server_pid=$!
    endpoint=http://127.0.0.1:$http_port/fixture.$media_container
    server_ready=''
    for _ in {1..20}; do
        range_result=$(curl --silent --show-error \
            --user $http_username:$http_password \
            --range 0-1023 \
            --output /dev/null \
            --write-out '%{http_code} %{size_download}' \
            $endpoint || true)
        if [[ $range_result == '206 1024' ]]; then
            server_ready=1
            break
        fi
        sleep 0.1
    done
    [[ -n $server_ready ]] || { print -u2 "Authenticated HTTP Range fixture did not start"; exit 1 }
    playable=http://$http_username:$http_password@127.0.0.1:$http_port/fixture.$media_container
else
    container=$(xcrun simctl get_app_container $device $bundle_id data)
    playable=$container/Documents/enchrom-real-media-verification.$media_container
    cp $fixture $playable
fi
xcrun simctl terminate $device $bundle_id >/dev/null 2>&1 || true

launch=$(env SIMCTL_CHILD_ENCHRON_RESET_MEDIA_LIBRARY=1 \
    SIMCTL_CHILD_ENCHRON_AUTOPLAY_FILE=$playable \
    SIMCTL_CHILD_ENCHRON_AUTOPLAY_USE_ASSET=$use_asset \
    xcrun simctl launch --terminate-running-process $device $bundle_id)
pid=${launch##*: }

for _ in {1..30}; do
    xcrun simctl spawn $device log show --last 1m --style compact \
        --predicate "processIdentifier == $pid AND (subsystem == 'app.enchron' OR subsystem == 'com.xiongzhipeng.PlaybackCore')" \
        >$runtime_log
    if rg -q 'session.firstSample' $runtime_log && rg -q 'session.firstEnqueue' $runtime_log; then
        break
    fi
    sleep 0.25
done

rg -q 'session.firstSample' $runtime_log
rg -q 'session.firstEnqueue' $runtime_log
rg -q 'rendererStatus=ready' $runtime_log

xcrun simctl io $device screenshot $first_frame >/dev/null
sleep 1
xcrun simctl io $device screenshot $second_frame >/dev/null
xcrun simctl spawn $device log show --last 1m --style compact \
    --predicate "processIdentifier == $pid AND (subsystem == 'app.enchron' OR subsystem == 'com.xiongzhipeng.PlaybackCore')" \
    >$runtime_log

snapshot_source=$(rg -o 'snapshot=[^ ]+' $runtime_log | head -1 | cut -d= -f2)
for _ in {1..20}; do
    if [[ -f $snapshot_source ]] && jq -e '
        .sampleCount >= $minimumVideo
        and .providerOpen.providerKind == $expectedProvider
        and .acceptedRendererInputCount >= $minimumVideo
        and .audioSampleBufferCount >= $minimumAudio
        and .lastAudioSample.sampleCount > 0
        and .audioRendererState.enqueuedSampleBufferCount >= $minimumAudio
        and .presentationBinding.entityAttached == true
        and .lastError == null
    ' --arg expectedProvider $expected_provider \
      --argjson minimumVideo $minimum_video_samples \
      --argjson minimumAudio $minimum_audio_samples \
      $snapshot_source >/dev/null; then
        break
    fi
    sleep 0.1
done
cp $snapshot_source $snapshot_evidence
if ! jq -e '
    .sampleCount >= $minimumVideo
    and .providerOpen.providerKind == $expectedProvider
    and .acceptedRendererInputCount >= $minimumVideo
    and .audioSampleBufferCount >= $minimumAudio
    and .lastAudioSample.sampleCount > 0
    and .audioRendererState.enqueuedSampleBufferCount >= $minimumAudio
    and .presentationBinding.entityAttached == true
    and .lastError == null
' --arg expectedProvider $expected_provider \
  --argjson minimumVideo $minimum_video_samples \
  --argjson minimumAudio $minimum_audio_samples \
  $snapshot_evidence >/dev/null; then
    print -u2 "FAIL PlaybackCore snapshot does not prove active video, audio, and presentation lanes"
    exit 1
fi

frame_stats=$(ffmpeg -hide_banner -loglevel info -i $first_frame \
    -vf 'crop=iw*0.40:ih*0.28:iw*0.30:ih*0.30,signalstats,metadata=print' \
    -frames:v 1 -f null - 2>&1)
sat_avg=$(print -r -- $frame_stats | rg -o 'SATAVG=[0-9.]+' | head -1 | cut -d= -f2)

motion_stats=$(ffmpeg -hide_banner -loglevel info -i $first_frame -i $second_frame \
    -filter_complex '[0:v]crop=iw*0.40:ih*0.28:iw*0.30:ih*0.30[a];[1:v]crop=iw*0.40:ih*0.28:iw*0.30:ih*0.30[b];[a][b]blend=all_mode=difference,signalstats,metadata=print' \
    -frames:v 1 -f null - 2>&1)
motion_y_avg=$(print -r -- $motion_stats | rg -o 'YAVG=[0-9.]+' | head -1 | cut -d= -f2)

print "video crop SATAVG=$sat_avg motion YAVG=$motion_y_avg"
if ! awk -v value=$sat_avg 'BEGIN { exit !(value > 25) }'; then
    print -u2 "FAIL captured surface is not a sufficiently saturated video frame"
    exit 1
fi
if ! awk -v value=$motion_y_avg 'BEGIN { exit !(value > 1) }'; then
    print -u2 "FAIL captured video surface did not change between frames"
    exit 1
fi

print "PASS $media_container $media_route real media first-frame and motion verification"
print "runtime log: $runtime_log"
print "PlaybackCore snapshot: $snapshot_evidence"
print "screenshots: $first_frame $second_frame"
