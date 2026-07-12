# 未来工作

这里保留后续方向；当前行为和验收状态分别以 `core-spec.md` 与 `acceptance/evidence.md` 为准。

## PanoramaScannerLab

`PanoramaScannerLab` 是未来视觉识别实验方向。它用于研究缺少明确 metadata 时，是否可以用画面特征推断 `Projection` 与 `StereoLayout`。

当前阶段只保留 Debug Snapshot 中的 scanner 占位字段。没有明确 metadata 时，播放核心使用安全默认值 `rectilinear + mono + Window`，并记录 `scanner.source = "notRun"`。

未来重新启动时需要回答：

- 生产采样 adapter 从哪里取帧。
- 采样成本、线程和远程源支持方式是什么。
- 如何不违反“播放核心不持有解码像素”的边界。
- classifier 的输入、输出、预算和评估指标是什么。
- 哪些误判会改变默认播放策略，哪些只影响诊断。

## 第一轮真机后的设备扩展

第一轮 L3 只验证最小设备专属事实。后续可以扩展：

- 更完整的 codec / device generation matrix。
- AV1 在 M5 Vision Pro 上的真实路径。
- 更多 HDR10、HLG、Dolby Vision、ProRes 和高码率样本。
- 更细的刷新率、掉帧、thermal 和长时播放指标。
- 真实字幕容器、图片字幕、复杂轨道和语言选择。

这些方向只有在当前 L1 / L2 基础管线稳定后才进入活跃规格、验收系统或验收证据账本。

## 产品集成

播放核心最终会复制进 `XrPlayer`。产品集成阶段需要单独决定：

- 播放列表、下一集、历史记录和续播策略。
- 正式 UI 控件与诊断信息暴露范围。
- 不确定识别结果的用户提示和手动选择入口。
- 场景资源、空间布局和 Reality Composer Pro 资产边界。

这些不是当前播放核心仓库的验收前置条件。
