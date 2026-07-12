# 节点 8：RealityKit renderer binding

## 作用与边界

节点 8 把节点 7 的 active `AVSampleBufferVideoRenderer` 写入 `VideoPlayerComponent(videoRenderer:)`，并把 component 挂到当前 Media Session 的 video entity。它不负责 sample delivery，也不负责把 entity 放入 `RealityView`。

完成条件是 component 引用当前 renderer graph 的 active video renderer，component 已挂到 video entity，binding 能追溯到同一个 Media Session、renderer graph 和 sample provenance。

## 输入与输出

输入包含 `mediaSessionID`、sample provenance、active video renderer、renderer graph revision 和 cleanup 信号。PlaybackCore Target Path 的 provenance 保留 `trackModelID`；Apple Sample Reference Path 保留 reference sample source identity。

输出是 renderer-backed video entity 和 RealityKit Binding Record。记录说明 renderer graph、active renderer、video entity、component attached state、binding identity、sample provenance 和最后一次失败。

## 稳定规则

renderer、component 和 entity 必须属于同一个 Media Session。component 必须引用节点 7 当前 active renderer。同一个 active renderer 只有一个 active video binding。renderer graph 被替换或 cleanup 后，旧 binding 不再声明 active。

## 验收方向

L1 验证 binding record、identity、唯一性和 stale rejection。L2 使用 macOS Playback Lab 分别运行 Apple Sample Reference Path 与 PlaybackCore Target Path，证明真实 `VideoPlayerComponent(videoRenderer:)` 使用节点 7 的 active renderer，并挂到当前 video entity。

具体 entity 类型、identity 生成和测试 hook 由实现阶段使用 `$tdd` 决定。
