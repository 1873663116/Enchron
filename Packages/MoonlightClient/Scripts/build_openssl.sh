#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="3.5.9"
CONFIGURATION_REVISION="static-vision-openssl-$VERSION"
BUILD_ROOT="$ROOT_DIR/.build/openssl"
ARCHIVE="$BUILD_ROOT/openssl-$VERSION.tar.gz"
ARCHIVE_SHA256="603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a"
SOURCE="$BUILD_ROOT/source-$CONFIGURATION_REVISION"
SOURCE_STAMP="$SOURCE/.enchron-source-ready"
VENDOR_DIR="$ROOT_DIR/Vendor/OpenSSL"
OUTPUT="$VENDOR_DIR/OpenSSL.xcframework"
HEADERS_OUT="$ROOT_DIR/Sources/COpenSSL/include"
JOBS="$(sysctl -n hw.logicalcpu)"

mkdir -p "$BUILD_ROOT" "$VENDOR_DIR"

if [[ ! -f "$ARCHIVE" ]]; then
  curl -L --fail --output "$ARCHIVE" "https://github.com/openssl/openssl/releases/download/openssl-$VERSION/openssl-$VERSION.tar.gz"
fi

actual_archive_sha256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$actual_archive_sha256" != "$ARCHIVE_SHA256" ]]; then
  echo "OpenSSL archive checksum mismatch" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_STAMP" ]]; then
  if [[ -e "$SOURCE" ]]; then
    echo "Incomplete OpenSSL source tree at $SOURCE" >&2
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

  if [[ -f "$prefix/lib/libcrypto.a" ]]; then
    return 0
  fi

  local attempt
  for attempt in "" "no-asm no-async"; do
    rm -rf "$build" "$prefix"
    mkdir -p "$build" "$prefix"
    if (
      cd "$build"
      CC="$(xcrun --sdk "$sdk" --find clang)" \
      CFLAGS="-target $target -isysroot $sysroot -fno-common -O3" \
      "$SOURCE/Configure" \
        no-shared \
        no-module \
        no-tests \
        no-apps \
        $attempt \
        --prefix="$prefix" \
        darwin64-arm64-cc
      make -j"$JOBS"
      make install_sw
    ); then
      return 0
    fi
    echo "OpenSSL slice $name failed to build with extra flags [$attempt]" >&2
  done

  echo "OpenSSL slice $name failed to build" >&2
  return 1
}

build_slice xros27-arm64 xros arm64-apple-xros27.0
build_slice xrsimulator27-arm64 xrsimulator arm64-apple-xros27.0-simulator

DEVICE_PREFIX="$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xros27-arm64"
SIMULATOR_PREFIX="$BUILD_ROOT/prefix-$CONFIGURATION_REVISION-xrsimulator27-arm64"

rm -rf "$HEADERS_OUT/openssl"
mkdir -p "$HEADERS_OUT"
cp -R "$DEVICE_PREFIX/include/openssl" "$HEADERS_OUT/openssl"

rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
  -library "$DEVICE_PREFIX/lib/libcrypto.a" \
  -headers "$DEVICE_PREFIX/include" \
  -library "$SIMULATOR_PREFIX/lib/libcrypto.a" \
  -headers "$SIMULATOR_PREFIX/include" \
  -output "$OUTPUT"

echo "OpenSSL $VERSION"
echo "  xcframework slices: $(ls "$OUTPUT" | grep -v '^Info.plist$' | tr '\n' ' ')"
echo "  header snapshot:    $HEADERS_OUT/openssl ($(ls -1 "$HEADERS_OUT/openssl" | wc -l | tr -d ' ') headers)"
echo "$OUTPUT"
