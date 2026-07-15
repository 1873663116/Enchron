# PlaybackCore 验证规则

验证只证明 `docs/core-spec.md` 中由 PlaybackCore 拥有的行为，不建立手工状态表。

`swift test` 负责公开接口、Media Session、sample contract、轨道、控制、Receiver async backpressure、stale rejection 和 cleanup 的确定性测试。生成或提交的 fixture 必须许可清楚、身份稳定并有明确预期；本机绝对路径不是 fixture registry。

真实 container、FFmpeg demux 和 compressed `CMSampleBuffer` 使用独立 probe 或集成测试验证。证据必须记录 Git revision、fixture identity、命令、唯一预期结果和第一处失败边界。

macOS 27 可以证明 sample contract、AVFoundation Receiver 接受、displayed-frame 进度和长时间运行；Vision Pro 的 visionOS 27 验收才能证明设备硬件解码、HDR / Dolby Vision 和 visionOS renderer 行为。RealityKit consumer、窗口、沉浸空间和最终产品呈现由 Enchron 验证。

构建成功、测试数量、某个 route 的历史成功、日志中没有错误或单张截图都不是更强声明的替代品。最近一次有效证据记录在 `evidence.md`，历史结果只作为背景。
