#!/bin/zsh

artifact_root=${ENCHRON_ARTIFACT_ROOT:-/Volumes/Cortisol/DevSpace/Xcode/Enchron}

if [[ "$artifact_root" == /Volumes/Cortisol || "$artifact_root" == /Volumes/Cortisol/* ]] &&
    ! /sbin/mount | /usr/bin/grep -Fq " on /Volumes/Cortisol ("; then
    echo "Cortisol is not mounted; refusing to write Enchron build and test artifacts to the system disk." >&2
    exit 72
fi

mkdir -p "$artifact_root/DerivedData" \
    "$artifact_root/SourcePackages" \
    "$artifact_root/TestEvidence" \
    "$artifact_root/Temporary"

export TMPDIR="$artifact_root/Temporary"
