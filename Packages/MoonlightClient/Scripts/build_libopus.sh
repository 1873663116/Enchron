#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="1.5.2"
CONFIGURATION_REVISION="libopus-$VERSION"
BUILD_ROOT="$ROOT_DIR/.build/libopus"
ARCHIVE="$BUILD_ROOT/opus-$VERSION.tar.gz"
ARCHIVE_SHA256="65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"
SOURCE="$BUILD_ROOT/source-$CONFIGURATION_REVISION"
SOURCE_STAMP="$SOURCE/.enchron-source-ready"
VENDOR_DIR="$ROOT_DIR/Vendor/Opus"
OUTPUT="$VENDOR_DIR/Opus.xcframework"
HEADERS_OUT="$ROOT_DIR/Sources/COpus/include/opus"

mkdir -p "$BUILD_ROOT" "$VENDOR_DIR"

if [[ ! -f "$ARCHIVE" ]]; then
  curl -L --fail --output "$ARCHIVE" "https://downloads.xiph.org/releases/opus/opus-$VERSION.tar.gz"
fi

actual_archive_sha256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$actual_archive_sha256" != "$ARCHIVE_SHA256" ]]; then
  echo "Opus archive checksum mismatch" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_STAMP" ]]; then
  if [[ -e "$SOURCE" ]]; then
    echo "Incomplete Opus source tree at $SOURCE" >&2
    exit 1
  fi
  source_staging="$(mktemp -d "$BUILD_ROOT/source-$CONFIGURATION_REVISION.XXXXXX")"
  tar -xf "$ARCHIVE" -C "$source_staging" --strip-components=1
  touch "$source_staging/.enchron-source-ready"
  mv "$source_staging" "$SOURCE"
fi

build_slice() {
  local name="$1"
  local sdk="$2"
  local target="$3"
  local build="$BUILD_ROOT/build-$CONFIGURATION_REVISION-$name"
  local prefix="$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-$name"
  local sysroot
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"

  mkdir -p "$build" "$prefix"
  if [[ ! -f "$prefix/lib/libopus.a" ]]; then
    (
      cd "$build"
      CC="$(xcrun --sdk "$sdk" --find clang)" \
      CFLAGS="-target $target -isysroot $sysroot -O3 -fno-common" \
      LDFLAGS="-target $target -isysroot $sysroot" \
        "$SOURCE/configure" \
          --host=arm-apple-darwin \
          --prefix="$prefix" \
          --disable-shared \
          --enable-static \
          --disable-doc \
          --disable-extra-programs \
          --disable-asm
      make -j"$(sysctl -n hw.logicalcpu)" install
    )
  fi
}

build_slice xros27-arm64 xros arm64-apple-xros27.0
build_slice xrsimulator27-arm64 xrsimulator arm64-apple-xros27.0-simulator

rm -rf "$HEADERS_OUT"
mkdir -p "$HEADERS_OUT"
cp "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros27-arm64/include/opus/"*.h "$HEADERS_OUT/"

rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
  -library "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros27-arm64/lib/libopus.a" \
  -headers "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros27-arm64/include" \
  -library "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator27-arm64/lib/libopus.a" \
  -headers "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator27-arm64/include" \
  -output "$OUTPUT"

for slice in "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros27-arm64/lib/libopus.a" \
             "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator27-arm64/lib/libopus.a"; do
  file "$slice"
done
xcrun nm -gU "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros27-arm64/lib/libopus.a" \
  | grep -E "_opus_multistream_(decoder_create|decode|encoder_create)"
xcrun nm -gU "$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator27-arm64/lib/libopus.a" \
  | grep -E "_opus_multistream_(decoder_create|decode|encoder_create)"

echo "libopus $VERSION"
echo "device:    $BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros27-arm64/lib/libopus.a"
echo "simulator: $BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator27-arm64/lib/libopus.a"
echo "headers:   $HEADERS_OUT"
echo "framework: $OUTPUT"
