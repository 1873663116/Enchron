#!/bin/zsh

set -euo pipefail

repository_root=${0:A:h:h:h}
xcode_app=${ENCHRON_XCODE_APP:-/Volumes/Cortisol/Applications/Xcode-beta3.app}
developer_dir="$xcode_app/Contents/Developer"
derived_data=${ENCHRON_DERIVED_DATA:-/private/tmp/EnchronOrganicArchitectureDerivedData}
source_packages=${ENCHRON_SOURCE_PACKAGES:-/private/tmp/EnchronOrganicArchitectureSourcePackages}
evidence_root=${ENCHRON_EVIDENCE_ROOT:-/private/tmp/enchron-validation-evidence/organic-architecture-20260723}

mkdir -p "$evidence_root"

python3 "$repository_root/Scripts/verification/verify_playback_surface_structure.py"
DEVELOPER_DIR="$developer_dir" python3 "$repository_root/Scripts/verification/verify_package_membership.py"

build_scheme() {
    local scheme=$1
    local destination=$2
    local result_name=$3

    DEVELOPER_DIR="$developer_dir" xcodebuild \
        -project "$repository_root/Enchron.xcodeproj" \
        -scheme "$scheme" \
        -configuration Debug \
        -destination "$destination" \
        -derivedDataPath "$derived_data" \
        -clonedSourcePackagesDirPath "$source_packages" \
        -resultBundlePath "$evidence_root/$result_name.xcresult" \
        CODE_SIGNING_ALLOWED=NO \
        build
}

build_scheme Enchron 'generic/platform=visionOS' Enchron-build
build_scheme EnchronMacOS 'platform=macOS' EnchronMacOS-build
build_scheme DesignPreview 'generic/platform=visionOS' DesignPreview-build

echo "Xcode product builds passed; evidence: $evidence_root"
