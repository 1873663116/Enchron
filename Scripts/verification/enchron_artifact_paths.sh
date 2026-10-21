#!/bin/zsh

repository_root=${0:a:h:h:h}
artifact_root=${ENCHRON_ARTIFACT_ROOT:-$repository_root/.scratch}
evidence_root=$repository_root/TestEvidence

mkdir -p "$artifact_root/DerivedData" "$artifact_root/SourcePackages" "$artifact_root/Temporary"

export TMPDIR="$artifact_root/Temporary"
