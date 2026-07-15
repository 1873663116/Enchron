#!/bin/zsh
set -euo pipefail

repo=${0:A:h:h}
device=${SIMULATOR_UDID:-booted}
destination="platform=visionOS Simulator,id=$device"
if [[ $device == booted ]]; then
    destination='platform=visionOS Simulator,name=Apple Vision Pro,OS=latest'
fi
bundle_id=com.xiongzhipeng.XrPlayer
work=${TMPDIR:-/tmp}/EnchronPhotosVerification
derived_data=${DERIVED_DATA_PATH:-$work/DerivedData}
fixture=$work/enchrom-photos-verification.mp4
runtime_log=$work/runtime.log
snapshot_evidence=$work/snapshot.json
first_frame=$work/frame-1.png
second_frame=$work/frame-2.png
pid=''

cleanup() {
    if [[ -n $pid ]]; then
        xcrun simctl terminate $device $bundle_id >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

for tool in xcodebuild xcrun ffmpeg rg jq; do
    command -v $tool >/dev/null || { print -u2 "Missing required tool: $tool"; exit 1 }
done

mkdir -p $work
rm -f $runtime_log $snapshot_evidence $first_frame $second_frame
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i 'testsrc2=size=640x360:rate=30,hue=H=PI*t/2:s=1' \
    -f lavfi -i 'sine=frequency=660:sample_rate=48000' \
    -t 12 -c:v libx264 -preset ultrafast -g 30 -pix_fmt yuv420p \
    -c:a aac -b:a 128k -movflags +faststart $fixture

xcodebuild build -quiet \
    -project $repo/XrPlayer.xcodeproj \
    -scheme XrPlayer \
    -destination $destination \
    -derivedDataPath $derived_data

app=$derived_data/Build/Products/Debug-xrsimulator/XrPlayer.app
xcrun simctl install $device $app
xcrun simctl addmedia $device $fixture
xcrun simctl privacy $device reset photos $bundle_id
env SIMCTL_CHILD_ENCHRON_RESET_MEDIA_LIBRARY=1 \
    SIMCTL_CHILD_ENCHRON_AUTOPLAY_FIRST_PHOTO=1 \
    xcrun simctl launch --terminate-running-process $device $bundle_id >/dev/null
sleep 2
xcrun simctl terminate $device $bundle_id >/dev/null 2>&1 || true
xcrun simctl privacy $device grant photos $bundle_id

launch=$(env SIMCTL_CHILD_ENCHRON_RESET_MEDIA_LIBRARY=1 \
    SIMCTL_CHILD_ENCHRON_AUTOPLAY_FIRST_PHOTO=1 \
    xcrun simctl launch --terminate-running-process $device $bundle_id)
pid=${launch##*: }

for _ in {1..120}; do
    xcrun simctl spawn $device log show --last 2m --style compact \
        --predicate "processIdentifier == $pid AND (subsystem == 'app.enchron' OR subsystem == 'com.xiongzhipeng.PlaybackCore')" \
        >$runtime_log
    if rg -q 'session.firstSample' $runtime_log && rg -q 'session.firstEnqueue' $runtime_log; then
        break
    fi
    sleep 0.25
done

rg -q 'Photos source (resolved as a directly readable file URL|staged for FFmpeg playback)' $runtime_log
rg -q 'session.firstSample' $runtime_log
rg -q 'session.firstEnqueue' $runtime_log

snapshot_source=$(rg -o 'snapshot=[^ ]+' $runtime_log | head -1 | cut -d= -f2)
for _ in {1..100}; do
    if [[ -f $snapshot_source ]] && jq -e '
        .providerOpen.providerKind == "FFmpegCompressed"
        and .acceptedRendererInputCount >= 30
        and .audioSampleBufferCount >= 30
        and .presentationBinding.entityAttached == true
        and .lastError == null
    ' $snapshot_source >/dev/null; then
        break
    fi
    sleep 0.1
done
cp $snapshot_source $snapshot_evidence
jq -e '
    .providerOpen.providerKind == "FFmpegCompressed"
    and .acceptedRendererInputCount >= 30
    and .audioSampleBufferCount >= 30
    and .presentationBinding.entityAttached == true
    and .lastError == null
' $snapshot_evidence >/dev/null

xcrun simctl io $device screenshot $first_frame >/dev/null
sleep 1
xcrun simctl io $device screenshot $second_frame >/dev/null
cmp -s $first_frame $second_frame && { print -u2 "Photos playback surface did not change"; exit 1 }

print "PASS Photos PHAsset reference and FFmpeg playback verification"
print "PlaybackCore snapshot: $snapshot_evidence"
print "screenshots: $first_frame $second_frame"
