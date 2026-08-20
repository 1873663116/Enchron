#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="9.0.1"
CONFIGURATION_REVISION="apac-passthrough-v1-ffmpeg-$VERSION"
BUILD_ROOT="$ROOT_DIR/.build/ffmpeg"
ARCHIVE="$BUILD_ROOT/ffmpeg-$VERSION.tar.xz"
ARCHIVE_SHA256="cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635"
SOURCE="$BUILD_ROOT/source-$CONFIGURATION_REVISION"
SOURCE_STAMP="$SOURCE/.enchron-source-ready"
VENDOR_DIR="$ROOT_DIR/Vendor/FFmpeg"
OUTPUT="$VENDOR_DIR/PlaybackFFmpeg.xcframework"
PATCH="$VENDOR_DIR/Patches/0001-mov-preserve-apple-apac-dapa.patch"

mkdir -p "$BUILD_ROOT" "$VENDOR_DIR"

if [[ ! -f "$ARCHIVE" ]]; then
  curl -L --fail --output "$ARCHIVE" "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
fi

actual_archive_sha256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$actual_archive_sha256" != "$ARCHIVE_SHA256" ]]; then
  echo "FFmpeg archive checksum mismatch" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_STAMP" ]]; then
  if [[ -e "$SOURCE" ]]; then
    echo "Incomplete FFmpeg source tree at $SOURCE" >&2
    exit 1
  fi
  source_staging="$(mktemp -d "$BUILD_ROOT/source-$CONFIGURATION_REVISION.XXXXXX")"
  tar -xf "$ARCHIVE" -C "$source_staging" --strip-components=1
  perl -0pi -e 's/#if TARGET_OS_IPHONE\n    CFDictionarySetValue\(buffer_attributes, kCVPixelBufferOpenGLESCompatibilityKey, kCFBooleanTrue\);\n#else\n    CFDictionarySetValue\(buffer_attributes, kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey, kCFBooleanTrue\);\n#endif/#if TARGET_OS_IPHONE \&\& !TARGET_OS_VISION\n    CFDictionarySetValue(buffer_attributes, kCVPixelBufferOpenGLESCompatibilityKey, kCFBooleanTrue);\n#elif !TARGET_OS_VISION\n    CFDictionarySetValue(buffer_attributes, kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey, kCFBooleanTrue);\n#endif/' "$source_staging/libavcodec/videotoolbox.c"
  patch -d "$source_staging" -p1 < "$PATCH"
  touch "$source_staging/.enchron-source-ready"
  mv "$source_staging" "$SOURCE"
fi

build_slice() {
  local name="$1"
  local sdk="$2"
  local arch="$3"
  local target="$4"
  local build="$BUILD_ROOT/build-$CONFIGURATION_REVISION-$name"
  local prefix="$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-$name"
  local sysroot
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"

  mkdir -p "$build" "$prefix"
  if [[ ! -f "$prefix/lib/libavformat.a" ]]; then
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
        --disable-avdevice \
        --disable-avfilter \
        --disable-encoders \
        --disable-hwaccels \
        --disable-muxers \
        --disable-swscale \
        --disable-autodetect \
        --enable-securetransport
      make -j"$(sysctl -n hw.logicalcpu)" install
    )
  fi

  /usr/bin/libtool -static -o "$prefix/lib/libPlaybackFFmpeg.a" \
    "$prefix/lib/libavformat.a" \
    "$prefix/lib/libavcodec.a" \
    "$prefix/lib/libswresample.a" \
    "$prefix/lib/libavutil.a"
}

build_slice macos27-arm64 macosx arm64 arm64-apple-macos27.0
build_slice xros27-arm64 xros arm64 arm64-apple-xros27.0
build_slice xrsimulator27-arm64 xrsimulator arm64 arm64-apple-xros27.0-simulator
build_slice xrsimulator27-x86_64 xrsimulator x86_64 x86_64-apple-xros27.0-simulator

SIMULATOR_DIR="$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator27-universal"
mkdir -p "$SIMULATOR_DIR/lib"
lipo -create \
  "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator27-arm64/lib/libPlaybackFFmpeg.a" \
  "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator27-x86_64/lib/libPlaybackFFmpeg.a" \
  -output "$SIMULATOR_DIR/lib/libPlaybackFFmpeg.a"

rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
  -library "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-macos27-arm64/lib/libPlaybackFFmpeg.a" \
  -headers "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-macos27-arm64/include" \
  -library "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros27-arm64/lib/libPlaybackFFmpeg.a" \
  -headers "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros27-arm64/include" \
  -library "$SIMULATOR_DIR/lib/libPlaybackFFmpeg.a" \
  -headers "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator27-arm64/include" \
  -output "$OUTPUT"

echo "$OUTPUT"
