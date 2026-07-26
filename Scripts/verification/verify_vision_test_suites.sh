#!/bin/zsh

set -euo pipefail

repository_root=${0:A:h:h:h}
xcode_app=${ENCHRON_XCODE_APP:-/Volumes/Cortisol/Applications/Xcode-beta3.app}
developer_dir="$xcode_app/Contents/Developer"
destination=${ENCHRON_VISION_TEST_DESTINATION:-platform=visionOS Simulator,id=6D3B4D6F-D370-4133-95E3-4BE4F23BCA0D}
derived_data=${ENCHRON_DERIVED_DATA:-/private/tmp/EnchronVisionTestSuitesDerivedData}
source_packages=${ENCHRON_SOURCE_PACKAGES:-/private/tmp/EnchronOrganicArchitectureSourcePackages}
evidence_root=${ENCHRON_EVIDENCE_ROOT:-/private/tmp/enchron-validation-evidence/vision-test-suites}

test_suites=(
    EnvironmentSceneMappingTests
    WindowPlaybackPageGeometryTests
    PlaybackPresentationStateTests
    PlaybackSourceAccessTests
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
