#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="9.0.1"
CONFIGURATION_REVISION="apac-passthrough-zlib-v2-ffmpeg-$VERSION-dynamic"
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
        --enable-securetransport \
        --enable-zlib
      make -j"$(sysctl -n hw.logicalcpu)" install
    )
  fi

  /usr/bin/libtool -static -o "$prefix/lib/libPlaybackFFmpeg.a" \
    "$prefix/lib/libavformat.a" \
    "$prefix/lib/libavcodec.a" \
    "$prefix/lib/libswresample.a" \
    "$prefix/lib/libavutil.a"

  local framework="$BUILD_ROOT/framework-$CONFIGURATION_REVISION-$name"
  rm -rf "$framework"
  mkdir -p "$framework/PlaybackFFmpeg.framework/Headers" "$framework/PlaybackFFmpeg.framework/Modules"
  cp -R "$prefix/include/" "$framework/PlaybackFFmpeg.framework/Headers/"

  /usr/bin/xcrun -sdk "$sdk" clang -dynamiclib \
    -target "$target" \
    -isysroot "$sysroot" \
    -install_name "@rpath/PlaybackFFmpeg.framework/PlaybackFFmpeg" \
    -compatibility_version 1.0.0 \
    -current_version 1.0.0 \
    -all_load "$prefix/lib/libPlaybackFFmpeg.a" \
    -framework Security \
    -framework CoreFoundation \
    -framework CoreMedia \
    -framework AudioToolbox \
    -liconv \
    -lz \
    -o "$framework/PlaybackFFmpeg.framework/PlaybackFFmpeg"

  cat > "$framework/PlaybackFFmpeg.framework/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>PlaybackFFmpeg</string>
	<key>CFBundleIdentifier</key>
	<string>app.enchron.PlaybackFFmpeg</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>PlaybackFFmpeg</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>9.0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
</dict>
</plist>
PLIST

  local minimum_os_key="MinimumOSVersion"
  if [[ "$sdk" == "macosx" ]]; then
    minimum_os_key="LSMinimumSystemVersion"
  fi
  /usr/libexec/PlistBuddy -c "Add :$minimum_os_key string 27.0" \
    "$framework/PlaybackFFmpeg.framework/Info.plist"

  cat > "$framework/PlaybackFFmpeg.framework/Modules/module.modulemap" <<'MODULEMAP'
framework module PlaybackFFmpeg {
  umbrella "Headers"
  export *
  module * { export * }
}
MODULEMAP
}

build_slice macos27-arm64 macosx arm64 arm64-apple-macos27.0
build_slice xros27-arm64 xros arm64 arm64-apple-xros27.0
build_slice xrsimulator27-arm64 xrsimulator arm64 arm64-apple-xros27.0-simulator
build_slice xrsimulator27-x86_64 xrsimulator x86_64 x86_64-apple-xros27.0-simulator

SIMULATOR_FRAMEWORK="$BUILD_ROOT/framework-$CONFIGURATION_REVISION-xrsimulator27-universal/PlaybackFFmpeg.framework"
rm -rf "$SIMULATOR_FRAMEWORK"
mkdir -p "$(dirname "$SIMULATOR_FRAMEWORK")"
cp -R "$BUILD_ROOT/framework-$CONFIGURATION_REVISION-xrsimulator27-arm64/PlaybackFFmpeg.framework" "$SIMULATOR_FRAMEWORK"
lipo -create \
  "$BUILD_ROOT/framework-$CONFIGURATION_REVISION-xrsimulator27-arm64/PlaybackFFmpeg.framework/PlaybackFFmpeg" \
  "$BUILD_ROOT/framework-$CONFIGURATION_REVISION-xrsimulator27-x86_64/PlaybackFFmpeg.framework/PlaybackFFmpeg" \
  -output "$SIMULATOR_FRAMEWORK/PlaybackFFmpeg"

HEADERS_OUT="$ROOT_DIR/Sources/PlaybackFFmpegBridge/ffmpeg-headers"
rm -rf "$HEADERS_OUT"
cp -R "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros27-arm64/include" "$HEADERS_OUT"

rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
  -framework "$BUILD_ROOT/framework-$CONFIGURATION_REVISION-macos27-arm64/PlaybackFFmpeg.framework" \
  -framework "$BUILD_ROOT/framework-$CONFIGURATION_REVISION-xros27-arm64/PlaybackFFmpeg.framework" \
  -framework "$SIMULATOR_FRAMEWORK" \
  -output "$OUTPUT"

echo "$OUTPUT"
