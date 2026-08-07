# PlaybackCore

PlaybackCore 是 Enchron 内部的 macOS/visionOS Swift Package。当前产品、target、依赖、平台和测试配置见 [`Package.swift`](Package.swift)，实现见 [`Sources/PlaybackCore`](Sources/PlaybackCore)，测试见 [`Tests`](Tests)。

```sh
./Scripts/build_ffmpeg.sh
swift test
```

它在 Enchron 中的代码所有权入口见仓库根 [`ARCHITECTURE.md`](../../ARCHITECTURE.md)；具体行为以当前源码、测试和运行结果为准。
