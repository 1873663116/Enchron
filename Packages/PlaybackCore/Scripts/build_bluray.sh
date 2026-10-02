#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$PACKAGE_ROOT/.build/bluray"
VENDOR_ROOT="$PACKAGE_ROOT/Vendor/BluRay"
OUTPUT="$VENDOR_ROOT/PlaybackBluRay.xcframework"
BLURAY_VERSION=1.4.1
UDF_VERSION=1.2.0
BLURAY_SHA256=76b5dc40097f28dca4ebb009c98ed51321b2927453f75cc72cf74acd09b9f449
UDF_SHA256=bb477cbd4cfbfc7787d9d05b71ee5e70430f5cfebf1297497f7e83547958050f
CONFIGURATION_REVISION=no-decryption-v2
BLURAY_ARCHIVE="$BUILD_ROOT/libbluray-$BLURAY_VERSION.tar.xz"
UDF_ARCHIVE="$BUILD_ROOT/libudfread-$UDF_VERSION.tar.xz"
SOURCE="$BUILD_ROOT/source-libbluray-$BLURAY_VERSION-udfread-$UDF_VERSION-$CONFIGURATION_REVISION"
PATCH="$VENDOR_ROOT/Patches/0001-allow-darwin-without-diskarbitration.patch"

mkdir -p "$BUILD_ROOT" "$VENDOR_ROOT"
download_and_verify() {
  local url="$1" archive="$2" expected="$3" actual
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --output "$archive" "$url"
  fi
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Archive checksum mismatch: $archive" >&2
    exit 1
  fi
}

download_and_verify \
  "https://download.videolan.org/pub/videolan/libbluray/$BLURAY_VERSION/libbluray-$BLURAY_VERSION.tar.xz" \
  "$BLURAY_ARCHIVE" "$BLURAY_SHA256"
download_and_verify \
  "https://download.videolan.org/pub/videolan/libudfread/libudfread-$UDF_VERSION.tar.xz" \
  "$UDF_ARCHIVE" "$UDF_SHA256"

if [[ ! -f "$SOURCE/.enchron-source-ready" ]]; then
  if [[ -e "$SOURCE" ]]; then
    echo "Incomplete Blu-ray source tree at $SOURCE" >&2
    exit 1
  fi
  staging="$(mktemp -d "$BUILD_ROOT/source.XXXXXX")"
  tar -xf "$BLURAY_ARCHIVE" -C "$staging" --strip-components=1
  udf_staging="$(mktemp -d "$BUILD_ROOT/udfread.XXXXXX")"
  tar -xf "$UDF_ARCHIVE" -C "$udf_staging" --strip-components=1
  # The release bundle includes a copy of libudfread. Replace it with the
  # separately pinned upstream archive so both inputs have explicit hashes.
  rm -rf "$staging/contrib/libudfread"
  mv "$udf_staging" "$staging/contrib/libudfread"
  patch -d "$staging" -p1 < "$PATCH"
  touch "$staging/.enchron-source-ready"
  mv "$staging" "$SOURCE"
fi

mkdir -p "$VENDOR_ROOT/Licenses"
cp "$SOURCE/COPYING" "$VENDOR_ROOT/Licenses/libbluray-COPYING"
cp "$SOURCE/contrib/libudfread/COPYING" "$VENDOR_ROOT/Licenses/libudfread-COPYING"

build_slice() {
  local name="$1" sdk="$2" arch="$3" target="$4"
  local build="$BUILD_ROOT/build-$CONFIGURATION_REVISION-$name"
  local prefix="$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-$name"
  local sysroot crossfile
  sysroot="$(/usr/bin/xcrun --sdk "$sdk" --show-sdk-path)"
  crossfile="$BUILD_ROOT/cross-$name.ini"
  printf '[binaries]\nc = [\x27/usr/bin/xcrun\x27, \x27--sdk\x27, \x27%s\x27, \x27clang\x27, \x27-target\x27, \x27%s\x27, \x27-isysroot\x27, \x27%s\x27]\nar = \x27/usr/bin/ar\x27\nstrip = \x27/usr/bin/strip\x27\npkg-config = \x27/opt/homebrew/bin/pkg-config\x27\n\n[properties]\npkg_config_libdir = [\x27/nonexistent\x27]\n\n[host_machine]\nsystem = \x27darwin\x27\ncpu_family = \x27%s\x27\ncpu = \x27%s\x27\nendian = \x27little\x27\n' \
    "$sdk" "$target" "$sysroot" \
    "$([[ "$arch" == "x86_64" ]] && echo x86_64 || echo aarch64)" "$arch" > "$crossfile"
  if [[ ! -f "$build/build.ninja" ]]; then
    meson setup "$build" "$SOURCE" --cross-file "$crossfile" \
      --prefix "$prefix" --wrap-mode=forcefallback \
      -Ddefault_library=static -Dbdj_jar=disabled \
      -Denable_tools=false -Denable_examples=false -Denable_devtools=false \
      -Dfreetype=disabled -Dfontconfig=disabled -Dlibxml2=disabled \
      -Dembed_udfread=true
  fi
  meson compile -C "$build"
  meson install -C "$build"
  /usr/bin/libtool -static -o "$prefix/lib/libPlaybackBluRay.a" \
    "$build/src/libbluray.a" \
    "$build/contrib/libudfread/src/libudfread.a"
}

build_slice macos-arm64 macosx arm64 arm64-apple-macos27.0
build_slice xros-arm64 xros arm64 arm64-apple-xros27.0
build_slice xrsimulator-arm64 xrsimulator arm64 arm64-apple-xros27.0-simulator
build_slice xrsimulator-x86_64 xrsimulator x86_64 x86_64-apple-xros27.0-simulator

sim_prefix="$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator-universal"
mkdir -p "$sim_prefix/lib" "$sim_prefix/include"
/usr/bin/lipo -create \
  "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator-arm64/lib/libPlaybackBluRay.a" \
  "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator-x86_64/lib/libPlaybackBluRay.a" \
  -output "$sim_prefix/lib/libPlaybackBluRay.a"
cp -R "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros-arm64/include/." "$sim_prefix/include/"

for name in macos-arm64 xros-arm64 xrsimulator-universal; do
  header_root="$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-$name/include"
  printf 'module PlaybackBluRay {\n  header "libbluray/bluray.h"\n  header "libbluray/filesystem.h"\n  export *\n}\n' \
    > "$header_root/module.modulemap"
done

if [[ -e "$OUTPUT" ]]; then
  rm -rf "$OUTPUT"
fi
/usr/bin/xcodebuild -create-xcframework \
  -library "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-macos-arm64/lib/libPlaybackBluRay.a" \
  -headers "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-macos-arm64/include" \
  -library "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros-arm64/lib/libPlaybackBluRay.a" \
  -headers "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros-arm64/include" \
  -library "$sim_prefix/lib/libPlaybackBluRay.a" \
  -headers "$sim_prefix/include" \
  -output "$OUTPUT"
echo "$OUTPUT"
