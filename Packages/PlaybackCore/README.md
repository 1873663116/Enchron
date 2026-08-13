# PlaybackCore

PlaybackCore 是 Enchron 内部的 visionOS Swift Package。当前产品、target、依赖和平台配置见 [`Package.swift`](Package.swift)，实现见 [`Sources/PlaybackCore`](Sources/PlaybackCore)。域测试由仓库根目录的 `EnchronDomainTests` target 在 visionOS Simulator 中运行。

```sh
./Packages/PlaybackCore/Scripts/build_ffmpeg.sh
./Scripts/test-visionos-domain.sh <visionos-simulator-id>
```

它在 Enchron 中的代码所有权入口见仓库根 [`ARCHITECTURE.md`](../../ARCHITECTURE.md)；具体行为以当前源码、测试和运行结果为准。
