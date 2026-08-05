#!/bin/zsh

set -euo pipefail

repository_root=${0:A:h:h:h}
xcode_app=${ENCHRON_XCODE_APP:-/Volumes/Cortisol/Applications/Xcode-beta3.app}
developer_dir="$xcode_app/Contents/Developer"
destination=${ENCHRON_VISION_TEST_DESTINATION:-}
media_card_ids=${ENCHRON_DEVICE_REGRESSION_MEDIA_CARD_IDS:-}
derived_data=${ENCHRON_DERIVED_DATA:-/private/tmp/EnchronVisionProCoreRegressionDerivedData}
source_packages=${ENCHRON_SOURCE_PACKAGES:-/private/tmp/EnchronVisionProCoreRegressionSourcePackages}
evidence_root=${ENCHRON_EVIDENCE_ROOT:-/private/tmp/enchron-validation-evidence/visionpro-core-regression-$(date +%Y%m%d-%H%M%S)}
test_iterations=${ENCHRON_TEST_ITERATIONS:-1}
test_session_timeout_seconds=${ENCHRON_TEST_SESSION_TIMEOUT_SECONDS:-}
only_testing=${ENCHRON_ONLY_TESTING:-}

if [[ -z "$destination" ]]; then
    echo "Set ENCHRON_VISION_TEST_DESTINATION to an explicit physical Vision Pro destination, for example platform=visionOS,id=<device-id>." >&2
    exit 64
fi

if [[ "$destination" != platform=visionOS,* || "$destination" == *Simulator* || "$destination" == *simulator* || "$destination" == *placeholder* ]]; then
    echo "VisionProCoreRegression requires an explicit physical Vision Pro destination." >&2
    exit 64
fi

if [[ "$destination" != *id=* ]]; then
    echo "VisionProCoreRegression requires id=<device-id> so the selected destination can be verified as a physical Vision Pro." >&2
    exit 64
fi

