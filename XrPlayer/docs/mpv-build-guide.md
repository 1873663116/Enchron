# mpv Build Guide for visionOS (arm64)

This guide describes a practical path to build `ffmpeg + mpv` for visionOS and integrate it into XrPlayer.

## 1) Cross-compile strategy

Use a two-stage build:
1. Build FFmpeg static libs for `visionOS arm64`.
2. Build libplacebo + mpv static lib against those FFmpeg libs.
3. Package all static outputs and headers into an `xcframework` (or vendored framework layout).

Recommended environment variables:

```bash
export DEVELOPER=$(xcode-select -p)
export SDKROOT=$(xcrun --sdk xros --show-sdk-path)
export CC="$(xcrun --sdk xros -f clang)"
export CXX="$(xcrun --sdk xros -f clang++)"
export AR="$(xcrun --sdk xros -f ar)"
export RANLIB="$(xcrun --sdk xros -f ranlib)"
export STRIP="$(xcrun --sdk xros -f strip)"
export CFLAGS="-arch arm64 -isysroot $SDKROOT -mvisionos-version-min=1.0"
export LDFLAGS="-arch arm64 -isysroot $SDKROOT -mvisionos-version-min=1.0"
```

## 2) FFmpeg configure flags (visionOS)

A minimal GPU-decoding-capable configure set:

```bash
./configure \
  --prefix=$PWD/build/visionos-arm64 \
  --target-os=darwin \
  --arch=arm64 \
  --enable-cross-compile \
  --cc="$CC" \
  --cxx="$CXX" \
  --sysroot="$SDKROOT" \
  --extra-cflags="$CFLAGS" \
  --extra-ldflags="$LDFLAGS" \
  --enable-static \
  --disable-shared \
  --disable-programs \
  --disable-doc \
  --enable-pic \
  --enable-videotoolbox \
  --enable-audiotoolbox \
  --enable-avcodec \
  --enable-avformat \
  --enable-avutil \
  --enable-swresample \
  --enable-swscale
```

Then:

```bash
make -j$(sysctl -n hw.ncpu)
make install
```

## 3) Build mpv for visionOS

Use Meson/Ninja and point dependencies to the FFmpeg prefix.

```bash
meson setup build-visionos \
  --default-library=static \
  -Dlibmpv=true \
  -Dcplayer=false \
  -Dtests=false \
  -Dmanpage-build=disabled \
  -Dvideotoolbox=enabled \
  -Dswift-build=disabled \
  -Dffmpeg=enabled \
  -Dprefix=$PWD/install/visionos-arm64 \
  --cross-file path/to/visionos-arm64.cross

ninja -C build-visionos
ninja -C build-visionos install
```

Cross-file should set `c`, `cpp`, `ar`, `strip`, `host_machine` (`aarch64`), and pass visionOS `c_args`/`c_link_args`.

## 4) xcframework packaging

Static libraries cannot be directly wrapped as one binary if they are split; package one umbrella static library or ship a framework with modulemap + all `.a` libs in linker settings.

Typical packaging flow:

1. Merge required static archives into one `libmpv_full.a`:

```bash
libtool -static -o libmpv_full.a \
  libmpv.a libavcodec.a libavformat.a libavutil.a libswscale.a libswresample.a
```

2. Create framework directory layout:
- `Headers/` includes `mpv/client.h`, `mpv/render.h`, and dependency headers.
- `Modules/module.modulemap` exports headers.
- `libmpv_full.a` as binary payload.

3. Package with `xcodebuild -create-xcframework` (device + simulator slices if available):

```bash
xcodebuild -create-xcframework \
  -library visionos-arm64/libmpv_full.a -headers visionos-arm64/Headers \
  -library visionos-sim-arm64/libmpv_full.a -headers visionos-sim-arm64/Headers \
  -output MPV.xcframework
```

## 5) Xcode/SPM integration

### Manual Xcode integration

1. Add `MPV.xcframework` to the app target.
2. Set `SWIFT_OBJC_BRIDGING_HEADER` to `XrPlayer-Bridging-Header.h`.
3. Add required system frameworks:
- `VideoToolbox`
- `CoreVideo`
- `CoreMedia`
- `Metal`
- `QuartzCore`
- `AudioToolbox`

4. If static dependency symbols are unresolved, add dependent `.a` libs explicitly under `Other Linker Flags`.

### Swift Package Manager integration

Use a `binaryTarget` pointing to `MPV.xcframework`, then expose a wrapper target with your Swift adapter sources.

```swift
.binaryTarget(name: "MPVBinary", path: "MPV.xcframework")
```

## 6) Open-source references

- `mpv-player/mpv` and `mpv-android/mpv-android` build scripts (cross-compilation patterns)
- `mpv-apple-build` style community scripts for Apple platform ffmpeg/mpv toolchains
- `FFmpegKit` Apple packaging patterns for architecture slicing and framework distribution

## 7) Notes for XrPlayer

- Keep mpv in `libmpv` mode and drive control via `mpv/client.h`.
- Enable hardware decode with `--hwdec=videotoolbox`.
- Use `mpv/render.h` render context (`sw` or OpenGL backend) and convert frames to `CVPixelBuffer` for `FrameOutput`.
- Treat simulator support as optional initially; prioritize `visionOS arm64` device slice.
