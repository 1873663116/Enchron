#!/bin/zsh

set -euo pipefail

repository_root=${0:A:h:h:h}
source "$repository_root/Scripts/verification/enchron_artifact_paths.sh"
xcode_app=${ENCHRON_XCODE_APP:-/Volumes/Cortisol/Applications/Xcode-beta3.app}
developer_dir="$xcode_app/Contents/Developer"
destination=${ENCHRON_VISION_TEST_DESTINATION:-}
derived_data=${ENCHRON_DERIVED_DATA:-$artifact_root/DerivedData/VisionTestSuites}
source_packages=${ENCHRON_SOURCE_PACKAGES:-$artifact_root/SourcePackages/VisionTestSuites}
evidence_root=${ENCHRON_EVIDENCE_ROOT:-$artifact_root/TestEvidence/vision-test-suites-$(date +%Y%m%d-%H%M%S)}

if [[ -z "$destination" ]]; then
    echo "Set ENCHRON_VISION_TEST_DESTINATION to an explicit physical Vision Pro destination, for example platform=visionOS,id=<device-id>." >&2
    exit 64
fi

if [[ "$destination" == *Simulator* || "$destination" == *simulator* ]]; then
    echo "Enchron visionOS regression requires a physical Vision Pro destination." >&2
    exit 64
fi

test_suites=(
    EnvironmentSceneMappingTests
    WindowPlaybackPageGeometryTests
    PlaybackPresentationStateTests
    PlaybackSourceAccessTests
    PlaybackSourceAndAudioSessionTests
    MediaLibraryTests
    LocalDataSourceAdapterTests
    FakeFileDataSourceTests
    SMBDataSourceAdapterTests
    WebDAVDataSourceAdapterTests
)

mkdir -p "$evidence_root"

for suite in $test_suites; do
    DEVELOPER_DIR="$developer_dir" xcodebuild test \
        -project "$repository_root/Enchron.xcodeproj" \
        -scheme Enchron \
        -configuration Debug \
        -destination "$destination" \
        -derivedDataPath "$derived_data" \
        -clonedSourcePackagesDirPath "$source_packages" \
        -resultBundlePath "$evidence_root/$suite.xcresult" \
        "-only-testing:EnchronAppTests/$suite"
done

echo "Sequential visionOS Swift Testing suites passed; evidence: $evidence_root"
