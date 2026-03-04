#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--target device|simulator|all]

Build FFmpeg static libraries for visionOS.
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
      echo "[ffmpeg] Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$TARGET" != "device" && "$TARGET" != "simulator" && "$TARGET" != "all" ]]; then
  echo "[ffmpeg] Invalid --target: $TARGET" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FFMPEG_SRC_DIR="$ROOT_DIR/third_party/ffmpeg"
OUT_BASE="$ROOT_DIR/build/ffmpeg"

if [[ ! -f "$FFMPEG_SRC_DIR/configure" ]]; then
  echo "[ffmpeg] Missing FFmpeg source at $FFMPEG_SRC_DIR" >&2
  echo "[ffmpeg] Run scripts/build-all.sh or clone FFmpeg first." >&2
  exit 1
fi

CPU_COUNT="$(sysctl -n hw.ncpu 2>/dev/null || echo 8)"

build_target() {
  local target="$1"
  local sdk
  local min_flags="-mvisionos-version-min=2.0"
  local target_triple=""

  if [[ "$target" == "device" ]]; then
    sdk="xros"
  else
    sdk="xrsimulator"
    target_triple="-target arm64-apple-xros2.0-simulator"
  fi

  local sdkroot
  sdkroot="$(xcrun --sdk "$sdk" --show-sdk-path)"

  local cc cxx ar ranlib strip
  cc="$(xcrun --sdk "$sdk" -f clang)"
  cxx="$(xcrun --sdk "$sdk" -f clang++)"
  ar="$(xcrun --sdk "$sdk" -f ar)"
  ranlib="$(xcrun --sdk "$sdk" -f ranlib)"
  strip="$(xcrun --sdk "$sdk" -f strip)"

  local cflags ldflags
  cflags="-arch arm64 -isysroot $sdkroot $min_flags $target_triple"
  ldflags="-arch arm64 -isysroot $sdkroot $min_flags $target_triple"

  local install_dir="$OUT_BASE/$target"
  local build_dir="$OUT_BASE/.work/$target"

  rm -rf "$build_dir" "$install_dir"
  mkdir -p "$build_dir" "$install_dir"

  echo "[ffmpeg] Configuring ($target)"
  pushd "$build_dir" >/dev/null

  "$FFMPEG_SRC_DIR/configure" \
    --prefix="$install_dir" \
    --target-os=darwin \
    --arch=arm64 \
    --enable-cross-compile \
    --cc="$cc" \
    --cxx="$cxx" \
    --ar="$ar" \
    --ranlib="$ranlib" \
    --strip="$strip" \
    --sysroot="$sdkroot" \
    --extra-cflags="$cflags" \
    --extra-ldflags="$ldflags" \
    --enable-static \
    --disable-shared \
    --disable-programs \
    --disable-doc \
    --disable-debug \
    --disable-network \
    --disable-avdevice \
    --disable-postproc \
    --disable-autodetect \
    --enable-pic \
    --enable-videotoolbox \
    --enable-audiotoolbox \
    --enable-hwaccels \
    --enable-avcodec \
    --enable-avformat \
    --enable-avutil \
    --enable-swresample \
    --enable-swscale \
    --enable-protocol=file \
    --enable-demuxer=mov,matroska \
    --enable-parser=h264,hevc,aac \
    --enable-decoder=h264,hevc,aac,opus,vorbis

  echo "[ffmpeg] Building ($target)"
  make -j"$CPU_COUNT"

  echo "[ffmpeg] Installing ($target) -> $install_dir"
  make install

  popd >/dev/null
}

if [[ "$TARGET" == "all" ]]; then
  build_target device
  build_target simulator
else
  build_target "$TARGET"
fi

echo "[ffmpeg] Done. Output: $OUT_BASE"
