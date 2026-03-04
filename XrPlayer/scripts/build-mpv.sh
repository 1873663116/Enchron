#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--target device|simulator|all]

Build libmpv (static) for visionOS.
USAGE
}

TARGET="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[mpv] Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$TARGET" != "device" && "$TARGET" != "simulator" && "$TARGET" != "all" ]]; then
  echo "[mpv] Invalid --target: $TARGET" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MPV_SRC_DIR="$ROOT_DIR/third_party/mpv"
OUT_BASE="$ROOT_DIR/build/mpv"
CROSS_DEVICE="$SCRIPT_DIR/visionos-arm64.cross"
CROSS_SIM="$SCRIPT_DIR/visionos-sim-arm64.cross"

if [[ ! -f "$MPV_SRC_DIR/meson.build" ]]; then
  echo "[mpv] Missing mpv source at $MPV_SRC_DIR" >&2
  echo "[mpv] Run scripts/build-all.sh or clone mpv first." >&2
  exit 1
fi

if ! command -v meson >/dev/null 2>&1; then
  echo "[mpv] meson is required but not found." >&2
  exit 1
fi

if ! command -v ninja >/dev/null 2>&1; then
  echo "[mpv] ninja is required but not found." >&2
  exit 1
fi

build_target() {
  local target="$1"
  local ffmpeg_prefix="$ROOT_DIR/build/ffmpeg/$target"
  local build_dir="$OUT_BASE/$target/build"
  local install_dir="$OUT_BASE/$target"
  local cross_template
  local cross_file
  local sdk

  if [[ "$target" == "device" ]]; then
    sdk="xros"
    cross_template="$CROSS_DEVICE"
  else
    sdk="xrsimulator"
    cross_template="$CROSS_SIM"
  fi

  local sdkroot
  sdkroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cross_file="$OUT_BASE/$target/meson.cross"

  if [[ ! -f "$ffmpeg_prefix/lib/pkgconfig/libavcodec.pc" ]]; then
    echo "[mpv] FFmpeg output not found for $target at $ffmpeg_prefix" >&2
    echo "[mpv] Run scripts/build-ffmpeg.sh --target $target first." >&2
    exit 1
  fi

  echo "[mpv] Building ($target)"
  rm -rf "$build_dir" "$install_dir"
  mkdir -p "$build_dir" "$install_dir"
  sed "s|__SDKROOT__|$sdkroot|g" "$cross_template" > "$cross_file"

  PKG_CONFIG_PATH="$ffmpeg_prefix/lib/pkgconfig" \
  meson setup "$build_dir" "$MPV_SRC_DIR" \
    --buildtype=release \
    --default-library=static \
    --prefix "$install_dir" \
    --cross-file "$cross_file" \
    -Dlibmpv=true \
    -Dcplayer=false \
    -Dtests=false \
    -Dmanpage-build=disabled \
    -Dswift-build=disabled \
    -Dvideotoolbox=enabled \
    -Dffmpeg=enabled

  PKG_CONFIG_PATH="$ffmpeg_prefix/lib/pkgconfig" ninja -C "$build_dir"
  PKG_CONFIG_PATH="$ffmpeg_prefix/lib/pkgconfig" ninja -C "$build_dir" install

  echo "[mpv] Installed ($target) -> $install_dir"
}

if [[ "$TARGET" == "all" ]]; then
  build_target device
  build_target simulator
else
  build_target "$TARGET"
fi

echo "[mpv] Done. Output: $OUT_BASE"
