#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
PKG_DIR="$BUILD_DIR/package"
OUT_XCFRAMEWORK="$BUILD_DIR/MPV.xcframework"
MODULEMAP_SRC="$ROOT_DIR/Libraries/mpv/module.modulemap"
HEADER_SRC_DIR="$ROOT_DIR/Libraries/mpv"

merge_target() {
  local target="$1"
  local ffmpeg_lib_dir="$BUILD_DIR/ffmpeg/$target/lib"
  local mpv_lib_dir="$BUILD_DIR/mpv/$target/lib"
  local out_dir="$PKG_DIR/$target"
  local merged_lib="$out_dir/libmpv_full.a"

  mkdir -p "$out_dir/Headers/Modules"

  local libs=(
    "$mpv_lib_dir/libmpv.a"
    "$ffmpeg_lib_dir/libavcodec.a"
    "$ffmpeg_lib_dir/libavformat.a"
    "$ffmpeg_lib_dir/libavutil.a"
    "$ffmpeg_lib_dir/libswresample.a"
    "$ffmpeg_lib_dir/libswscale.a"
  )

  for lib in "${libs[@]}"; do
    if [[ ! -f "$lib" ]]; then
      echo "[package] Missing library for $target: $lib" >&2
      exit 1
    fi
  done

  echo "[package] Merging static libraries ($target)"
  libtool -static -o "$merged_lib" "${libs[@]}"

  cp "$HEADER_SRC_DIR/client.h" "$out_dir/Headers/client.h"
  cp "$HEADER_SRC_DIR/render.h" "$out_dir/Headers/render.h"
  cp "$MODULEMAP_SRC" "$out_dir/Headers/Modules/module.modulemap"
}

if [[ ! -f "$MODULEMAP_SRC" ]]; then
  echo "[package] Missing module map: $MODULEMAP_SRC" >&2
  exit 1
fi

rm -rf "$PKG_DIR" "$OUT_XCFRAMEWORK"
mkdir -p "$PKG_DIR"

merge_target device
merge_target simulator

echo "[package] Creating MPV.xcframework"
xcodebuild -create-xcframework \
  -library "$PKG_DIR/device/libmpv_full.a" -headers "$PKG_DIR/device/Headers" \
  -library "$PKG_DIR/simulator/libmpv_full.a" -headers "$PKG_DIR/simulator/Headers" \
  -output "$OUT_XCFRAMEWORK"

echo "[package] Done. Output: $OUT_XCFRAMEWORK"
