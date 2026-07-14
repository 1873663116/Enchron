# 运行中调试协议

PlaybackCore 为每个 Media Session 持续输出版本化 Snapshot 与结构化 JSONL event。macOS Playback Lab 另外提供原子 command inbox，使外部程序可以在不重启 App 的情况下执行控制并等待真实完成结果。

## 文件布局

根目录是当前用户 `FileManager.default.temporaryDirectory/playbackcore-live-debug/`：

```text
playbackcore-live-debug/
├── current.json
├── <media-session-id>/
│   ├── snapshot.json
│   └── events.jsonl
├── commands/<command-id>.json
└── acknowledgements/<command-id>.json
```

`current.json` 只包含当前 Media Session ID、platform、route 与两个 artifact 路径。Snapshot 不写完整 source path；event 默认只记录节点和 operation 边界，不逐 sample 刷盘。close 后该会话 Snapshot 保留 `lastMediaSession`、最后 operation、flush 与失效后的 binding facts。

## Command 与 acknowledgement

`PlaybackDebugCLI` 先用 atomic write 产生唯一 command JSON。常驻 App 按文件名顺序读取，完成 handler 后写 acknowledgement，再移除 command。ack status 只有：

- `completed`：命令及其完成边界已经发生。
- `failed`：执行失败；`message` 保存可公开错误。
- `rejected`：payload 无效或 route 不存在。

command kind 是 `snapshot`、`play`、`pause`、`rate`、`seek`、`route`、`close` 或 `reopen`。`seek` 的 completed 边界是新 Stream Epoch 中 PTS 不早于 target 的 sample 已被 renderer accepted；`route` 在新会话节点 9 attach 后完成；`close` 等待 removal-flush completion；`reopen` 必须创建不同的 Media Session ID。

## 使用

保持 Playback Lab 运行，然后调用构建出的 CLI：

```text
PlaybackDebugCLI pause
PlaybackDebugCLI seek 7.5
PlaybackDebugCLI rate 0.5
PlaybackDebugCLI route ffmpegCompressed
PlaybackDebugCLI snapshot
PlaybackDebugCLI close
PlaybackDebugCLI reopen
```

CLI 等待最多 15 秒。超时或 failed acknowledgement 返回非零状态。协议不使用 `DistributedNotificationCenter`；该通道在当前 macOS 安全模型下会被系统拒绝，不能作为验收入口。

visionOS target 使用同一 recorder 与 Snapshot schema。device artifact 位于 App container；命令 inbox 当前只属于 macOS Lab adapter，Vision Pro 仍通过 Xcode 运行与设备容器取证。

## 资源收尾

macOS 单进程调试结束后停止由 probe 启动的 Playback Lab。visionOS Simulator 只为平台差分用例临时启动；取得 build / run、scene 或截图证据后，先停止 App，再 shutdown 对应 Simulator device。常驻的 Simulator 不属于证据，也不能作为下一次用例的隐式前置状态。
