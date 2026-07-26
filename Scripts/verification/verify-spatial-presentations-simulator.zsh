#!/bin/zsh
set -euo pipefail

repo=${0:A:h:h:h}
device=${SIMULATOR_UDID:-booted}
destination="platform=visionOS Simulator,id=$device"
if [[ $device == booted ]]; then
    destination='platform=visionOS Simulator,name=Apple Vision Pro,OS=latest'
fi
port=18737
username=enchrolab
password=verification
work=${TMPDIR:-/tmp}/EnchronSpatialAcceptance-$(date +%Y%m%d-%H%M%S)
derived_data=$work/DerivedData
fixture=$work/spatial-acceptance.mp4
server_log=$work/server.log
test_log=$work/xcodebuild.log
runtime_log=$work/runtime.log
result_bundle=$work/SpatialPresentationAcceptance.xcresult
snapshot_evidence=$work/snapshot.json
events_evidence=$work/events.jsonl
test_timeout_seconds=${ENCHRON_SPATIAL_TEST_TIMEOUT_SECONDS:-600}
ui_test_selection=${ENCHRON_SPATIAL_UI_TEST_SELECTION:-EnchronAppUITests/SpatialPresentationAcceptanceUITests/testRealPlaybackDockedAndPanoramaRoundTrips}
verify_spatial_binding=${ENCHRON_SPATIAL_VERIFY_BINDING:-1}
server_pid=''
test_pid=''

