#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="8.0.1"
BUILD_ROOT="$ROOT_DIR/.build/ffmpeg"
ARCHIVE="$BUILD_ROOT/ffmpeg-$VERSION.tar.xz"
SOURCE="$BUILD_ROOT/ffmpeg-$VERSION"
VENDOR_DIR="$ROOT_DIR/Vendor/FFmpeg"
OUTPUT="$VENDOR_DIR/PlaybackFFmpeg.xcframework"

mkdir -p "$BUILD_ROOT" "$VENDOR_DIR"

if [[ ! -f "$ARCHIVE" ]]; then
  curl -L --fail --output "$ARCHIVE" "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
fi

if [[ ! -d "$SOURCE" ]]; then
  tar -xf "$ARCHIVE" -C "$BUILD_ROOT"
  perl -0pi -e 's/#if TARGET_OS_IPHONE\n    CFDictionarySetValue\(buffer_attributes, kCVPixelBufferOpenGLESCompatibilityKey, kCFBooleanTrue\);\n#else\n    CFDictionarySetValue\(buffer_attributes, kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey, kCFBooleanTrue\);\n#endif/#if TARGET_OS_IPHONE \&\& !TARGET_OS_VISION\n    CFDictionarySetValue(buffer_attributes, kCVPixelBufferOpenGLESCompatibilityKey, kCFBooleanTrue);\n#elif !TARGET_OS_VISION\n    CFDictionarySetValue(buffer_attributes, kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey, kCFBooleanTrue);\n#endif/' "$SOURCE/libavcodec/videotoolbox.c"
fi

build_slice() {
  local name="$1"
  local sdk="$2"
  local arch="$3"
  local target="$4"
  local build="$BUILD_ROOT/build-$name"
  local prefix="$BUILD_ROOT/prefix-$name"
  local sysroot
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"

  mkdir -p "$build" "$prefix"
  if [[ ! -f "$prefix/lib/libswresample.a" ]]; then
    (
      cd "$build"
      "$SOURCE/configure" \
        --prefix="$prefix" \
        --target-os=darwin \
        --arch="$arch" \
        --enable-cross-compile \
        --sysroot="$sysroot" \
        --cc="/usr/bin/xcrun -sdk $sdk clang" \
        --ar="/usr/bin/xcrun -sdk $sdk ar" \
        --ranlib="/usr/bin/xcrun -sdk $sdk ranlib" \
        --strip="/usr/bin/xcrun -sdk $sdk strip" \
        --extra-cflags="-target $target" \
        --extra-ldflags="-target $target" \
        --enable-static \
        --disable-shared \
        --enable-pic \
        --disable-programs \
        --disable-doc \
        --disable-network \
        --disable-avdevice \
        --disable-avfilter \
        --disable-encoders \
        --disable-muxers \
        --disable-autodetect \
        --enable-audiotoolbox
      make -j"$(sysctl -n hw.logicalcpu)" install
    )
  fi

  /usr/bin/libtool -static -o "$prefix/lib/libPlaybackFFmpeg.a" \
    "$prefix/lib/libavformat.a" \
    "$prefix/lib/libavcodec.a" \
    "$prefix/lib/libswresample.a" \
    "$prefix/lib/libswscale.a" \
    "$prefix/lib/libavutil.a"
}

build_slice macos-arm64 macosx arm64 arm64-apple-macos26.0
build_slice xros-arm64 xros arm64 arm64-apple-xros26.0
build_slice xrsimulator-arm64 xrsimulator arm64 arm64-apple-xros26.0-simulator
build_slice xrsimulator-x86_64 xrsimulator x86_64 x86_64-apple-xros26.0-simulator

SIMULATOR_DIR="$BUILD_ROOT/prefix-xrsimulator-universal"
mkdir -p "$SIMULATOR_DIR/lib"
lipo -create \
  "$BUILD_ROOT/prefix-xrsimulator-arm64/lib/libPlaybackFFmpeg.a" \
  "$BUILD_ROOT/prefix-xrsimulator-x86_64/lib/libPlaybackFFmpeg.a" \
  -output "$SIMULATOR_DIR/lib/libPlaybackFFmpeg.a"

rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
  -library "$BUILD_ROOT/prefix-macos-arm64/lib/libPlaybackFFmpeg.a" \
  -headers "$BUILD_ROOT/prefix-macos-arm64/include" \
  -library "$BUILD_ROOT/prefix-xros-arm64/lib/libPlaybackFFmpeg.a" \
  -headers "$BUILD_ROOT/prefix-xros-arm64/include" \
  -library "$SIMULATOR_DIR/lib/libPlaybackFFmpeg.a" \
  -headers "$BUILD_ROOT/prefix-xrsimulator-arm64/include" \
  -output "$OUTPUT"

echo "$OUTPUT"
