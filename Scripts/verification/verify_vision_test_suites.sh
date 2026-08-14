#!/bin/zsh

set -euo pipefail

repository_root=${0:A:h:h:h}
source "$repository_root/Scripts/verification/enchron_artifact_paths.sh"
xcode_app=${ENCHRON_XCODE_APP:-}
if [[ -n "$xcode_app" ]]; then
    developer_dir="$xcode_app/Contents/Developer"
else
    developer_dir=$(xcode-select -p)
fi

if [[ ! -d "$developer_dir" ]]; then
    echo "Developer directory does not exist: $developer_dir" >&2
    exit 72
fi
xcodebuild_command=${ENCHRON_XCODEBUILD:-xcodebuild}
destination=${ENCHRON_VISION_TEST_DESTINATION:-}
derived_data=${ENCHRON_DERIVED_DATA:-$artifact_root/DerivedData/VisionTestSuites}
source_packages=${ENCHRON_SOURCE_PACKAGES:-$artifact_root/SourcePackages/VisionTestSuites}
evidence_root=${ENCHRON_EVIDENCE_ROOT:-$artifact_root/TestEvidence/vision-test-suites-$(date +%Y%m%d-%H%M%S)}
plan_only=${ENCHRON_VISION_TEST_PLAN_ONLY:-0}

if [[ -z "$destination" ]]; then
    echo "Set ENCHRON_VISION_TEST_DESTINATION to an explicit physical Vision Pro destination, for example platform=visionOS,id=<device-id>." >&2
    exit 64
fi

if [[ "$destination" == *Simulator* || "$destination" == *simulator* ]]; then
    echo "Enchron visionOS regression requires a physical Vision Pro destination." >&2
    exit 64
fi

mkdir -p "$evidence_root"

selection_command=(
    python3 "$repository_root/Scripts/verification/xcodebuild_test_selection.py"
    --xcodebuild "$xcodebuild_command"
    target-run
    --target EnchronAppTests
    --evidence-root "$evidence_root"
    --keep-enumeration "$evidence_root/test-enumeration.json"
)

case "$plan_only" in
    0) ;;
    1) selection_command+=(--plan-only) ;;
    *)
        echo "ENCHRON_VISION_TEST_PLAN_ONLY must be 0 or 1." >&2
        exit 64
        ;;
esac

selection_command+=(
    --
    test
    -project "$repository_root/Enchron.xcodeproj"
    -scheme Enchron
    -configuration Debug
    -destination "$destination"
    -derivedDataPath "$derived_data"
    -clonedSourcePackagesDirPath "$source_packages"
)

DEVELOPER_DIR="$developer_dir" "${selection_command[@]}"

if [[ "$plan_only" == 1 ]]; then
    echo "Vision test invocation plan passed without launching device tests; evidence: $evidence_root"
else
    echo "Sequential visionOS test invocations passed; evidence: $evidence_root"
fi