cleanup() {
    if [[ -n $test_pid ]]; then
        kill -TERM $test_pid >/dev/null 2>&1 || true
        wait $test_pid >/dev/null 2>&1 || true
    fi
    if [[ -n $server_pid ]]; then
        kill $server_pid >/dev/null 2>&1 || true
        wait $server_pid >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

for tool in xcodebuild xcrun ffmpeg rg jq python3 curl; do
    command -v $tool >/dev/null || { print -u2 "Missing required tool: $tool"; exit 1 }
done

mkdir -p $work
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i 'testsrc2=size=1280x720:rate=30,hue=H=PI*t/2:s=1' \
    -f lavfi -i 'sine=frequency=440:sample_rate=48000' \
    -t 30 -c:v libx264 -preset ultrafast -g 30 -pix_fmt yuv420p \
    -c:a aac -b:a 128k -movflags +faststart $fixture

python3 $repo/Scripts/fixtures/range-http-server.py \
    --directory $work \
    --port $port \
    --username $username \
    --password $password >$server_log 2>&1 &
server_pid=$!

server_ready=''
for _ in {1..30}; do
    result=$(curl --silent --show-error \
        --user $username:$password \
        --range 0-0 \
        --output /dev/null \
        --write-out '%{http_code} %{size_download}' \
        http://127.0.0.1:$port/spatial-acceptance.mp4 || true)
    if [[ $result == '206 1' ]]; then
        server_ready=1
        break
    fi
    sleep 0.1
done
[[ -n $server_ready ]] || { print -u2 "Spatial fixture server did not start"; exit 1 }

started_at=$(date -u '+%Y-%m-%d %H:%M:%S')
set +e
xcodebuild test \
    -project $repo/Enchron.xcodeproj \
    -scheme Enchron \
    -destination $destination \
    -derivedDataPath $derived_data \
    -resultBundlePath $result_bundle \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 300 \
    -maximum-test-execution-time-allowance 420 \
    -only-testing:$ui_test_selection \
    >$test_log 2>&1 &
test_pid=$!
test_deadline=$(( SECONDS + test_timeout_seconds ))
test_timed_out=''
while kill -0 $test_pid >/dev/null 2>&1; do
    if (( SECONDS >= test_deadline )); then
        test_timed_out=1
        kill -INT $test_pid >/dev/null 2>&1 || true
        for _ in {1..10}; do
            kill -0 $test_pid >/dev/null 2>&1 || break
            sleep 1
        done
        kill -TERM $test_pid >/dev/null 2>&1 || true
        break
    fi
    sleep 1
done
wait $test_pid
test_status=$?
set -e

if [[ -n $test_timed_out ]]; then
    print -u2 "Spatial UI test exceeded ${test_timeout_seconds}s; inspect the first unfinished Xcode operation below."
    tail -n 200 $test_log
    if rg -q 'waiting for workers to materialize|IDELaunchiPhoneSimulatorLauncher' $test_log; then
        print -u2 "INFRASTRUCTURE FAILURE: visionOS XCTest worker did not materialize; no product assertion ran."
    fi
    print -u2 "Result bundle: $result_bundle"
    exit 124
fi

xcrun simctl spawn $device log show \
    --start "$started_at" \
    --style compact \
    --predicate "subsystem == 'app.enchron' OR subsystem == 'com.xiongzhipeng.PlaybackCore'" \
    >$runtime_log

if (( test_status != 0 )); then
    tail -n 160 $test_log
    print -u2 "Spatial UI test failed; runtime log: $runtime_log"
    print -u2 "Result bundle: $result_bundle"
    exit $test_status
fi

if [[ $verify_spatial_binding != 1 ]]; then
    print "PASS real PlaybackCore UI tests: $ui_test_selection"
    print "Result bundle: $result_bundle"
    print "Runtime log: $runtime_log"
    exit 0
fi

if rg -q 'fixture surface attached' $runtime_log; then
    print -u2 "FAIL spatial acceptance used the UI-test PlaybackRuntime fixture"
    exit 1
fi
rg -q 'session prepared id=' $runtime_log
rg -q 'world load completed' $runtime_log

snapshot_source=$(rg -o 'snapshot=[^ ]+' $runtime_log | tail -1 | cut -d= -f2)
events_source=$(rg -o 'events=[^ ]+' $runtime_log | tail -1 | cut -d= -f2)
[[ -f $snapshot_source ]] || { print -u2 "PlaybackCore snapshot was not found: $snapshot_source"; exit 1 }
[[ -f $events_source ]] || { print -u2 "PlaybackCore events were not found: $events_source"; exit 1 }
cp $snapshot_source $snapshot_evidence
cp $events_source $events_evidence

jq -e '
    .mediaSession.mediaSessionID == .presentationBinding.mediaSessionID
    and .mediaSession.mediaSessionID == .realityKitBinding.mediaSessionID
    and .presentationBinding.entityAttached == true
    and .presentationBinding.sceneContainer.value == "WindowGroup"
    and .realityKitBinding.active == true
    and .sampleCount >= 60
    and .acceptedRendererInputCount >= 60
    and .audioSampleBufferCount >= 60
    and .audioRendererState.enqueuedSampleBufferCount >= 60
    and .lastError == null
' $snapshot_evidence >/dev/null

python3 - $events_evidence <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
states = [
    event["details"]
    for event in events
    if event.get("kind") == "presentation.stateChanged"
]
modes = []
for state in states:
    mode = state.get("requestedMode")
    if mode and (not modes or modes[-1] != mode):
        modes.append(mode)
expected = ["window", "docked", "window", "panorama", "window"]
if modes != expected:
    raise SystemExit(f"presentation sequence mismatch: expected {expected}, got {modes}")
settled = [
    state for state in states
    if state.get("requestedMode") == "panorama" and state.get("phase") == "settled"
]
if not settled:
    raise SystemExit("panorama never reached a settled VideoPlayerComponent observation")
state = settled[-1]
required = {
    "desiredImmersiveViewingMode": "progressive",
    "actualImmersiveViewingMode": "progressive",
    "desiredViewingMode": "mono",
    "actualViewingMode": "mono",
    "desiredSpatialVideoMode": "screen",
    "actualSpatialVideoMode": "screen",
}
unexpected = {key: state.get(key) for key, value in required.items() if state.get(key) != value}
if unexpected:
    raise SystemExit(f"panorama settled with unexpected modes: {unexpected}")
PY

print "PASS real PlaybackCore Window -> Docked -> Window -> Panorama -> Window"
print "stateBinding=passed simulatorVisual=evidence-captured deviceL3=not-run"
print "Result bundle: $result_bundle"
print "Runtime log: $runtime_log"
print "PlaybackCore snapshot: $snapshot_evidence"
print "PlaybackCore events: $events_evidence"
