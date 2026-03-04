#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
THIRD_PARTY_DIR="$ROOT_DIR/third_party"
FFMPEG_DIR="$THIRD_PARTY_DIR/ffmpeg"
MPV_DIR="$THIRD_PARTY_DIR/mpv"

FFMPEG_REPO="https://github.com/FFmpeg/FFmpeg.git"
FFMPEG_TAG="n7.1"
MPV_REPO="https://github.com/mpv-player/mpv.git"
MPV_TAG="v0.39.0"

ensure_repo() {
  local repo_url="$1"
  local tag="$2"
  local dir="$3"

  if [[ -d "$dir/.git" ]]; then
    echo "[all] Updating $(basename "$dir") to $tag"
    git -C "$dir" fetch --tags --force
  else
    echo "[all] Cloning $(basename "$dir")"
    git clone "$repo_url" "$dir"
  fi

  git -C "$dir" checkout "$tag"
}

mkdir -p "$THIRD_PARTY_DIR"

ensure_repo "$FFMPEG_REPO" "$FFMPEG_TAG" "$FFMPEG_DIR"
ensure_repo "$MPV_REPO" "$MPV_TAG" "$MPV_DIR"

"$SCRIPT_DIR/build-ffmpeg.sh" --target all
"$SCRIPT_DIR/build-mpv.sh" --target all
"$SCRIPT_DIR/package-xcframework.sh"

echo "[all] Success. Final artifact: $ROOT_DIR/build/MPV.xcframework"
