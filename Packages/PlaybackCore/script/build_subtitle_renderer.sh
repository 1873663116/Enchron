#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build/subtitle-renderer"
VENDOR_DIR="$ROOT_DIR/Vendor/SubtitleRenderer"
OUTPUT="$VENDOR_DIR/PlaybackSubtitleRenderer.xcframework"

LIBASS_VERSION="0.17.4"
HARFBUZZ_VERSION="14.2.0"
FRIBIDI_VERSION="1.0.16"
FREETYPE_VERSION="2.14.3"
REVISION="libass-0.17.4-minimal-v1"
JOBS="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

download() {
  local name="$1"
  local url="$2"
  local sha256="$3"
  local archive="$BUILD_ROOT/$name"
  if [[ ! -f "$archive" ]]; then
    curl -L --fail --output "$archive" "$url"
  fi
  if [[ "$(shasum -a 256 "$archive" | awk '{print $1}')" != "$sha256" ]]; then
    echo "Checksum mismatch: $archive" >&2
    exit 1
  fi
}

extract() {
  local archive="$1"
  local directory="$2"
  if [[ ! -d "$directory" ]]; then
    tar -xf "$archive" -C "$BUILD_ROOT"
  fi
}

build_slice() {
  local name="$1"
  local sdk="$2"
  local arch="$3"
  local target="$4"
  local cpu_family="$5"
  local host="$6"
  local prefix="$BUILD_ROOT/prefix-$REVISION-$name"
  local build="$BUILD_ROOT/build-$REVISION-$name"
  local sysroot
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"

  mkdir -p "$prefix" "$build"
  export CC="/usr/bin/xcrun -sdk $sdk clang"
  export CXX="/usr/bin/xcrun -sdk $sdk clang++"
  export AR="/usr/bin/xcrun -sdk $sdk ar"
  export RANLIB="/usr/bin/xcrun -sdk $sdk ranlib"
  export STRIP="/usr/bin/xcrun -sdk $sdk strip"
  export CFLAGS="-target $target -isysroot $sysroot -Os"
  export CXXFLAGS="$CFLAGS"
  export CPPFLAGS="-I$prefix/include"
  export LDFLAGS="-target $target -isysroot $sysroot -L$prefix/lib"
  export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
  export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"

  mkdir -p "$build/freetype"
  if [[ ! -f "$prefix/lib/libfreetype.a" ]]; then
    (
      cd "$build/freetype"
      "$BUILD_ROOT/freetype-$FREETYPE_VERSION/configure" \
        --host="$host" \
        --prefix="$prefix" \
        --disable-shared \
        --enable-static \
        --without-zlib \
        --without-bzip2 \
        --without-png \
        --without-brotli \
        --without-harfbuzz
      make -j"$JOBS" install
    )
  fi

  mkdir -p "$build/fribidi"
  if [[ ! -f "$prefix/lib/libfribidi.a" ]]; then
    (
      cd "$build/fribidi"
      "$BUILD_ROOT/fribidi-$FRIBIDI_VERSION/configure" \
        --host="$host" \
        --prefix="$prefix" \
        --disable-shared \
        --enable-static \
        --disable-debug \
        --disable-dependency-tracking \
        --disable-silent-rules
      make -j"$JOBS" install
    )
  fi

  if [[ ! -f "$prefix/lib/libharfbuzz.a" ]]; then
    local cross_file="$build/harfbuzz-cross.ini"
    sed \
      -e "s|@SDK@|$sdk|g" \
      -e "s|@TARGET@|$target|g" \
      -e "s|@SYSROOT@|$sysroot|g" \
      -e "s|@CPU_FAMILY@|$cpu_family|g" \
      -e "s|@CPU@|$arch|g" \
      "$ROOT_DIR/script/harfbuzz-apple-cross.ini.in" > "$cross_file"
    meson setup "$build/harfbuzz" "$BUILD_ROOT/harfbuzz-$HARFBUZZ_VERSION" \
      --cross-file "$cross_file" \
      --prefix "$prefix" \
      --default-library static \
      -Dfreetype=enabled \
      -Dcoretext=disabled \
      -Dglib=disabled \
      -Dgobject=disabled \
      -Dcairo=disabled \
      -Dicu=disabled \
      -Dgraphite=disabled \
      -Dtests=disabled \
      -Dutilities=disabled \
      -Ddocs=disabled \
      -Dintrospection=disabled
    meson compile -C "$build/harfbuzz"
    meson install -C "$build/harfbuzz"
  fi

  mkdir -p "$build/libass"
  if [[ ! -f "$prefix/lib/libass.a" ]]; then
    (
      cd "$build/libass"
      LIBS="-framework CoreText -framework CoreFoundation" \
        "$BUILD_ROOT/libass-$LIBASS_VERSION/configure" \
          --host="$host" \
          --prefix="$prefix" \
          --disable-shared \
          --enable-static \
          --disable-fontconfig \
          --disable-libunibreak \
          --disable-asm
      make -j"$JOBS" install
    )
  fi

  /usr/bin/libtool -static -o "$prefix/lib/libPlaybackSubtitleRenderer.a" \
    "$prefix/lib/libass.a" \
    "$prefix/lib/libharfbuzz.a" \
    "$prefix/lib/libfreetype.a" \
    "$prefix/lib/libfribidi.a"
  /usr/bin/xcrun --sdk "$sdk" strip -S -x "$prefix/lib/libPlaybackSubtitleRenderer.a"
}

