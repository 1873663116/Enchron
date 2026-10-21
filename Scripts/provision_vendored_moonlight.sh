#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DONOR="${1:-${ENCHRON_MOONLIGHT_DONOR:-}}"

if [[ -n "$DONOR" ]]; then
  if [[ ! -d "$DONOR" ]]; then
    echo "donor clone does not exist: $DONOR" >&2
    exit 1
  fi
  DONOR="$(cd "$DONOR" && pwd)"
fi

provision() {
  local relative="$1"
  local builder="$2"
  if [[ -d "$ROOT/$relative" ]]; then
    echo "$ROOT/$relative"
    return 0
  fi
  if [[ -z "$DONOR" ]]; then
    "$ROOT/$builder"
    echo "$ROOT/$relative"
    return 0
  fi
  if [[ ! -d "$DONOR/$relative" ]]; then
    "$DONOR/$builder"
  fi
  mkdir -p "$(dirname "$ROOT/$relative")"
  ln -s "$DONOR/$relative" "$ROOT/$relative"
  if [[ ! -d "$ROOT/$relative" ]]; then
    echo "framework link does not resolve: $ROOT/$relative -> $DONOR/$relative" >&2
    exit 1
  fi
  echo "$ROOT/$relative"
}

provision "Packages/MoonlightClient/Vendor/OpenSSL/OpenSSL.xcframework" "Packages/MoonlightClient/Scripts/build_openssl.sh"
provision "Packages/MoonlightClient/Vendor/Opus/Opus.xcframework" "Packages/MoonlightClient/Scripts/build_libopus.sh"
