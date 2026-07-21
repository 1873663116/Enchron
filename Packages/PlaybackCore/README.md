# PlaybackCore

PlaybackCore 是 Enchron 内部的 macOS/visionOS Swift Package，负责 container、Media Session、compressed sample、控制语义与 AVFoundation renderer graph。

```sh
./Scripts/build_ffmpeg.sh
swift test
```

核心行为的唯一规格位于仓库根 `docs/core-spec.md`；系统节点、验证规则和证据位于仓库根 `docs/acceptance/`。模块边界见仓库根 `ARCHITECTURE.md` 和 `CONTEXT.md`。