stage_headers() {
  local source="$1"
  local destination="$2"
  mkdir -p "$destination/ass"
  cp "$source/include/ass/ass.h" "$destination/ass/"
  cp "$source/include/ass/ass_types.h" "$destination/ass/"
}

mkdir -p "$BUILD_ROOT" "$VENDOR_DIR"
download \
  "libass-$LIBASS_VERSION.tar.xz" \
  "https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.xz" \
  "78f1179b838d025e9c26e8fef33f8092f65611444ffa1bfc0cfac6a33511a05a"
download \
  "harfbuzz-$HARFBUZZ_VERSION.tar.xz" \
  "https://github.com/harfbuzz/harfbuzz/releases/download/$HARFBUZZ_VERSION/harfbuzz-$HARFBUZZ_VERSION.tar.xz" \
  "94017020f96d025bb66ae91574e4cf334bcad23e8175a8a40565b3721bc2eaff"
download \
  "fribidi-$FRIBIDI_VERSION.tar.xz" \
  "https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/fribidi-$FRIBIDI_VERSION.tar.xz" \
  "1b1cde5b235d40479e91be2f0e88a309e3214c8ab470ec8a2744d82a5a9ea05c"
download \
  "freetype-$FREETYPE_VERSION.tar.xz" \
  "https://download.savannah.gnu.org/releases/freetype/freetype-$FREETYPE_VERSION.tar.xz" \
  "36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f"

extract "$BUILD_ROOT/libass-$LIBASS_VERSION.tar.xz" "$BUILD_ROOT/libass-$LIBASS_VERSION"
extract "$BUILD_ROOT/harfbuzz-$HARFBUZZ_VERSION.tar.xz" "$BUILD_ROOT/harfbuzz-$HARFBUZZ_VERSION"
extract "$BUILD_ROOT/fribidi-$FRIBIDI_VERSION.tar.xz" "$BUILD_ROOT/fribidi-$FRIBIDI_VERSION"
extract "$BUILD_ROOT/freetype-$FREETYPE_VERSION.tar.xz" "$BUILD_ROOT/freetype-$FREETYPE_VERSION"

build_slice macos27-arm64 macosx arm64 arm64-apple-macos27.0 aarch64 aarch64-apple-darwin
build_slice xros27-arm64 xros arm64 arm64-apple-xros27.0 aarch64 aarch64-apple-darwin
build_slice xrsimulator27-arm64 xrsimulator arm64 arm64-apple-xros27.0-simulator aarch64 aarch64-apple-darwin
build_slice xrsimulator27-x86_64 xrsimulator x86_64 x86_64-apple-xros27.0-simulator x86_64 x86_64-apple-darwin

SIMULATOR_DIR="$BUILD_ROOT/prefix-$REVISION-xrsimulator27-universal"
mkdir -p "$SIMULATOR_DIR/lib" "$SIMULATOR_DIR/include/ass"
lipo -create \
  "$BUILD_ROOT/prefix-$REVISION-xrsimulator27-arm64/lib/libPlaybackSubtitleRenderer.a" \
  "$BUILD_ROOT/prefix-$REVISION-xrsimulator27-x86_64/lib/libPlaybackSubtitleRenderer.a" \
  -output "$SIMULATOR_DIR/lib/libPlaybackSubtitleRenderer.a"
cp "$BUILD_ROOT/prefix-$REVISION-xrsimulator27-arm64/include/ass/ass.h" "$SIMULATOR_DIR/include/ass/"
cp "$BUILD_ROOT/prefix-$REVISION-xrsimulator27-arm64/include/ass/ass_types.h" "$SIMULATOR_DIR/include/ass/"

MACOS_HEADERS="$BUILD_ROOT/headers-$REVISION-macos27"
XROS_HEADERS="$BUILD_ROOT/headers-$REVISION-xros27"
stage_headers "$BUILD_ROOT/prefix-$REVISION-macos27-arm64" "$MACOS_HEADERS"
stage_headers "$BUILD_ROOT/prefix-$REVISION-xros27-arm64" "$XROS_HEADERS"

rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
  -library "$BUILD_ROOT/prefix-$REVISION-macos27-arm64/lib/libPlaybackSubtitleRenderer.a" \
  -headers "$MACOS_HEADERS" \
  -library "$BUILD_ROOT/prefix-$REVISION-xros27-arm64/lib/libPlaybackSubtitleRenderer.a" \
  -headers "$XROS_HEADERS" \
  -library "$SIMULATOR_DIR/lib/libPlaybackSubtitleRenderer.a" \
  -headers "$SIMULATOR_DIR/include" \
  -output "$OUTPUT"

echo "$OUTPUT"
