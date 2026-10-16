#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
source_file="$repo_root/Scripts/verification/host_forensic_patch.swift"
tmp_base="${TMPDIR:-/tmp}"
tmp_base="${tmp_base%/}"
build_dir="$tmp_base/enchron-forensic-patch"
binary="$build_dir/bin/host_forensic_patch"

if [[ ! -x "$binary" || "$source_file" -nt "$binary" ]]; then
    mkdir -p "$build_dir/bin"
    xcrun swiftc -O "$source_file" -o "$binary"
fi

exec "$binary" "$@"