device_identifier=${destination#*id=}
device_identifier=${device_identifier%%,*}

if [[ -z "$media_card_ids" || "$media_card_ids" != *,* ]]; then
    echo "Set ENCHRON_DEVICE_REGRESSION_MEDIA_CARD_IDS to at least two comma-separated Media Library accessibility identifiers." >&2
    exit 64
fi

if ! [[ "$test_iterations" =~ ^[1-9][0-9]*$ ]]; then
    echo "ENCHRON_TEST_ITERATIONS must be a positive integer." >&2
    exit 64
fi

if [[ -n "$test_session_timeout_seconds" ]] &&
    ! [[ "$test_session_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
    echo "ENCHRON_TEST_SESSION_TIMEOUT_SECONDS must be a positive integer." >&2
    exit 64
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "VisionProCoreRegression requires jq to validate the executed test count." >&2
    exit 69
fi

python3 "$repository_root/Scripts/verification/verify_visionpro_core_regression_plan.py"

device_lock_status() {
    local lock_state_file
    if [[ -z "$device_identifier" ]]; then
        echo unavailable
        return
    fi

    lock_state_file=$(mktemp)
    if ! DEVELOPER_DIR="$developer_dir" xcrun devicectl device info lockState \
        --device "$device_identifier" \
        --timeout 10 \
        --json-output "$lock_state_file" >/dev/null 2>&1; then
        rm -f "$lock_state_file"
        echo unavailable
        return
    fi

    jq -r '
        if .result.passcodeRequired == false then "false"
        elif .result.passcodeRequired == true then "true"
        else "unavailable"
        end
    ' "$lock_state_file"
    rm -f "$lock_state_file"
}

require_physical_vision_pro() {
    local device_list_file
    local is_physical_vision_pro
    device_list_file=$(mktemp)
    if ! DEVELOPER_DIR="$developer_dir" xcrun devicectl list devices \
        --json-output "$device_list_file" >/dev/null 2>&1; then
        rm -f "$device_list_file"
        echo "The physical-device service could not enumerate the selected Vision Pro." >&2
        exit 75
    fi

    is_physical_vision_pro=$(jq -r --arg identifier "$device_identifier" '
        any(
            .result.devices[]?;
            .identifier == $identifier
                and .hardwareProperties.platform == "visionOS"
                and .hardwareProperties.reality == "physical"
        )
    ' "$device_list_file")
    rm -f "$device_list_file"

    if [[ "$is_physical_vision_pro" != true ]]; then
        echo "The selected destination is not an enumerated physical Vision Pro." >&2
        exit 64
    fi
}

terminate_enchron_ui_test_runners() {
    local process_file
    local runner_pid
    local -a runner_pids
    if [[ -z "$device_identifier" ]]; then
        return
    fi

    process_file=$(mktemp)
    if ! DEVELOPER_DIR="$developer_dir" xcrun devicectl device info processes \
        --device "$device_identifier" \
        --timeout 10 \
        --json-output "$process_file" >/dev/null 2>&1; then
        rm -f "$process_file"
        return
    fi

    runner_pids=($(jq -r '
        .. | objects
        | select(
            ((.executable? // .name? // .processName? // "") | tostring)
            | contains("EnchronAppUITests-Runner")
        )
        | (.processIdentifier? // .pid? // empty)
    ' "$process_file" | sort -u))
    rm -f "$process_file"

    for runner_pid in $runner_pids; do
        DEVELOPER_DIR="$developer_dir" xcrun devicectl device process terminate \
            --device "$device_identifier" \
            --pid "$runner_pid" \
            --timeout 10 >/dev/null 2>&1 || true
    done
}

test_selection_arguments=()
if [[ -n "$only_testing" ]]; then
    requested_tests=("${(@s:,:)only_testing}")
    for requested_test in $requested_tests; do
        requested_test=${requested_test//[[:space:]]/}
        if ! jq -e --arg requested_test "$requested_test" '
            any(.testTargets[].selectedTests[]; . == $requested_test)
        ' "$repository_root/VisionProCoreRegression.xctestplan" >/dev/null; then
            echo "ENCHRON_ONLY_TESTING contains a test that is not selected by VisionProCoreRegression: $requested_test" >&2
            exit 64
        fi
        test_selection_arguments+=(
            "-only-testing:EnchronAppUITests/$requested_test"
        )
    done
    expected_test_count=${#requested_tests[@]}
    selection_description="the requested $expected_test_count registered test executions"
else
    expected_test_count=$(jq '[.testTargets[].selectedTests[]] | length' \
        "$repository_root/VisionProCoreRegression.xctestplan")
    selection_description="all $expected_test_count registered test executions"
fi
expected_test_count=$(( expected_test_count * test_iterations ))

if [[ -z "$test_session_timeout_seconds" ]]; then
    test_session_timeout_seconds=$(( 120 + expected_test_count * 180 ))
fi

test_iteration_arguments=()
if (( test_iterations > 1 )); then
    test_iteration_arguments=(
        -test-iterations "$test_iterations"
    )
fi

require_physical_vision_pro
mkdir -p "$evidence_root"
device_diagnostic_log="$evidence_root/device-state-diagnostics.log"

record_device_diagnostic() {
    local phase=$1
    local passcode_required
    passcode_required=$(device_lock_status)
    echo "$phase passcodeRequired=$passcode_required" >> "$device_diagnostic_log"
}

record_device_diagnostic "before-build"

common_arguments=(
    -project "$repository_root/Enchron.xcodeproj"
    -scheme Enchron
    -testPlan VisionProCoreRegression
    -configuration Debug
    -destination "$destination"
    -derivedDataPath "$derived_data"
    -clonedSourcePackagesDirPath "$source_packages"
    -parallel-testing-enabled NO
    CODE_SIGNING_ALLOWED=YES
)

capture_manifest() {
    local result=$1
    local manifest_arguments=(
        --output "$evidence_root/manifest.json"
        --artifact "$evidence_root"
        --result "$result"
        --command "xcodebuild build-for-testing and test-without-building with VisionProCoreRegression; $selection_description"
    )
    DEVELOPER_DIR="$developer_dir" python3 \
        "$repository_root/Scripts/verification/capture_validation_manifest.py" \
        "${manifest_arguments[@]}"
}

set +e
DEVELOPER_DIR="$developer_dir" \
ENCHRON_DEVICE_REGRESSION_MEDIA_CARD_IDS="$media_card_ids" \
xcodebuild \
    build-for-testing \
    "${common_arguments[@]}" \
    -resultBundlePath "$evidence_root/VisionProCoreRegression-build.xcresult" \
    2>&1 \
    | sed -E \
        -e "s/$device_identifier/<physical-vision-pro>/g" \
        -e 's/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}/<physical-vision-pro>/g' \
    | tee "$evidence_root/build.log"
build_exit=$?
set -e

if (( build_exit != 0 )); then
    capture_manifest "build-for-testing failed with exit code $build_exit"
    exit "$build_exit"
fi

terminate_enchron_ui_test_runners
record_device_diagnostic "before-test"

test_log="$evidence_root/test.log"
set +e
DEVELOPER_DIR="$developer_dir" \
ENCHRON_DEVICE_REGRESSION_MEDIA_CARD_IDS="$media_card_ids" \
/usr/bin/perl -e 'alarm shift; exec @ARGV or die "exec failed: $!"' \
    "$test_session_timeout_seconds" \
    xcodebuild \
    test-without-building \
    "${common_arguments[@]}" \
    "${test_selection_arguments[@]}" \
    "${test_iteration_arguments[@]}" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 180 \
    -maximum-test-execution-time-allowance 180 \
    -collect-test-diagnostics on-failure \
    -resultBundlePath "$evidence_root/VisionProCoreRegression.xcresult" \
    2>&1 \
    | sed -E \
        -e "s/$device_identifier/<physical-vision-pro>/g" \
        -e 's/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}/<physical-vision-pro>/g' \
    | tee "$test_log"
test_exit=$?
set -e

result_bundle="$evidence_root/VisionProCoreRegression.xcresult"
summary_path="$evidence_root/test-summary.json"
failure_detail=""
outcome="not evaluated"

if (( test_exit == 142 )); then
    failure_detail="XCTest did not complete within ${test_session_timeout_seconds} seconds"
    echo "VisionProCoreRegression exceeded its ${test_session_timeout_seconds}-second test-session limit before XCTest completed." >&2
fi

if [[ -d "$result_bundle" ]]; then
    set +e
    DEVELOPER_DIR="$developer_dir" xcrun xcresulttool get test-results summary \
        --path "$result_bundle" > "$summary_path"
    summary_exit=$?
    set -e
else
    summary_exit=1
fi

if (( summary_exit == 0 )); then
    total_test_count=$(jq -r '.totalTestCount // 0' "$summary_path")
    passed_test_count=$(jq -r '.passedTests // 0' "$summary_path")
    failed_test_count=$(jq -r '.failedTests // 0' "$summary_path")
    skipped_test_count=$(jq -r '.skippedTests // 0' "$summary_path")
    result=$(jq -r '.result // "unknown"' "$summary_path")
else
    total_test_count=0
    passed_test_count=0
    failed_test_count=0
    skipped_test_count=0
    result=missing
fi

if (( summary_exit == 0 )); then
    set +e
    summary_validation_json=$(python3 \
        "$repository_root/Scripts/verification/validate_visionpro_regression_result.py" \
        "$summary_path" \
        "$expected_test_count" \
        --test-log "$test_log" \
        --format json)
    summary_validation_exit=$?
    set -e
    summary_validation_reason=$(jq -r '.reason' <<< "$summary_validation_json")
    summary_validation_kind=$(jq -r '.kind' <<< "$summary_validation_json")
else
    summary_validation_reason="XCTest did not produce a readable test summary"
    summary_validation_kind="incomplete_test_session"
    summary_validation_exit=65
fi

if (( summary_validation_exit != 0 )); then
    echo "$summary_validation_reason" >&2
    if (( test_exit == 0 )); then
        test_exit=$summary_validation_exit
    fi
fi

recording_analysis_root="$evidence_root/ui-recordings"
recording_analysis_log="$evidence_root/ui-recording-extraction.log"
if [[ -d "$result_bundle" ]]; then
    set +e
    DEVELOPER_DIR="$developer_dir" python3 \
        "$repository_root/Scripts/verification/extract_visionpro_ui_recording.py" \
        "$result_bundle" \
        "$recording_analysis_root" \
        >"$recording_analysis_log" 2>&1
    recording_analysis_exit=$?
    set -e
else
    recording_analysis_exit=66
    echo "The XCTest result bundle was unavailable, so its physical Vision Pro UI recording could not be recovered." \
        >"$recording_analysis_log"
fi

if (( recording_analysis_exit != 0 )); then
    recording_failure="physical Vision Pro UI recording extraction failed with exit code $recording_analysis_exit"
    echo "$recording_failure" >&2
    if (( test_exit == 0 )); then
        test_exit=66
    fi
fi

if [[ "$summary_validation_kind" == "device_infrastructure_failure" ]]; then
    outcome="device test infrastructure failure before test method entry"
elif (( failed_test_count > 0 )); then
    outcome="test failure"
elif (( recording_analysis_exit != 0 )); then
    outcome="evidence capture failure"
elif (( test_exit == 0 )); then
    outcome="passed"
fi

if (( test_exit == 0 )); then
    capture_manifest "VisionProCoreRegression passed all $expected_test_count required test executions"
else
    record_device_diagnostic "after-unsuccessful-test-session"
    terminate_enchron_ui_test_runners
    if [[ -z "$failure_detail" && -n "${recording_failure:-}" ]]; then
        failure_detail="$recording_failure"
    elif [[ -z "$failure_detail" ]]; then
        failure_detail="$summary_validation_reason"
    fi
    capture_manifest "VisionProCoreRegression $outcome: $failure_detail; exit=$test_exit expected=$expected_test_count total=$total_test_count passed=$passed_test_count failed=$failed_test_count skipped=$skipped_test_count result=$result"
fi

echo "Vision Pro core regression completed; evidence: $evidence_root"
exit "$test_exit"
