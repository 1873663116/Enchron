# macOS PlaybackCore 运行时控制

当前只定义 `open(source:)`、`close()`、`play()` 和 `pause()`。

`open(source:)` 创建新的 Media Session 和 Open Operation。PlaybackCore Target Path 按节点 2 到节点 9 推进；Apple Sample Reference Path 创建独立验证会话并从 reference sample source 进入节点 7。

`play()` 和 `pause()` 只作用于当前 Media Session 的 `AVSampleBufferRenderSynchronizer`。没有 active Media Session 时不产生隐藏状态变化。

`close()` 终止当前 sample delivery，停止 renderer 请求，解除 RealityKit binding 和 `RealityView` presentation，并释放当前媒体槽位。旧 Media Session 后续到达的 sample 或 callback 不能更新当前状态。

每个请求记录 request identity、目标 Media Session、admission 和最终执行结果。Debug Snapshot 能解释最近请求、当前 synchronizer rate、active renderer graph、binding 和 cleanup 状态。

具体状态转换、测试拆分和错误映射由实现阶段使用 `$tdd` 决定。
